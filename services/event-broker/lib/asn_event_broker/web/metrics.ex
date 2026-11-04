defmodule AsnEventBroker.Web.Metrics do
  @moduledoc """
  Prometheus text exposition (ADR 0008 §11).

  Counters accumulate from the broker's own `:telemetry` events into an ETS
  table and stay exact between scrapes. Gauge-style database state (queue
  depths, oldest pending timestamp) is refreshed on
  `:metrics, :gauge_interval_ms` by this process and cached in a second ETS
  table, so `render/0` performs no database query. `/metrics` is
  unauthenticated: a scrape-time aggregate would let any caller turn a scrape
  into a full scan of `deliveries`.

  Payloads and tokens are never part of any metric.
  """

  use GenServer

  import Ecto.Query
  require Logger

  alias AsnEventBroker.Delivery.Delivery
  alias AsnEventBroker.Repo

  @table :asn_event_broker_metrics
  @gauges :asn_event_broker_gauges
  @handler_id "asn-event-broker-metrics"
  @default_gauge_interval_ms 5_000
  @empty_gauges %{pending: 0, leased: 0, dead: 0, oldest: nil}

  @counter_events [
    {[:publish, :accepted], %{name: :publish_accepted_total, labels: [:type, :outcome]}},
    {[:publish, :rejected], %{name: :publish_rejected_total, labels: [:reason]}},
    {[:ack], %{name: :acks_total, labels: []}},
    {[:nack], %{name: :nacks_total, labels: []}},
    {[:dead_letter], %{name: :dead_lettered_total, labels: []}},
    {[:lease_expired], %{name: :lease_expired_total, labels: []}},
    {[:replay], %{name: :replays_total, labels: []}},
    {[:skip], %{name: :skips_total, labels: []}},
    {[:retention_purge], %{name: :retention_purged_total, labels: []}}
  ]

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(@gauges, [:named_table, :set, :public, read_concurrency: true])

    :telemetry.attach_many(
      @handler_id,
      Enum.map(@counter_events, fn {event, _} -> [:asn_event_broker | event] end),
      &__MODULE__.handle_event/4,
      @handler_id
    )

    interval_ms = gauge_interval_ms()
    if interval_ms > 0, do: Process.send_after(self(), :refresh_gauges, 0)

    {:ok, %{interval_ms: interval_ms}}
  end

  @impl true
  def handle_info(:refresh_gauges, %{interval_ms: interval_ms} = state) do
    refresh()

    if interval_ms > 0, do: Process.send_after(self(), :refresh_gauges, interval_ms)

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @doc "Telemetry handler; attached once by this process."
  def handle_event([:asn_event_broker | event], measurements, metadata, handler_id) do
    case Enum.find(@counter_events, fn {e, _} -> e == event end) do
      {_, %{name: name, labels: label_keys}} ->
        labels =
          label_keys
          |> Enum.map(fn key -> ~s(#{key}="#{escape(label_value(metadata[key]))}") end)
          |> Enum.join(",")

        key = {name, labels}

        :ets.update_counter(
          @table,
          key,
          {2, Map.get(measurements, :count, 1)},
          {key, 0}
        )

      nil ->
        :ok
    end
  rescue
    ArgumentError ->
      # The metrics table can be gone while a handler is still attached (for
      # example during shutdown). Detach rather than crash the emitter.
      if handler_id, do: :telemetry.detach(handler_id)
      :ok
  end

  @doc """
  Recomputes the cached gauges from the database.

  Runs in the caller, which lets a test call it inside its sandbox checkout;
  the scheduled refresh calls it from this process. A database failure keeps
  the previous values instead of crashing the metrics process (and losing the
  counters, which live in its ETS table).
  """
  @spec refresh() :: :ok
  def refresh do
    :ets.insert(@gauges, {:gauges, gauge_state()})
    :ok
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] ->
      Logger.warning(
        "metrics gauge refresh failed, keeping the previous values: " <>
          Exception.message(error)
      )

      :ok
  end

  @doc "Renders the Prometheus text exposition."
  @spec render() :: String.t()
  def render do
    counters = render_counters()
    gauges = render_gauges(cached_gauges())

    IO.iodata_to_binary([counters, gauges])
  end

  defp render_counters do
    rows = :ets.tab2list(@table)

    rows
    |> Enum.map(fn {{name, _}, _} -> name end)
    |> Enum.uniq()
    |> Enum.map(fn name ->
      header =
        "# TYPE asn_event_broker_#{name} counter\n" <>
          "# HELP asn_event_broker_#{name} broker #{String.replace(to_string(name), "_", " ")}\n"

      series =
        rows
        |> Enum.filter(fn {{n, _}, _} -> n == name end)
        |> Enum.sort()
        |> Enum.map(fn {{_name, labels}, value} ->
          "asn_event_broker_#{name}{#{labels}} #{value}\n"
        end)

      [header | series]
    end)
  end

  defp render_gauges(%{pending: pending, leased: leased, dead: dead, oldest: oldest}) do
    [
      gauge("pending", "pending deliveries", pending),
      gauge("leased", "in-flight (leased) deliveries", leased),
      gauge("dead", "dead deliveries awaiting replay or skip", dead),
      gauge(
        "oldest_pending_seconds",
        "age of the oldest pending delivery",
        oldest_pending_age(oldest)
      )
    ]
  end

  defp cached_gauges do
    if :ets.whereis(@gauges) == :undefined do
      @empty_gauges
    else
      case :ets.lookup(@gauges, :gauges) do
        [{:gauges, gauges}] -> gauges
        [] -> @empty_gauges
      end
    end
  end

  defp gauge(name, help, value) do
    "# TYPE asn_event_broker_#{name} gauge\n# HELP asn_event_broker_#{name} #{help}\nasn_event_broker_#{name} #{value}\n"
  end

  # One round trip per refresh; FILTER aggregates return all four values.
  defp gauge_state do
    Repo.one!(
      from d in Delivery,
        select: %{
          pending: filter(count(d.id), d.state == :pending),
          leased: filter(count(d.id), d.state == :leased),
          dead: filter(count(d.id), d.state == :dead),
          oldest: filter(min(d.created_at), d.state == :pending)
        }
    )
  end

  defp oldest_pending_age(nil), do: 0

  defp oldest_pending_age(%DateTime{} = oldest) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    DateTime.diff(now, oldest)
  end

  defp gauge_interval_ms do
    :asn_event_broker
    |> Application.get_env(:metrics, [])
    |> Keyword.get(:gauge_interval_ms, @default_gauge_interval_ms)
  end

  defp escape(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end

  defp label_value(nil), do: "unknown"
  defp label_value(value) when is_atom(value), do: to_string(value)
  defp label_value(value) when is_binary(value), do: value
  defp label_value(value), do: to_string(inspect(value))
end
