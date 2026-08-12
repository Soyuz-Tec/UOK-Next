defmodule UokNextWeb.RequestCommand do
  @moduledoc false

  import Plug.Conn

  alias UokNext.Kernel.CommandError

  @spec idempotency_key(Plug.Conn.t()) :: {:ok, String.t()} | {:error, CommandError.t()}
  def idempotency_key(conn) do
    case get_req_header(conn, "idempotency-key") do
      [key] when byte_size(key) in 8..128 ->
        {:ok, key}

      _invalid ->
        {:error,
         CommandError.new(
           "invalid_idempotency_key",
           "one Idempotency-Key header containing 8 to 128 characters is required",
           400
         )}
    end
  end

  @spec positive_integer(term(), atom()) :: {:ok, pos_integer()} | {:error, CommandError.t()}
  def positive_integer(value, _field) when is_integer(value) and value > 0, do: {:ok, value}

  def positive_integer(value, field) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _invalid -> invalid_integer(field)
    end
  end

  def positive_integer(_value, field), do: invalid_integer(field)

  defp invalid_integer(field) do
    {:error, CommandError.new("invalid_request", "#{field} must be a positive integer", 400)}
  end
end
