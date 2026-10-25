defmodule AsnEventBroker.DeadLetterTest do
  use AsnEventBroker.DataCase, async: true

  alias AsnEventBroker.{Acknowledgements, DeadLetter, Delivery, Publishing, Repo}
  alias AsnEventBroker.Audit.AuditEntry
  alias AsnEventBroker.Subscriptions.Subscription

  @agg_id "01912345-6789-7000-8000-00000000000e"

  def publish_versions(versions) do
    for v <- versions do
      attrs = %{
        "event_id" => Ecto.UUID.generate(),
        "type" => "user.updated",
        "schema_version" => 1,
        "occurred_at" => "2026-10-25T10:00:00Z",
        "aggregate_type" => "user",
        "aggregate_id" => @agg_id,
        "aggregate_version" => v,
        "payload" => %{"version" => v}
      }

      assert {:ok, :created} = Publishing.publish(attrs, "social-api")
    end
  end

  def dead_first_version(max_attempts \\ 1) do
    %Subscription{}
    |> Subscription.changeset(%{
      id: Ecto.UUID.generate(),
      name: "chat-identity",
      consumer: "chat-service",
      max_attempts: max_attempts
    })
    |> Repo.insert!()

    publish_versions([1, 2])

    {:ok, [first]} = Delivery.claim("chat-identity", 10, 0)
    assert {:ok, :dead} = Acknowledgements.nack(first.delivery_id, first.lease_token, "poison")
    first
  end

  test "replay returns a dead delivery to pending with a fresh budget" do
    dead = dead_first_version()

    # Dead v1 blocks v2 (head-of-line).
    assert {:ok, []} = Delivery.claim("chat-identity", 10, 0)

    assert {:ok, :replayed} = DeadLetter.replay(dead.delivery_id, Ecto.UUID.generate())
    assert {:ok, [claimed]} = Delivery.claim("chat-identity", 10, 0)
    assert claimed.delivery_id == dead.delivery_id
    assert claimed.attempts == 1
    assert :ok = Acknowledgements.ack(claimed.delivery_id, claimed.lease_token)

    # With v1 delivered, v2 becomes claimable.
    assert {:ok, [next]} = Delivery.claim("chat-identity", 10, 0)
    assert next.aggregate_version == 2
  end

  test "replay writes an audit entry with the state change" do
    dead = dead_first_version()
    actor = Ecto.UUID.generate()

    assert {:ok, :replayed} = DeadLetter.replay(dead.delivery_id, actor)

    entries = Repo.all(AuditEntry)
    assert [entry] = entries
    assert entry.actor_credential_id == actor
    assert entry.action == "dead_letter.replay"
    assert entry.target == "delivery:" <> dead.delivery_id
  end

  test "skip is terminal and releases the aggregate" do
    dead = dead_first_version()
    actor = Ecto.UUID.generate()

    assert {:ok, :skipped} = DeadLetter.skip(dead.delivery_id, actor)

    # v1 skipped never claims; v2 is now claimable (skipped does not block).
    assert {:ok, [next]} = Delivery.claim("chat-identity", 10, 0)
    assert next.aggregate_version == 2

    assert [entry] = Repo.all(AuditEntry)
    assert entry.action == "dead_letter.skip"
  end

  test "replay and skip only act on dead deliveries" do
    dead = dead_first_version()
    actor = Ecto.UUID.generate()

    assert {:ok, :replayed} = DeadLetter.replay(dead.delivery_id, actor)
    assert {:error, :not_dead} = DeadLetter.replay(dead.delivery_id, actor)
    assert {:error, :not_dead} = DeadLetter.skip(dead.delivery_id, actor)
    assert {:error, :not_found} = DeadLetter.replay(Ecto.UUID.generate(), actor)
  end

  test "list_dead inspects dead deliveries newest first" do
    dead = dead_first_version()

    assert [row] = DeadLetter.list_dead("chat-identity")
    assert row.delivery_id == dead.delivery_id
    assert row.type == "user.updated"
    assert row.aggregate_version == 1
    assert row.last_error_kind == "poison"
    assert DeadLetter.list_dead("no-such-subscription") == []
  end
end
