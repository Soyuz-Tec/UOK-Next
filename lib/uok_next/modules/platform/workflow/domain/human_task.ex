defmodule UokNext.Modules.Platform.Workflow.Domain.HumanTask do
  @moduledoc """
  Pure validation and lifecycle rules for a governed human task.
  """

  @identifier_pattern ~r/^[a-z][a-z0-9_.:-]{2,119}$/
  @subject_pattern ~r/^[a-z][a-z0-9_.:-]{1,119}$/
  @uuid_pattern ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
  @resolutions ~w(approve hold)

  @spec validate_open(map()) :: {:ok, map()} | {:error, map()}
  def validate_open(attrs) when is_map(attrs) do
    with {:ok, task_kind} <- identifier(value(attrs, :task_kind), :task_kind),
         {:ok, subject_type} <- subject_type(value(attrs, :subject_type)),
         {:ok, subject_id} <- uuid(value(attrs, :subject_id), :subject_id),
         {:ok, subject_version} <- version(value(attrs, :subject_version), :subject_version),
         {:ok, required_permission} <-
           identifier(value(attrs, :required_permission), :required_permission),
         {:ok, reason} <- reason(value(attrs, :reason)) do
      {:ok,
       %{
         task_kind: task_kind,
         subject_type: subject_type,
         subject_id: subject_id,
         subject_version: subject_version,
         required_permission: required_permission,
         reason: reason
       }}
    end
  end

  def validate_open(_attrs), do: error(:command, "must be an object")

  @spec validate_completion(map(), map()) :: {:ok, map()} | {:error, map()}
  def validate_completion(task, attrs) when is_map(task) and is_map(attrs) do
    with :ok <- open(task),
         {:ok, subject_type} <- subject_type(value(attrs, :subject_type)),
         {:ok, subject_id} <- uuid(value(attrs, :subject_id), :subject_id),
         {:ok, subject_version} <- version(value(attrs, :subject_version), :subject_version),
         :ok <- matching_subject(task, subject_type, subject_id, subject_version),
         {:ok, resolution} <- member(value(attrs, :resolution), :resolution, @resolutions),
         {:ok, reason} <- reason(value(attrs, :reason)) do
      {:ok, %{resolution: resolution, reason: reason}}
    end
  end

  def validate_completion(_task, _attrs), do: error(:command, "must be an object")

  defp open(%{status: "open"}), do: :ok
  defp open(_task), do: error(:status, "does not allow completion")

  defp matching_subject(task, subject_type, subject_id, subject_version) do
    if task.subject_type == subject_type and task.subject_id == subject_id and
         task.subject_version == subject_version do
      :ok
    else
      error(:subject, "does not match the governed task")
    end
  end

  defp identifier(value, field) when is_binary(value) do
    normalized = String.trim(value)
    if Regex.match?(@identifier_pattern, normalized), do: {:ok, normalized}, else: invalid(field)
  end

  defp identifier(_value, field), do: invalid(field)

  defp subject_type(value) when is_binary(value) do
    normalized = String.trim(value)

    if Regex.match?(@subject_pattern, normalized),
      do: {:ok, normalized},
      else: invalid(:subject_type)
  end

  defp subject_type(_value), do: invalid(:subject_type)

  defp uuid(value, field) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()
    if Regex.match?(@uuid_pattern, normalized), do: {:ok, normalized}, else: invalid_uuid(field)
  end

  defp uuid(_value, field), do: invalid_uuid(field)

  defp version(value, _field) when is_integer(value) and value > 0, do: {:ok, value}
  defp version(_value, field), do: error(field, "must be a positive integer")

  defp reason(value) when is_binary(value) do
    normalized = String.trim(value)
    length = String.length(normalized)

    if String.printable?(normalized) and length in 3..500 do
      {:ok, normalized}
    else
      error(:reason, "must contain 3 to 500 printable characters")
    end
  end

  defp reason(_value), do: error(:reason, "must contain 3 to 500 printable characters")

  defp member(value, field, allowed) do
    if value in allowed, do: {:ok, value}, else: error(field, "is not allowed")
  end

  defp invalid(field), do: error(field, "must contain a governed identifier")
  defp invalid_uuid(field), do: error(field, "must be a UUID")
  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  defp error(field, message), do: {:error, %{field: Atom.to_string(field), message: message}}
end
