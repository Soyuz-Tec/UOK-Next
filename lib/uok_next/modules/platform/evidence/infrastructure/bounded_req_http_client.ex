defmodule UokNext.Modules.Platform.Evidence.Infrastructure.BoundedReqHttpClient do
  @moduledoc """
  ExAws HTTP client that fails closed when a control response exceeds 64 KiB.

  S3 control operations normally return empty or small XML bodies. Streaming
  them through a fixed collector prevents a dishonest provider from exhausting
  the BEAM before the evidence adapter can normalize the response.
  """

  @behaviour ExAws.Request.HttpClient

  @maximum_response_bytes 65_536
  @default_options [receive_timeout: 30_000]

  @impl true
  def request(method, url, body \\ "", headers \\ [], http_options \\ []) do
    options =
      [method: method, url: url, body: body, headers: headers]
      |> Keyword.merge(Application.get_env(:ex_aws, :req_opts, @default_options))
      |> Keyword.merge(normalize_http_options(http_options))
      |> Keyword.put(:decode_body, false)
      |> Keyword.put(:retry, false)
      |> Keyword.put(:redirect, false)
      |> Keyword.put(:raw, true)
      |> Keyword.put(:into, bounded_collector())

    case Req.request(options) do
      {:ok, response} -> normalize_response(response)
      {:error, reason} -> {:error, %{reason: reason}}
    end
  rescue
    _error -> {:error, %{reason: :request_failed}}
  catch
    _kind, _reason -> {:error, %{reason: :request_failed}}
  end

  defp normalize_response(response) do
    case bounded_body(response.body) do
      {:ok, body} ->
        {:ok,
         %{
           status_code: response.status,
           headers: Req.get_headers_list(response),
           body: body
         }}

      {:error, :response_too_large} ->
        {:error, %{reason: :response_too_large}}
    end
  end

  defp bounded_body(%{bytes: bytes, chunks: chunks, overflow?: false})
       when bytes <= @maximum_response_bytes,
       do: {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}

  defp bounded_body(body) when is_binary(body) and byte_size(body) <= @maximum_response_bytes,
    do: {:ok, body}

  defp bounded_body(_body), do: {:error, :response_too_large}

  defp bounded_collector do
    fn {:data, data}, {request, response} ->
      state = response_state(response.body)
      received_bytes = state.bytes + byte_size(data)
      overflow? = received_bytes > @maximum_response_bytes

      response = %{
        response
        | body: %{
            bytes: received_bytes,
            chunks: if(overflow?, do: [], else: [data | state.chunks]),
            overflow?: overflow?
          }
      }

      if overflow?, do: {:halt, {request, response}}, else: {:cont, {request, response}}
    end
  end

  defp response_state(%{bytes: bytes, chunks: chunks, overflow?: overflow?})
       when is_integer(bytes) and is_list(chunks) and is_boolean(overflow?),
       do: %{bytes: bytes, chunks: chunks, overflow?: overflow?}

  defp response_state(_initial_body), do: %{bytes: 0, chunks: [], overflow?: false}

  defp normalize_http_options(options) do
    {receive_timeout, options} = Keyword.pop(options, :recv_timeout)
    options = Keyword.delete(options, :follow_redirect)

    if is_nil(receive_timeout),
      do: options,
      else: Keyword.put(options, :receive_timeout, receive_timeout)
  end
end
