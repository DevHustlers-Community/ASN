defmodule AsnChat.DevicesTest do
  use AsnChat.DataCase, async: true

  alias AsnChat.Devices
  alias AsnChat.Devices.Device
  alias AsnChat.Events.{Envelope, Outbox, Relay}
  alias AsnChat.UUIDv7

  defp device_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "platform" => "android",
        "device_label" => "Test device",
        "identity_key_public" => :crypto.strong_rand_bytes(32),
        "identity_key_fingerprint" => "fingerprint-#{System.unique_integer([:positive])}-abcdef"
      },
      overrides
    )
  end

  defp device_events(device_id) do
    Repo.all(
      from e in Outbox,
        where: e.aggregate_type == "device" and e.aggregate_id == ^device_id,
        order_by: [asc: e.aggregate_version]
    )
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)

  test "register_device/3 creates an active device and a v1 outbox event" do
    user = user_fixture()
    attrs = device_attrs()

    assert {:ok, device, :created} = Devices.register_device(user.id, attrs)

    assert device.status == :active
    assert device.user_id == user.id
    assert device.platform == :android
    assert device.device_label == "Test device"
    assert device.created_at
    assert is_nil(device.revoked_at)
    assert device.identity_key_public == attrs["identity_key_public"]
    assert String.at(device.id, 14) == "7"

    assert [event] = device_events(device.id)
    assert event.published_at == nil
    assert event.type == "chat.device.registered"
    assert event.schema_version == 1
    assert event.aggregate_type == "device"
    assert event.aggregate_id == device.id
    assert event.aggregate_version == 1

    wire = Envelope.from_outbox(event)

    assert wire["payload"] == %{
             "device_id" => device.id,
             "user_id" => user.id,
             "platform" => "android",
             "identity_key_fingerprint" => attrs["identity_key_fingerprint"]
           }

    refute Map.has_key?(wire["payload"], "identity_key_public")
    refute Map.has_key?(wire["payload"], "device_label")
  end

  test "re-registering the same active key is idempotent and writes no event" do
    user = user_fixture()
    attrs = device_attrs()

    assert {:ok, first, :created} = Devices.register_device(user.id, attrs)
    assert {:ok, second, :existing} = Devices.register_device(user.id, attrs)

    assert second.id == first.id
    assert second.created_at == first.created_at
    assert length(device_events(first.id)) == 1
  end

  test "the same fingerprint with different key bytes conflicts and writes nothing" do
    user = user_fixture()
    attrs = device_attrs()

    assert {:ok, device, :created} = Devices.register_device(user.id, attrs)

    conflicting =
      device_attrs(%{
        "identity_key_fingerprint" => attrs["identity_key_fingerprint"],
        "identity_key_public" => :crypto.strong_rand_bytes(32)
      })

    assert {:error, :identity_key_conflict} = Devices.register_device(user.id, conflicting)

    assert Repo.aggregate(from(d in Device, where: d.user_id == ^user.id), :count) == 1
    assert length(device_events(device.id)) == 1
  end

  test "a retry with different platform or label returns the existing device unchanged" do
    user = user_fixture()
    attrs = device_attrs()

    assert {:ok, device, :created} = Devices.register_device(user.id, attrs)

    retry =
      device_attrs(%{
        "platform" => "ios",
        "device_label" => "Different label",
        "identity_key_public" => attrs["identity_key_public"],
        "identity_key_fingerprint" => attrs["identity_key_fingerprint"]
      })

    assert {:ok, existing, :existing} = Devices.register_device(user.id, retry)
    assert existing.id == device.id
    assert existing.platform == :android
    assert existing.device_label == "Test device"
  end

  test "different fingerprints create distinct active devices" do
    user = user_fixture()

    assert {:ok, first, :created} = Devices.register_device(user.id, device_attrs())
    assert {:ok, second, :created} = Devices.register_device(user.id, device_attrs())

    assert first.id != second.id
    assert length(device_events(first.id)) == 1
    assert length(device_events(second.id)) == 1
  end

  test "the same fingerprint is allowed for two different users" do
    first_user = user_fixture()
    second_user = user_fixture()
    attrs = device_attrs()

    assert {:ok, first, :created} = Devices.register_device(first_user.id, attrs)
    assert {:ok, second, :created} = Devices.register_device(second_user.id, attrs)

    assert first.id != second.id
    assert first.identity_key_fingerprint == second.identity_key_fingerprint
  end

  test "an unknown user cannot register a device" do
    assert {:error, :user_not_found} = Devices.register_device(UUIDv7.generate(), device_attrs())
    assert Repo.aggregate(Device, :count) == 0
    assert Repo.aggregate(Outbox, :count) == 0
  end

  test "a malformed user id cannot register a device" do
    assert {:error, :user_not_found} = Devices.register_device("not-a-uuid", device_attrs())
    assert Repo.aggregate(Device, :count) == 0
  end

  test "invalid registration attributes write nothing" do
    user = user_fixture()

    assert {:error, %Ecto.Changeset{} = changeset} =
             Devices.register_device(user.id, device_attrs(%{"platform" => "desktop"}))

    refute changeset.valid?
    assert changeset.errors[:platform]
    assert Repo.aggregate(Device, :count) == 0
    assert Repo.aggregate(Outbox, :count) == 0
  end

  test "a revoked fingerprint can be registered again as a new device" do
    user = user_fixture()
    attrs = device_attrs()

    assert {:ok, first, :created} = Devices.register_device(user.id, attrs)
    assert {:ok, revoked, :revoked} = Devices.revoke_device(user.id, first.id)
    assert revoked.status == :revoked

    assert {:ok, second, :created} = Devices.register_device(user.id, attrs)
    assert second.id != first.id
    assert second.status == :active

    assert [event] = device_events(second.id)
    assert event.aggregate_version == 1
  end

  test "the public key is stored as raw bytes" do
    user = user_fixture()
    key = :crypto.strong_rand_bytes(48)
    attrs = device_attrs(%{"identity_key_public" => key})

    assert {:ok, device, :created} = Devices.register_device(user.id, attrs)
    assert device.identity_key_public == key
  end

  test "device and outbox rows roll back together" do
    user = user_fixture()

    assert {:error, :forced} =
             Repo.transaction(fn ->
               assert {:ok, _device, :created} = Devices.register_device(user.id, device_attrs())
               Repo.rollback(:forced)
             end)

    assert Repo.aggregate(from(d in Device, where: d.user_id == ^user.id), :count) == 0
    assert Repo.aggregate(Outbox, :count) == 0
  end

  test "list_devices/1 returns only the caller's devices, including revoked, ordered by creation" do
    user = user_fixture()
    other_user = user_fixture()

    older = DateTime.add(now(), -60, :second)
    newer = now()

    first = device_fixture(user_id: user.id, created_at: older)

    second =
      device_fixture(user_id: user.id, status: :revoked, created_at: newer, revoked_at: newer)

    _foreign = device_fixture(user_id: other_user.id)

    assert {:ok, [listed_first, listed_second]} = Devices.list_devices(user.id)
    assert listed_first.id == first.id
    assert listed_second.id == second.id
    assert listed_second.status == :revoked
  end

  test "list_devices/1 returns an empty list for a user with no devices" do
    user = user_fixture()

    assert {:ok, []} = Devices.list_devices(user.id)
  end

  test "list_devices/1 returns an empty list for a malformed user id" do
    assert {:ok, []} = Devices.list_devices("not-a-uuid")
  end

  test "revoke_device/3 marks the device revoked and records a v2 event" do
    user = user_fixture()
    assert {:ok, device, :created} = Devices.register_device(user.id, device_attrs())

    assert {:ok, revoked, :revoked} = Devices.revoke_device(user.id, device.id)

    assert revoked.status == :revoked
    assert revoked.revoked_at
    assert DateTime.compare(revoked.revoked_at, revoked.created_at) in [:gt, :eq]

    assert [v1, v2] = device_events(device.id)
    assert v1.aggregate_version == 1
    assert v2.type == "chat.device.revoked"
    assert v2.schema_version == 1
    assert v2.aggregate_version == 2

    assert Envelope.from_outbox(v2)["payload"] == %{
             "device_id" => device.id,
             "user_id" => user.id
           }
  end

  test "revoking an already revoked device is idempotent" do
    user = user_fixture()
    assert {:ok, device, :created} = Devices.register_device(user.id, device_attrs())
    assert {:ok, revoked, :revoked} = Devices.revoke_device(user.id, device.id)

    assert {:ok, again, :already_revoked} = Devices.revoke_device(user.id, device.id)
    assert again.revoked_at == revoked.revoked_at
    assert length(device_events(device.id)) == 2
  end

  test "a user cannot revoke another user's device" do
    owner = user_fixture()
    intruder = user_fixture()
    assert {:ok, device, :created} = Devices.register_device(owner.id, device_attrs())

    assert {:error, :not_found} = Devices.revoke_device(intruder.id, device.id)

    assert Repo.get!(Device, device.id).status == :active
    assert length(device_events(device.id)) == 1
  end

  test "revoking an unknown or malformed device id returns not_found" do
    user = user_fixture()

    assert {:error, :not_found} = Devices.revoke_device(user.id, UUIDv7.generate())
    assert {:error, :not_found} = Devices.revoke_device(user.id, "not-a-uuid")
  end

  test "a pending_verification device can be revoked" do
    user = user_fixture()
    device = device_fixture(user_id: user.id, status: :pending_verification)

    assert {:ok, revoked, :revoked} = Devices.revoke_device(user.id, device.id)
    assert revoked.status == :revoked

    assert [event] = device_events(device.id)
    assert event.aggregate_version == 2
  end

  test "the relay publishes device lifecycle events in aggregate order" do
    user = user_fixture()
    assert {:ok, device, :created} = Devices.register_device(user.id, device_attrs())
    assert {:ok, _revoked, :revoked} = Devices.revoke_device(user.id, device.id)

    [v1, v2] = device_events(device.id)
    test_process = self()

    http_client = fn envelope ->
      send(test_process, {:published, envelope})
      {:ok, 201}
    end

    assert {:ok, published_ids} = Relay.publish_batch(http_client: http_client)
    assert published_ids == [v1.id, v2.id]

    assert_received {:published, first}
    assert_received {:published, second}
    assert first["type"] == "chat.device.registered"
    assert second["type"] == "chat.device.revoked"
    refute Map.has_key?(first["payload"], "identity_key_public")
    refute Map.has_key?(first["payload"], "device_label")

    assert Enum.all?(device_events(device.id), & &1.published_at)
  end

  test "the partial unique index rejects a second active device with the same fingerprint" do
    user = user_fixture()
    fingerprint = "duplicate-fingerprint-1234"
    _existing = device_fixture(user_id: user.id, identity_key_fingerprint: fingerprint)

    changeset =
      Device.registration_changeset(user.id, %{
        "platform" => "ios",
        "identity_key_public" => :crypto.strong_rand_bytes(32),
        "identity_key_fingerprint" => fingerprint
      })

    assert {:error, %Ecto.Changeset{} = error} =
             Repo.transaction(fn ->
               case Repo.insert(changeset) do
                 {:ok, device} -> device
                 {:error, changeset} -> Repo.rollback(changeset)
               end
             end)

    assert error.errors[:user_id]
    assert Repo.aggregate(from(d in Device, where: d.user_id == ^user.id), :count) == 1
  end

  test "a revoked device does not block an active device with the same fingerprint" do
    user = user_fixture()
    fingerprint = "reusable-fingerprint-1234"

    _revoked =
      device_fixture(
        user_id: user.id,
        identity_key_fingerprint: fingerprint,
        status: :revoked
      )

    active = device_fixture(user_id: user.id, identity_key_fingerprint: fingerprint)

    assert active.status == :active
    assert Repo.aggregate(from(d in Device, where: d.user_id == ^user.id), :count) == 2
  end
end
