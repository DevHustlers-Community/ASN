defmodule AsnChat.Authorization.SocialClient do
  @moduledoc """
  Production authorization check against Social's internal M2M endpoint.

  Chat never reads `social_db`. It calls one narrow Social REST endpoint with a
  service token and fails closed on any timeout, transport error, non-200
  response, or malformed body (ADR 0016). The endpoint contract is a Social
  follow-up; until it exists and `SOCIAL_INTERNAL_URL` plus an M2M token
  provider are configured, every call returns `{:error, :unavailable}`.
  """

  @behaviour AsnChat.Authorization

  @spec authorize(String.t(), DateTime.t(), keyword()) ::
          :ok | {:error, :inactive | :stale_token | :unavailable}
  @impl true
  def authorize(user_id, %DateTime{} = issued_at, opts \\ []) do
    config = Application.get_env(:asn_chat, :auth, [])
    http_get = Keyword.get(opts, :http_get, &get/4)

    with {:ok, base_url} <- fetch_string(config, :social_base_url),
         {:ok, token} <- m2m_token(config),
         {:ok, body} <- http_get.(base_url, user_id, token, config),
         {:ok, status, cutoff} <- decode(body) do
      cond do
        status != "active" -> {:error, :inactive}
        is_nil(cutoff) -> :ok
        DateTime.compare(issued_at, cutoff) == :gt -> :ok
        true -> {:error, :stale_token}
      end
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp fetch_string(config, key) do
    case Keyword.get(config, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :unavailable}
    end
  end

  defp m2m_token(config) do
    case Keyword.get(config, :m2m_token) do
      token when is_binary(token) and token != "" ->
        {:ok, token}

      fun when is_function(fun, 0) ->
        case fun.() do
          {:ok, token} when is_binary(token) and token != "" -> {:ok, token}
          token when is_binary(token) and token != "" -> {:ok, token}
          _ -> {:error, :unavailable}
        end

      _ ->
        {:error, :unavailable}
    end
  end

  defp get(base_url, user_id, token, config) do
    case URI.parse(base_url) do
      %URI{scheme: "https", host: host} when is_binary(host) ->
        do_get(base_url, user_id, token, config)

      _ ->
        {:error, :unavailable}
    end
  end

  # The authorization answer decides whether a request proceeds, so the Social
  # endpoint must be TLS with peer and hostname verification.
  defp do_get(base_url, user_id, token, config) do
    timeout = Keyword.get(config, :authorization_timeout_ms, 300)

    url =
      String.trim_trailing(base_url, "/") <>
        "/internal/v1/users/" <> URI.encode(user_id) <> "/authorization"

    headers = [
      {~c"authorization", String.to_charlist("Bearer " <> token)},
      {~c"accept", ~c"application/json"}
    ]

    request = {String.to_charlist(url), headers}

    http_options = [
      timeout: timeout,
      connect_timeout: timeout,
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      ]
    ]

    options = [body_format: :binary]

    case :httpc.request(:get, request, http_options, options) do
      {:ok, {{_version, 200, _reason}, _headers, body}} -> {:ok, body}
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp decode(body) do
    with {:ok, %{"status" => status} = map} when is_binary(status) <- Jason.decode(body),
         {:ok, cutoff_value} <- Map.fetch(map, "sessions_valid_after"),
         {:ok, cutoff} <- parse_cutoff(cutoff_value) do
      {:ok, status, cutoff}
    else
      _ -> {:error, :unavailable}
    end
  end

  # An explicit null means "no cutoff"; a missing key is a malformed response
  # and fails closed with 503 (ADR 0016 §8).
  defp parse_cutoff(nil), do: {:ok, nil}

  defp parse_cutoff(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> :invalid
    end
  end

  defp parse_cutoff(_value), do: :invalid
end
