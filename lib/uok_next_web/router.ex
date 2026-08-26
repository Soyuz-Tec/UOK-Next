defmodule UokNextWeb.Router do
  use UokNextWeb, :router

  @browser_security_headers %{
    "content-security-policy" =>
      "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; " <>
        "img-src 'self' data:; font-src 'self'; object-src 'none'; base-uri 'none'; " <>
        "frame-ancestors 'none'; form-action 'self'",
    "permissions-policy" => "camera=(), geolocation=(), microphone=(), payment=()",
    "referrer-policy" => "no-referrer",
    "x-frame-options" => "DENY"
  }

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :session_create do
    plug :accepts, ["json"]
    plug UokNextWeb.RequireJsonContentType
  end

  pipeline :authenticated_api do
    plug :accepts, ["json"]
    plug UokNextWeb.AuthenticateAccess
  end

  pipeline :browser do
    plug :accepts, ["html"]

    plug :put_secure_browser_headers, @browser_security_headers
  end

  scope "/", UokNextWeb do
    pipe_through :browser

    get "/", ShellController, :index
  end

  scope "/api/v1", UokNextWeb do
    pipe_through :api

    get "/health", HealthController, :show
    get "/health/live", HealthController, :live
    get "/health/ready", HealthController, :ready
    get "/health/startup", HealthController, :startup
    get "/release", HealthController, :release
    get "/metrics", MetricsController, :show
    get "/openapi.json", OpenApiController, :show
  end

  scope "/api/v1", UokNextWeb do
    pipe_through :session_create

    post "/session", SessionController, :create
  end

  scope "/api/v1", UokNextWeb do
    pipe_through :authenticated_api

    get "/session", SessionController, :show
    delete "/session", SessionController, :delete
    post "/session/password", SessionController, :change_password
    get "/identity/users", LocalUserController, :index
    post "/identity/users", LocalUserController, :create
    get "/identity/access-profiles", LocalUserController, :profiles
    get "/parties", PartyController, :index
    post "/parties", PartyController, :create
    get "/parties/:id", PartyController, :show
    post "/parties/:id/evidence", EvidenceController, :create
    post "/parties/:id/decision", PartyController, :decide
    get "/products", ProductController, :index
    post "/products", ProductController, :create
    get "/products/:id", ProductController, :show
    get "/locations", LocationController, :index
    post "/locations", LocationController, :create
    get "/locations/:id", LocationController, :show

    get "/location-references/major-seaports/countries",
        MajorSeaportReferenceController,
        :countries

    get "/location-references/major-seaports", MajorSeaportReferenceController, :index
    get "/sourcing-lanes", SourcingLaneController, :index
    post "/sourcing-lanes", SourcingLaneController, :create
    get "/sourcing-lanes/:id", SourcingLaneController, :show
    post "/sourcing-lanes/:id/evidence", SourcingLaneEvidenceController, :create
    post "/sourcing-lanes/:id/decision", SourcingLaneController, :decide
    get "/purchase-requisitions", ProcurementController, :requisitions_index
    post "/purchase-requisitions", ProcurementController, :requisition_create
    get "/rfqs", ProcurementController, :rfqs_index
    post "/rfqs", ProcurementController, :rfq_create
    get "/supplier-quotes", ProcurementController, :quotes_index
    post "/supplier-quotes", ProcurementController, :quote_create
    post "/supplier-quotes/:id/evidence", SupplierQuoteEvidenceController, :create
    get "/quote-comparisons", ProcurementController, :comparisons_index
    post "/quote-comparisons", ProcurementController, :comparison_create
    post "/quote-comparisons/:id/decision", ProcurementController, :comparison_decide
    get "/purchase-commitment-proposals", CommitmentController, :index
    post "/purchase-commitment-proposals", CommitmentController, :create

    post "/purchase-commitment-proposals/:id/evidence",
         PurchaseCommitmentEvidenceController,
         :create

    post "/purchase-commitment-proposals/:id/decision", CommitmentController, :decide
    get "/shipment-readiness-cases", ReadinessController, :index
    post "/shipment-readiness-cases", ReadinessController, :create

    post "/shipment-readiness-cases/:id/evidence",
         ReadinessEvidenceController,
         :create

    post "/shipment-readiness-cases/:id/decision", ReadinessController, :decide
    get "/operational-reports/:id", OperationalReportController, :show
    get "/review-tasks", WorkflowController, :index
  end

  if Application.compile_env(:uok_next, :framework_spike_routes, false) do
    scope "/api/v1/spikes", UokNextWeb.Spikes do
      pipe_through :api

      post "/:implementation/parties", PartyController, :create
      get "/:implementation/parties/:id", PartyController, :show
      post "/:implementation/parties/:id/evidence", PartyController, :submit_evidence
      post "/:implementation/parties/:id/decision", PartyController, :decide
    end
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:uok_next, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: UokNextWeb.Telemetry
    end
  end
end
