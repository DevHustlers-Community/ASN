if Mix.env() == :dev do
  user_id = "0190f1e2-6d7e-7f80-b192-3d4e5f607182"

  case AsnSocial.Accounts.authorization(user_id) do
    {:error, :not_found} ->
      {:ok, _user} =
        AsnSocial.Accounts.create_user(
          %{
            auth0_sub: "dev|local-user",
            username: "dev-user",
            display_name: "Development User"
          },
          id: user_id
        )

      Mix.shell().info("Development Social user: #{user_id}")

    {:ok, _view} ->
      Mix.shell().info("Development Social user already exists: #{user_id}")
  end
else
  Mix.shell().info("Skipping development seed outside dev environment")
end
