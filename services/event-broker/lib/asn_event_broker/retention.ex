defmodule AsnEventBroker.Retention do
  @moduledoc """
  Dependency-aware retention purge (ADR 0008 §8).

  Retention is a deletion policy; replay availability is defined separately.
  Delivered deliveries purge after 24 hours, dead and skipped after 30 days.
  An event purges only past the 7-day event-log floor AND when no delivery
  referencing it is non-terminal or within its own retention window — each
  terminal state is compared against its own cutoff (delivered 24 h, dead and
  skipped 30 days), not the event-log floor — so events backing live dead
  letters survive the full dead-letter window and replay always finds its
  payload. Purges run in batches.
  """

  alias AsnEventBroker.{Repo, Telemetry}

  @purge_delivered_sql """
  DELETE FROM deliveries
  WHERE id IN (
    SELECT id FROM deliveries
    WHERE state = 'delivered'
      AND delivered_at <= $1
    LIMIT $2
  )
  """

  @purge_terminal_sql """
  DELETE FROM deliveries
  WHERE id IN (
    SELECT id FROM deliveries
    WHERE (state = 'dead' AND dead_lettered_at <= $1)
       OR (state = 'skipped' AND skipped_at <= $1)
    LIMIT $2
  )
  """

  @purge_events_sql """
  DELETE FROM events
  WHERE event_id IN (
    SELECT e.event_id
    FROM events e
    WHERE e.received_at <= $1
      AND NOT EXISTS (
        SELECT 1 FROM deliveries d
        WHERE d.event_id = e.event_id
          AND (
            d.state IN ('pending', 'leased')
            OR (d.state = 'delivered' AND d.delivered_at > $2)
            OR (d.state = 'dead' AND d.dead_lettered_at > $3)
            OR (d.state = 'skipped' AND d.skipped_at > $3)
          )
      )
    LIMIT $4
  )
  """

  @spec purge(non_neg_integer()) :: %{
          delivered: non_neg_integer(),
          terminal: non_neg_integer(),
          events: non_neg_integer()
        }
  def purge(batch_size \\ 1_000) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    cutoff_delivered = DateTime.add(now, -delivered_retention_hours(), :hour)
    cutoff_terminal = DateTime.add(now, -terminal_retention_days(), :day)
    cutoff_events = DateTime.add(now, -event_log_days(), :day)

    delivered = delete_in_batches(@purge_delivered_sql, [cutoff_delivered, batch_size])
    terminal = delete_in_batches(@purge_terminal_sql, [cutoff_terminal, batch_size])

    events =
      delete_in_batches(@purge_events_sql, [
        cutoff_events,
        cutoff_delivered,
        cutoff_terminal,
        batch_size
      ])

    Telemetry.emit([:retention_purge], %{count: delivered + terminal + events}, %{
      delivered: delivered,
      terminal: terminal,
      events: events
    })

    %{delivered: delivered, terminal: terminal, events: events}
  end

  defp delete_in_batches(sql, params) do
    total = do_delete(sql, params, 0)
    total
  end

  defp do_delete(sql, params, total) do
    case Repo.query!(sql, params) do
      %{num_rows: 0} -> total
      %{num_rows: n} -> do_delete(sql, params, total + n)
    end
  end

  defp delivered_retention_hours,
    do: Keyword.fetch!(Application.fetch_env!(:asn_event_broker, :retention), :delivered_hours)

  defp terminal_retention_days,
    do: Keyword.fetch!(Application.fetch_env!(:asn_event_broker, :retention), :terminal_days)

  defp event_log_days,
    do: Keyword.fetch!(Application.fetch_env!(:asn_event_broker, :retention), :event_log_days)
end
