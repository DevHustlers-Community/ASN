defmodule AsnEventBroker.PublishingTest do
  use AsnEventBroker.DataCase, async: true

  alias AsnEventBroker.Delivery.Delivery
  alias AsnEventBroker.Events.Event
  alias AsnEventBroker.Publishing
  alias AsnEventBroker.Repo
  alias AsnEventBroker.Subscriptions.Subscription

  @event_id "01912345-6789-7000-8000-00000000000a"
  @user_id "01912345-6789-7000-8000-000000000002"

  def event_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "event_id" => @event_id,
        "type" => "user.created",
        "schema_version" => 1,
        "occurred_at" => "2026-10-25T10:00:00Z",
        "payload" => %{"user_id" => @user_id}
      },
      overrides
    )
  end

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

  test "publish creates the event and fans out per eligibility rules" do
    insert_subscription("chat-identity")
    insert_subscription("mod-cases", event_types: ["report.created"])
    insert_subscription("chat-all", status: :paused)

    assert {:ok, :created} = Publishing.publish(event_attrs(), "social-api")

    assert %Event{} = Repo.get!(Event, @event_id)
    deliveries = Repo.all(Delivery)

    # chat-identity (no filter) and chat-all (paused subscriptions still
    # receive deliveries per ADR §7); mod-cases is filtered out.
    assert length(deliveries) == 2

    for d <- deliveries do
      assert d.state == :pending
      assert d.attempts == 0
      assert d.max_attempts == 5
      assert d.event_id == @event_id
      assert d.aggregate_type == nil
    end
  end

  test "republishing identical content is a duplicate with no new deliveries" do
    insert_subscription("chat-identity")
    assert {:ok, :created} = Publishing.publish(event_attrs(), "social-api")
    assert {:ok, :duplicate} = Publishing.publish(event_attrs(), "social-api")
    assert length(Repo.all(Delivery)) == 1
  end

  test "equivalent timestamp representations are the same event, not a conflict" do
    insert_subscription("chat-identity")

    assert {:ok, :created} =
             Publishing.publish(
               event_attrs(%{"occurred_at" => "2026-10-25T12:00:00+02:00"}),
               "social-api"
             )

    assert {:ok, :duplicate} =
             Publishing.publish(
               event_attrs(%{"occurred_at" => "2026-10-25T10:00:00.000000Z"}),
               "social-api"
             )

    assert {:error, :conflict} =
             Publishing.publish(
               event_attrs(%{"occurred_at" => "2026-10-25T12:00:00.000001+02:00"}),
               "social-api"
             )
  end

  test "same event_id with different content is a conflict" do
    insert_subscription("chat-identity")
    assert {:ok, :created} = Publishing.publish(event_attrs(), "social-api")

    assert {:error, :conflict} =
             Publishing.publish(
               event_attrs(%{"payload" => %{"user_id" => "changed"}}),
               "social-api"
             )
  end

  test "same event_id with a different publisher is a conflict" do
    insert_subscription("chat-identity")
    assert {:ok, :created} = Publishing.publish(event_attrs(), "social-api")
    assert {:error, :conflict} = Publishing.publish(event_attrs(), "moderation-api")
  end

  test "a different event_id reusing an aggregate_version is rejected" do
    insert_subscription("chat-identity")

    attrs =
      event_attrs(%{
        "aggregate_type" => "user",
        "aggregate_id" => @user_id,
        "aggregate_version" => 1
      })

    assert {:ok, :created} = Publishing.publish(attrs, "social-api")

    second =
      event_attrs(%{
        "event_id" => "01912345-6789-7000-8000-00000000000b",
        "type" => "user.updated",
        "aggregate_type" => "user",
        "aggregate_id" => @user_id,
        "aggregate_version" => 1
      })

    assert {:error, :aggregate_version_taken} = Publishing.publish(second, "social-api")
  end

  test "invalid envelopes are rejected without side effects" do
    insert_subscription("chat-identity")

    assert {:error, {:invalid_envelope, _}} =
             Publishing.publish(event_attrs(%{"type" => "BAD"}), "social-api")

    assert Repo.all(Event) == []
    assert Repo.all(Delivery) == []
  end

  test "publish without a publisher is rejected" do
    assert {:error, {:invalid_publisher, _}} = Publishing.publish(event_attrs(), nil)
  end

  test "concurrent duplicate publishes are serialized to one created and one duplicate" do
    insert_subscription("chat-identity")

    parent = self()

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          receive do
            :go -> Publishing.publish(event_attrs(), "social-api")
          end
        end)
      end

    # Sandbox connections are per-process; explicitly hand each task the
    # test's sandbox owner so no child touches a real connection.
    Enum.each(tasks, &Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, &1.pid))
    Enum.each(tasks, &send(&1.pid, :go))

    results = Task.await_many(tasks)
    assert Enum.sort(results) == [ok: :created, ok: :duplicate]
    assert length(Repo.all(Delivery)) == 1
  end
end
