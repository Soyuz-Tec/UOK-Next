import Config

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
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  database_url =
    case System.get_env("DATABASE_URL") do
      value when is_binary(value) and value != "" -> value
      _ -> raise "environment variable DATABASE_URL is missing or empty"
    end

  database_uri = URI.parse(database_url)

  ssl_override? =
    case database_uri.query do
      nil -> false
      query -> Enum.any?(URI.query_decoder(query), fn {key, _value} -> key == "ssl" end)
    end

  if ssl_override? do
    raise "DATABASE_URL must not override the repository-owned SSL policy"
  end

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :uok_next, UokNext.Repo,
    url: database_url,
    ssl: true,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

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

  config :uok_next, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :uok_next, UokNextWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Fail closed until a deployment ADR proves a private, header-sanitizing
      # proxy boundary or configures application-level TLS.
      ip: {0, 0, 0, 0, 0, 0, 0, 1}
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
