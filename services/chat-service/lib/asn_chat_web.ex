defmodule AsnChatWeb do
  @moduledoc """
  The entrypoint for defining the JSON API and channels.

  This can be used in your application as:

      use AsnChatWeb, :controller
      use AsnChatWeb, :channel

  The definitions below are executed for every controller and channel, so keep
  them short and focused on imports, uses, and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  def static_paths, do: []

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: AsnChatWeb.Endpoint,
        router: AsnChatWeb.Router,
        statics: AsnChatWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller or channel.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
