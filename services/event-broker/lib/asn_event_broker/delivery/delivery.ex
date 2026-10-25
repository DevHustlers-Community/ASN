defmodule AsnEventBroker.Delivery.Delivery do
  @moduledoc """
  One row per (subscription, event): the unit of at-least-once delivery.

  Aggregate columns are denormalized from `events` at fan-out time so the
  claim query can enforce the per-aggregate ordering invariant without joins
  back to the log. State transitions and lease rules are owned by
  `AsnEventBroker.Delivery` and `AsnEventBroker.Acknowledgements`.
  """

  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  @foreign_key_type Ecto.UUID
  schema "deliveries" do
    belongs_to :subscription, AsnEventBroker.Subscriptions.Subscription,
      foreign_key: :subscription_id,
      references: :id

    belongs_to :event, AsnEventBroker.Events.Event,
      foreign_key: :event_id,
      references: :event_id

    field :aggregate_type, :string
    field :aggregate_id, Ecto.UUID
    field :aggregate_version, :integer

    field :state, Ecto.Enum,
      values: [:pending, :leased, :delivered, :dead, :skipped],
      default: :pending

    field :attempts, :integer, default: 0
    field :max_attempts, :integer
    field :lease_token_hash, :string
    field :lease_expires_at, :utc_datetime_usec
    field :next_attempt_at, :utc_datetime_usec
    field :last_error_kind, :string
    field :last_error_message, :string
    field :delivered_at, :utc_datetime_usec
    field :dead_lettered_at, :utc_datetime_usec
    field :skipped_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
  end
end
