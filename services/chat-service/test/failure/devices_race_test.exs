defmodule AsnChat.Devices.RaceTest do
  @moduledoc """
  Real-database race tests for device registration and revocation.

  These tests intentionally bypass the SQL sandbox so two processes can hold
  separate connections and contend on the same `chat_users` row. They are
  synchronous to avoid interfering with sandboxed tests.
  """

  use ExUnit.Case, async: false

  import Ecto.Query

  alias AsnChat.Accounts.User
  alias AsnChat.ChatFixtures
  alias AsnChat.Devices
  alias AsnChat.Devices.Device
  alias AsnChat.Events.Outbox
  alias AsnChat.Repo

  @moduletag :race

  setup do
    user = unboxed(fn -> ChatFixtures.user_fixture() end)

    on_exit(fn ->
      unboxed(fn ->
        device_ids = Repo.all(from d in Device, where: d.user_id == ^user.id, select: d.id)

        Repo.delete_all(
          from e in Outbox,
            where: e.aggregate_type == "device" and e.aggregate_id in ^device_ids
        )

        Repo.delete_all(from d in Device, where: d.user_id == ^user.id)
        Repo.delete_all(from u in User, where: u.id == ^user.id)
      end)
    end)

    %{user: user}
  end

  test "concurrent registration with the same key creates one device and one event", %{
    user: user
  } do
    attrs = device_attrs()

    results = race(fn -> Devices.register_device(user.id, attrs) end)

    assert [{:ok, first, first_status}, {:ok, second, second_status}] = results
    assert first.id == second.id
    assert Enum.sort([first_status, second_status]) == [:created, :existing]

    assert [%Outbox{aggregate_version: 1}] = device_events(user.id)
  end

  test "concurrent registration with different keys creates one device and one conflict", %{
    user: user
  } do
    fingerprint = "race-fingerprint-123456"

    first_attrs =
      device_attrs(%{
        "identity_key_fingerprint" => fingerprint,
        "identity_key_public" => :crypto.strong_rand_bytes(32)
      })

    second_attrs =
      device_attrs(%{
        "identity_key_fingerprint" => fingerprint,
        "identity_key_public" => :crypto.strong_rand_bytes(32)
      })

    results =
      race(
        fn -> Devices.register_device(user.id, first_attrs) end,
        fn -> Devices.register_device(user.id, second_attrs) end
      )

    assert Enum.any?(results, &match?({:ok, _device, :created}, &1))
    assert Enum.any?(results, &match?({:error, :identity_key_conflict}, &1))

    assert [%Outbox{aggregate_version: 1}] = device_events(user.id)
  end

  test "concurrent revocation emits exactly one v2 event", %{user: user} do
    assert {:ok, device, :created} =
             unboxed(fn -> Devices.register_device(user.id, device_attrs()) end)

    results =
      race(
        fn -> Devices.revoke_device(user.id, device.id) end,
        fn -> Devices.revoke_device(user.id, device.id) end
      )

    statuses = Enum.map(results, fn {:ok, _device, status} -> status end)
    assert Enum.sort(statuses) == [:already_revoked, :revoked]

    events = device_events(user.id)
    assert length(events) == 2
    assert Enum.count(events, &(&1.aggregate_version == 2)) == 1
  end

  defp race(fun), do: race(fun, fun)

  defp race(first_fun, second_fun) do
    parent = self()

    tasks = [
      Task.async(fn -> run_after_barrier(parent, first_fun) end),
      Task.async(fn -> run_after_barrier(parent, second_fun) end)
    ]

    pids =
      for _ <- 1..2 do
        assert_receive {:ready, pid}, 5_000
        pid
      end

    Enum.each(pids, &send(&1, :go))
    Task.await_many(tasks, 15_000)
  end

  defp run_after_barrier(parent, fun) do
    send(parent, {:ready, self()})

    receive do
      :go -> :ok
    end

    unboxed(fn -> fun.() end)
  end

  defp unboxed(fun) do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fun)
  end

  defp device_events(user_id) do
    unboxed(fn ->
      device_ids = Repo.all(from d in Device, where: d.user_id == ^user_id, select: d.id)

      Repo.all(
        from e in Outbox,
          where: e.aggregate_type == "device" and e.aggregate_id in ^device_ids,
          order_by: [asc: e.aggregate_version]
      )
    end)
  end

  defp device_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "platform" => "android",
        "device_label" => "Race device",
        "identity_key_public" => :crypto.strong_rand_bytes(32),
        "identity_key_fingerprint" => "race-fingerprint-#{System.unique_integer([:positive])}"
      },
      overrides
    )
  end
end
