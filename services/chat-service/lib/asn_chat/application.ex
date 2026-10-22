defmodule AsnChat.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AsnChatWeb.Telemetry,
      AsnChat.Repo,
      {DNSCluster, query: Application.get_env(:asn_chat, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AsnChat.PubSub},
      # Start a worker by calling: AsnChat.Worker.start_link(arg)
      # {AsnChat.Worker, arg},
      # Start to serve requests, typically the last entry
      AsnChatWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AsnChat.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AsnChatWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
