defmodule UokNext.Security.HttpResponseLimitsTest do
  use ExUnit.Case, async: true

  alias UokNext.Modules.Platform.Evidence.Infrastructure.BoundedReqHttpClient

  @moduletag timeout: 10_000
  @request_timeout 2_000
  @chunked_headers "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"

  test "accepts ordinary and chunked responses, including a legal chunk extension" do
    responses = [
      "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK",
      @chunked_headers <> "2;source=fixture\r\nOK\r\n0\r\n\r\n"
    ]

    for response <- responses do
      assert {:ok, %{status_code: 200, body: "OK"}} = request_from_server(response)
    end
  end

  test "rejects an unterminated oversized status line before a transport timeout" do
    response = "HTTP/1.1 200 " <> String.duplicate("x", 270_000)

    assert_line_limit(request_from_server(response), byte_size(response))
  end

  test "rejects an unterminated oversized chunk extension before a transport timeout" do
    response = @chunked_headers <> "1;" <> String.duplicate("x", 270_000)

    assert_line_limit(request_from_server(response), byte_size(response))
  end

  test "rejects excessive chunk-size digits before waiting for a line terminator" do
    response = @chunked_headers <> String.duplicate("f", 16_384)

    assert {:error, %{reason: %Req.HTTPError{protocol: :http1, reason: :invalid_chunk_size}}} =
             request_from_server(response)
  end

  defp assert_line_limit(result, sent_bytes) do
    assert {:error,
            %{
              reason: %Req.HTTPError{
                protocol: :http1,
                reason: {:response_line_too_long, size, limit}
              }
            }} =
             result

    assert limit > 0 and limit <= 262_144
    assert size > limit and size <= sent_bytes
  end

  defp request_from_server(response) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false, packet: :raw])

    {:ok, {{127, 0, 0, 1}, port}} = :inet.sockname(listener)
    server = Task.async(fn -> serve_response(listener, response) end)

    try do
      result =
        BoundedReqHttpClient.request(:get, "http://127.0.0.1:#{port}/", "", [],
          connect_options: [timeout: @request_timeout, protocols: [:http1]],
          receive_timeout: @request_timeout,
          request_timeout: @request_timeout
        )

      send(server.pid, :close)
      assert :ok = Task.await(server, @request_timeout)
      result
    after
      Task.shutdown(server, :brutal_kill)
      :gen_tcp.close(listener)
    end
  end

  defp serve_response(listener, response) do
    {:ok, socket} = :gen_tcp.accept(listener, @request_timeout)

    try do
      {:ok, _request} = :gen_tcp.recv(socket, 0, @request_timeout)
      :ok = :gen_tcp.send(socket, response)

      # Keep incomplete malicious lines open until the client returns: EOF or
      # receive timeout must not masquerade as successful parser protection.
      receive do
        :close -> :ok
      after
        5_000 -> raise "HTTP response client did not finish within its deadline"
      end
    after
      :gen_tcp.close(socket)
    end
  end
end
