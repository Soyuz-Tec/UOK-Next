repo_config = Application.fetch_env!(:uok_next, UokNext.Repo)
outbox_repo_config = Application.fetch_env!(:uok_next, UokNext.OutboxRepo)
endpoint_config = Application.fetch_env!(:uok_next, UokNextWeb.Endpoint)
build_revision = Application.fetch_env!(:uok_next, :build_revision)
object_store = Application.fetch_env!(:uok_next, :object_store)
durable_work = Application.fetch_env!(:uok_next, :durable_work)
force_ssl = endpoint_config |> Keyword.fetch!(:force_ssl) |> Plug.SSL.init()

unless is_binary(build_revision) and Regex.match?(~r/\A[0-9a-f]{40}\z/, build_revision) do
  raise "local qualification release identity must be compiled from a full Git revision"
end

{:ok, effective_repo_config} =
  Ecto.Repo.Supervisor.init_config(:supervisor, UokNext.Repo, :uok_next, [])

{:ok, effective_outbox_repo_config} =
  Ecto.Repo.Supervisor.init_config(:supervisor, UokNext.OutboxRepo, :uok_next, [])

unless repo_config |> Keyword.fetch!(:url) |> URI.parse() |> Map.fetch!(:host) == "postgres" do
  raise "local qualification database must use the isolated Compose dependency"
end

unless effective_repo_config[:ssl] == false do
  raise "local qualification is the only profile allowed to use its isolated plaintext database"
end

outbox_database_uri = outbox_repo_config |> Keyword.fetch!(:url) |> URI.parse()

unless outbox_database_uri.host == "postgres" and
         outbox_database_uri.userinfo |> String.split(":", parts: 2) |> hd() == "uok_outbox" and
         effective_outbox_repo_config[:ssl] == false and durable_work[:enabled] and
         durable_work[:repo] == UokNext.OutboxRepo and
         durable_work[:publisher] == UokNext.Kernel.PostgresOutboxPublisher do
  raise "local qualification durable work must use the isolated worker role and handoff"
end

unless effective_repo_config[:target_server_type] == :primary and
         Application.fetch_env!(:uok_next, :database_target_major) == 19 and
         Application.fetch_env!(:uok_next, :database_prerelease_allowed) == true do
  raise "local qualification must exercise a PostgreSQL 19 primary and may allow the pinned beta"
end

unless endpoint_config[:http][:ip] == {0, 0, 0, 0} do
  raise "local qualification container must bind its private container interface"
end

unless Application.fetch_env!(:uok_next, :deployment_profile) == :local_qualification do
  raise "local qualification must use its explicit deployment profile"
end

local_identity = Application.fetch_env!(:uok_next, :local_qualification_identity)

unless match?({:ok, _tenant_id}, Ecto.UUID.cast(local_identity.tenant_id)) and
         match?({:ok, _actor_id}, Ecto.UUID.cast(local_identity.actor_id)) and
         is_binary(local_identity.access_code) and byte_size(local_identity.access_code) in 32..128 and
         Enum.sort(local_identity.permissions) ==
           Enum.sort([
             "communications:deliver",
             "communications:link",
             "communications:read",
             "communications:reconcile",
             "contracts:commitment-proposals:approve",
             "contracts:commitment-proposals:create",
             "contracts:commitment-proposals:evidence:submit",
             "contracts:commitment-proposals:read",
             "evidence:read",
             "evidence:upload",
             "identity:users:manage",
             "locations:create",
             "locations:read",
             "parties:approve",
             "parties:create",
             "parties:evidence:submit",
             "parties:read",
             "products:create",
             "products:read",
             "reports:operational:read",
             "shipments:readiness:create",
             "shipments:readiness:decide",
             "shipments:readiness:evidence:submit",
             "shipments:readiness:read",
             "sourcing:comparisons:approve",
             "sourcing:comparisons:create",
             "sourcing:comparisons:read",
             "sourcing:lanes:approve",
             "sourcing:lanes:create",
             "sourcing:lanes:evidence:submit",
             "sourcing:lanes:read",
             "sourcing:quotes:create",
             "sourcing:quotes:evidence:submit",
             "sourcing:quotes:read",
             "sourcing:requisitions:create",
             "sourcing:requisitions:read",
             "sourcing:rfqs:create",
             "sourcing:rfqs:read",
             "workflow:tasks:read"
           ]) do
  raise "local qualification identity must be server-owned and least-authorized"
end

local_browser_conn =
  :get
  |> Plug.Test.conn("/")
  |> Map.put(:host, "127.0.0.1")
  |> Plug.SSL.call(force_ssl)

if local_browser_conn.halted do
  raise "the isolated local browser path must remain reachable over loopback HTTP"
end

non_local_browser_conn =
  :get
  |> Plug.Test.conn("/")
  |> Map.put(:host, "example.invalid")
  |> Plug.SSL.call(force_ssl)

unless non_local_browser_conn.halted and non_local_browser_conn.status == 301 do
  raise "the local profile must not permit plaintext browser delivery for a non-local host"
end

unless is_binary(Application.fetch_env!(:uok_next, :metrics_access_token)) do
  raise "local qualification must protect metrics with a bearer token"
end

unless object_store[:adapter] ==
         UokNext.Modules.Platform.Evidence.Infrastructure.S3ObjectStore and
         Application.fetch_env!(:ex_aws, :http_client) ==
           UokNext.Modules.Platform.Evidence.Infrastructure.BoundedReqHttpClient and
         object_store[:scheme] == "http://" and object_store[:host] == "object-store" and
         object_store[:port] == 8_333 and object_store[:bucket] == "uok-evidence" and
         object_store[:max_object_bytes] == 8_388_608 do
  raise "local qualification must use the isolated bounded S3 dependency"
end

IO.puts("Local qualification security configuration verification passed.")
