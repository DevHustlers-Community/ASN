defmodule AsnChat.Devices.DeviceTest do
  use ExUnit.Case, async: true

  alias AsnChat.Devices.Device
  alias AsnChat.UUIDv7

  defp valid_attrs(overrides \\ %{}) do
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

  defp changeset(attrs, opts \\ []) do
    user_id = Keyword.get(opts, :user_id, UUIDv7.generate())

    Device.registration_changeset(user_id, attrs, Keyword.delete(opts, :user_id))
  end

  test "a valid registration changeset sets context-owned fields" do
    user_id = UUIDv7.generate()
    id = UUIDv7.generate()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    attrs = valid_attrs()

    changeset = Device.registration_changeset(user_id, attrs, id: id, now: now)

    assert changeset.valid?
    device = Ecto.Changeset.apply_changes(changeset)

    assert device.id == id
    assert device.user_id == user_id
    assert device.status == :active
    assert device.created_at == now
    assert device.platform == :android
    assert device.identity_key_public == attrs["identity_key_public"]
    assert String.at(device.id, 14) == "7"
  end

  test "user_id, id, and status cannot be supplied through attrs" do
    user_id = UUIDv7.generate()
    id = UUIDv7.generate()

    attrs =
      valid_attrs(%{
        "user_id" => UUIDv7.generate(),
        "id" => UUIDv7.generate(),
        "status" => "revoked"
      })

    changeset = Device.registration_changeset(user_id, attrs, id: id)
    device = Ecto.Changeset.apply_changes(changeset)

    assert device.user_id == user_id
    assert device.id == id
    assert device.status == :active
  end

  test "rejects an unsupported platform" do
    changeset = changeset(valid_attrs(%{"platform" => "desktop"}))
    refute changeset.valid?
    assert changeset.errors[:platform]
  end

  test "accepts fingerprint lengths at the contract bounds" do
    assert changeset(valid_attrs(%{"identity_key_fingerprint" => String.duplicate("a", 16)})).valid?

    assert changeset(valid_attrs(%{"identity_key_fingerprint" => String.duplicate("a", 128)})).valid?
  end

  test "rejects fingerprint lengths outside the contract bounds" do
    refute changeset(valid_attrs(%{"identity_key_fingerprint" => String.duplicate("a", 15)})).valid?

    refute changeset(valid_attrs(%{"identity_key_fingerprint" => String.duplicate("a", 129)})).valid?
  end

  test "accepts an 80 code point label" do
    assert changeset(valid_attrs(%{"device_label" => String.duplicate("a", 80)})).valid?
  end

  test "rejects labels over 80 code points even when grapheme count is lower" do
    # Each grapheme is two code points; PostgreSQL varchar(80) counts code points.
    label = String.duplicate("e\u0301", 80)
    assert String.length(label) == 80

    changeset = changeset(valid_attrs(%{"device_label" => label}))

    refute changeset.valid?
    assert changeset.errors[:device_label]
  end

  test "rejects null bytes in text fields" do
    label_changeset = changeset(valid_attrs(%{"device_label" => "bad" <> <<0>>}))
    refute label_changeset.valid?
    assert label_changeset.errors[:device_label]

    fingerprint_changeset =
      changeset(valid_attrs(%{"identity_key_fingerprint" => "fingerprint-1234" <> <<0>>}))

    refute fingerprint_changeset.valid?
    assert fingerprint_changeset.errors[:identity_key_fingerprint]
  end

  test "rejects invalid UTF-8 in text fields" do
    changeset = changeset(valid_attrs(%{"device_label" => <<0xFF>>}))
    refute changeset.valid?
    assert changeset.errors[:device_label]
  end

  test "rejects an empty public key" do
    changeset = changeset(valid_attrs(%{"identity_key_public" => <<>>}))
    refute changeset.valid?
    assert changeset.errors[:identity_key_public]
  end

  test "revoke_changeset/2 marks the device revoked" do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    device = %Device{
      id: UUIDv7.generate(),
      user_id: UUIDv7.generate(),
      platform: :android,
      identity_key_public: :crypto.strong_rand_bytes(32),
      identity_key_fingerprint: "fingerprint-123456",
      status: :active,
      created_at: now
    }

    revoked = device |> Device.revoke_changeset(now) |> Ecto.Changeset.apply_changes()

    assert revoked.status == :revoked
    assert revoked.revoked_at == now
  end
end
