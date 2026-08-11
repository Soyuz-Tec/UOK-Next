import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :uok_next, UokNext.Repo,
  username: System.get_env("UOK_DB_USER", "uok_next"),
  password: System.get_env("UOK_DB_PASSWORD", "uok_next_local_only"),
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

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
