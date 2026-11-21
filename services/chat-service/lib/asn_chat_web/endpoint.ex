defmodule AsnChatWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :asn_chat

  @max_body_bytes Application.compile_env(:asn_chat, [:request_limits, :max_body_bytes], 262_144)

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :asn_chat
  end

  plug Plug.RequestId, assign_as: :request_id
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug AsnChatWeb.Plugs.ProblemContentType

  # ADR 0016: 256 KiB request bodies, rejected before parsing when the client
  # declares the length, and bounded by the parser for chunked bodies.
  plug AsnChatWeb.Plugs.BodyLimit, max_bytes: @max_body_bytes

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    length: @max_body_bytes,
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug AsnChatWeb.Router
end
