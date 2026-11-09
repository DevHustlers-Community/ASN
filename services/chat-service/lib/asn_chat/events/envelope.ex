defmodule AsnChat.Events.Envelope do
  @moduledoc """
  Rebuilds the publish envelope from an `outbox_events` row (ADR 0015).

  The outbox stores the event fields, not a second copy of the envelope. Every
  field the broker hashes must be rebuilt here, and `occurred_at` must be
  rendered at microsecond precision to match the broker's normalization, so a
  retry after a restart publishes content with the same canonical hash.

  Optional `aggregate_*` and `trace_id` fields are omitted from the map when
  absent. The broker reads them as `nil` either way, so the canonical envelope
  is unchanged.
  """

  @doc """
  Builds the envelope map for `outbox_events` row `row`.

  The row must expose `id`, `type`, `schema_version`, `occurred_at`, `payload`,
  `aggregate_type`, `aggregate_id`, `aggregate_version`, and `trace_id`.
  """
  @spec from_outbox(struct() | map()) :: map()
  def from_outbox(row) do
    %{
      "event_id" => row.id,
      "type" => row.type,
      "schema_version" => row.schema_version,
      "occurred_at" => format_occurred_at(row.occurred_at),
      "payload" => row.payload
    }
    |> put_aggregate(row)
    |> put_trace_id(row)
  end

  defp put_aggregate(envelope, %{aggregate_type: nil}), do: envelope

  defp put_aggregate(envelope, row) do
    Map.merge(envelope, %{
      "aggregate_type" => row.aggregate_type,
      "aggregate_id" => row.aggregate_id,
      "aggregate_version" => row.aggregate_version
    })
  end

  defp put_trace_id(envelope, %{trace_id: nil}), do: envelope
  defp put_trace_id(envelope, row), do: Map.put(envelope, "trace_id", row.trace_id)

  defp format_occurred_at(%DateTime{} = occurred_at) do
    %{microsecond: {microseconds, _precision}} = occurred_at

    occurred_at
    |> Map.put(:microsecond, {microseconds, 6})
    |> DateTime.to_iso8601()
  end
end
