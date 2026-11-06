defmodule AsnChat.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def up do
    create table(:conversations, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :kind, :text, null: false
      add :direct_key, :text
      add :community_id, :uuid
      add :channel_id, :uuid
      add :title, :text
      add :last_seq, :bigint, null: false, default: 0
      add :last_message_at, :utc_datetime_usec
      add :crypto_protocol, :text, null: false, default: "dev-opaque-v1"
      add :crypto_protocol_version, :integer, null: false, default: 1
      add :crypto_state_version, :bigint, null: false, default: 0

      add :created_at, :utc_datetime_usec, null: false
    end

    create constraint(:conversations, :conversations_kind_check,
             check: "kind IN ('direct', 'community')"
           )

    # Kind-guarded shape rules (each applies to one kind; kind is separately
    # constrained). The kind guard is required so rows of the other kind are
    # not rejected by this rule.
    create constraint(:conversations, :conversations_direct_shape_check,
             check:
               "kind <> 'direct' OR (direct_key IS NOT NULL AND community_id IS NULL AND channel_id IS NULL)"
           )

    create constraint(:conversations, :conversations_community_shape_check,
             check:
               "kind <> 'community' OR (direct_key IS NULL AND channel_id IS NOT NULL AND community_id IS NOT NULL)"
           )

    create unique_index(:conversations, [:direct_key])
    create unique_index(:conversations, [:channel_id])

    # Inbox ordering cursor (architecture §3.5).
    create index(:conversations, ["last_message_at DESC", "id DESC"],
             name: :conversations_inbox_order_index
           )
  end

  def down do
    drop index(:conversations, ["last_message_at DESC", "id DESC"],
           name: :conversations_inbox_order_index
         )

    drop unique_index(:conversations, [:channel_id])
    drop unique_index(:conversations, [:direct_key])

    drop constraint(:conversations, :conversations_community_shape_check)
    drop constraint(:conversations, :conversations_direct_shape_check)
    drop constraint(:conversations, :conversations_kind_check)

    drop table(:conversations)
  end
end
