defmodule AsnEventBroker.DeadLetter do
  @moduledoc """
  Dead-letter inspection, replay, and skip (ADR 0008 §3, §5, §9).

  Replay returns a dead delivery to `pending` with a fresh attempt budget
  (attempts reset to zero); skip is a terminal operator decision. Both are
  admin-scope operations and both write an audit entry in the same
  transaction as the state change. Head-of-line blocking means replaying or
  skipping an earlier dead version releases the aggregate.
  """

  import Ecto.Query

  alias AsnEventBroker.{Audit, Repo, Telemetry}
  alias AsnEventBroker.Delivery.Delivery
  alias AsnEventBroker.Events.Event
  alias AsnEventBroker.Subscriptions.Subscription

  @replay_sql """
  UPDATE deliveries
  SET state = 'pending',
      attempts = 0,
      next_attempt_at = NULL,
      dead_lettered_at = NULL,
      updated_at = $2
  WHERE id = $1 AND state = 'dead'
  RETURNING id
  """

  @skip_sql """
  UPDATE deliveries
  SET state = 'skipped',
      skipped_at = $2,
      dead_lettered_at = NULL,
      updated_at = $2
  WHERE id = $1 AND state = 'dead'
  RETURNING id
  """

  @spec replay(String.t(), String.t() | nil) ::
          {:ok, :replayed} | {:error, :not_found} | {:error, :not_dead}
  def replay(delivery_id, actor_credential_id) do
    transition(delivery_id, actor_credential_id, "dead_letter.replay", @replay_sql, :replayed)
  end

  @spec skip(String.t(), String.t() | nil) ::
          {:ok, :skipped} | {:error, :not_found} | {:error, :not_dead}
  def skip(delivery_id, actor_credential_id) do
    transition(delivery_id, actor_credential_id, "dead_letter.skip", @skip_sql, :skipped)
  end

  @doc "Dead deliveries for inspection, newest first, optionally per subscription."
  @spec list_dead(String.t() | nil, pos_integer()) :: [map()]
  def list_dead(subscription_name, limit \\ 50) do
    query =
      from d in Delivery,
        join: e in Event,
        on: e.event_id == d.event_id,
        join: s in Subscription,
        on: s.id == d.subscription_id,
        where: d.state == :dead,
        order_by: [desc: d.dead_lettered_at],
        limit: ^limit,
        select: %{
          delivery_id: d.id,
          subscription_name: s.name,
          event_id: d.event_id,
          type: e.type,
          schema_version: e.schema_version,
          aggregate_type: d.aggregate_type,
          aggregate_id: d.aggregate_id,
          aggregate_version: d.aggregate_version,
          attempts: d.attempts,
          last_error_kind: d.last_error_kind,
          last_error_message: d.last_error_message,
          dead_lettered_at: d.dead_lettered_at
        }

    query =
      if subscription_name do
        where(query, [d, e, s], s.name == ^subscription_name)
      else
        query
      end

    Repo.all(query)
  end

  defp transition(delivery_id, actor_credential_id, action, sql, result) do
    case Ecto.UUID.cast(delivery_id) do
      {:ok, uuid} ->
        do_transition(uuid, actor_credential_id, action, sql, result)

      :error ->
        {:error, :not_found}
    end
  end

  defp do_transition(uuid, actor_credential_id, action, sql, result) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.transaction(fn ->
      case Repo.query!(sql, [Ecto.UUID.dump!(uuid), now]) do
        %{num_rows: 1} ->
          Audit.record(actor_credential_id, action, "delivery:" <> uuid, %{
            "delivery_id" => uuid
          })

          result

        %{num_rows: 0} ->
          if Repo.get(Delivery, uuid) do
            Repo.rollback(:not_dead)
          else
            Repo.rollback(:not_found)
          end
      end
    end)
    |> case do
      {:ok, result} ->
        Telemetry.emit_count(transition_event(result), %{})
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp transition_event(:replayed), do: [:replay]
  defp transition_event(:skipped), do: [:skip]
end
