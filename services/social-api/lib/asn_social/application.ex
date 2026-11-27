defmodule AsnSocial.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AsnSocialWeb.Telemetry,
      AsnSocial.Repo,
      {DNSCluster, query: Application.get_env(:asn_social, :dns_cluster_query) || :ignore},
      AsnSocialWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: AsnSocial.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    AsnSocialWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
