defmodule AsnChat.Auth.JwksTest do
  use ExUnit.Case, async: false

  alias AsnChat.Auth.Jwks

  @cache_key {Jwks, :jwks}
  @url "http://127.0.0.1:1/jwks"

  setup do
    :persistent_term.erase(@cache_key)

    config =
      Application.get_env(:asn_chat, :auth, [])
      |> Keyword.put(:jwks, nil)
      |> Keyword.put(:dev_keys_path, nil)
      |> Keyword.put(:jwks_url, @url)
      |> Keyword.put(:jwks_cache_ms, 1)
      |> Keyword.put(:jwks_timeout_ms, 100)

    on_exit(fn -> :persistent_term.erase(@cache_key) end)
    %{config: config}
  end

  defp jwks do
    jwk = JOSE.JWK.generate_key({:rsa, 2048})
    {_fields, public} = JOSE.JWK.to_map(JOSE.JWK.to_public(jwk))
    %{"keys" => [Map.put(public, "kid", "cached-key")]}
  end

  test "a stale cache is used when a refresh fails", %{config: config} do
    :persistent_term.put(@cache_key, %{
      url: @url,
      fetched_at: System.monotonic_time(:millisecond) - 10_000,
      jwks: jwks()
    })

    assert {:ok, _key} = Jwks.key_for("cached-key", config)
  end

  test "an unknown kid is an authentication failure", %{config: config} do
    :persistent_term.put(@cache_key, %{
      url: @url,
      fetched_at: System.monotonic_time(:millisecond),
      jwks: jwks()
    })

    assert {:error, :unknown_key} = Jwks.key_for("other-key", config)
  end

  test "a non-https JWKS url is rejected without a request", %{config: config} do
    assert {:error, :jwks_unavailable} = Jwks.key_for("cached-key", config)
  end
end
