defmodule AsnEventBroker.Security.ServiceCredential do
  @moduledoc """
  A bearer credential for one service. The plaintext token exists only at
  issuance; the broker stores its SHA-256 hash and compares constant-time.
  Multiple active credentials per service enable zero-downtime rotation
  (ADR 0008 §9).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AsnEventBroker.Events.Envelope

  @primary_key {:credential_id, Ecto.UUID, autogenerate: false}
  @foreign_key_type Ecto.UUID
  schema "service_credentials" do
    field :service_name, :string
    field :token_hash, :string
    field :scopes, {:array, Ecto.Enum}, values: [:publish, :consume, :admin]
    field :allowed_event_types, {:array, :string}
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
  end

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [
      :credential_id,
      :service_name,
      :token_hash,
      :scopes,
      :allowed_event_types,
      :expires_at,
      :revoked_at
    ])
    |> validate_required([:credential_id, :service_name, :token_hash, :scopes])
    |> validate_length(:service_name, min: 1)
    |> validate_length(:token_hash, is: 64)
    |> validate_change(:scopes, fn
      :scopes, scopes when is_list(scopes) ->
        known = [:publish, :consume, :admin]

        if scopes != [] and Enum.all?(scopes, &(&1 in known)) do
          []
        else
          [scopes: "must be a non-empty subset of publish, consume, admin"]
        end

      :scopes, _ ->
        [scopes: "must be a list of scopes"]
    end)
    |> validate_change(:allowed_event_types, fn
      :allowed_event_types, types when is_list(types) ->
        if types != [] and Enum.all?(types, &Envelope.type_valid?/1) do
          []
        else
          [allowed_event_types: "must be a non-empty list of dotted lowercase event types"]
        end

      :allowed_event_types, _ ->
        [allowed_event_types: "must be a list of dotted lowercase event types"]
    end)
  end
end
