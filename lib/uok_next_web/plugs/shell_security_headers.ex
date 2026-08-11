defmodule UokNextWeb.ShellSecurityHeaders do
  @moduledoc """
  Applies the repository-owned browser policy before Phoenix serves shell assets.
  """

  @behaviour Plug

  @headers %{
    "content-security-policy" =>
      "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; " <>
        "img-src 'self' data:; font-src 'self'; object-src 'none'; base-uri 'none'; " <>
        "frame-ancestors 'none'; form-action 'self'",
    "permissions-policy" => "camera=(), geolocation=(), microphone=(), payment=()",
    "referrer-policy" => "no-referrer",
    "x-frame-options" => "DENY"
  }

  @spec headers() :: %{String.t() => String.t()}
  def headers, do: @headers

  @impl Plug
  def init(options), do: options

  @impl Plug
  def call(%Plug.Conn{path_info: ["uok-ui" | _rest]} = conn, _options) do
    Phoenix.Controller.put_secure_browser_headers(conn, @headers)
  end

  def call(conn, _options), do: conn
end
