defmodule AsnEventBroker.Security do
  @moduledoc """
  Credential verification and authorization for the HTTP edge (ADR 0008 §9).

  Tokens are verified by hashing the presented bearer token and comparing
  constant-time against stored hashes of non-revoked, unexpired credentials.
  The broker's first admin credential is seeded from `BROKER_ADMIN_TOKEN` at
  first boot only (when the credentials table is empty); later rotation
  happens through the admin API.
  """

  import Ecto.Query

  alias AsnEventBroker.{Repo, UUIDv7}
  alias AsnEventBroker.Security.ServiceCredential

  @admin_scopes [:publish, :consume, :admin]

  @spec issue(String.t(), [atom()], keyword()) :: %{credential_id: String.t(), token: String.t()}
  def issue(service_name, scopes, opts \\ []) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    credential =
      %ServiceCredential{}
      |> ServiceCredential.changeset(%{
        credential_id: UUIDv7.generate(),
        service_name: service_name,
        token_hash: hash(token),
        scopes: scopes,
        allowed_event_types: Keyword.get(opts, :allowed_event_types)
      })
      |> Repo.insert!()

    %{credential_id: credential.credential_id, token: token}
  end

  @doc "Seeds the first admin credential when the credentials table is empty."
  @spec bootstrap_admin() :: :seeded | :exists
  def bootstrap_admin do
    token = System.get_env("BROKER_ADMIN_TOKEN")

    if is_binary(token) and token != "" do
      case Repo.aggregate(ServiceCredential, :count) do
        0 ->
          admin = issue("asn-admin", @admin_scopes, opts_for_bootstrap(token))
          seed_token(admin.credential_id, token)
          :seeded

        _ ->
          :exists
      end
    else
      :exists
    end
  end

  defp opts_for_bootstrap(_token), do: []

  # The bootstrap token comes from the environment rather than being
  # generated; replace the generated hash with the environment token's.
  defp seed_token(credential_id, token) do
    Repo.query!("UPDATE service_credentials SET token_hash = $1 WHERE credential_id = $2", [
      hash(token),
      Ecto.UUID.dump!(credential_id)
    ])
  end

  @spec authorize(String.t() | nil) ::
          {:ok, ServiceCredential.t()} | {:error, :unauthorized}
  def authorize(nil), do: {:error, :unauthorized}

  def authorize("Bearer " <> token) when is_binary(token) and token != "" do
    presented = hash(token)

    candidates =
      Repo.all(
        from c in ServiceCredential,
          where: is_nil(c.revoked_at) and (is_nil(c.expires_at) or c.expires_at > ^now())
      )

    matching =
      Enum.find(candidates, fn credential ->
        hash_equals(presented, credential.token_hash)
      end)

    if matching, do: {:ok, matching}, else: {:error, :unauthorized}
  end

  def authorize(_), do: {:error, :unauthorized}

  defp hash_equals(a, b) when byte_size(a) == byte_size(b) do
    :crypto.hash_equals(a, b)
  end

  defp hash_equals(_, _), do: false

  @spec scope_authorized?(ServiceCredential.t(), atom()) :: boolean()
  def scope_authorized?(%ServiceCredential{scopes: scopes}, scope), do: scope in scopes

  @spec event_type_authorized?(ServiceCredential.t(), String.t()) :: boolean()
  def event_type_authorized?(%ServiceCredential{allowed_event_types: nil}, _type), do: true

  def event_type_authorized?(%ServiceCredential{allowed_event_types: types}, type)
      when is_list(types),
      do: type in types

  @doc "Marks a credential revoked (admin rotation/revocation)."
  @spec revoke(String.t()) :: :ok | {:error, :not_found}
  def revoke(credential_id) do
    case Repo.get(ServiceCredential, credential_id) do
      nil ->
        {:error, :not_found}

      credential ->
        credential
        |> Ecto.Changeset.change(
          revoked_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        )
        |> Repo.update!()

        :ok
    end
  end

  defp hash(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
