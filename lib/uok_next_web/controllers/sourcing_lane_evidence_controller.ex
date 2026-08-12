defmodule UokNextWeb.SourcingLaneEvidenceController do
  use UokNextWeb, :controller

  alias UokNext.Kernel.{CommandError, IdempotencyKey}
  alias UokNext.Modules.Platform.Evidence.Public, as: Evidence
  alias UokNext.Modules.Trade.Sourcing.Public, as: Sourcing
  alias UokNextWeb.{ApiResponse, RequestCommand}

  @maximum_bytes 8_388_608

  def create(%{assigns: %{command_context: context}} = conn, %{"id" => lane_id} = params) do
    with {:ok, key} <- RequestCommand.idempotency_key(conn),
         {:ok, version} <-
           RequestCommand.positive_integer(params["expected_version"], :expected_version),
         {:ok, evidence_id} <- uuid(params["evidence_id"]),
         {:ok, candidate} <-
           find_or_store_candidate(lane_id, evidence_id, version, params, context, key) do
      result =
        Sourcing.submit_evidence(
          lane_id,
          %{"evidence_id" => candidate["id"], "reason" => params["reason"]},
          version,
          context,
          IdempotencyKey.derive(key, "sourcing-lane-evidence-submit")
        )

      ApiResponse.command(conn, result, :ok)
    else
      {:error, %CommandError{} = error} -> ApiResponse.error(conn, error)
      {:error, reason} -> ApiResponse.error(conn, storage_error(reason))
    end
  end

  defp find_or_store_candidate(lane_id, evidence_id, version, params, context, key) do
    case Evidence.get_verified_candidate(evidence_id, "sourcing_lane", lane_id, context) do
      {:ok, candidate} ->
        {:ok, candidate}

      {:error, %CommandError{code: "not_found"}} ->
        store_new_candidate(lane_id, evidence_id, version, params, context, key)

      {:error, %CommandError{} = error} ->
        {:error, error}
    end
  end

  defp store_new_candidate(lane_id, evidence_id, version, params, context, key) do
    with :ok <- Sourcing.preflight_evidence(lane_id, version, context),
         {:ok, upload, content} <- bounded_upload(params["file"]),
         {:ok, candidate, _disposition} <-
           Evidence.store_candidate(
             evidence_id,
             "sourcing_lane",
             lane_id,
             upload_attrs(params, upload),
             content,
             context,
             key
           ) do
      {:ok, candidate}
    end
  end

  # The temporary path is created by Plug's multipart parser and cannot be
  # selected by a serialized client payload. Metadata remains untrusted.
  # sobelow_skip ["Traversal.FileModule"]
  defp bounded_upload(%Plug.Upload{} = upload) do
    with {:ok, %{type: :regular, size: size}} when size in 1..@maximum_bytes <-
           File.stat(upload.path),
         {:ok, content} when byte_size(content) == size <- File.read(upload.path) do
      {:ok, upload, content}
    else
      _invalid ->
        {:error, CommandError.new("invalid_upload", "file must contain 1 to 8388608 bytes", 422)}
    end
  end

  defp bounded_upload(_missing),
    do: {:error, CommandError.new("invalid_upload", "one evidence file is required", 422)}

  defp upload_attrs(params, upload) do
    %{
      "classification" => params["classification"],
      "content_type" => upload.content_type,
      "reason" => params["reason"]
    }
  end

  defp uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, CommandError.new("invalid_request", "evidence_id must be a UUID", 400)}
    end
  end

  defp storage_error(reason)
       when reason in [:object_store_unavailable, :object_store_integrity_failure],
       do: CommandError.new("evidence_store_unavailable", "evidence storage is unavailable", 503)

  defp storage_error(_reason),
    do: CommandError.new("invalid_upload", "evidence upload was rejected", 422)
end
