import Config

parse_bounded_integer = fn name, default, minimum, maximum ->
  value = System.get_env(name, default)

  case Integer.parse(value) do
    {parsed, ""} when parsed >= minimum and parsed <= maximum -> parsed
    _ -> raise "#{name} must be an integer between #{minimum} and #{maximum}"
  end
end

required_bounded_token = fn name, minimum, maximum ->
  value = System.get_env(name)

  if is_binary(value) and byte_size(value) in minimum..maximum and
       Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9._~-]*\z/, value) do
    value
  else
    raise "#{name} must contain #{minimum} to #{maximum} URL-safe characters"
  end
end

required_object_store_url = fn local_qualification? ->
  value = System.get_env("OBJECT_STORE_URL")
  uri = if is_binary(value), do: URI.parse(value), else: %URI{}
  expected_scheme = if local_qualification?, do: "http", else: "https"

  valid_path? = uri.path in [nil, "", "/"]
  valid_port? = is_nil(uri.port) or uri.port in 1..65_535
  valid_local_host? = not local_qualification? or uri.host == "object-store"

  unless uri.scheme == expected_scheme and is_binary(uri.host) and uri.host != "" and
           valid_path? and valid_port? and valid_local_host? and is_nil(uri.userinfo) and
           is_nil(uri.query) and is_nil(uri.fragment) do
    raise "OBJECT_STORE_URL must identify the approved S3 endpoint and transport"
  end

  uri
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/uok_next start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") in ~w(true 1) do
  config :uok_next, UokNextWeb.Endpoint, server: true
end

config :uok_next, UokNextWeb.Endpoint,
  http: [port: parse_bounded_integer.("PORT", "4000", 1, 65_535)]

if config_env() == :prod do
  build_revision = Application.fetch_env!(:uok_next, :build_revision)

  unless is_binary(build_revision) and Regex.match?(~r/\A[0-9a-f]{40}\z/, build_revision) do
    raise "the compiled UOK_BUILD_REVISION must be a full lowercase Git revision"
  end

  deployment_profile = System.get_env("UOK_DEPLOYMENT_PROFILE", "production")
  local_qualification? = deployment_profile == "local_qualification"

  database_url =
    case System.get_env("DATABASE_URL") do
      value when is_binary(value) and value != "" -> value
      _ -> raise "environment variable DATABASE_URL is missing or empty"
    end

  database_uri = URI.parse(database_url)

  if database_uri.query not in [nil, ""] do
    raise "DATABASE_URL query parameters are not allowed to override repository-owned settings"
  end

  database_credentials = String.split(database_uri.userinfo || "", ":", parts: 2)

  unless database_uri.scheme in ["ecto", "postgres", "postgresql"] and
           is_binary(database_uri.host) and database_uri.host != "" and
           length(database_credentials) == 2 and
           Enum.all?(database_credentials, &(&1 != "")) and
           is_binary(database_uri.path) and Regex.match?(~r|\A/[^/]+\z|, database_uri.path) and
           database_uri.fragment in [nil, ""] and
           (is_nil(database_uri.port) or database_uri.port in 1..65_535) do
    raise "DATABASE_URL must contain a supported scheme, credentials, host, and one database name"
  end

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  if local_qualification? and database_uri.host not in ["postgres", "host.containers.internal"] do
    raise "local qualification DATABASE_URL must target the isolated local dependency"
  end

  database_ssl =
    if local_qualification? do
      false
    else
      database_ca_cert_file = System.get_env("DATABASE_CA_CERT_FILE")

      unless is_binary(database_ca_cert_file) and Path.type(database_ca_cert_file) == :absolute and
               File.regular?(database_ca_cert_file) do
        raise "DATABASE_CA_CERT_FILE must name a readable absolute CA trust file"
      end

      [cacertfile: database_ca_cert_file]
    end

  config :uok_next, :database_prerelease_allowed, local_qualification?

  config :uok_next, UokNext.Repo,
    url: database_url,
    ssl: database_ssl,
    target_server_type: :primary,
    disconnect_on_error_codes: [:read_only_sql_transaction],
    pool_size: parse_bounded_integer.("POOL_SIZE", "10", 1, 20),
    queue_target: parse_bounded_integer.("DB_QUEUE_TARGET_MS", "50", 1, 60_000),
    queue_interval: parse_bounded_integer.("DB_QUEUE_INTERVAL_MS", "1000", 1, 60_000),
    timeout: parse_bounded_integer.("DB_CHECKOUT_TIMEOUT_MS", "5000", 100, 120_000),
    parameters: [
      statement_timeout:
        parse_bounded_integer.("DB_STATEMENT_TIMEOUT_MS", "5000", 100, 300_000) |> to_string(),
      lock_timeout:
        parse_bounded_integer.("DB_LOCK_TIMEOUT_MS", "2000", 100, 120_000) |> to_string(),
      idle_in_transaction_session_timeout:
        parse_bounded_integer.("DB_IDLE_TRANSACTION_TIMEOUT_MS", "10000", 100, 300_000)
        |> to_string(),
      application_name: "uok-next",
      timezone: "UTC"
    ],
    socket_options: maybe_ipv6

  object_store_uri = required_object_store_url.(local_qualification?)
  object_store_access_key = required_bounded_token.("OBJECT_STORE_ACCESS_KEY", 16, 64)
  object_store_secret_key = required_bounded_token.("OBJECT_STORE_SECRET_KEY", 32, 128)
  object_store_bucket = System.get_env("OBJECT_STORE_BUCKET", "uok-evidence")
  object_store_region = System.get_env("OBJECT_STORE_REGION", "us-east-1")

  unless Regex.match?(~r/\A[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]\z/, object_store_bucket) and
           not String.contains?(object_store_bucket, "..") do
    raise "OBJECT_STORE_BUCKET must be a DNS-compatible S3 bucket name"
  end

  unless Regex.match?(~r/\A[a-z0-9][a-z0-9-]{1,30}[a-z0-9]\z/, object_store_region) do
    raise "OBJECT_STORE_REGION must be a bounded lowercase region identifier"
  end

  config :uok_next, :object_store,
    adapter: UokNext.Modules.Platform.Evidence.Infrastructure.S3ObjectStore,
    scheme: object_store_uri.scheme <> "://",
    host: object_store_uri.host,
    port: object_store_uri.port || if(local_qualification?, do: 8_333, else: 443),
    access_key_id: object_store_access_key,
    secret_access_key: object_store_secret_key,
    bucket: object_store_bucket,
    region: object_store_region,
    max_object_bytes:
      parse_bounded_integer.("OBJECT_STORE_MAX_OBJECT_BYTES", "8388608", 1, 8_388_608)

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    case System.get_env("SECRET_KEY_BASE") do
      value when is_binary(value) and byte_size(value) >= 64 -> value
      _ -> raise "environment variable SECRET_KEY_BASE must contain at least 64 bytes"
    end

  host =
    case System.get_env("PHX_HOST") do
      value when is_binary(value) and value != "" -> value
      _ -> raise "environment variable PHX_HOST is missing or empty"
    end

  if local_qualification? and host != "localhost" do
    raise "local qualification PHX_HOST must be localhost"
  end

  metrics_access_token =
    case System.get_env("METRICS_ACCESS_TOKEN") do
      nil -> nil
      value when byte_size(value) in 32..256 -> value
      _ -> raise "METRICS_ACCESS_TOKEN must contain 32 to 256 bytes when configured"
    end

  if metrics_access_token do
    config :uok_next, :metrics_access_token, metrics_access_token
  end

  config :uok_next, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :uok_next, UokNextWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Fail closed until a deployment ADR proves a private, header-sanitizing
      # proxy boundary or configures application-level TLS.
      ip: if(local_qualification?, do: {0, 0, 0, 0}, else: {0, 0, 0, 0, 0, 0, 0, 1}),
      port: parse_bounded_integer.("PORT", "4000", 1, 65_535)
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :uok_next, UokNextWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :uok_next, UokNextWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
