defmodule AsnEventBroker.Repo do
  use Ecto.Repo,
    otp_app: :asn_event_broker,
    adapter: Ecto.Adapters.Postgres
end
