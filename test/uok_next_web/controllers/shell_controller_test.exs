defmodule UokNextWeb.ShellControllerTest do
  use UokNextWeb.ConnCase, async: true

  test "GET / directs clients to the compiled shell without caching", %{conn: conn} do
    response_conn = get(conn, ~p"/")

    assert redirected_to(response_conn, 302) == "/uok-ui/index.html"
    assert get_resp_header(response_conn, "cache-control") == ["no-store"]

    assert get_resp_header(response_conn, "content-security-policy") == [
             UokNextWeb.ShellSecurityHeaders.headers()["content-security-policy"]
           ]
  end

  test "compiled shell uses a restrictive delivery policy", %{conn: conn} do
    response_conn = get(conn, "/uok-ui/index.html")

    assert html_response(response_conn, 200) =~ "<title>UOK Next</title>"
    assert get_resp_header(response_conn, "cache-control") == ["no-store"]
    assert get_resp_header(response_conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(response_conn, "referrer-policy") == ["no-referrer"]

    assert get_resp_header(response_conn, "permissions-policy") == [
             "camera=(), geolocation=(), microphone=(), payment=()"
           ]

    [content_security_policy] = get_resp_header(response_conn, "content-security-policy")
    assert content_security_policy =~ "default-src 'none'"
    assert content_security_policy =~ "frame-ancestors 'none'"
    assert content_security_policy =~ "connect-src 'self'"
  end
end
