defmodule AsnSocialWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :asn_social

  @max_body_bytes Application.compile_env(
                    :asn_social,
                    [:request_limits, :max_body_bytes],
                    262_144
                  )

  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :asn_social
  end

  plug Plug.RequestId, assign_as: :request_id
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug AsnSocialWeb.Plugs.ProblemContentType

  plug AsnSocialWeb.Plugs.BodyLimit, max_bytes: @max_body_bytes

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["*/*"],
    length: @max_body_bytes,
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug AsnSocialWeb.Router
end
