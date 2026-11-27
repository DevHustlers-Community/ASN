defmodule AsnSocial.Auth.Jwks do
  @moduledoc """
  Resolves Auth0 signing keys from static configuration, a development key
  file, or an HTTPS JWKS endpoint with bounded stale reuse.
  """

  @cache_key {__MODULE__, :jwks}

  @type error :: :unknown_key | :jwks_unavailable

  @spec key_for(String.t() | nil, keyword()) :: {:ok, JOSE.JWK.t()} | {:error, error()}
  def key_for(kid, config) do
    with {:ok, jwks} <- jwks(config),
         {:ok, key} <- find_key(jwks, kid) do
      {:ok, JOSE.JWK.from_map(key)}
    else
      {:error, _} = error -> error
    end
  rescue
    _ -> {:error, :jwks_unavailable}
  end

  defp jwks(config) do
    cond do
      is_map(Keyword.get(config, :jwks)) ->
        {:ok, Keyword.get(config, :jwks)}

      path = Keyword.get(config, :dev_keys_path) ->
        AsnSocial.Auth.DevKeys.jwks(path)

      url = Keyword.get(config, :jwks_url) ->
        fetch_cached(url, config)

      true ->
        {:error, :jwks_unavailable}
    end
  end

  defp find_key(%{"keys" => keys}, kid) when is_list(keys) do
    case {kid, keys} do
      {kid, keys} when is_binary(kid) ->
        case Enum.find(keys, &(is_map(&1) and &1["kid"] == kid)) do
          nil -> {:error, :unknown_key}
          key -> {:ok, key}
        end

      _ ->
        {:error, :unknown_key}
    end
  end

  defp find_key(_jwks, _kid), do: {:error, :jwks_unavailable}

  defp fetch_cached(url, config) do
    ttl = Keyword.get(config, :jwks_cache_ms, 300_000)
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get(@cache_key, nil) do
      %{url: ^url, fetched_at: fetched_at, jwks: jwks} when now - fetched_at < ttl ->
        {:ok, jwks}

      cached ->
        case fetch(url, config) do
          {:ok, jwks} ->
            :persistent_term.put(@cache_key, %{
              url: url,
              fetched_at: now,
              jwks: jwks
            })

            {:ok, jwks}

          {:error, _reason} when is_map(cached) ->
            max_stale = Keyword.get(config, :jwks_max_stale_ms, 3_600_000)
            stale_for = now - Map.get(cached, :fetched_at, now)

            if Map.get(cached, :url) == url and stale_for <= max_stale do
              {:ok, cached.jwks}
            else
              {:error, :jwks_unavailable}
            end

          {:error, _reason} ->
            {:error, :jwks_unavailable}
        end
    end
  end

  defp fetch(url, config) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) -> do_fetch(url, config)
      _ -> {:error, :jwks_unavailable}
    end
  end

  defp do_fetch(url, config) do
    timeout = Keyword.get(config, :jwks_timeout_ms, 2_000)
    request = {String.to_charlist(url), [{~c"accept", ~c"application/json"}]}

    http_options = [
      timeout: timeout,
      connect_timeout: timeout,
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      ]
    ]

    case :httpc.request(:get, request, http_options, body_format: :binary) do
      {:ok, {{_version, 200, _reason}, _headers, body}} ->
        with {:ok, %{"keys" => keys} = jwks} when is_list(keys) <- Jason.decode(body) do
          {:ok, jwks}
        else
          _ -> {:error, :jwks_unavailable}
        end

      _ ->
        {:error, :jwks_unavailable}
    end
  rescue
    _ -> {:error, :jwks_unavailable}
  end
end
