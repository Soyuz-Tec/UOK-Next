import Config

# Force using SSL in production. This also sets the "strict-security-transport" header,
# known as HSTS. If you have a health check endpoint, you may want to exclude it below.
# Note `:force_ssl` is required to be set at compile-time.
config :uok_next, UokNextWeb.Endpoint,
  force_ssl: [
    exclude: [
      conn: {UokNextWeb.LocalQualificationTransport, :http_allowed?, []},
      paths: [
        "/api/v1/health",
        "/api/v1/health/live",
        "/api/v1/health/ready",
        "/api/v1/health/startup",
        "/api/v1/release",
        "/api/v1/metrics"
      ]
    ]
  ]

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
