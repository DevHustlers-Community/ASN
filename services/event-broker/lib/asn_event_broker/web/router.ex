defmodule AsnEventBroker.Web.Router do
  @moduledoc """
  The HTTP edge (ADR 0008 §2, §10): Plug + Bandit only. Authentication and
  request validation happen here; routing, lease, retry, and retention rules
  stay in the domain modules (broker CODE_MAP transport boundary).

  Errors are RFC 9457 Problem Details with a stable `code` extension
  (`contracts/openapi/README.md`); the shared error envelope remains open in
  §9.1. The 256 KiB limit applies to the whole request body, enforced before
  parsing.
  """

  use Plug.Router
  use Plug.ErrorHandler
  require Logger

  import Ecto.Query

  alias AsnEventBroker.{Audit, DeadLetter, Delivery, Publishing, Repo, Security}
  alias AsnEventBroker.Acknowledgements
  alias AsnEventBroker.Security.ServiceCredential
  alias AsnEventBroker.Subscriptions.Subscription

  @max_body_bytes 256 * 1024

  plug(Plug.RequestId)
  plug(:envelope_limit)
  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason,
    length: @max_body_bytes
  )

  plug(:authenticate)
  plug(:dispatch)

  post "/v1/events" do
    if Security.scope_authorized?(conn.assigns.credential, :publish) do
      case publish(conn.body_params, conn.assigns.credential) do
        {:ok, :created} ->
          send_json(conn, 201, %{"status" => "created"})

        {:ok, :duplicate} ->
          send_json(conn, 200, %{"status" => "duplicate"})

        {:error, {:invalid_envelope, reasons}} ->
          problem(conn, 400, "invalid_envelope", Enum.join(reasons, "; "))

        {:error, {:invalid_publisher, message}} ->
          problem(conn, 400, "invalid_publisher", message)

        {:error, :conflict} ->
          problem(
            conn,
            409,
            "event_conflict",
            "event_id exists with different content or publisher"
          )

        {:error, :aggregate_version_taken} ->
          problem(
            conn,
            422,
            "aggregate_version_taken",
            "one event per aggregate version is a deliberate constraint"
          )

        {:error, :event_type_forbidden} ->
          problem(conn, 403, "event_type_forbidden", "credential may not publish this event type")

        _ ->
          problem(conn, 500, "internal", "unexpected publish result")
      end
    else
      problem(conn, 403, "missing_scope", "publish scope required")
    end
  end

  post "/v1/subscriptions/:name/claims" do
    if Security.scope_authorized?(conn.assigns.credential, :consume) do
      max = body_int(conn.body_params["max"], 10)
      wait_ms = min(body_int(conn.body_params["wait_ms"], 0), delivery_cfg(:long_poll_max_ms))

      case Delivery.claim(name, max, wait_ms) do
        {:ok, deliveries} ->
          send_json(conn, 200, %{"deliveries" => with_event_payloads(deliveries)})

        {:error, :paused} ->
          problem(conn, 409, "subscription_paused", "subscription is paused")

        {:error, :not_found} ->
          problem(conn, 404, "not_found", "unknown subscription")
      end
    else
      problem(conn, 403, "missing_scope", "consume scope required")
    end
  end

  post "/v1/deliveries/:id/ack" do
    consume_action(conn, fn -> Acknowledgements.ack(id, conn.body_params["lease_token"]) end)
  end

  post "/v1/deliveries/:id/nack" do
    consume_action(conn, fn ->
      Acknowledgements.nack(
        id,
        conn.body_params["lease_token"],
        conn.body_params["error_kind"],
        conn.body_params["error_message"]
      )
    end)
  end

  post "/v1/deliveries/:id/extend" do
    consume_action(conn, fn -> Acknowledgements.extend(id, conn.body_params["lease_token"]) end)
  end

  post "/v1/deliveries/:id/skip" do
    admin_action(conn, fn actor -> DeadLetter.skip(id, actor) end)
  end

  get "/v1/deliveries" do
    if Security.scope_authorized?(conn.assigns.credential, :admin) do
      state = conn.params["state"]

      if state == "dead" do
        limit = body_int(conn.params["limit"], 50)

        send_json(conn, 200, %{
          "deliveries" => DeadLetter.list_dead(conn.params["subscription"], limit)
        })
      else
        problem(conn, 400, "unsupported_filter", "only state=dead inspection is available")
      end
    else
      problem(conn, 403, "missing_scope", "admin scope required")
    end
  end

  post "/v1/dead-letters/replay" do
    admin_action(conn, fn actor -> DeadLetter.replay(conn.body_params["delivery_id"], actor) end)
  end

  get "/v1/subscriptions" do
    if Security.scope_authorized?(conn.assigns.credential, :admin) do
      subs =
        AsnEventBroker.Repo.all(Subscription)
        |> Enum.map(&subscription_view/1)

      send_json(conn, 200, %{"subscriptions" => subs})
    else
      problem(conn, 403, "missing_scope", "admin scope required")
    end
  end

  post "/v1/subscriptions" do
    if Security.scope_authorized?(conn.assigns.credential, :admin) do
      attrs =
        conn.body_params
        |> Map.take(["name", "consumer", "event_types", "status", "max_attempts"])
        |> Map.put("id", AsnEventBroker.UUIDv7.generate())

      case %Subscription{} |> Subscription.changeset(attrs) |> AsnEventBroker.Repo.insert() do
        {:ok, sub} ->
          send_json(conn, 201, subscription_view(sub))

        {:error, changeset} ->
          problem(conn, 409, "subscription_rejected", format_changeset(changeset))
      end
    else
      problem(conn, 403, "missing_scope", "admin scope required")
    end
  end

  patch "/v1/subscriptions/:name" do
    if Security.scope_authorized?(conn.assigns.credential, :admin) do
      actor = conn.assigns.credential.credential_id
      attrs = Map.take(conn.body_params, ["status", "event_types", "max_attempts"])

      case Repo.get_by(Subscription, name: name) do
        nil ->
          problem(conn, 404, "not_found", "unknown subscription")

        subscription ->
          case subscription |> Subscription.changeset(attrs) |> Repo.update() do
            {:ok, updated} ->
              Audit.record(actor, "subscription.update", "subscription:" <> name, %{
                "status" => attrs["status"],
                "event_types" => attrs["event_types"],
                "max_attempts" => attrs["max_attempts"]
              })

              send_json(conn, 200, subscription_view(updated))

            {:error, changeset} ->
              problem(conn, 409, "subscription_rejected", format_changeset(changeset))
          end
      end
    else
      problem(conn, 403, "missing_scope", "admin scope required")
    end
  end

  get "/v1/credentials" do
    if Security.scope_authorized?(conn.assigns.credential, :admin) do
      credentials =
        Repo.all(ServiceCredential)
        |> Enum.map(&credential_view/1)

      send_json(conn, 200, %{"credentials" => credentials})
    else
      problem(conn, 403, "missing_scope", "admin scope required")
    end
  end

  post "/v1/credentials" do
    if Security.scope_authorized?(conn.assigns.credential, :admin) do
      actor = conn.assigns.credential.credential_id
      body = conn.body_params

      with :ok <- validate_scopes(body["scopes"]),
           {:ok, scopes} <- to_scopes(body["scopes"]) do
        issued =
          Security.issue(body["service_name"] || "", scopes,
            actor_credential_id: actor,
            allowed_event_types: body["allowed_event_types"]
          )

        send_json(conn, 201, %{
          "credential_id" => issued.credential_id,
          "token" => issued.token
        })
      else
        {:error, reason} -> problem(conn, 400, "invalid_credential", reason)
      end
    else
      problem(conn, 403, "missing_scope", "admin scope required")
    end
  end

  post "/v1/credentials/:id/revoke" do
    if Security.scope_authorized?(conn.assigns.credential, :admin) do
      actor = conn.assigns.credential.credential_id

      case Security.revoke(id, actor) do
        :ok -> send_json(conn, 200, %{"status" => "revoked"})
        {:error, :not_found} -> problem(conn, 404, "not_found", "unknown credential")
      end
    else
      problem(conn, 403, "missing_scope", "admin scope required")
    end
  end

  get "/healthz" do
    send_json(conn, 200, %{"status" => "up"})
  end

  get "/readyz" do
    case AsnEventBroker.Repo.query!("SELECT 1", []) do
      %{num_rows: 1} -> send_json(conn, 200, %{"status" => "ready"})
      _ -> problem(conn, 503, "not_ready", "database check failed")
    end
  end

  match _ do
    problem(conn, 404, "not_found", "no such route")
  end

  # -- helpers -------------------------------------------------------------

  defp publish(params, credential) do
    type = params["type"]

    if is_binary(type) and Security.event_type_authorized?(credential, type) do
      Publishing.publish(params, credential.service_name)
    else
      {:error, :event_type_forbidden}
    end
  end

  defp respond_action(result, conn) do
    case result do
      :ok ->
        send_json(conn, 200, %{"status" => "acknowledged"})

      {:ok, :pending} ->
        send_json(conn, 200, %{"status" => "rescheduled"})

      {:ok, :dead} ->
        send_json(conn, 200, %{"status" => "dead_lettered"})

      {:ok, :skipped} ->
        send_json(conn, 200, %{"status" => "skipped"})

      {:ok, :replayed} ->
        send_json(conn, 200, %{"status" => "replayed"})

      {:ok, %DateTime{} = expiry} ->
        send_json(conn, 200, %{"lease_expires_at" => DateTime.to_iso8601(expiry)})

      {:error, :not_found} ->
        problem(conn, 404, "not_found", "unknown delivery")

      {:error, :not_dead} ->
        problem(conn, 409, "not_dead", "delivery is not dead")

      {:error, :stale_lease} ->
        problem(conn, 409, "stale_lease", "stale token or expired lease")

      _ ->
        problem(conn, 400, "invalid_request", "missing or malformed parameters")
    end
  end

  defp consume_action(conn, fun) do
    if Security.scope_authorized?(conn.assigns.credential, :consume) do
      fun.() |> respond_action(conn)
    else
      problem(conn, 403, "missing_scope", "consume scope required")
    end
  end

  defp admin_action(conn, fun) do
    if Security.scope_authorized?(conn.assigns.credential, :admin) do
      actor = conn.assigns.credential.credential_id
      fun.(actor) |> respond_action(conn)
    else
      problem(conn, 403, "missing_scope", "admin scope required")
    end
  end

  # Claim responses carry the canonical event envelope plus delivery metadata
  # (ADR 0008 §2). Aggregate columns and error metadata come from the delivery
  # row; the envelope fields come from the event log.
  defp with_event_payloads(claimed) when claimed == [], do: []

  defp with_event_payloads(claimed) do
    event_ids = Enum.map(claimed, & &1.event_id)

    events =
      AsnEventBroker.Repo.all(
        from e in AsnEventBroker.Events.Event,
          where: e.event_id in ^event_ids,
          select: {e.event_id, e}
      )
      |> Map.new()

    Enum.map(claimed, fn c ->
      event = Map.fetch!(events, c.event_id)

      %{
        delivery_id: c.delivery_id,
        event_id: c.event_id,
        type: event.type,
        schema_version: event.schema_version,
        occurred_at: DateTime.to_iso8601(event.occurred_at),
        aggregate_type: event.aggregate_type,
        aggregate_id: event.aggregate_id,
        aggregate_version: event.aggregate_version,
        trace_id: event.trace_id,
        payload: event.payload,
        attempts: c.attempts,
        lease_token: c.lease_token,
        lease_expires_at: DateTime.to_iso8601(c.lease_expires_at)
      }
    end)
  end

  defp validate_scopes(scopes) when is_list(scopes) do
    known = ["publish", "consume", "admin"]

    if scopes != [] and Enum.all?(scopes, &(&1 in known)) do
      :ok
    else
      {:error, "scopes must be a non-empty subset of publish, consume, admin"}
    end
  end

  defp validate_scopes(_), do: {:error, "scopes must be a non-empty list of known scopes"}

  defp to_scopes(scopes), do: {:ok, Enum.map(scopes, &String.to_existing_atom/1)}

  defp credential_view(credential) do
    %{
      "credential_id" => credential.credential_id,
      "service_name" => credential.service_name,
      "scopes" => Enum.map(credential.scopes, &to_string/1),
      "allowed_event_types" => credential.allowed_event_types,
      "expires_at" => timestamp(credential.expires_at),
      "revoked_at" => timestamp(credential.revoked_at),
      "created_at" => timestamp(credential.created_at)
    }
  end

  defp timestamp(nil), do: nil
  defp timestamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp subscription_view(sub) do
    %{
      "id" => sub.id,
      "name" => sub.name,
      "consumer" => sub.consumer,
      "event_types" => sub.event_types,
      "status" => to_string(sub.status),
      "max_attempts" => sub.max_attempts
    }
  end

  defp format_changeset(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
    |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(List.wrap(v), ", ")}" end)
    |> Enum.join("; ")
  end

  defp authenticate(%{request_path: path} = conn, _opts) when path in ["/healthz", "/readyz"],
    do: conn

  defp authenticate(conn, _opts) do
    case Security.authorize(get_req_header(conn, "authorization") |> List.first()) do
      {:ok, credential} ->
        assign(conn, :credential, credential)

      {:error, :unauthorized} ->
        conn |> problem(401, "unauthorized", "missing or invalid bearer token") |> halt()
    end
  end

  # Whole-request-body limit, enforced before parsing (ADR 0008 §10).
  defp envelope_limit(conn, _opts) do
    case get_req_header(conn, "content-length") do
      [len] ->
        case Integer.parse(len) do
          {bytes, ""} when bytes <= @max_body_bytes ->
            conn

          _ ->
            conn
            |> problem(413, "payload_too_large", "request body exceeds the envelope limit")
            |> halt()
        end

      [] ->
        conn
    end
  end

  @impl Plug.ErrorHandler
  def handle_errors(conn, %{kind: :error, exception: exception}) do
    Logger.error("broker request failed: " <> Exception.format(:error, exception))

    if conn.halted do
      conn
    else
      if plug_status(exception) == 413 do
        problem(conn, 413, "payload_too_large", "request body exceeds the envelope limit")
      else
        problem(conn, 500, "internal", "internal error")
      end
    end
  end

  def handle_errors(conn, _), do: conn

  defp plug_status(exception) do
    Plug.Exception.status(exception)
  rescue
    _ -> 500
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp problem(conn, status, code, detail) do
    body = %{
      "type" => "about:blank",
      "title" => Plug.Conn.Status.reason_phrase(status),
      "status" => status,
      "code" => code,
      "detail" => detail
    }

    conn
    |> put_resp_content_type("application/problem+json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp body_int(nil, default), do: default
  defp body_int(value, _default) when is_integer(value) and value >= 0, do: value

  defp body_int(value, _default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int >= 0 -> int
      _ -> 0
    end
  end

  defp body_int(_, default), do: default

  defp delivery_cfg(key),
    do: Keyword.fetch!(Application.fetch_env!(:asn_event_broker, :delivery), key)
end
