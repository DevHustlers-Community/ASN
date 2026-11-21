defmodule AsnChatWeb.ErrorJSON do
  @moduledoc """
  Fallback error rendering for framework-level failures that bypass a
  controller (unknown routes, body parsing, unhandled exceptions).

  The body follows the same RFC 9457 shape as `AsnChatWeb.Problem`; controller
  responses use `application/problem+json` directly, while this fallback keeps
  Phoenix's negotiated JSON content type. Details are never leaked.
  """

  @spec render(String.t(), map()) :: map()
  def render(template, assigns) do
    status = status_from_template(template)

    %{
      type: "about:blank",
      title: Plug.Conn.Status.reason_phrase(status),
      status: status,
      code: code_for(status),
      request_id: assigns[:request_id] || "unknown"
    }
  end

  defp status_from_template(template) do
    case Integer.parse(template) do
      {status, _rest} when status in 400..599 -> status
      _other -> 500
    end
  end

  defp code_for(400), do: "invalid_request"
  defp code_for(401), do: "unauthorized"
  defp code_for(403), do: "forbidden"
  defp code_for(404), do: "not_found"
  defp code_for(405), do: "invalid_request"
  defp code_for(409), do: "conflict"
  defp code_for(413), do: "payload_too_large"
  defp code_for(415), do: "invalid_request"
  defp code_for(422), do: "unprocessable"
  defp code_for(429), do: "rate_limited"
  defp code_for(503), do: "service_unavailable"
  defp code_for(status) when status in 500..599, do: "internal_error"
  defp code_for(_status), do: "internal_error"
end
