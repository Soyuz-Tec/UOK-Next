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
  required_schema_version: 20_260_811_102_000

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

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
