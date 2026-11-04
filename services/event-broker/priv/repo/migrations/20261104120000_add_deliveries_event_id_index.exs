defmodule AsnEventBroker.Repo.Migrations.AddDeliveriesEventIdIndex do
  @moduledoc """
  Forward-only index for the retention event purge (ADR 0008 §8).

  The purge's `NOT EXISTS` probe (`d.event_id = e.event_id`) and the
  `ON DELETE RESTRICT` check on `deliveries.event_id` had no leading
  `event_id` index, so both read every retained delivery. The unique
  `(subscription_id, event_id)` index cannot serve a lookup that does not
  know the subscription.

  Built without `CONCURRENTLY` because the deploy story does not run
  migrations outside a transaction yet; a later migration can rebuild it
  concurrently if the write lock becomes a problem.
  """

  use Ecto.Migration

  def change do
    create index(:deliveries, [:event_id])
  end
end
