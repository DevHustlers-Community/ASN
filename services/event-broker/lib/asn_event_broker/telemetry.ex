defmodule AsnEventBroker.Telemetry do
  @moduledoc """
  Telemetry emission for the broker's main paths (ADR 0008 §11). Events are
  namespaced under `[:asn_event_broker, ...]`; consumers of metrics attach
  handlers externally. Payloads and tokens are never included.

  Emitted events:

  - `[:asn_event_broker, :publish, :accepted]` — `%{count: 1}`, metadata
    `%{type, outcome: :created | :duplicate}` (conflicts are counted, not
    accepted)
  - `[:asn_event_broker, :publish, :rejected]` — `%{count: 1}`,
    `%{reason: :conflict | :aggregate_version_taken | :invalid_envelope}`
  - `[:asn_event_broker, :claim]` — `%{count: n}`, `%{subscription}` (n = 0
    for empty claims: the empty-claim rate metric)
  - `[:asn_event_broker, :ack]`, `[:asn_event_broker, :nack]`,
    `[:asn_event_broker, :lease_expired]`, `[:asn_event_broker, :dead_letter]`,
    `[:asn_event_broker, :replay]`, `[:asn_event_broker, :skip]`,
    `[:asn_event_broker, :retention_purge]`
  """

  @spec emit([atom()], map(), map()) :: :ok
  def emit(event, measurements \\ %{}, metadata \\ %{}) do
    :telemetry.execute([:asn_event_broker | event], measurements, metadata)
  end

  def emit_count(event, metadata), do: emit(event, %{count: 1}, metadata)
end
