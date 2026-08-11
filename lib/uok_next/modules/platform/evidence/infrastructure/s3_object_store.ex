defmodule UokNext.Modules.Platform.Evidence.Infrastructure.S3ObjectStore do
  @moduledoc """
  S3-compatible adapter for the provider-neutral evidence-object port.

  The adapter uses path-style addressing, bounded timeouts, immutable keys, and
  normalized errors that never expose credentials, signed URLs, or provider
  response bodies. Read URLs are signed for sixty seconds and remain internal
  to this server-side adapter.
  """

  @behaviour UokNext.Modules.Platform.Evidence.Application.ObjectStore

  alias ExAws.S3
  alias UokNext.Modules.Platform.Evidence.Domain.EvidenceObject

  @impl true
  def ready? do
    case request(S3.head_bucket(bucket())) do
      {:ok, _response} -> :ok
      {:error, _reason} -> {:error, :object_store_unavailable}
    end
  end

  @impl true
  def put(%EvidenceObject{} = evidence, content) do
    options = [
      content_type: evidence.content_type,
      content_length: Integer.to_string(evidence.byte_size),
      if_none_match: "*"
    ]

    with :ok <- EvidenceObject.verify_content(evidence, content),
         {:ok, response} <-
           request(S3.put_object(bucket(), evidence.object_key, content, options)) do
      {:ok, receipt(evidence, response)}
    end
  end

  @impl true
  def fetch(%EvidenceObject{} = evidence) do
    with {:ok, head} <- request(S3.head_object(bucket(), evidence.object_key)),
         :ok <- verify_content_length(head, evidence.byte_size),
         {:ok, signed_url} <- signed_read_url(evidence),
         {:ok, content} <- fetch_signed_content(signed_url, evidence.byte_size),
         :ok <- EvidenceObject.verify_content(evidence, content) do
      {:ok, content}
    else
      {:error, :not_found} -> {:error, :not_found}
      _error -> {:error, :object_store_integrity_failure}
    end
  end

  @impl true
  def delete(%EvidenceObject{} = evidence) do
    case request(S3.delete_object(bucket(), evidence.object_key)) do
      {:ok, _response} -> :ok
      {:error, _reason} -> {:error, :object_store_unavailable}
    end
  end

  defp request(operation) do
    case ExAws.request(operation, request_config()) do
      {:ok, response} -> {:ok, response}
      {:error, {:http_error, 404, _response}} -> {:error, :not_found}
      {:error, _reason} -> {:error, :object_store_unavailable}
    end
  rescue
    _error -> {:error, :object_store_unavailable}
  catch
    _kind, _reason -> {:error, :object_store_unavailable}
  end

  defp request_config do
    config = object_store_config()

    [
      access_key_id: Keyword.fetch!(config, :access_key_id),
      secret_access_key: Keyword.fetch!(config, :secret_access_key),
      region: Keyword.fetch!(config, :region),
      scheme: Keyword.fetch!(config, :scheme),
      host: Keyword.fetch!(config, :host),
      port: Keyword.fetch!(config, :port),
      retries: [max_attempts: 1]
    ]
  end

  defp signed_read_url(evidence) do
    :s3
    |> ExAws.Config.new(request_config())
    |> S3.presigned_url(:get, bucket(), evidence.object_key, expires_in: 60)
    |> case do
      {:ok, signed_url} when is_binary(signed_url) -> {:ok, signed_url}
      _error -> {:error, :object_store_unavailable}
    end
  end

  defp fetch_signed_content(signed_url, expected_bytes) do
    case Req.get(signed_url,
           connect_options: [timeout: 2_000],
           receive_timeout: 5_000,
           retry: false,
           redirect: false,
           decode_body: false,
           raw: true,
           into: bounded_collector(expected_bytes)
         ) do
      {:ok, %Req.Response{status: 200, body: {^expected_bytes, chunks}}} ->
        {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      _error ->
        {:error, :object_store_unavailable}
    end
  rescue
    _error -> {:error, :object_store_unavailable}
  catch
    _kind, _reason -> {:error, :object_store_unavailable}
  end

  defp bounded_collector(expected_bytes) do
    fn {:data, data}, {request, response} ->
      {current_bytes, chunks} =
        case response.body do
          {bytes, accumulated} when is_integer(bytes) and is_list(accumulated) ->
            {bytes, accumulated}

          _initial_body ->
            {0, []}
        end

      received_bytes = current_bytes + byte_size(data)
      body = {received_bytes, [data | chunks]}
      response = %{response | body: body}

      if received_bytes <= expected_bytes do
        {:cont, {request, response}}
      else
        {:halt, {request, response}}
      end
    end
  end

  defp receipt(evidence, response) do
    %{
      provider: "s3",
      bucket: bucket(),
      key: evidence.object_key,
      etag: response_header(response, "etag")
    }
  end

  defp verify_content_length(response, expected_bytes) do
    case response_header(response, "content-length") do
      value when is_binary(value) -> parse_content_length(value, expected_bytes)
      _missing -> {:error, :invalid_content_length}
    end
  end

  defp parse_content_length(value, expected_bytes) do
    case Integer.parse(value) do
      {^expected_bytes, ""} -> :ok
      _invalid -> {:error, :invalid_content_length}
    end
  end

  defp response_header(%{headers: headers}, name) when is_list(headers) do
    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(to_string(key)) == name, do: to_string(value)
    end)
  end

  defp response_header(_response, _name), do: nil
  defp bucket, do: Keyword.fetch!(object_store_config(), :bucket)
  defp object_store_config, do: Application.fetch_env!(:uok_next, :object_store)
end
