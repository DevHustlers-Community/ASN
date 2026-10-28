defmodule AsnEventBroker.Repo.Migrations.AddBrokerPurgeClaimIndexes do
  @moduledoc """
  Forward-only purge and inspection indexes (ADR 0008 §8).

  Retention deletes terminal deliveries by their own timestamp and events by
  `received_at`; dead-letter inspection lists by `dead_lettered_at`. Partial
  indexes keep those scans proportional to the rows that are still eligible.
  """

  use Ecto.Migration

  def change do
    create index(:deliveries, [:delivered_at], where: "state = 'delivered'")
    create index(:deliveries, [:dead_lettered_at], where: "state = 'dead'")
    create index(:deliveries, [:skipped_at], where: "state = 'skipped'")
    create index(:events, [:received_at])
  end
end
