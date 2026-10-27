defmodule AsnEventBroker.Web.Metrics do
  @moduledoc """
  Prometheus text exposition (ADR 0008 §11).

  Counters accumulate from the broker's own `:telemetry` events into an ETS
  table; gauge-style database state (queue depths, oldest pending age) is
  queried at scrape time. Payloads and tokens are never part of any metric.
  """

  use GenServer

  import Ecto.Query

  alias AsnEventBroker.Delivery.Delivery
  alias AsnEventBroker.Repo

  @table :asn_event_broker_metrics

  @counter_events [
    {[:publish, :accepted], %{name: :publish_accepted_total, labels: [:type, :outcome]}},
    {[:publish, :rejected], %{name: :publish_rejected_total, labels: [:reason]}},
    {[:ack], %{name: :acks_total, labels: []}},
    {[:dead_letter], %{name: :dead_lettered_total, labels: []}},
    {[:lease_expired], %{name: :lease_expired_total, labels: []}},
    {[:retention_purge], %{name: :retention_purged_total, labels: []}}
  ]

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

    :telemetry.attach_many(
      "asn-event-broker-metrics",
      Enum.map(@counter_events, fn {event, _} -> [:asn_event_broker | event] end),
      &__MODULE__.handle_event/4,
      nil
    )

    {:ok, %{}}
  end

  @doc "Telemetry handler; attached once by this process."
  def handle_event([:asn_event_broker | event], measurements, metadata, _nil) do
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
  end

  @doc "Renders the Prometheus text exposition."
  @spec render() :: String.t()
  def render do
    counters = render_counters()
    gauges = render_gauges()

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

  defp render_gauges do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    [
      gauge("pending", "pending deliveries", gauge_count(:pending)),
      gauge("leased", "in-flight (leased) deliveries", gauge_count(:leased)),
      gauge("dead", "dead deliveries awaiting replay or skip", gauge_count(:dead)),
      gauge(
        "oldest_pending_seconds",
        "age of the oldest pending delivery",
        oldest_pending_age(now) || 0
      )
    ]
  end

  defp gauge(name, help, value) do
    "# TYPE asn_event_broker_#{name} gauge\n# HELP asn_event_broker_#{name} #{help}\nasn_event_broker_#{name} #{value}\n"
  end

  defp gauge_count(state) do
    Repo.one!(from d in Delivery, where: d.state == ^state, select: count())
  end

  defp oldest_pending_age(now) do
    case Repo.one!(
           from d in Delivery,
             where: d.state == :pending,
             select: max(d.created_at)
         ) do
      nil -> nil
      %DateTime{} = oldest -> DateTime.diff(now, oldest)
    end
  end

  defp escape(value), do: String.replace(value, "\\\"", "\\\\\\\"")

  defp label_value(nil), do: "unknown"
  defp label_value(value) when is_atom(value), do: to_string(value)
  defp label_value(value) when is_binary(value), do: value
  defp label_value(value), do: to_string(inspect(value))
end
