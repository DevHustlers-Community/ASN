defmodule AsnChat.Auth.Token do
  @moduledoc """
  Verifies Auth0-style JWT access tokens (ADR 0016).

  Signature validation is local: the token's `kid` selects a key from the
  configured JWKS, and only the configured algorithm is accepted. The issuer,
  audience, expiry, issue time, and namespaced `user_id` claim are mandatory;
  `nbf` is validated when present. Authorization freshness is a separate check
  performed by `AsnChat.Authorization`.
  """

  alias AsnChat.Auth.Jwks

  @type claims :: %{
          user_id: String.t(),
          issued_at: DateTime.t(),
          expires_at: DateTime.t(),
          scopes: [String.t()]
        }

  @type error ::
          :invalid_token
          | :expired
          | :unknown_key
          | :jwks_unavailable

  @spec verify(binary(), keyword()) :: {:ok, claims()} | {:error, error()}
  def verify(token, opts \\ []) when is_binary(token) do
    config = Keyword.merge(Application.get_env(:asn_chat, :auth, []), opts)

    with {:ok, header} <- peek_header(token),
         {:ok, alg} <- allowed_algorithm(header["alg"], config),
         {:ok, jwk} <- Jwks.key_for(header["kid"], config),
         {:ok, jwt} <- verify_signature(jwk, alg, token),
         {:ok, claims} <- validate_claims(jwt.fields, config) do
      {:ok, claims}
    end
  end

  defp peek_header(token) do
    try do
      jws = JOSE.JWT.peek_protected(token)
      {_fields, header} = JOSE.JWS.to_map(jws)

      if is_map(header) and is_binary(header["alg"]) do
        {:ok, header}
      else
        {:error, :invalid_token}
      end
    rescue
      _ -> {:error, :invalid_token}
    end
  end

  defp allowed_algorithm(alg, config) when is_binary(alg) do
    allowed = Keyword.get(config, :allowed_algs, ["RS256"])

    if alg in allowed do
      {:ok, alg}
    else
      {:error, :invalid_token}
    end
  end

  defp allowed_algorithm(_alg, _config), do: {:error, :invalid_token}

  defp verify_signature(jwk, alg, token) do
    try do
      case JOSE.JWT.verify_strict(jwk, [alg], token) do
        {true, %JOSE.JWT{} = jwt, _jws} -> {:ok, jwt}
        _ -> {:error, :invalid_token}
      end
    rescue
      _ -> {:error, :invalid_token}
    end
  end

  defp validate_claims(fields, config) when is_map(fields) do
    now = System.system_time(:second)
    leeway = Keyword.get(config, :leeway_seconds, 30)

    with :ok <- check_issuer(fields["iss"], config),
         :ok <- check_audience(fields["aud"], config),
         :ok <- check_exp(fields["exp"], now, leeway),
         :ok <- check_nbf(fields["nbf"], now, leeway),
         {:ok, iat} <- check_iat(fields["iat"], now, leeway),
         {:ok, user_id} <- fetch_user_id(fields, config) do
      {:ok,
       %{
         user_id: user_id,
         issued_at: DateTime.from_unix!(iat, :second),
         expires_at: DateTime.from_unix!(fields["exp"], :second),
         scopes: parse_scopes(fields)
       }}
    end
  end

  defp validate_claims(_fields, _config), do: {:error, :invalid_token}

  defp check_issuer(iss, config) when is_binary(iss) do
    expected = Keyword.get(config, :issuer)

    if is_binary(expected) and iss == expected do
      :ok
    else
      {:error, :invalid_token}
    end
  end

  defp check_issuer(_iss, _config), do: {:error, :invalid_token}

  defp check_audience(aud, config) do
    expected = Keyword.get(config, :audience)

    cond do
      not is_binary(expected) -> {:error, :invalid_token}
      is_binary(aud) and aud == expected -> :ok
      is_list(aud) and expected in aud -> :ok
      true -> {:error, :invalid_token}
    end
  end

  defp check_exp(exp, now, leeway) when is_integer(exp) do
    if exp + leeway > now, do: :ok, else: {:error, :expired}
  end

  defp check_exp(_exp, _now, _leeway), do: {:error, :invalid_token}

  defp check_nbf(nil, _now, _leeway), do: :ok

  defp check_nbf(nbf, now, leeway) when is_integer(nbf) do
    if nbf <= now + leeway, do: :ok, else: {:error, :invalid_token}
  end

  defp check_nbf(_nbf, _now, _leeway), do: {:error, :invalid_token}

  defp check_iat(iat, now, leeway) when is_integer(iat) do
    if iat <= now + leeway, do: {:ok, iat}, else: {:error, :invalid_token}
  end

  defp check_iat(_iat, _now, _leeway), do: {:error, :invalid_token}

  defp fetch_user_id(fields, config) do
    claim = Keyword.get(config, :user_id_claim)
    value = if is_binary(claim), do: fields[claim]

    case value do
      value when is_binary(value) ->
        case Ecto.UUID.cast(value) do
          {:ok, uuid} -> {:ok, uuid}
          :error -> {:error, :invalid_token}
        end

      _ ->
        {:error, :invalid_token}
    end
  end

  defp parse_scopes(%{"scope" => scope}) when is_binary(scope) do
    String.split(scope, " ", trim: true)
  end

  defp parse_scopes(%{"scopes" => scopes}) when is_list(scopes) do
    Enum.filter(scopes, &is_binary/1)
  end

  defp parse_scopes(_fields), do: []
end
