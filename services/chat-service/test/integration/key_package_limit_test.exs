defmodule AsnChat.KeyPackageLimitTest do
  use AsnChat.DataCase, async: true

  import AsnChat.ChatFixtures

  alias AsnChat.Devices
  alias AsnChat.Devices.KeyPackage
  alias AsnChat.Repo

  setup do
    user = user_fixture()
    device = device_fixture(%{user_id: user.id})
    %{user: user, device: device}
  end

  defp attrs do
    %{
      ciphersuite: 1,
      expires_at: DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:microsecond),
      last_resort: false
    }
  end

  test "the per-device cap rejects further unconsumed packages", %{user: user, device: device} do
    assert {:ok, _first} =
             Devices.upload_key_package(
               user.id,
               device.id,
               :crypto.strong_rand_bytes(32),
               attrs(),
               max_per_device: 1
             )

    assert {:error, :limit_reached} =
             Devices.upload_key_package(
               user.id,
               device.id,
               :crypto.strong_rand_bytes(32),
               attrs(),
               max_per_device: 1
             )
  end

  test "duplicate bytes are rejected at the context boundary", %{user: user, device: device} do
    bytes = :crypto.strong_rand_bytes(32)

    assert {:ok, _first} = Devices.upload_key_package(user.id, device.id, bytes, attrs())
    assert {:error, :duplicate} = Devices.upload_key_package(user.id, device.id, bytes, attrs())
  end

  test "expired packages do not consume the per-device cap", %{user: user, device: device} do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.insert!(%KeyPackage{
      id: Ecto.UUID.generate(),
      device_id: device.id,
      key_package: :crypto.strong_rand_bytes(32),
      key_package_sha256: :crypto.strong_rand_bytes(32),
      ciphersuite: 1,
      created_at: DateTime.add(now, -2, :day),
      expires_at: DateTime.add(now, -1, :day),
      last_resort: false
    })

    assert {:ok, _uploaded} =
             Devices.upload_key_package(
               user.id,
               device.id,
               :crypto.strong_rand_bytes(32),
               attrs(),
               max_per_device: 1
             )
  end

  test "list_key_packages returns metadata alongside the stored bytes", %{
    user: user,
    device: device
  } do
    bytes = :crypto.strong_rand_bytes(32)
    assert {:ok, _} = Devices.upload_key_package(user.id, device.id, bytes, attrs())

    assert {:ok, [package]} = Devices.list_key_packages(user.id, device.id)
    assert package.device_id == device.id
    assert package.key_package == bytes
  end
end
