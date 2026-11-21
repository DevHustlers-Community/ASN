defmodule AsnChat.Authorization do
  @moduledoc """
  Authoritative account-status and session-revocation check (ADR 0016).

  The check runs before every authenticated handler, for reads and writes. It
  fails closed: an unavailable, timed-out, or malformed answer is
  `{:error, :unavailable}` and the request answers `503`, never a stale allow.
  """

  @prod Mix.env() == :prod

  @type error :: :inactive | :stale_token | :unavailable

  @callback authorize(user_id :: String.t(), issued_at :: DateTime.t()) ::
              :ok | {:error, error()}

  @spec authorize(String.t(), DateTime.t()) :: :ok | {:error, error()}
  def authorize(user_id, %DateTime{} = issued_at) do
    # The per-process override is a test seam only. ADR 0016 §11 forbids an
    # authorization-skip switch in production, so production never reads it.
    adapter =
      if @prod do
        adapter_from_config()
      else
        Process.get(:asn_chat_authorization_adapter) || adapter_from_config()
      end

    adapter.authorize(user_id, issued_at)
  rescue
    _ -> {:error, :unavailable}
  end

  @doc """
  Returns the configured adapter. Tests may override it per process with
  `Process.put(:asn_chat_authorization_adapter, Module)`.
  """
  @spec adapter_from_config() :: module()
  def adapter_from_config do
    :asn_chat
    |> Application.get_env(:auth, [])
    |> Keyword.get(:authorization_adapter, AsnChat.Authorization.SocialClient)
  end
end
