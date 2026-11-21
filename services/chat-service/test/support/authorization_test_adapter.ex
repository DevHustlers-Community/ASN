defmodule AsnChat.Authorization.TestAdapter do
  @moduledoc """
  Per-process authorization adapter for HTTP tests.

  Defaults to `:ok`; a test can set
  `Process.put({:asn_chat_authorization, user_id}, {:error, reason})` and
  `Process.put(:asn_chat_authorization_adapter, __MODULE__)` to exercise
  inactive, revoked, or unavailable paths without a real Social service.
  """

  @behaviour AsnChat.Authorization

  @impl true
  def authorize(user_id, _issued_at) do
    Process.get({:asn_chat_authorization, user_id}, :ok)
  end
end
