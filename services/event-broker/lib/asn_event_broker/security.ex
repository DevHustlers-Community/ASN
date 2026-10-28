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
  require Logger

  alias AsnEventBroker.{Audit, Repo, UUIDv7}
  alias AsnEventBroker.Security.ServiceCredential

  @admin_scopes [:publish, :consume, :admin]

  @doc """
  Issues a credential and its audit entry in one transaction.

  Validation failures (for example a blank `service_name` or an empty
  `allowed_event_types`) return `{:error, changeset}` so the edge can answer
  400 instead of crashing.
  """
  @spec issue(String.t(), [atom()], keyword()) ::
          {:ok, %{credential_id: String.t(), token: String.t()}}
          | {:error, Ecto.Changeset.t()}
  def issue(service_name, scopes, opts \\ []) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    allowed_event_types = Keyword.get(opts, :allowed_event_types)

    changeset =
      %ServiceCredential{}
      |> ServiceCredential.changeset(%{
        credential_id: UUIDv7.generate(),
        service_name: service_name,
        token_hash: hash(token),
        scopes: scopes,
        allowed_event_types: allowed_event_types
      })

    # Audited per ADR 0008 §9. The plaintext token is never recorded; the
    # bootstrap credential (no actor yet) is its own audit actor. The insert
    # and its audit entry commit together or not at all.
    Repo.transaction(fn ->
      case Repo.insert(changeset) do
        {:ok, credential} ->
          Audit.record(
            Keyword.get(opts, :actor_credential_id) || credential.credential_id,
            "credential.create",
            "credential:" <> credential.credential_id,
            %{
              "service_name" => service_name,
              "scopes" => Enum.map(scopes, &to_string/1),
              "allowed_event_types" => allowed_event_types
            }
          )

          %{credential_id: credential.credential_id, token: token}

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc "Seeds the first admin credential when the credentials table is empty."
  @spec bootstrap_admin() :: :seeded | :exists
  def bootstrap_admin do
    token = System.get_env("BROKER_ADMIN_TOKEN")

    if is_binary(token) and token != "" do
      case Repo.aggregate(ServiceCredential, :count) do
        0 ->
          # The generated-hash insert and the environment-token rewrite (plus
          # their audit entry) are one transaction: a bootstrap credential
          # never exists without its audit record.
          Repo.transaction(fn ->
            case issue("asn-admin", @admin_scopes, opts_for_bootstrap(token)) do
              {:ok, admin} ->
                seed_token(admin.credential_id, token)
                :seeded

              {:error, changeset} ->
                Repo.rollback(changeset)
            end
          end)
          |> case do
            {:ok, :seeded} ->
              :seeded

            {:error, changeset} ->
              errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
              Logger.warning("broker admin bootstrap failed: " <> inspect(errors))

              :exists
          end

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

  @doc "Marks a credential revoked (admin rotation/revocation), with an audit entry."
  @spec revoke(String.t(), String.t()) :: :ok | {:error, :not_found} | {:error, term()}
  def revoke(credential_id, actor_credential_id) do
    case Repo.get(ServiceCredential, credential_id) do
      nil ->
        {:error, :not_found}

      credential ->
        # The revocation and its audit entry commit together or not at all.
        case Repo.transaction(fn ->
               credential
               |> Ecto.Changeset.change(
                 revoked_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
               )
               |> Repo.update!()

               Audit.record(
                 actor_credential_id,
                 "credential.revoke",
                 "credential:" <> credential_id,
                 %{
                   "service_name" => credential.service_name
                 }
               )

               :ok
             end) do
          {:ok, :ok} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp hash(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
