defmodule AsnSocial.Events.Envelope do
  @moduledoc "Rebuilds the canonical broker envelope from a Social outbox row."

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

  defp format_occurred_at(%NaiveDateTime{} = occurred_at) do
    occurred_at
    |> DateTime.from_naive!("Etc/UTC")
    |> format_occurred_at()
  end
end
