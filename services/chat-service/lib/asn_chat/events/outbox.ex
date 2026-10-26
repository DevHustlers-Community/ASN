defmodule AsnChat.Events.Outbox do
  @moduledoc """
  Chat's transactional outbox (architecture §2): chat business changes and
  their events land in `chat_db` in the same transaction, and the relay
  publishes committed rows to the broker afterwards. Per ADR 0008 §5, the
  relay publishes per aggregate in version order and advances only after the
  broker definitively accepts (201 or 200).

  Envelopes stored here are already-validated map representations of
  `contracts/events/common/event-envelope.schema.json`. They never contain
  plaintext chat content.
  """

  use Ecto.Schema
  import Ecto.Query

  alias AsnChat.Repo
  alias AsnChat.UUIDv7

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "outbox_events" do
    field :event_id, Ecto.UUID
    field :envelope, :map
    field :aggregate_type, :string
    field :aggregate_id, Ecto.UUID
    field :aggregate_version, :integer
    field :published_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
  end

  @doc """
  Records an outbox row inside the caller's transaction (the business change
  and its event commit together).
  """
  def record(envelope) when is_map(envelope) do
    %__MODULE__{}
    |> Ecto.Changeset.change(%{
      id: UUIDv7.generate(),
      event_id: envelope["event_id"],
      envelope: envelope,
      aggregate_type: envelope["aggregate_type"],
      aggregate_id: envelope["aggregate_id"],
      aggregate_version: envelope["aggregate_version"]
    })
    |> Repo.insert()
  end

  @doc """
  The next unpublished batch in per-aggregate version order. The relay must
  not publish version N+1 for an aggregate before N is definitively accepted,
  so the batch is ordered and the relay stops at the first non-acceptance.
  """
  def unpublished(limit \\ 100) do
    Repo.all(
      from o in __MODULE__,
        where: is_nil(o.published_at),
        order_by: [asc: o.aggregate_type, asc: o.aggregate_id, asc: o.aggregate_version],
        limit: ^limit
    )
  end

  @spec mark_published(String.t()) :: :ok
  def mark_published(event_id) do
    Repo.update_all(
      from(o in __MODULE__, where: o.event_id == ^event_id and is_nil(o.published_at)),
      set: [published_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)]
    )

    :ok
  end
end
