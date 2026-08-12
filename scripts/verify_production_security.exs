repo_config = Application.fetch_env!(:uok_next, UokNext.Repo)
endpoint_config = Application.fetch_env!(:uok_next, UokNextWeb.Endpoint)
build_revision = Application.fetch_env!(:uok_next, :build_revision)
object_store = Application.fetch_env!(:uok_next, :object_store)
force_ssl = Keyword.fetch!(endpoint_config, :force_ssl)
http = Keyword.fetch!(endpoint_config, :http)

unless is_binary(build_revision) and Regex.match?(~r/\A[0-9a-f]{40}\z/, build_revision) do
  raise "production release identity must be compiled from a full Git revision"
end

{:ok, effective_repo_config} =
  Ecto.Repo.Supervisor.init_config(:supervisor, UokNext.Repo, :uok_next, [])

database_ca_cert_file = System.fetch_env!("DATABASE_CA_CERT_FILE")

unless effective_repo_config[:ssl] == [cacertfile: database_ca_cert_file] do
  raise "production PostgreSQL must verify peer identity against the declared CA trust file"
end

unless effective_repo_config[:target_server_type] == :primary and
         effective_repo_config[:disconnect_on_error_codes] == [:read_only_sql_transaction] do
  raise "production writes must target a primary and disconnect after read-only failover errors"
end

unless Application.fetch_env!(:uok_next, :database_target_major) == 19 and
         Application.fetch_env!(:uok_next, :database_prerelease_allowed) == false do
  raise "production must require PostgreSQL 19 GA"
end

unless object_store[:adapter] ==
         UokNext.Modules.Platform.Evidence.Infrastructure.S3ObjectStore and
         Application.fetch_env!(:ex_aws, :http_client) ==
           UokNext.Modules.Platform.Evidence.Infrastructure.BoundedReqHttpClient and
         object_store[:scheme] == "https://" and object_store[:port] in 1..65_535 and
         object_store[:bucket] == "uok-evidence" and
         object_store[:max_object_bytes] == 8_388_608 do
  raise "production object storage must use the bounded provider-neutral S3 contract over HTTPS"
end

database_uri = repo_config |> Keyword.fetch!(:url) |> URI.parse()

if database_uri.query not in [nil, ""] do
  raise "production DATABASE_URL must not contain query-owned connection settings"
end

health_paths = [
  "/api/v1/health",
  "/api/v1/health/live",
  "/api/v1/health/ready",
  "/api/v1/health/startup",
  "/api/v1/release",
  "/api/v1/metrics"
]

unless Application.fetch_env!(:uok_next, :deployment_profile) == :production do
  raise "production must not activate the local qualification transport profile"
end

if Application.get_env(:uok_next, :local_qualification_identity) do
  raise "production must not configure the local qualification identity adapter"
end

unless force_ssl == [
         exclude: [
           conn: {UokNextWeb.LocalQualificationTransport, :http_allowed?, []},
           paths: health_paths
         ]
       ] do
  raise "production force_ssl must retain only the fail-closed local guard and health paths"
end

unless http[:ip] == {0, 0, 0, 0, 0, 0, 0, 1} do
  raise "production origin must default to the IPv6 loopback address"
end

plug_ssl_options = Plug.SSL.init(force_ssl)

spoofed_proxy_conn =
  :get
  |> Plug.Test.conn("/")
  |> Plug.Conn.put_req_header("x-forwarded-proto", "https")
  |> Plug.SSL.call(plug_ssl_options)

unless spoofed_proxy_conn.halted and spoofed_proxy_conn.status == 301 do
  raise "spoofed X-Forwarded-Proto must not bypass the HTTPS redirect"
end

health_conn =
  :get
  |> Plug.Test.conn("/api/v1/health/ready")
  |> Plug.SSL.call(plug_ssl_options)

if health_conn.halted do
  raise "the readiness probe must remain reachable inside the private origin boundary"
end

spoofed_host_conn =
  :get
  |> Plug.Test.conn("/")
  |> Map.put(:host, "localhost")
  |> Plug.SSL.call(plug_ssl_options)

unless spoofed_host_conn.halted and spoofed_host_conn.status == 301 do
  raise "spoofed localhost Host must not bypass the HTTPS redirect"
end

https_conn =
  :get
  |> Plug.Test.conn("/")
  |> Map.put(:scheme, :https)
  |> Plug.SSL.call(plug_ssl_options)

if https_conn.halted or Plug.Conn.get_resp_header(https_conn, "strict-transport-security") == [] do
  raise "legitimate HTTPS requests must continue with HSTS"
end

IO.puts("Production security configuration verification passed.")
