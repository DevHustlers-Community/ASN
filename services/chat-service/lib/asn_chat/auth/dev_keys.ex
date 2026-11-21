defmodule AsnChat.Auth.DevKeys do
  @moduledoc """
  Development-only RSA key material for local JWT issuance.

  The key is generated on first use and written to a gitignored path with
  `0600` permissions. It exists only to exercise the same claim shape and
  validation path as Auth0; it is never used in production. Tests inject their
  own JWKS instead.
  """

  @key_size 2048
  @kid_prefix "dev-"

  @type key_path :: String.t()

  @doc """
  Returns the private development JWK, generating and persisting it when absent.
  """
  @spec key(key_path()) :: {:ok, JOSE.JWK.t()} | {:error, :key_unavailable}
  def key(path) when is_binary(path) do
    case File.read(path) do
      {:ok, json} ->
        decode(json)

      {:error, :enoent} ->
        generate(path)

      {:error, _reason} ->
        {:error, :key_unavailable}
    end
  end

  @doc """
  Returns the public JWKS for the development key.
  """
  @spec jwks(key_path()) :: {:ok, map()} | {:error, :key_unavailable}
  def jwks(path) do
    with {:ok, jwk} <- key(path) do
      public = JOSE.JWK.to_public(jwk)
      {_fields, map} = JOSE.JWK.to_map(public)
      {:ok, %{"keys" => [map]}}
    end
  end

  defp generate(path) do
    jwk = JOSE.JWK.generate_key({:rsa, @key_size})
    {_fields, map} = JOSE.JWK.to_map(jwk)
    kid = @kid_prefix <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)
    map = Map.put(map, "kid", kid)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, Jason.encode!(map), [:binary]),
         :ok <- File.chmod(path, 0o600) do
      {:ok, JOSE.JWK.from_map(map)}
    else
      _ -> {:error, :key_unavailable}
    end
  rescue
    _ -> {:error, :key_unavailable}
  end

  defp decode(json) do
    with {:ok, map} when is_map(map) <- Jason.decode(json),
         jwk when not is_nil(jwk) <- JOSE.JWK.from_map(map) do
      {:ok, jwk}
    else
      _ -> {:error, :key_unavailable}
    end
  rescue
    _ -> {:error, :key_unavailable}
  end
end
