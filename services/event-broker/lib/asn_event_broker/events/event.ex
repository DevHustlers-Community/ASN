defmodule AsnEventBroker.Events.Event do
  @moduledoc """
  A durable event in the broker log, persisted from a validated envelope.

  `event_id` is the primary key and the idempotency anchor: publishers retry
  the same `event_id` with identical content, and the broker answers 200 for
  accepted duplicates (see `AsnEventBroker.Publishing`).
  """

  use Ecto.Schema

  @primary_key {:event_id, Ecto.UUID, autogenerate: false}
  @foreign_key_type Ecto.UUID
  schema "events" do
    field :type, :string
    field :schema_version, :integer
    field :occurred_at, :utc_datetime_usec
    field :aggregate_type, :string
    field :aggregate_id, Ecto.UUID
    field :aggregate_version, :integer
    field :trace_id, :string
    field :payload, :map
    field :content_hash, :string
    field :publisher, :string
    field :received_at, :utc_datetime_usec
  end

  def new_from_envelope(%AsnEventBroker.Events.Envelope{} = envelope, publisher, received_at) do
    %__MODULE__{
      event_id: envelope.event_id,
      type: envelope.type,
      schema_version: envelope.schema_version,
      occurred_at: envelope.occurred_at,
      aggregate_type: envelope.aggregate_type,
      aggregate_id: envelope.aggregate_id,
      aggregate_version: envelope.aggregate_version,
      trace_id: envelope.trace_id,
      payload: envelope.payload,
      content_hash: AsnEventBroker.Events.Envelope.content_hash(envelope),
      publisher: publisher,
      received_at: received_at
    }
  end
end
