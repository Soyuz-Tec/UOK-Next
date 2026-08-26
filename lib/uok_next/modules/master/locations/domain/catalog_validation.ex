defmodule UokNext.Modules.Master.Locations.Domain.CatalogValidation do
  @moduledoc false

  @spec read_bounded!(Path.t(), pos_integer(), String.t()) :: binary()
  # Paths are compile-time application resources, never request-derived input.
  # sobelow_skip ["Traversal.FileModule"]
  def read_bounded!(path, maximum_bytes, label)
      when is_integer(maximum_bytes) and maximum_bytes > 0 do
    File.open!(path, [:read, :binary], fn device ->
      case IO.binread(device, maximum_bytes + 1) do
        data when is_binary(data) and byte_size(data) in 1..maximum_bytes//1 -> data
        data when is_binary(data) -> raise "#{label} exceeds its byte limit"
        :eof -> raise "#{label} is empty"
        {:error, reason} -> raise "#{label} could not be read: #{inspect(reason)}"
      end
    end)
  end

  @spec bounded_text?(term(), Range.t(), pos_integer()) :: boolean()
  def bounded_text?(value, grapheme_range, maximum_bytes)
      when is_struct(grapheme_range, Range) and is_integer(maximum_bytes) do
    is_binary(value) and String.length(value) in grapheme_range and
      byte_size(value) <= maximum_bytes
  end
end
