defmodule AsnChat.Accounts do
  @moduledoc """
  Account projections used by Chat.

  Social owns the account identity; Chat keeps a read-only projection in
  `chat_users`. This context intentionally exposes only the operations other
  Chat contexts need, starting with a row lock used to serialize per-user
  writes.
  """

  import Ecto.Query

  alias AsnChat.Accounts.User
  alias AsnChat.Repo

  @doc """
  Locks the user's projection row inside the caller's transaction.

  Returns the projected user, or `nil` when the id is malformed or the user has
  not been projected yet. The caller must already be inside `Repo.transaction/1`;
  the lock is released when that transaction ends.
  """
  @spec lock_user(String.t()) :: User.t() | nil
  def lock_user(user_id) do
    unless Repo.in_transaction?() do
      raise ArgumentError, "lock_user/1 must be called inside a transaction"
    end

    case Ecto.UUID.cast(user_id) do
      {:ok, uuid} ->
        Repo.one(
          from u in User,
            where: u.id == ^uuid,
            lock: "FOR NO KEY UPDATE"
        )

      :error ->
        nil
    end
  end
end
