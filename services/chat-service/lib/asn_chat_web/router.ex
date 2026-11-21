defmodule AsnChatWeb.Router do
  use AsnChatWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :read do
    plug AsnChatWeb.Plugs.Authenticate, scopes: ["chat:read"]
  end

  pipeline :devices do
    plug AsnChatWeb.Plugs.Authenticate, scopes: ["chat:devices"]
  end

  scope "/api/v1", AsnChatWeb do
    pipe_through [:api, :read]

    get "/devices", DeviceController, :index
    get "/devices/:device_id/key-packages", KeyPackageController, :index
  end

  scope "/api/v1", AsnChatWeb do
    pipe_through [:api, :devices]

    post "/devices", DeviceController, :create
    post "/devices/:device_id/revoke", DeviceController, :revoke
    post "/devices/:device_id/key-packages", KeyPackageController, :create
  end
end
