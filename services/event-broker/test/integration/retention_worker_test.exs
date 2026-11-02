defmodule AsnEventBroker.RetentionWorkerTest do
  # async: false: these tests mutate the global :retention config, and the
  # failure-path test intentionally installs a value that makes any concurrent
  # Retention.purge/1 crash (retention_test.exs runs async: true and purges).
  use AsnEventBroker.DataCase, async: false

  alias AsnEventBroker.{Acknowledgements, Delivery, Publishing, Repo, Workers.RetentionWorker}
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

  test "is disabled under the test sandbox" do
    assert Application.get_env(:asn_event_broker, :start_workers) == false
    assert Process.whereis(RetentionWorker) == nil
  end

  test "purges cohorts past their cutoffs on its interval" do
    original = Application.fetch_env!(:asn_event_broker, :retention)

    # Safety net registered before the worker starts: a failed assertion must
    # not orphan a 20 ms-ticking worker. Idempotent via whereis.
    on_exit(fn ->
      if pid = Process.whereis(RetentionWorker), do: GenServer.stop(pid)
    end)

    on_exit(fn -> Application.put_env(:asn_event_broker, :retention, original) end)

    Application.put_env(
      :asn_event_broker,
      :retention,
      Keyword.put(original, :retention_interval_ms, 20)
    )

    claimed = publish_and_ack(@event_id)
    backdate_delivered(claimed.delivery_id, @old)
    backdate_event(@event_id, @old)

    {:ok, worker} = RetentionWorker.start_link()

    # With async: false the DataCase sandbox owner runs in shared mode, so the
    # worker process checks out the shared connection without an explicit
    # Sandbox.allow/3 — no first-tick ownership race.
    wait_until(1_000, fn ->
      is_nil(Repo.get(AsnEventBroker.Delivery.Delivery, claimed.delivery_id)) and
        Repo.all(AsnEventBroker.Events.Event) == []
    end)

    refute Repo.get(AsnEventBroker.Delivery.Delivery, claimed.delivery_id)

    GenServer.stop(RetentionWorker)
    refute Process.whereis(RetentionWorker)
    refute Process.alive?(worker)
  end

  test "exits with a non-normal reason when the purge raises" do
    original = Application.fetch_env!(:asn_event_broker, :retention)

    on_exit(fn -> Application.put_env(:asn_event_broker, :retention, original) end)

    # `delivered_hours: "not-an-integer"` makes the first cutoff computation
    # inside Retention.purge raise deterministically (the unary minus against
    # a string raises ArithmeticError) before any SQL runs, which crashes the
    # GenServer tick instead of swallowing it.
    broken =
      original
      |> Keyword.put(:retention_interval_ms, 20)
      |> Keyword.put(:delivered_hours, "not-an-integer")

    Application.put_env(:asn_event_broker, :retention, broken)

    Process.flag(:trap_exit, true)
    {:ok, worker} = RetentionWorker.start_link()

    assert_receive {:EXIT, ^worker, reason}, 1_000
    refute reason == :normal
    refute reason == :shutdown
    # OTP 29 delivers raised exceptions as {reason, stacktrace}; the purge
    # crash is the ArithmeticError from the unary minus, not a swallowed error.
    assert elem(reason, 0) == :badarith
  end

  defp wait_until(timeout_ms, fun),
    do: wait_until(System.monotonic_time(:millisecond) + timeout_ms, fun, timeout_ms)

  defp wait_until(deadline, fun, timeout_ms) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(10)
        wait_until(deadline, fun, timeout_ms)
      else
        flunk("condition not met within #{timeout_ms} ms")
      end
    end
  end
end
