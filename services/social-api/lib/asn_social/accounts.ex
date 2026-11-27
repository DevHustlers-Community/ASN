defmodule AsnSocial.Accounts do
  @moduledoc "Account identity, authorization state, and user lifecycle events."

  import Ecto.Query

  alias AsnSocial.Accounts.User
  alias AsnSocial.Events.{Outbox, UserEvents}
  alias AsnSocial.Repo

  @spec create_user(map(), keyword()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def create_user(attrs, opts \\ []) do
    Repo.transaction(fn ->
      changeset = User.create_changeset(attrs, opts)

      with {:ok, user} <- Repo.insert(changeset),
           {:ok, _event} <- Outbox.record(UserEvents.created(user, opts)) do
        user
      else
        {:error, %Ecto.Changeset{} = error} -> Repo.rollback(error)
      end
    end)
  end

  @spec authorization(String.t()) :: {:ok, map()} | {:error, :not_found}
  def authorization(user_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(user_id) do
      case Repo.one(
             from u in User,
               where: u.id == ^uuid,
               select: {u.id, u.status, u.sessions_valid_after}
           ) do
        nil ->
          {:error, :not_found}

        {id, status, sessions_valid_after} ->
          user = %User{id: id, status: status, sessions_valid_after: sessions_valid_after}
          {:ok, User.authorization_view(user)}
      end
    else
      _ -> {:error, :not_found}
    end
  end
end
