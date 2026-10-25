defmodule AsnEventBroker.Audit.AuditEntry do
  @moduledoc """
  Append-only record of an administrative action. Written in the same
  `broker_db` transaction as the state change it describes (ADR 0008 §9);
  `actor_credential_id` is a soft reference so audit history survives
  credential deletion.
  """

  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  @foreign_key_type Ecto.UUID
  schema "audit_log" do
    field :actor_credential_id, Ecto.UUID
    field :action, :string
    field :target, :string
    field :params, :map
    field :at, :utc_datetime_usec
  end
end
