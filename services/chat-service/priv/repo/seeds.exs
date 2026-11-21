# Development seed only. Production data arrives from Social through the
# `user.*` projection consumer; Chat never creates accounts in production.
if Mix.env() == :dev do
  alias AsnChat.Accounts.User
  alias AsnChat.Repo

  user_id = "0190f1e2-6d7e-7f80-b192-3d4e5f607182"

  unless Repo.get(User, user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.insert!(%User{
      id: user_id,
      username: "dev-user",
      display_name: "Development User",
      show_presence: true,
      plan: "free",
      source_version: 0,
      created_at: now,
      updated_at: now
    })
  end

  Mix.shell().info("Development chat user: #{user_id}")
  Mix.shell().info("Mint a token with: mix asn_chat.dev_token --user #{user_id}")
else
  Mix.shell().info("Skipping development seed outside the dev environment")
end
