# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :uok_next,
  build_revision: System.get_env("UOK_BUILD_REVISION", "uncommitted"),
  ecto_repos: [UokNext.Repo],
  generators: [timestamp_type: :utc_datetime_usec, binary_id: true],
  required_schema_version: 20_260_905_010_000,
  communications_adapter: :disabled,
  password_hash_iterations: 600_000,
  database_target_major: 19,
  database_prerelease_allowed: true

config :uok_next, :durable_work,
  enabled: false,
  repo: UokNext.OutboxRepo,
  publisher: UokNext.Kernel.PostgresOutboxPublisher,
  poll_interval_ms: 1_000,
  batch_size: 25,
  lease_ms: 30_000,
  max_attempts: 5,
  base_backoff_ms: 1_000,
  max_backoff_ms: 60_000

config :uok_next, UokNext.Repo, migration_lock: :table_lock

config :ex_aws,
  http_client: UokNext.Modules.Platform.Evidence.Infrastructure.BoundedReqHttpClient,
  json_codec: Jason

config :ex_aws, :req_opts,
  connect_options: [timeout: 2_000],
  receive_timeout: 5_000,
  retry: false,
  raw: true

config :ex_aws_s3, :content_hash_algorithm, :sha256

# Configure the endpoint
config :uok_next, UokNextWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: UokNextWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: UokNext.PubSub,
  live_view: [signing_salt: "fildX14x"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :tenant_id, :actor_id, :correlation_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason
config :phoenix, :filter_parameters, ["password", "access_code", "credential", "secret", "token"]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
