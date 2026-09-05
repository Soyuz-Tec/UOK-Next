import Config

repository_root =
  __DIR__
  |> Path.join("..")
  |> Path.expand()
  |> String.replace("\\", "/")
  |> String.trim_trailing("/")
  |> String.downcase()

clone_hash = :crypto.hash(:sha256, repository_root) |> Base.encode16(case: :lower)
local_application_data = System.get_env("LOCALAPPDATA")

local_password_path =
  if is_binary(local_application_data) and local_application_data != "" do
    Path.join([local_application_data, "UOK-Next", "credentials", clone_hash, "uok-db-password"])
  end

database_password =
  System.get_env("UOK_DB_PASSWORD") ||
    if local_password_path do
      case File.read(local_password_path) do
        {:ok, value} -> String.trim(value)
        _ -> nil
      end
    end

unless is_binary(database_password) and
         Regex.match?(~r/\A[A-Za-z0-9._~-]{32,128}\z/, database_password) do
  raise "run scripts/start_local_postgres.ps1 to create the clone-local database credential"
end

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :uok_next, UokNext.Repo,
  username: System.get_env("UOK_DB_USER", "uok_next"),
  password: database_password,
  hostname: System.get_env("UOK_DB_HOST", "127.0.0.1"),
  port: String.to_integer(System.get_env("UOK_DB_PORT", "15432")),
  database:
    "#{System.get_env("UOK_TEST_DB_NAME", "uok_next_test")}#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :uok_next, UokNextWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "UdwJ7WlKN6qWV8PlsKLFL9nNHpeYtzGaV1IDServi1lDia4ZX3VHGl9eAHOhBFnw",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

config :uok_next, framework_spike_routes: true
config :uok_next, metrics_access_token: "uok-next-test-metrics-token-only"
config :uok_next, deployment_profile: :local_qualification
config :uok_next, allow_sql_sandbox_snapshot: true

config :uok_next, :local_qualification_identity, %{
  tenant_id: "11111111-1111-4111-8111-111111111111",
  actor_id: "22222222-2222-4222-8222-222222222222",
  access_code: "uok-next-test-access-code-00000001",
  permissions: [
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
  ]
}

config :uok_next, password_hash_iterations: 1_000

config :uok_next, :object_store,
  adapter: UokNext.ObjectStoreStub,
  max_object_bytes: 8_388_608

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
