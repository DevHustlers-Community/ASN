defmodule AsnChat.Authorization.SocialClientTest do
  use ExUnit.Case, async: false

  alias AsnChat.Authorization.SocialClient

  @issued_at ~U[2026-01-01T00:00:00.000000Z]

  setup do
    auth = Application.get_env(:asn_chat, :auth, [])

    Application.put_env(
      :asn_chat,
      :auth,
      auth
      |> Keyword.put(:social_base_url, "https://social.example")
      |> Keyword.put(:m2m_token, "service-token")
    )

    on_exit(fn -> Application.put_env(:asn_chat, :auth, auth) end)
    :ok
  end

  defp answer(status, cutoff \\ nil) do
    body =
      %{"status" => status, "sessions_valid_after" => cutoff}
      |> Jason.encode!()

    fn _base_url, _user_id, _token, _config -> {:ok, body} end
  end

  test "an active account with no cutoff is allowed" do
    assert :ok = SocialClient.authorize("user", @issued_at, http_get: answer("active"))
  end

  test "an inactive account is rejected" do
    assert {:error, :inactive} =
             SocialClient.authorize("user", @issued_at, http_get: answer("banned"))
  end

  test "a token issued at or before sessions_valid_after is stale" do
    cutoff = "2026-01-01T00:00:00.000000Z"

    assert {:error, :stale_token} =
             SocialClient.authorize("user", @issued_at, http_get: answer("active", cutoff))

    after_cutoff = ~U[2026-01-02T00:00:00.000000Z]

    assert :ok =
             SocialClient.authorize("user", after_cutoff, http_get: answer("active", cutoff))
  end

  test "a missing cutoff or malformed body fails closed" do
    missing =
      fn _base, _user, _token, _config -> {:ok, ~s({"status":"active"})} end

    malformed = fn _base, _user, _token, _config -> {:ok, "not json"} end

    assert {:error, :unavailable} =
             SocialClient.authorize("user", @issued_at, http_get: missing)

    assert {:error, :unavailable} =
             SocialClient.authorize("user", @issued_at, http_get: malformed)
  end

  test "an unavailable dependency fails closed" do
    failing = fn _base, _user, _token, _config -> {:error, :unavailable} end

    assert {:error, :unavailable} =
             SocialClient.authorize("user", @issued_at, http_get: failing)
  end

  test "a non-https base url is rejected before any request" do
    auth = Application.get_env(:asn_chat, :auth, [])

    Application.put_env(
      :asn_chat,
      :auth,
      Keyword.put(auth, :social_base_url, "http://social.example")
    )

    on_exit(fn -> Application.put_env(:asn_chat, :auth, auth) end)

    assert {:error, :unavailable} = SocialClient.authorize("user", @issued_at)
  end
end
