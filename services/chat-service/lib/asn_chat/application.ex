defmodule AsnChat.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        AsnChatWeb.Telemetry,
        AsnChat.Repo,
        {DNSCluster, query: Application.get_env(:asn_chat, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: AsnChat.PubSub}
      ] ++ maybe_relay()

    # Start to serve requests, typically the last entry
    children = children ++ [AsnChatWeb.Endpoint]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AsnChat.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # The broker relay runs against the real world; disabled under the test
  # sandbox (relay logic is exercised by direct invocation with an injected
  # HTTP client).
  defp maybe_relay do
    relay = Application.get_env(:asn_chat, :events_relay, [])

    if Keyword.get(relay, :enabled, true) do
      [AsnChat.Events.Relay]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AsnChatWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
