defmodule UokNext.Modules.Master.Products.Domain.Product do
  @moduledoc """
  Pure validation for governed product reference records.
  """

  @product_kinds ~w(commodity packaging service)
  @stable_identifier_pattern ~r/^[A-Za-z0-9][A-Za-z0-9._:\/-]{2,99}$/
  @unit_pattern ~r/^[A-Z][A-Z0-9._-]{0,15}$/

  @spec validate_create(map()) :: {:ok, map()} | {:error, map()}
  def validate_create(attrs) when is_map(attrs) do
    with {:ok, stable_identifier} <- stable_identifier(value(attrs, :stable_identifier)),
         {:ok, name} <- bounded_text(value(attrs, :name), :name, 2, 200),
         {:ok, product_kind} <- member(value(attrs, :product_kind), :product_kind, @product_kinds),
         {:ok, base_unit_code} <- unit_code(value(attrs, :base_unit_code)),
         {:ok, reason} <- bounded_text(value(attrs, :reason), :reason, 3, 500) do
      {:ok,
       %{
         stable_identifier: stable_identifier,
         name: name,
         product_kind: product_kind,
         base_unit_code: base_unit_code,
         reason: reason
       }}
    end
  end

  def validate_create(_attrs), do: error(:command, "must be an object")

  defp stable_identifier(value) when is_binary(value) do
    normalized = String.trim(value)

    if Regex.match?(@stable_identifier_pattern, normalized),
      do: {:ok, normalized},
      else: error(:stable_identifier, "must contain 3 to 100 safe characters")
  end

  defp stable_identifier(_value),
    do: error(:stable_identifier, "must contain 3 to 100 safe characters")

  defp unit_code(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.upcase()

    if Regex.match?(@unit_pattern, normalized),
      do: {:ok, normalized},
      else: error(:base_unit_code, "must be a governed unit code")
  end

  defp unit_code(_value), do: error(:base_unit_code, "must be a governed unit code")

  defp bounded_text(value, field, minimum, maximum) when is_binary(value) do
    normalized = String.trim(value)
    length = String.length(normalized)

    if String.printable?(normalized) and length in minimum..maximum,
      do: {:ok, normalized},
      else: error(field, "must contain #{minimum} to #{maximum} printable characters")
  end

  defp bounded_text(_value, field, minimum, maximum),
    do: error(field, "must contain #{minimum} to #{maximum} printable characters")

  defp member(value, field, allowed) do
    if value in allowed, do: {:ok, value}, else: error(field, "is not allowed")
  end

  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  defp error(field, message), do: {:error, %{field => [message]}}
end
