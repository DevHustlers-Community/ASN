defmodule AsnEventBroker.Audit do
  @moduledoc """
  Append-only audit records for administrative actions (ADR 0008 §9). Entries
  are written in the same `broker_db` transaction as the state change they
  describe: an operation either commits with its audit entry or not at all.
  """

  alias AsnEventBroker.{Repo, UUIDv7}
  alias AsnEventBroker.Audit.AuditEntry

  @spec record(String.t() | nil, String.t(), String.t(), map()) :: AuditEntry.t()
  def record(actor_credential_id, action, target, params) do
    %AuditEntry{}
    |> struct(
      id: UUIDv7.generate(),
      actor_credential_id: actor_credential_id,
      action: action,
      target: target,
      params: params || %{},
      at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    )
    |> Repo.insert!()
  end
end
