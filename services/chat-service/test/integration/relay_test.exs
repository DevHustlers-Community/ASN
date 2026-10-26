defmodule AsnChat.Events.RelayTest do
  use AsnChat.DataCase, async: true

  alias AsnChat.Events.{Outbox, Relay}

  @agg_id "01912345-6789-7000-8000-0000000000aa"

  def envelope(event_id, version, type \\ "chat.device.registered") do
    %{
      "event_id" => event_id,
      "type" => type,
      "schema_version" => 1,
      "occurred_at" => "2026-10-26T10:00:00Z",
      "aggregate_type" => "conversation",
      "aggregate_id" => @agg_id,
      "aggregate_version" => version,
      "payload" => %{"device_id" => "d-1"}
    }
  end

  def record!(env) do
    {:ok, _} = Outbox.record(env)
    env["event_id"]
  end

  def accepting_client(ets, status \\ 201) do
    fn env ->
      :ets.update_counter(ets, :attempts, {2, 1}, {:attempts, 0})
      :ets.insert(ets, {:last, env["event_id"]})
      {:ok, status}
    end
  end

  def attempts(ets), do: :ets.lookup_element(ets, :attempts, 2)

  test "publishes committed rows and marks them published on acceptance" do
    v1 = record!(envelope(Ecto.UUID.generate(), 1))
    v2 = record!(envelope(Ecto.UUID.generate(), 2))

    assert {:ok, [^v1, ^v2] = published} =
             Relay.publish_batch(http_client: accepting_client(:ets.new(:t1, [:set, :public])))

    assert Enum.sort(published) == Enum.sort([v1, v2])
    assert Outbox.unpublished() == []
  end

  test "advances only after the current version is definitively accepted" do
    record!(envelope(Ecto.UUID.generate(), 1))
    v2 = record!(envelope(Ecto.UUID.generate(), 2))
    ets = :ets.new(:t2, [:set, :public])

    # Accept only one row per batch: the relay publishes v1, then stops
    # before v2 on the next version of the same aggregate? No: v1 accepted,
    # v2 also attempted and accepted. Gate the client to accept v1 only.
    gated = fn env ->
      :ets.update_counter(ets, :attempts, {2, 1}, {:attempts, 0})
      :ets.insert(ets, {:last, env["event_id"]})

      if :ets.lookup_element(ets, :attempts, 2) == 1 do
        {:ok, 201}
      else
        {:error, :timeout}
      end
    end

    assert {:ok, [_only_first]} = Relay.publish_batch(http_client: gated)
    assert attempts(ets) == 2

    # v2 remains unpublished; the next batch publishes it (same event_id,
    # identical content — idempotent publish makes that safe).
    assert [%{event_id: event_id}] = Outbox.unpublished()
    assert event_id == v2
  end

  test "a 409 halts the batch without publishing later versions" do
    v1 = record!(envelope(Ecto.UUID.generate(), 1))
    v2 = record!(envelope(Ecto.UUID.generate(), 2))
    ets = :ets.new(:t3, [:set, :public])

    rejecting = fn env ->
      :ets.update_counter(ets, :attempts, {2, 1}, {:attempts, 0})
      :ets.insert(ets, {:last, env["event_id"]})
      {:ok, 409}
    end

    assert {:ok, []} = Relay.publish_batch(http_client: rejecting)

    # The relay attempted v1, halted, and never attempted v2.
    assert attempts(ets) == 1
    assert [{:last, attempted}] = :ets.lookup(ets, :last)
    assert attempted == v1
    assert [first, second] = Outbox.unpublished()
    assert first.event_id == v1
    assert second.event_id == v2
  end

  test "timeout ambiguity leaves rows unpublished for retry of the same event_id" do
    v1 = record!(envelope(Ecto.UUID.generate(), 1))
    ets = :ets.new(:t4, [:set, :public])

    assert {:ok, []} = Relay.publish_batch(http_client: fn _env -> {:error, :timeout} end)
    assert [%{event_id: ^v1}] = Outbox.unpublished()

    # Next tick with a working broker accepts the identical retry.
    assert {:ok, [^v1]} = Relay.publish_batch(http_client: accepting_client(ets, 200))
    assert Outbox.unpublished() == []
  end
end
