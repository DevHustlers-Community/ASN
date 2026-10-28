defmodule AsnEventBroker.DeliveryTest do
  use AsnEventBroker.DataCase, async: true

  alias AsnEventBroker.{Acknowledgements, Delivery, Publishing, Repo}
  alias AsnEventBroker.Subscriptions.Subscription
  alias AsnEventBroker.Workers.LeaseReaper

  @agg_id "01912345-6789-7000-8000-00000000000f"

  def insert_subscription(name, opts \\ []) do
    %Subscription{}
    |> Subscription.changeset(%{
      id: Ecto.UUID.generate(),
      name: name,
      consumer: "chat-service",
      event_types: Keyword.get(opts, :event_types),
      status: Keyword.get(opts, :status, :active),
      max_attempts: Keyword.get(opts, :max_attempts, 5)
    })
    |> Repo.insert!()
  end

  def publish_aggregate_versions(_name, versions) do
    Enum.each(versions, fn v ->
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
    end)
  end

  def expire_lease(delivery_id) do
    Repo.query!(
      "UPDATE deliveries SET lease_expires_at = now() - interval '1 second' WHERE id = $1",
      [
        Ecto.UUID.dump!(delivery_id)
      ]
    )
  end

  def force_due(delivery_id) do
    Repo.query!(
      "UPDATE deliveries SET next_attempt_at = now() - interval '1 second' WHERE id = $1",
      [
        Ecto.UUID.dump!(delivery_id)
      ]
    )
  end

  def set_paused(name) do
    Repo.query!("UPDATE subscriptions SET status = 'paused' WHERE name = $1", [name])
  end

  test "claim leases the earliest version and blocks later versions (head-of-line)" do
    insert_subscription("chat-identity")
    publish_aggregate_versions("chat-identity", [1, 2, 3])

    assert {:ok, [claimed]} = Delivery.claim("chat-identity", 10, 0)
    assert claimed.aggregate_version == 1
    assert claimed.attempts == 1
    assert String.valid?(claimed.lease_token) or is_binary(claimed.lease_token)
    assert DateTime.compare(claimed.lease_expires_at, DateTime.utc_now()) == :gt

    # v2 and v3 are blocked by the leased v1.
    assert {:ok, []} = Delivery.claim("chat-identity", 10, 0)
  end

  test "after ack the next version becomes claimable" do
    insert_subscription("chat-identity")
    publish_aggregate_versions("chat-identity", [1, 2])

    {:ok, [first]} = Delivery.claim("chat-identity", 10, 0)
    assert :ok = Acknowledgements.ack(first.delivery_id, first.lease_token)

    assert {:ok, [second]} = Delivery.claim("chat-identity", 10, 0)
    assert second.aggregate_version == 2
  end

  test "concurrent claims of the same aggregate lease at most one" do
    insert_subscription("chat-identity")
    publish_aggregate_versions("chat-identity", [1])

    parent = self()

    tasks =
      for _ <- 1..3 do
        Task.async(fn ->
          receive do
            :go -> Delivery.claim("chat-identity", 10, 0)
          end
        end)
      end

    Enum.each(tasks, &Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, &1.pid))
    Enum.each(tasks, &send(&1.pid, :go))

    results = Task.await_many(tasks)
    claimed = Enum.flat_map(results, fn {:ok, deliveries} -> deliveries end)
    assert length(claimed) == 1
  end

  test "repeat ack with the final token is idempotent; superseded tokens cannot act" do
    insert_subscription("chat-identity", max_attempts: 5)
    publish_aggregate_versions("chat-identity", [1, 2])

    {:ok, [first]} = Delivery.claim("chat-identity", 10, 0)
    assert :ok = Acknowledgements.ack(first.delivery_id, first.lease_token)
    assert :ok = Acknowledgements.ack(first.delivery_id, first.lease_token)

    # Claim the next version, force expiry, reaper returns it to pending,
    # claim again -> a fresh token supersedes the old one.
    assert {:ok, [second]} = Delivery.claim("chat-identity", 10, 0)
    expire_lease(second.delivery_id)
    assert LeaseReaper.reap() == 1
    assert {:ok, [third]} = Delivery.claim("chat-identity", 10, 0)
    refute third.lease_token == second.lease_token
    assert {:error, :stale_lease} = Acknowledgements.ack(third.delivery_id, second.lease_token)
    assert :ok = Acknowledgements.ack(third.delivery_id, third.lease_token)
  end

  test "ack with an expired lease fails without changing state" do
    insert_subscription("chat-identity")
    publish_aggregate_versions("chat-identity", [1])

    {:ok, [claimed]} = Delivery.claim("chat-identity", 10, 0)
    expire_lease(claimed.delivery_id)

    assert {:error, :stale_lease} = Acknowledgements.ack(claimed.delivery_id, claimed.lease_token)
  end

  test "nack reschedules with backoff and keeps accumulating attempts" do
    insert_subscription("chat-identity")
    publish_aggregate_versions("chat-identity", [1])

    {:ok, [claimed]} = Delivery.claim("chat-identity", 10, 0)

    assert {:ok, :pending} =
             Acknowledgements.nack(
               claimed.delivery_id,
               claimed.lease_token,
               "consumer_error",
               "boom"
             )

    # Not due yet: backoff is in the future.
    assert {:ok, []} = Delivery.claim("chat-identity", 10, 0)

    force_due(claimed.delivery_id)
    assert {:ok, [second]} = Delivery.claim("chat-identity", 10, 0)
    assert second.attempts == 2

    assert {:ok, :pending} =
             Acknowledgements.nack(second.delivery_id, second.lease_token, "consumer_error")
  end

  test "nack exhausting attempts dead-letters and blocks later versions" do
    insert_subscription("chat-identity", max_attempts: 1)
    publish_aggregate_versions("chat-identity", [1, 2])

    {:ok, [first]} = Delivery.claim("chat-identity", 10, 0)
    assert {:ok, :dead} = Acknowledgements.nack(first.delivery_id, first.lease_token, "poison")

    # Dead v1 blocks v2 until an admin replays or skips (ADR §6).
    assert {:ok, []} = Delivery.claim("chat-identity", 10, 0)
  end

  test "reaper returns expired leases and dead-letters exhausted attempts" do
    insert_subscription("chat-identity", max_attempts: 1)
    publish_aggregate_versions("chat-identity", [1])

    {:ok, [claimed]} = Delivery.claim("chat-identity", 10, 0)
    expire_lease(claimed.delivery_id)
    assert LeaseReaper.reap() == 1

    row =
      Repo.one!(
        from d in "deliveries",
          where: d.id == ^Ecto.UUID.dump!(claimed.delivery_id) and d.state == "dead",
          select: d.id
      )

    assert row

    # A second reap finds nothing left to do.
    assert LeaseReaper.reap() == 0
  end

  test "extend prolongs the lease; an expired lease cannot be extended" do
    insert_subscription("chat-identity")
    publish_aggregate_versions("chat-identity", [1])

    {:ok, [claimed]} = Delivery.claim("chat-identity", 10, 0)
    assert {:ok, extended} = Acknowledgements.extend(claimed.delivery_id, claimed.lease_token)
    assert DateTime.compare(extended, claimed.lease_expires_at) == :gt

    expire_lease(claimed.delivery_id)

    assert {:error, :stale_lease} =
             Acknowledgements.extend(claimed.delivery_id, claimed.lease_token)
  end

  test "paused subscriptions cannot claim" do
    insert_subscription("chat-paused")
    publish_aggregate_versions("chat-paused", [1])

    # Active first: claiming works.
    assert {:ok, [_]} = Delivery.claim("chat-paused", 10, 0)

    set_paused("chat-paused")
    publish_aggregate_versions("chat-paused", [2])
    assert {:error, :paused} = Delivery.claim("chat-paused", 10, 0)
  end

  test "unknown subscriptions are not found" do
    assert {:error, :not_found} = Delivery.claim("does-not-exist", 10, 0)
  end

  test "aggregate-less events are claimed without ordering constraints" do
    insert_subscription("chat-identity")

    for _ <- 1..3 do
      attrs = %{
        "event_id" => Ecto.UUID.generate(),
        "type" => "system.pulse",
        "schema_version" => 1,
        "occurred_at" => "2026-10-25T10:00:00Z",
        "payload" => %{}
      }

      assert {:ok, :created} = Publishing.publish(attrs, "social-api")
    end

    assert {:ok, claimed} = Delivery.claim("chat-identity", 10, 0)
    assert length(claimed) == 3
  end

  test "publish wakes parked claims before the fallback sweep" do
    insert_subscription("chat-wake")

    parent = self()

    task =
      Task.async(fn ->
        receive do
          :go -> Delivery.claim("chat-wake", 10, 500)
        end
      end)

    Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, task.pid)
    send(task.pid, :go)

    # Let the claim park first (sweep interval is 1s, wait is 500ms, so only
    # a publish wakeup can return a delivery in time).
    Process.sleep(100)

    attrs = %{
      "event_id" => Ecto.UUID.generate(),
      "type" => "user.created",
      "schema_version" => 1,
      "occurred_at" => "2026-10-25T10:00:00Z",
      "payload" => %{}
    }

    started = System.monotonic_time(:millisecond)
    assert {:ok, :created} = Publishing.publish(attrs, "social-api")
    assert {:ok, [_]} = Task.await(task)
    assert System.monotonic_time(:millisecond) - started < 400
  end

  test "publishing with no eligible subscriptions does not wait for waiters" do
    insert_subscription("chat-filtered", event_types: ["report.created"])

    attrs = %{
      "event_id" => Ecto.UUID.generate(),
      "type" => "user.created",
      "schema_version" => 1,
      "occurred_at" => "2026-10-25T10:00:00Z",
      "payload" => %{}
    }

    started = System.monotonic_time(:millisecond)
    assert {:ok, :created} = Publishing.publish(attrs, "social-api")
    assert System.monotonic_time(:millisecond) - started < 400
    assert Repo.all(AsnEventBroker.Delivery.Delivery) == []
  end
end
