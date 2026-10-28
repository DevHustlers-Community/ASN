defmodule AsnEventBroker.RetentionTest do
  use AsnEventBroker.DataCase, async: true

  alias AsnEventBroker.{Acknowledgements, DeadLetter, Delivery, Publishing, Repo, Retention}
  alias AsnEventBroker.Subscriptions.Subscription

  @event_id "01912345-6789-7000-8000-000000000001"
  @old "2020-01-01T00:00:00.000000Z"
  @now "2026-10-25T10:00:00.000000Z"

  def insert_subscription(name) do
    %Subscription{}
    |> Subscription.changeset(%{id: Ecto.UUID.generate(), name: name, consumer: "chat-service"})
    |> Repo.insert!()
  end

  def publish_and_ack(event_id, occurred_at \\ @now) do
    insert_subscription("chat-identity")

    attrs = %{
      "event_id" => event_id,
      "type" => "user.created",
      "schema_version" => 1,
      "occurred_at" => occurred_at,
      "payload" => %{}
    }

    assert {:ok, :created} = Publishing.publish(attrs, "social-api")
    {:ok, [claimed]} = Delivery.claim("chat-identity", 10, 0)
    assert :ok = Acknowledgements.ack(claimed.delivery_id, claimed.lease_token)
    claimed
  end

  def backdate_event(event_id, received_at) do
    Repo.query!("UPDATE events SET received_at = $1 WHERE event_id = $2", [
      elem(DateTime.from_iso8601(received_at), 1),
      Ecto.UUID.dump!(event_id)
    ])
  end

  def backdate_delivered(delivery_id, delivered_at) do
    Repo.query!("UPDATE deliveries SET delivered_at = $1 WHERE id = $2", [
      elem(DateTime.from_iso8601(delivered_at), 1),
      Ecto.UUID.dump!(delivery_id)
    ])
  end

  def backdate_dead(delivery_id, dead_lettered_at) do
    Repo.query!("UPDATE deliveries SET dead_lettered_at = $1 WHERE id = $2", [
      elem(DateTime.from_iso8601(dead_lettered_at), 1),
      Ecto.UUID.dump!(delivery_id)
    ])
  end

  def backdate_skipped(delivery_id, skipped_at) do
    Repo.query!("UPDATE deliveries SET skipped_at = $1 WHERE id = $2", [
      elem(DateTime.from_iso8601(skipped_at), 1),
      Ecto.UUID.dump!(delivery_id)
    ])
  end

  # Dead-letters the only delivery of a fresh event (max_attempts = 1).
  def dead_event(event_id) do
    sub = insert_subscription("chat-identity")
    Repo.update!(Ecto.Changeset.change(sub, max_attempts: 1))

    attrs = %{
      "event_id" => event_id,
      "type" => "user.created",
      "schema_version" => 1,
      "occurred_at" => @now,
      "payload" => %{}
    }

    assert {:ok, :created} = Publishing.publish(attrs, "social-api")
    {:ok, [claimed]} = Delivery.claim("chat-identity", 10, 0)

    assert {:ok, :dead} =
             Acknowledgements.nack(claimed.delivery_id, claimed.lease_token, "poison")

    claimed
  end

  test "old delivered deliveries purge; fresh ones survive" do
    claimed = publish_and_ack(@event_id)
    backdate_delivered(claimed.delivery_id, @old)
    backdate_event(@event_id, @old)

    assert %{delivered: 1} = Retention.purge()
    refute Repo.get(AsnEventBroker.Delivery.Delivery, claimed.delivery_id)

    # Second purge is a no-op.
    assert %{delivered: 0} = Retention.purge()
  end

  test "events purge only past the log floor with no live deliveries" do
    claimed = publish_and_ack(@event_id)

    # Delivered fresh, but event past the floor: delivery within its retention
    # window keeps the event alive.
    backdate_event(@event_id, @old)
    assert %{events: 0, delivered: 0} = Retention.purge()
    assert Repo.get(AsnEventBroker.Events.Event, @event_id)

    # Age the delivery past its window: one purge drops the delivery and,
    # in the same run, the event that no delivery needs anymore.
    backdate_delivered(claimed.delivery_id, @old)
    assert %{delivered: 1, events: 1} = Retention.purge()
    assert Repo.all(AsnEventBroker.Events.Event) == []
  end

  test "events backing live dead letters survive the full terminal window" do
    sub = insert_subscription("chat-identity")
    Repo.update!(Ecto.Changeset.change(sub, max_attempts: 1))

    attrs = %{
      "event_id" => @event_id,
      "type" => "user.created",
      "schema_version" => 1,
      "occurred_at" => @now,
      "aggregate_type" => "user",
      "aggregate_id" => "01912345-6789-7000-8000-000000000009",
      "aggregate_version" => 1,
      "payload" => %{}
    }

    assert {:ok, :created} = Publishing.publish(attrs, "social-api")
    {:ok, [claimed]} = Delivery.claim("chat-identity", 10, 0)

    assert {:ok, :dead} =
             Acknowledgements.nack(claimed.delivery_id, claimed.lease_token, "poison")

    backdate_event(@event_id, @old)
    assert %{events: 0} = Retention.purge()
    assert Repo.get(AsnEventBroker.Events.Event, @event_id)
  end

  test "dead letters use the terminal cutoff, not the event-log floor" do
    claimed = dead_event(@event_id)
    backdate_event(@event_id, @old)

    # Ten days old: past the 7-day event-log floor but inside the 30-day
    # terminal window, so both rows survive.
    backdate_dead(claimed.delivery_id, "2026-10-15T00:00:00.000000Z")
    assert %{terminal: 0, events: 0} = Retention.purge()
    assert Repo.get(AsnEventBroker.Events.Event, @event_id)
    assert Repo.get(AsnEventBroker.Delivery.Delivery, claimed.delivery_id)

    # Past 30 days: the terminal delivery goes first, then the event that no
    # longer has a referencing delivery (the FK is satisfied in one run).
    backdate_dead(claimed.delivery_id, @old)
    assert %{terminal: 1, events: 1} = Retention.purge()
    refute Repo.get(AsnEventBroker.Delivery.Delivery, claimed.delivery_id)
    refute Repo.get(AsnEventBroker.Events.Event, @event_id)
  end

  test "skipped deliveries use the terminal cutoff, not the event-log floor" do
    claimed = dead_event(@event_id)
    assert {:ok, :skipped} = DeadLetter.skip(claimed.delivery_id, Ecto.UUID.generate())
    backdate_event(@event_id, @old)

    backdate_skipped(claimed.delivery_id, "2026-10-15T00:00:00.000000Z")
    assert %{terminal: 0, events: 0} = Retention.purge()
    assert Repo.get(AsnEventBroker.Events.Event, @event_id)

    backdate_skipped(claimed.delivery_id, @old)
    assert %{terminal: 1, events: 1} = Retention.purge()
    refute Repo.get(AsnEventBroker.Delivery.Delivery, claimed.delivery_id)
    refute Repo.get(AsnEventBroker.Events.Event, @event_id)
  end

  test "delivered deliveries purge after 24h, not the 30d terminal window" do
    claimed = publish_and_ack(@event_id)

    # ~5 days old: past the 24h delivered window but inside the 30d terminal
    # window. Under the old (single-cutoff) code this would survive; with the
    # per-state cutoff it purges.
    backdate_delivered(claimed.delivery_id, "2026-10-20T10:00:00.000000Z")
    backdate_event(@event_id, "2026-10-20T10:00:00.000000Z")

    assert %{delivered: 1, events: 1} = Retention.purge()
    refute Repo.get(AsnEventBroker.Delivery.Delivery, claimed.delivery_id)
    refute Repo.get(AsnEventBroker.Events.Event, @event_id)
  end

  test "fresh delivered deliveries survive purge" do
    claimed = publish_and_ack(@event_id)
    backdate_event(@event_id, @old)

    assert %{delivered: 0, events: 0} = Retention.purge()
    assert Repo.get(AsnEventBroker.Delivery.Delivery, claimed.delivery_id)
    assert Repo.get(AsnEventBroker.Events.Event, @event_id)
  end
end
