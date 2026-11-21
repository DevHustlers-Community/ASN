defmodule Mix.Tasks.AsnChat.DevToken do
  @shortdoc "Mints a development JWT access token"

  @moduledoc """
  Mints a JWT for local development using the generated development key.

      mix asn_chat.dev_token --user 0190f1e2-6d7e-7f80-b192-3d4e5f607182

  Options:

    * `--user` (required) - `chat_users.id` / `social_db.users.id` as UUIDv7
    * `--ttl` - access-token lifetime in seconds (default 900)

  The token uses the same issuer, audience, claim namespace, and scopes as the
  configured validation path. It is for local development only; the development
  key file is gitignored and must never be used outside a development machine.
  """

  use Mix.Task

  @default_ttl 900

  @impl true
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args, strict: [user: :string, ttl: :integer])

    user_id = opts[:user] || Mix.raise("--user is required")
    ttl = opts[:ttl] || @default_ttl

    if ttl <= 0 do
      Mix.raise("--ttl must be a positive integer")
    end

    case Ecto.UUID.cast(user_id) do
      {:ok, uuid} -> mint(uuid, ttl)
      :error -> Mix.raise("--user must be a UUID")
    end
  end

  defp mint(user_id, ttl) do
    auth = Application.get_env(:asn_chat, :auth, [])
    path = auth[:dev_keys_path] || Mix.raise("dev_keys_path is not configured")

    {:ok, jwk} = AsnChat.Auth.DevKeys.key(path)
    {_fields, map} = JOSE.JWK.to_map(jwk)

    now = System.system_time(:second)

    claims = %{
      "iss" => auth[:issuer],
      "aud" => auth[:audience],
      "sub" => "dev|" <> user_id,
      "iat" => now,
      "exp" => now + ttl,
      "scope" => "chat:read chat:write chat:devices",
      auth[:user_id_claim] => user_id
    }

    token =
      JOSE.JWT.sign(jwk, %{"alg" => "RS256", "kid" => map["kid"]}, claims)
      |> JOSE.JWS.compact()
      |> elem(1)

    Mix.shell().info(token)
  end
end
