defmodule UokNext.Modules.Platform.Evidence.Infrastructure.BoundedReqHttpClientTest do
  use ExUnit.Case, async: true

  alias UokNext.Modules.Platform.Evidence.Infrastructure.BoundedReqHttpClient

  test "returns a bounded provider response as a binary" do
    body = String.duplicate("a", 65_536)

    assert {:ok, %{status_code: 200, body: ^body}} =
             BoundedReqHttpClient.request(:get, "http://provider.invalid", "", [],
               plug: response_plug(200, body)
             )
  end

  test "fails closed before returning an oversized provider response" do
    body = String.duplicate("a", 65_537)

    assert {:error, %{reason: :response_too_large}} =
             BoundedReqHttpClient.request(:get, "http://provider.invalid", "", [],
               plug: response_plug(200, body)
             )
  end

  test "does not follow provider redirects" do
    plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "http://redirect.invalid")
      |> Plug.Conn.send_resp(302, "redirect")
    end

    assert {:ok, %{status_code: 302, body: "redirect"}} =
             BoundedReqHttpClient.request(:get, "http://provider.invalid", "", [], plug: plug)
  end

  defp response_plug(status, body) do
    fn conn -> Plug.Conn.send_resp(conn, status, body) end
  end
end
