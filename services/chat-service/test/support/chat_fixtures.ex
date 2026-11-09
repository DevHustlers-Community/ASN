defmodule AsnChat.ChatFixtures do
  @moduledoc """
  Test fixtures for Chat database records.

  Fixtures insert valid rows directly so tests can exercise read paths, revoked
  or pending states, and ordering without pretending those states were produced
  by a public context call.
  """

  alias AsnChat.Accounts.User
  alias AsnChat.Devices.Device
  alias AsnChat.Repo
  alias AsnChat.UUIDv7

  @doc """
  Inserts a projected Chat user.
  """
  def user_fixture(attrs \\ %{}) do
    now = now()

    attrs =
      attrs
      |> Map.new()
      |> Map.put_new(:id, UUIDv7.generate())
      |> Map.put_new(:username, "user-#{System.unique_integer([:positive])}")
      |> Map.put_new(:show_presence, true)
      |> Map.put_new(:plan, "free")
      |> Map.put_new(:source_version, 0)
      |> Map.put_new(:created_at, now)
      |> Map.put_new(:updated_at, now)

    struct!(User, attrs) |> Repo.insert!()
  end

  @doc """
  Inserts a device row. Defaults to a valid active device owned by a new user.

  Pass `:user_id` to attach the device to an existing user, and `:status` to
  create `:revoked` or `:pending_verification` rows.
  """
  def device_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    now = now()
    status = Map.get(attrs, :status, :active)

    defaults = %{
      id: UUIDv7.generate(),
      user_id: Map.get_lazy(attrs, :user_id, fn -> user_fixture().id end),
      platform: :android,
      device_label: nil,
      identity_key_public: :crypto.strong_rand_bytes(32),
      identity_key_fingerprint: "fixture-fingerprint-#{System.unique_integer([:positive])}",
      registration_id: nil,
      status: status,
      created_at: now,
      last_seen_at: nil,
      revoked_at: if(status == :revoked, do: now, else: nil)
    }

    attrs = Map.merge(defaults, attrs)

    struct!(Device, attrs) |> Repo.insert!()
  end

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:microsecond)
  end
end
