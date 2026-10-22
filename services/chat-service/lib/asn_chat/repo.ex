defmodule AsnChat.Repo do
  use Ecto.Repo,
    otp_app: :asn_chat,
    adapter: Ecto.Adapters.Postgres
end
