defmodule UokNext.Kernel.CommandError do
  @moduledoc """
  Stable rejection contract for expected command failures.
  """

  @enforce_keys [:code, :message, :http_status]
  defstruct [:code, :message, :http_status, details: %{}]

  @type t :: %__MODULE__{
          code: String.t(),
          message: String.t(),
          http_status: pos_integer(),
          details: map()
        }

  @spec new(String.t(), String.t(), pos_integer(), map()) :: t()
  def new(code, message, http_status, details \\ %{}) do
    %__MODULE__{
      code: code,
      message: message,
      http_status: http_status,
      details: details
    }
  end
end
