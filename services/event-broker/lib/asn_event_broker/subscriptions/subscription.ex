defmodule AsnEventBroker.Subscriptions.Subscription do
  @moduledoc """
  A durable subscription: which events a consuming service wants.

  Fan-out happens at publish time; a new subscription starts from its creation
  and receives no historical backfill (ADR 0008 §7).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  @foreign_key_type Ecto.UUID
  schema "subscriptions" do
    field :name, :string
    field :consumer, :string
    field :event_types, {:array, :string}
    field :status, Ecto.Enum, values: [:active, :paused], default: :active
    field :max_attempts, :integer
    timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:id, :name, :consumer, :event_types, :status, :max_attempts])
    |> validate_required([:id, :name, :consumer])
    |> validate_length(:name, min: 1)
    |> validate_length(:consumer, min: 1)
    |> validate_number(:max_attempts, greater_than: 0)
    |> validate_inclusion(:status, [:active, :paused])
    |> validate_change(:event_types, fn
      :event_types, nil ->
        []

      :event_types, types when is_list(types) ->
        if Enum.all?(types, &is_binary/1) and types != [] do
          []
        else
          [event_types: "must be a non-empty list of event types when present"]
        end

      :event_types, _ ->
        [event_types: "must be a list of event types when present"]
    end)
    |> unique_constraint(:name)
  end
end
