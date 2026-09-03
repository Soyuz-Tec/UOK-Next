defmodule UokNext.Kernel.DurableWorkWorker do
  @moduledoc false

  use GenServer

  require Logger

  alias UokNext.Kernel.DurableWork

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @impl true
  def init(options) do
    send(self(), :drain)
    {:ok, options}
  end

  @impl true
  def handle_info(:drain, options) do
    case DurableWork.drain(options) do
      {:ok, _outcomes} -> :ok
      {:error, reason} -> Logger.error("durable work cycle failed: #{reason}")
    end

    Process.send_after(self(), :drain, options[:poll_interval_ms])
    {:noreply, options}
  end
end
