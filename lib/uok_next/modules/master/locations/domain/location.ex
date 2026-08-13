defmodule UokNext.Modules.Master.Locations.Domain.Location do
  @moduledoc "Pure validation for governed location reference records."

  @location_kinds ~w(country region locality port facility)
  @stable_identifier_pattern ~r/^[A-Za-z0-9][A-Za-z0-9._:\/-]{2,99}$/

  @spec validate_create(map()) :: {:ok, map()} | {:error, map()}
  def validate_create(attrs) when is_map(attrs) do
    with {:ok, stable_identifier} <- stable_identifier(value(attrs, :stable_identifier)),
         {:ok, name} <- bounded_text(value(attrs, :name), :name, 2, 200),
         {:ok, country_code} <- country_code(value(attrs, :country_code)),
         {:ok, location_kind} <-
           member(value(attrs, :location_kind), :location_kind, @location_kinds),
         {:ok, reason} <- bounded_text(value(attrs, :reason), :reason, 3, 500) do
      {:ok,
       %{
         stable_identifier: stable_identifier,
         name: name,
         country_code: country_code,
         location_kind: location_kind,
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

  defp country_code(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.upcase()

    if Regex.match?(~r/^[A-Z]{2}$/, normalized),
      do: {:ok, normalized},
      else: error(:country_code, "must be a two-letter code")
  end

  defp country_code(_value), do: error(:country_code, "must be a two-letter code")

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
