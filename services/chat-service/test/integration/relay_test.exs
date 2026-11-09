defmodule AsnChat.Events.RelayTest do
  use AsnChat.DataCase, async: true

  alias AsnChat.Events.{Envelope, Outbox, Relay}
  alias AsnChat.UUIDv7

  @aggregate_id "01912345-6789-7000-8000-0000000000aa"
  @other_aggregate_id "01912345-6789-7000-8000-0000000000bb"

  defp envelope(version, overrides) do
    Map.merge(
      %{
        "event_id" => UUIDv7.generate(),
        "type" => "chat.device.registered",
        "schema_version" => 1,
        "occurred_at" => "2026-10-26T10:00:00Z",
        "aggregate_type" => "conversation",
        "aggregate_id" => @aggregate_id,
        "aggregate_version" => version,
        "payload" => %{"device_id" => "d-1"}
      },
      overrides
    )
  end

  defp record!(version, overrides \\ %{}) do
    {:ok, row} = Outbox.record(envelope(version, overrides))
    row
  end

  defp new_calls, do: :ets.new(:calls, [:ordered_set, :public])

  defp calls(ets) do
    ets
    |> :ets.tab2list()
    |> Enum.sort_by(fn {sequence, _envelope} -> sequence end)
    |> Enum.map(fn {_sequence, envelope} -> envelope end)
  end

  defp client(ets, fun) do
    fn envelope ->
      :ets.insert(ets, {:ets.info(ets, :size) + 1, envelope})
      fun.(envelope)
    end
  end

  defp unpublished_ids do
    Enum.map(Outbox.unpublished(), & &1.id)
  end

  test "publishes unpublished rows in per-aggregate version order and marks them published" do
    a1 = record!(1)
    b1 = record!(1, %{"aggregate_id" => @other_aggregate_id})
    a2 = record!(2)
    calls_ets = new_calls()

    assert {:ok, published} =
             Relay.publish_batch(http_client: client(calls_ets, fn _ -> {:ok, 201} end))

    assert published == [a1.id, a2.id, b1.id]
    assert Enum.map(calls(calls_ets), & &1["event_id"]) == [a1.id, a2.id, b1.id]
    assert unpublished_ids() == []
  end

  test "publishes the rebuilt envelope, not the stored row" do
    row = record!(3)
    calls_ets = new_calls()

    assert {:ok, [id]} =
             Relay.publish_batch(http_client: client(calls_ets, fn _ -> {:ok, 201} end))

    assert id == row.id

    assert [published] = calls(calls_ets)
    assert published == Envelope.from_outbox(Repo.get!(Outbox, row.id))
    assert published["event_id"] == row.id
    assert published["occurred_at"] == "2026-10-26T10:00:00.000000Z"
    assert published["aggregate_version"] == 3
  end

  test "200 is an accepted duplicate publish" do
    row = record!(1)

    assert {:ok, [id]} = Relay.publish_batch(http_client: fn _ -> {:ok, 200} end)
    assert id == row.id
    assert unpublished_ids() == []
  end

  test "does not republish rows that are already published" do
    first = record!(1)
    second = record!(2)
    assert :ok = Outbox.mark_published(first.id)

    calls_ets = new_calls()

    assert {:ok, [id]} =
             Relay.publish_batch(http_client: client(calls_ets, fn _ -> {:ok, 201} end))

    assert id == second.id
    assert Enum.map(calls(calls_ets), & &1["event_id"]) == [second.id]
  end

  test "stops at the first unconfirmed version and retries it next tick" do
    v1 = record!(1)
    v2 = record!(2)
    calls_ets = new_calls()

    gated =
      client(calls_ets, fn
        %{"event_id" => event_id} when event_id == v1.id -> {:ok, 201}
        _envelope -> {:error, :timeout}
      end)

    assert {:ok, [published_id]} = Relay.publish_batch(http_client: gated)
    assert published_id == v1.id
    assert Enum.map(calls(calls_ets), & &1["event_id"]) == [v1.id, v2.id]
    assert unpublished_ids() == [v2.id]

    assert {:ok, [retried_id]} =
             Relay.publish_batch(http_client: fn _ -> {:ok, 201} end)

    assert retried_id == v2.id
    assert unpublished_ids() == []
  end

  test "retries the same event id with identical rebuilt content" do
    row = record!(1)

    first_calls = new_calls()

    assert {:ok, []} =
             Relay.publish_batch(http_client: client(first_calls, fn _ -> {:error, :timeout} end))

    second_calls = new_calls()

    assert {:ok, [id]} =
             Relay.publish_batch(http_client: client(second_calls, fn _ -> {:ok, 201} end))

    assert id == row.id
    assert [first_attempt] = calls(first_calls)
    assert [second_attempt] = calls(second_calls)
    assert first_attempt == second_attempt
  end

  test "a rejection halts later versions of the same aggregate" do
    v1 = record!(1)
    v2 = record!(2)
    calls_ets = new_calls()

    assert {:ok, []} =
             Relay.publish_batch(http_client: client(calls_ets, fn _ -> {:ok, 409} end))

    assert Enum.map(calls(calls_ets), & &1["event_id"]) == [v1.id]
    assert unpublished_ids() == [v1.id, v2.id]
  end

  test "a rejection on one aggregate does not block another aggregate" do
    a1 = record!(1)
    a2 = record!(2)
    b1 = record!(1, %{"aggregate_id" => @other_aggregate_id})
    calls_ets = new_calls()

    rejecting_a =
      client(calls_ets, fn envelope ->
        if envelope["event_id"] == a1.id, do: {:ok, 409}, else: {:ok, 201}
      end)

    assert {:ok, [published_id]} = Relay.publish_batch(http_client: rejecting_a)
    assert published_id == b1.id

    # a1 was rejected, a2 was never attempted, and b1 still published.
    assert Enum.map(calls(calls_ets), & &1["event_id"]) == [a1.id, b1.id]
    assert unpublished_ids() == [a1.id, a2.id]
  end

  test "a retryable failure on one aggregate does not block another aggregate" do
    a1 = record!(1)
    b1 = record!(1, %{"aggregate_id" => @other_aggregate_id})

    timing_out_a = fn envelope ->
      if envelope["event_id"] == a1.id, do: {:error, :timeout}, else: {:ok, 201}
    end

    assert {:ok, [published_id]} = Relay.publish_batch(http_client: timing_out_a)
    assert published_id == b1.id
    assert unpublished_ids() == [a1.id]
  end

  test "halts on non-retryable statuses without attempting later rows" do
    for status <- [400, 401, 403, 404, 409, 413, 422, 302, 204] do
      row = record!(1, %{"aggregate_id" => UUIDv7.generate()})
      calls_ets = new_calls()

      assert {:ok, []} =
               Relay.publish_batch(http_client: client(calls_ets, fn _ -> {:ok, status} end)),
             "expected HTTP #{status} to halt the relay"

      assert length(calls(calls_ets)) == 1
      assert unpublished_ids() == [row.id]

      Repo.delete_all(Outbox)
    end
  end

  test "retries on transient statuses" do
    for status <- [408, 425, 429, 500, 503, 599] do
      row = record!(1, %{"aggregate_id" => UUIDv7.generate()})
      calls_ets = new_calls()

      assert {:ok, []} =
               Relay.publish_batch(http_client: client(calls_ets, fn _ -> {:ok, status} end)),
             "expected HTTP #{status} to be retried"

      assert length(calls(calls_ets)) == 1
      assert unpublished_ids() == [row.id]

      Repo.delete_all(Outbox)
    end
  end

  test "retries on transport errors" do
    row = record!(1)

    assert {:ok, []} =
             Relay.publish_batch(http_client: fn _ -> {:error, :econnrefused} end)

    assert unpublished_ids() == [row.id]
  end

  test "publishes an event without an aggregate" do
    env = %{
      "event_id" => UUIDv7.generate(),
      "type" => "chat.server.started",
      "schema_version" => 1,
      "occurred_at" => "2026-10-26T10:00:00.500000Z",
      "payload" => %{"node" => "chat-1"}
    }

    {:ok, row} = Outbox.record(env)
    calls_ets = new_calls()

    assert {:ok, [id]} =
             Relay.publish_batch(http_client: client(calls_ets, fn _ -> {:ok, 201} end))

    assert id == row.id

    assert [published] = calls(calls_ets)
    refute Map.has_key?(published, "aggregate_type")
    refute Map.has_key?(published, "trace_id")
    assert published["occurred_at"] == "2026-10-26T10:00:00.500000Z"
    assert unpublished_ids() == []
  end

  test "does nothing when the outbox is empty" do
    assert {:ok, []} = Relay.publish_batch(http_client: fn _ -> flunk("must not publish") end)
  end
end
