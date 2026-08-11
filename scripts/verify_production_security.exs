repo_config = Application.fetch_env!(:uok_next, UokNext.Repo)
endpoint_config = Application.fetch_env!(:uok_next, UokNextWeb.Endpoint)
force_ssl = Keyword.fetch!(endpoint_config, :force_ssl)
http = Keyword.fetch!(endpoint_config, :http)

{:ok, effective_repo_config} =
  Ecto.Repo.Supervisor.init_config(:supervisor, UokNext.Repo, :uok_next, [])

unless effective_repo_config[:ssl] == true do
  raise "production PostgreSQL must require authenticated TLS"
end

database_uri = repo_config |> Keyword.fetch!(:url) |> URI.parse()

if database_uri.query &&
     Enum.any?(URI.query_decoder(database_uri.query), fn {key, _value} -> key == "ssl" end) do
  raise "production DATABASE_URL must not control the repository-owned SSL policy"
end

unless force_ssl == [exclude: []] do
  raise "production force_ssl must not trust client forwarding or Host metadata"
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
