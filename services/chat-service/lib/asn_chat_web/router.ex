defmodule AsnChatWeb.Router do
  use AsnChatWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", AsnChatWeb do
    pipe_through :api
  end
end
