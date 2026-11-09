defmodule AsnChat.AccountsTest do
  use AsnChat.DataCase, async: true

  alias AsnChat.Accounts
  alias AsnChat.Accounts.User
  alias AsnChat.UUIDv7

  test "lock_user/1 returns the projected user" do
    user = user_fixture()

    assert {:ok, %User{id: id}} = Repo.transaction(fn -> Accounts.lock_user(user.id) end)
    assert id == user.id
  end

  test "lock_user/1 returns nil for an unknown user" do
    assert {:ok, nil} =
             Repo.transaction(fn -> Accounts.lock_user(UUIDv7.generate()) end)
  end

  test "lock_user/1 returns nil for a malformed id" do
    assert {:ok, nil} =
             Repo.transaction(fn -> Accounts.lock_user("not-a-uuid") end)
  end
end
