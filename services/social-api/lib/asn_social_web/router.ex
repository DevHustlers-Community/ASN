defmodule AsnSocialWeb.Router do
  use AsnSocialWeb, :router

  @compile {:no_warn_undefined,
            [
              AsnSocialWeb.Controllers.HealthController,
              AsnSocialWeb.Controllers.AuthorizationController
            ]}

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :m2m_auth do
    plug AsnSocialWeb.Plugs.AuthenticateM2M
  end

  get "/healthz", AsnSocialWeb.Controllers.HealthController, :live
  get "/readyz", AsnSocialWeb.Controllers.HealthController, :ready

  scope "/internal/v1" do
    pipe_through [:api, :m2m_auth]

    get "/users/:user_id/authorization", AsnSocialWeb.Controllers.AuthorizationController, :show
  end
end
