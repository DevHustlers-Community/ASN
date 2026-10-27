#!/usr/bin/env bash
# Cross-service end-to-end: chat outbox relay -> live broker -> claim -> ack.
#
# Prerequisites: PostgreSQL reachable via the URLs below (compose or a CI
# service), both services' dependencies fetched, curl + python3 on PATH.
# The script owns its lifecycle: migrates, boots the broker, issues a real
# credential through the admin API, records a chat outbox row, runs the
# relay, claims the delivery, and asserts the metrics trail.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Random port per run: a stale broker from an interrupted run cannot
# squat it (beam processes do not match pkill by script name).
PORT="${E2E_BROKER_PORT:-$((4190 + RANDOM % 100))}"
BASE_URL="http://localhost:${PORT}"
ADMIN_TOKEN="e2e-admin-${RANDOM}"

BROKER_DATABASE_URL="${E2E_BROKER_DATABASE_URL:-postgres://asn_broker:change_me@localhost:5432/broker_db}"
BROKER_TEST_DATABASE_URL="${E2E_BROKER_TEST_DATABASE_URL:-postgres://asn_broker:change_me@localhost:5432/broker_db_test}"
CHAT_DATABASE_URL="${E2E_CHAT_DATABASE_URL:-postgres://asn_chat:change_me@localhost:5432/chat_db}"

fail() { echo "E2E FAIL: $*" >&2; exit 1; }

BROKER_PID=""
cleanup() {
  if [ -n "$BROKER_PID" ]; then
    kill "$BROKER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "==> Migrate broker and chat databases"
(cd "$REPO_ROOT/services/event-broker" &&
  BROKER_DATABASE_URL="$BROKER_DATABASE_URL" BROKER_TEST_DATABASE_URL="$BROKER_TEST_DATABASE_URL" \
  mix ecto.create >/dev/null && mix ecto.migrate >/dev/null)
(cd "$REPO_ROOT/services/chat-service" &&
  CHAT_DATABASE_URL="$CHAT_DATABASE_URL" mix ecto.create >/dev/null && mix ecto.migrate >/dev/null)

echo "==> Reset e2e state (the script owns its lifecycle)"
psql "$BROKER_DATABASE_URL" -q -c \
  "TRUNCATE deliveries, subscriptions, service_credentials, audit_log, events CASCADE;" >/dev/null
psql "$CHAT_DATABASE_URL" -q -c "TRUNCATE outbox_events CASCADE;" >/dev/null

command -v fuser >/dev/null 2>&1 && fuser -k "${PORT}/tcp" >/dev/null 2>&1 || true

echo "==> Boot the broker on port ${PORT}"
(cd "$REPO_ROOT/services/event-broker" &&
  BROKER_DATABASE_URL="$BROKER_DATABASE_URL" \
  BROKER_ADMIN_TOKEN="$ADMIN_TOKEN" \
  EVENT_BROKER_PORT="$PORT" \
  mix run --no-halt >/tmp/e2e-broker.log 2>&1 &
  echo $! > /tmp/e2e-broker.pid)
BROKER_PID="$(cat /tmp/e2e-broker.pid)"

for _ in $(seq 1 60); do
  if curl -sf "$BASE_URL/readyz" >/dev/null 2>&1; then break; fi
  sleep 1
done
curl -sf "$BASE_URL/readyz" >/dev/null 2>&1 || { cat /tmp/e2e-broker.log >&2; fail "broker did not become ready"; }
echo "    broker ready"

echo "==> Issue a real publish+consume credential through the admin API"
CREDENTIALS_JSON="$(curl -sf -X POST "$BASE_URL/v1/credentials" \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "content-type: application/json" \
  -d '{"service_name":"chat-service","scopes":["publish","consume"]}')"
PUBLISH_TOKEN="$(echo "$CREDENTIALS_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')"
[ -n "$PUBLISH_TOKEN" ] || fail "credential issuance returned no token"

echo "==> Create the e2e subscription (admin)"
curl -sf -X POST "$BASE_URL/v1/subscriptions" \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "content-type: application/json" \
  -d '{"name":"e2e-chat-relay","consumer":"chat-service"}' >/dev/null

echo "==> Record an envelope in the chat outbox"
EVENT_ID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
(cd "$REPO_ROOT/services/chat-service" &&
  CHAT_DATABASE_URL="$CHAT_DATABASE_URL" E2E_EVENT_ID="$EVENT_ID" \
  mix run -e '
    envelope = %{
      "event_id" => System.fetch_env!("E2E_EVENT_ID"),
      "type" => "chat.device.registered",
      "schema_version" => 1,
      "occurred_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "aggregate_type" => "conversation",
      "aggregate_id" => "01912345-6789-7000-8000-0000000000e2",
      "aggregate_version" => 1,
      "trace_id" => "e2e",
      "payload" => %{"device_id" => "e2e-device"}
    }

    {:ok, _} = AsnChat.Events.Outbox.record(envelope)
    IO.puts("outbox row recorded")
  ' >/dev/null)

echo "==> Run the relay (one batch) against the live broker"
(cd "$REPO_ROOT/services/chat-service" &&
  CHAT_DATABASE_URL="$CHAT_DATABASE_URL" \
  BROKER_BASE_URL="$BASE_URL" \
  BROKER_SERVICE_TOKEN="$PUBLISH_TOKEN" \
  mix run -e '
    {:ok, published} = AsnChat.Events.Relay.publish_batch()
    IO.puts("PUBLISHED=" <> Enum.join(published, ","))
  ' >/tmp/e2e-relay.log 2>&1)
grep -q "^PUBLISHED=" /tmp/e2e-relay.log || { cat /tmp/e2e-relay.log >&2; fail "relay produced no result"; }
PUBLISHED="$(grep -o 'PUBLISHED=.*' /tmp/e2e-relay.log | cut -d= -f2)"
[ "$PUBLISHED" = "$EVENT_ID" ] || fail "relay published [$PUBLISHED], expected [$EVENT_ID]"

echo "==> Claim the delivery as a consumer"
CLAIM_JSON="$(curl -sf -X POST "$BASE_URL/v1/subscriptions/e2e-chat-relay/claims" \
  -H "Authorization: Bearer $PUBLISH_TOKEN" -H "content-type: application/json" \
  -d '{"max": 10, "wait_ms": 0}')"
echo "$CLAIM_JSON" | python3 -c '
import json, sys
data = json.load(sys.stdin)
deliveries = data["deliveries"]
assert len(deliveries) == 1, f"expected exactly one delivery, got {len(deliveries)}"
d = deliveries[0]
assert d["type"] == "chat.device.registered", d["type"]
assert d["payload"]["device_id"] == "e2e-device"
assert d["lease_token"], "missing lease token"
print("claimed", d["delivery_id"], "with envelope intact")
' || fail "claim assertion failed"

echo "==> Ack it"
DELIVERY_ID="$(echo "$CLAIM_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["deliveries"][0]["delivery_id"])')"
LEASE_TOKEN="$(echo "$CLAIM_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["deliveries"][0]["lease_token"])')"
curl -sf -X POST "$BASE_URL/v1/deliveries/$DELIVERY_ID/ack" \
  -H "Authorization: Bearer $PUBLISH_TOKEN" -H "content-type: application/json" \
  -d "{\"lease_token\": \"$LEASE_TOKEN\"}" >/dev/null

echo "==> Metrics show the loop"
METRICS="$(curl -sf "$BASE_URL/metrics")"
echo "$METRICS" | grep -q 'asn_event_broker_publish_accepted_total' || fail "metrics missing publish counter"
echo "$METRICS" | grep -q 'asn_event_broker_acks_total' || fail "metrics missing ack counter"

echo ""
echo "E2E PASS: chat outbox -> relay -> broker -> claim -> ack -> metrics"
