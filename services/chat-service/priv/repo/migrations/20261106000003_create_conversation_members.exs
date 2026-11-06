defmodule AsnChat.Repo.Migrations.CreateConversationMembers do
  use Ecto.Migration

  def up do
    create table(:conversation_members, primary_key: false) do
      add :conversation_id,
          references(:conversations, type: :uuid),
          primary_key: true,
          null: false

      add :user_id,
          references(:chat_users, type: :uuid),
          primary_key: true,
          null: false

      add :role, :text, null: false, default: "member"
      add :last_read_seq, :bigint, null: false, default: 0
      add :muted_until, :utc_datetime_usec
      add :joined_at, :utc_datetime_usec, null: false
      add :left_at, :utc_datetime_usec
      add :membership_version, :bigint, null: false, default: 1
    end

    create constraint(:conversation_members, :conversation_members_role_check,
             check: "role IN ('member', 'admin')"
           )

    # Membership lookup for the user (architecture §3.6); active rows only.
    create index(:conversation_members, [:user_id, :conversation_id],
             name: :conversation_members_active_per_user_index,
             where: "left_at IS NULL"
           )
  end

  def down do
    drop index(:conversation_members, [:user_id, :conversation_id],
           name: :conversation_members_active_per_user_index
         )

    drop constraint(:conversation_members, :conversation_members_role_check)

    drop table(:conversation_members)
  end
end
