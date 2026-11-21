defmodule AsnChat.Authorization.DevAdapter do
  @moduledoc """
  Development and test implementation of the authorization check.

  It reads the `chat_users` projection: a missing or hidden account is
  inactive. `sessions_valid_after` has no Chat column because Social owns it;
  development and tests may supply a cutoff globally or per process. Production
  uses `AsnChat.Authorization.SocialClient`.
  """

  @behaviour AsnChat.Authorization

  alias AsnChat.Accounts.User
  alias AsnChat.Repo

  @impl true
  def authorize(user_id, %DateTime{} = issued_at) do
    case Ecto.UUID.cast(user_id) do
      {:ok, uuid} ->
        case Repo.get(User, uuid) do
          nil -> {:error, :inactive}
          %User{hidden_at: hidden_at} when not is_nil(hidden_at) -> {:error, :inactive}
          %User{} -> check_cutoff(user_id, issued_at)
        end

      :error ->
        {:error, :inactive}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp check_cutoff(user_id, issued_at) do
    case cutoff(user_id) do
      nil ->
        :ok

      %DateTime{} = value ->
        if DateTime.compare(issued_at, value) == :gt do
          :ok
        else
          {:error, :stale_token}
        end

      _other ->
        {:error, :unavailable}
    end
  end

  defp cutoff(user_id) do
    Process.get({:asn_chat_dev_sessions_valid_after, user_id}) ||
      case Application.get_env(:asn_chat, :auth, [])[:dev_sessions_valid_after] do
        %{} = cutoffs -> Map.get(cutoffs, user_id)
        value -> value
      end
  end
end
