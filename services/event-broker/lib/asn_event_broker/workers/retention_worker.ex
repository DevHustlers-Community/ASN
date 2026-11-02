defmodule AsnEventBroker.Workers.RetentionWorker do
  @moduledoc """
  Schedules the dependency-aware retention purge (ADR 0008 §8). Purge
  frequency is `:retention_interval_ms` in the `:retention` config.

  The logic lives in `Retention.purge/1` so tests call it directly; the
  GenServer is only the scheduler and is disabled under the test sandbox.
  """

  use GenServer

  require Logger

  alias AsnEventBroker.Retention

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    schedule_purge()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:purge, state) do
    log_purge(Retention.purge())
    schedule_purge()
    {:noreply, state}
  end

  defp log_purge(%{delivered: d, terminal: t, events: e}) when d + t + e > 0,
    do: Logger.info("retention purge: #{d} delivered, #{t} terminal, #{e} events deleted")

  defp log_purge(_), do: :ok

  defp schedule_purge, do: Process.send_after(self(), :purge, interval_ms())

  defp interval_ms,
    do:
      Keyword.fetch!(
        Application.fetch_env!(:asn_event_broker, :retention),
        :retention_interval_ms
      )
end
