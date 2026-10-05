defmodule UokNext.Modules.Platform.Evidence.Infrastructure.HttpTransportSecurityTest do
  use ExUnit.Case, async: true

  @line_limit 256
  @chunked_headers "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"

  for {name, prefix} <- [
        {"status", "HTTP/1.1 200 "},
        {"chunk extension", @chunked_headers <> "1;"}
      ] do
    test "rejects an unterminated #{name} line at the configured limit" do
      {conn, _ref} = connection(Mint.HTTP1, max_header_list_size: @line_limit)
      response = unquote(prefix) <> String.duplicate("a", @line_limit + 1)

      assert {:error, _conn,
              %Mint.HTTPError{reason: {:response_line_too_long, size, @line_limit}}, _responses} =
               stream(conn, response)

      assert size > @line_limit
    end
  end

  test "rejects excessive chunk-size digits before receiving a body" do
    {conn, _ref} = connection(Mint.HTTP1)
    response = @chunked_headers <> String.duplicate("f", 33)

    assert {:error, _conn, %Mint.HTTPError{reason: :invalid_chunk_size}, _responses} =
             stream(conn, response)
  end

  test "accepts a legitimate chunked response with an extension" do
    {conn, ref} = connection(Mint.HTTP1, max_header_list_size: @line_limit)

    assert {:ok, _conn,
            [
              {:status, ^ref, 200},
              {:headers, ^ref, _headers},
              {:data, ^ref, "hello"},
              {:done, ^ref}
            ]} = stream(conn, @chunked_headers <> "5;source=proof\r\nhello\r\n0\r\n\r\n")
  end

  test "rejects malformed chunk extensions instead of accepting ambiguous framing" do
    {conn, _ref} = connection(Mint.HTTP1)

    assert {:error, _conn, %Mint.HTTPError{reason: :invalid_chunk_size}, _responses} =
             stream(conn, @chunked_headers <> "5 invalid\r\nhello\r\n0\r\n\r\n")
  end

  test "uses close-delimited framing when chunked is not the final transfer coding" do
    {conn, ref} = connection(Mint.HTTP1)
    body = "5\r\nhello\r\n0\r\n\r\n"
    response = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked, gzip\r\n\r\n" <> body

    assert {:ok, conn, [{:status, ^ref, 200}, {:headers, ^ref, _headers}, {:data, ^ref, ^body}]} =
             stream(conn, response)

    assert {:ok, _conn, [{:done, ^ref}]} =
             Mint.HTTP.stream(conn, {:tcp_closed, Mint.HTTP.get_socket(conn)})
  end

  test "bounds the decoded HTTP/2 header list before joining indexed cookies" do
    {conn, ref} = connection(Mint.HTTP2, client_settings: [max_header_list_size: @line_limit])
    headers = [{":status", "200"} | List.duplicate({"cookie", String.duplicate("a", 64)}, 6)]
    {encoded, _table} = HPAX.encode(:store, headers, HPAX.new(4_096))
    payload = IO.iodata_to_binary(encoded)
    assert byte_size(payload) < @line_limit
    frame = headers_frame(conn, ref, payload)

    assert {:ok, _conn,
            [
              {:error, ^ref,
               %Mint.HTTPError{reason: {:max_header_list_size_exceeded, size, @line_limit}}}
            ]} =
             stream(conn, frame)

    assert size > @line_limit
  end

  test "accepts a legitimate HTTP/2 response within the decoded header limit" do
    {conn, ref} = connection(Mint.HTTP2, client_settings: [max_header_list_size: @line_limit])
    headers = [{":status", "200"}, {"cookie", "source=proof"}]
    {encoded, _table} = HPAX.encode(:store, headers, HPAX.new(4_096))
    frame = headers_frame(conn, ref, IO.iodata_to_binary(encoded))

    assert {:ok, _conn,
            [{:status, ^ref, 200}, {:headers, ^ref, [{"cookie", "source=proof"}]}, {:done, ^ref}]} =
             stream(conn, frame)
  end

  test "rejects an oversized HTTP/2 frame from its header without buffering its payload" do
    {conn, _ref} = connection(Mint.HTTP2)
    frame_header = <<16_385::24, 0, 0, 0::1, 1::31>>

    assert {:error, _conn, %Mint.HTTPError{reason: {:frame_size_error, _details}}, []} =
             stream(conn, frame_header)
  end

  defp connection(protocol, options \\ []) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    on_exit(fn -> :gen_tcp.close(listener) end)
    {:ok, {_address, port}} = :inet.sockname(listener)
    {:ok, conn} = protocol.connect(:http, "127.0.0.1", port, options)
    socket = Mint.HTTP.get_socket(conn)
    on_exit(fn -> :gen_tcp.close(socket) end)

    conn =
      if protocol == Mint.HTTP2 do
        {:ok, conn, []} = stream(conn, <<0::24, 4, 0, 0::1, 0::31>>)
        conn
      else
        conn
      end

    {:ok, conn, ref} = Mint.HTTP.request(conn, "GET", "/", [], nil)
    {conn, ref}
  end

  defp stream(conn, bytes), do: Mint.HTTP.stream(conn, {:tcp, Mint.HTTP.get_socket(conn), bytes})

  defp headers_frame(conn, ref, payload) do
    stream_id = Map.fetch!(conn.ref_to_stream_id, ref)
    <<byte_size(payload)::24, 1, 5, 0::1, stream_id::31, payload::binary>>
  end
end
