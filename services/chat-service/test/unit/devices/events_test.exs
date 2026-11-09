defmodule AsnChat.Devices.EventsTest do
  use ExUnit.Case, async: true

  alias AsnChat.Devices.{Device, Events}
  alias AsnChat.Events.Envelope
  alias AsnChat.UUIDv7

  @examples Path.expand("../../../../../contracts/events/examples", __DIR__)

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)

  defp device(overrides \\ %{}) do
    now = now()

    defaults = %{
      id: UUIDv7.generate(),
      user_id: UUIDv7.generate(),
      platform: :android,
      device_label: "Test device",
      identity_key_public: :crypto.strong_rand_bytes(32),
      identity_key_fingerprint: "fingerprint-#{System.unique_integer([:positive])}",
      status: :active,
      created_at: now,
      revoked_at: nil
    }

    struct!(Device, Map.merge(defaults, Map.new(overrides)))
  end

  defp example(name) do
    @examples
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
  end

  test "registered/2 builds a v1 device envelope with identifiers only" do
    device = device()
    envelope = Events.registered(device)

    assert envelope["type"] == "chat.device.registered"
    assert envelope["schema_version"] == 1
    assert envelope["aggregate_type"] == "device"
    assert envelope["aggregate_id"] == device.id
    assert envelope["aggregate_version"] == 1
    assert envelope["occurred_at"] == device.created_at
    refute Map.has_key?(envelope, "trace_id")

    assert envelope["payload"] == %{
             "device_id" => device.id,
             "user_id" => device.user_id,
             "platform" => "android",
             "identity_key_fingerprint" => device.identity_key_fingerprint
           }

    refute Map.has_key?(envelope["payload"], "identity_key_public")
    refute Map.has_key?(envelope["payload"], "device_label")
  end

  test "revoked/2 builds a v2 device envelope with identifiers only" do
    revoked_at = now()
    device = device(%{status: :revoked, revoked_at: revoked_at})
    envelope = Events.revoked(device)

    assert envelope["type"] == "chat.device.revoked"
    assert envelope["schema_version"] == 1
    assert envelope["aggregate_type"] == "device"
    assert envelope["aggregate_id"] == device.id
    assert envelope["aggregate_version"] == 2
    assert envelope["occurred_at"] == revoked_at

    assert envelope["payload"] == %{
             "device_id" => device.id,
             "user_id" => device.user_id
           }
  end

  test "trace_id is included only when provided" do
    device = device()

    refute Map.has_key?(Events.registered(device), "trace_id")
    refute Map.has_key?(Events.registered(device, trace_id: nil), "trace_id")
    refute Map.has_key?(Events.registered(device, trace_id: ""), "trace_id")

    envelope = Events.registered(device, trace_id: "trace-123")
    assert envelope["trace_id"] == "trace-123"
  end

  test "every event gets a distinct UUIDv7 event id" do
    device = device()

    event_ids =
      for _ <- 1..20 do
        Events.registered(device)["event_id"]
      end

    assert length(Enum.uniq(event_ids)) == 20

    assert Enum.all?(event_ids, fn id ->
             {:ok, _} = Ecto.UUID.cast(id)
             String.at(id, 14) == "7"
             String.at(id, 19) in ~w(8 9 a b)
           end)
  end

  test "registered/2 requires created_at" do
    assert_raise ArgumentError, fn ->
      Events.registered(%Device{id: UUIDv7.generate(), created_at: nil})
    end
  end

  test "revoked/2 requires revoked_at" do
    assert_raise ArgumentError, fn ->
      Events.revoked(%Device{id: UUIDv7.generate(), revoked_at: nil})
    end
  end

  test "registered envelope keys match the committed contract example" do
    example = example("valid-chat-device-registered.json")
    device = device()

    envelope =
      Envelope.from_outbox(%{
        id: UUIDv7.generate(),
        type: "chat.device.registered",
        schema_version: 1,
        occurred_at: device.created_at,
        aggregate_type: "device",
        aggregate_id: device.id,
        aggregate_version: 1,
        trace_id: "trace-123",
        payload: Events.registered(device)["payload"]
      })

    assert sorted_keys(envelope) == sorted_keys(example)
    assert sorted_keys(envelope["payload"]) == sorted_keys(example["payload"])
  end

  test "revoked envelope keys match the committed contract example" do
    example = example("valid-chat-device-revoked.json")
    device = device(%{status: :revoked, revoked_at: now()})

    envelope =
      Envelope.from_outbox(%{
        id: UUIDv7.generate(),
        type: "chat.device.revoked",
        schema_version: 1,
        occurred_at: device.revoked_at,
        aggregate_type: "device",
        aggregate_id: device.id,
        aggregate_version: 2,
        trace_id: "trace-123",
        payload: Events.revoked(device)["payload"]
      })

    assert sorted_keys(envelope) == sorted_keys(example)
    assert sorted_keys(envelope["payload"]) == sorted_keys(example["payload"])
  end

  defp sorted_keys(map), do: map |> Map.keys() |> Enum.sort()
end
