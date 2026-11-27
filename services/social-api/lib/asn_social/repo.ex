defmodule AsnSocial.Repo do
  use Ecto.Repo,
    otp_app: :asn_social,
    adapter: Ecto.Adapters.Postgres
end
