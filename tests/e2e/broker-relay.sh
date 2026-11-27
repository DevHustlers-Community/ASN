#!/usr/bin/env bash
# Cross-service end-to-end: chat outbox relay -> live broker -> claim -> ack.
#
# This script is destructive and only accepts loopback PostgreSQL URLs whose
# database names end in _test. CI and local runs must opt in explicitly.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [ "${E2E_ALLOW_DESTRUCTIVE:-}" != "1" ]; then
  echo "E2E FAIL: refusing to run without E2E_ALLOW_DESTRUCTIVE=1" >&2
  exit 1
fi

BROKER_DATABASE_URL="${E2E_BROKER_DATABASE_URL:-postgres://asn_broker:change_me@localhost:5432/broker_db_test}"
CHAT_DATABASE_URL="${E2E_CHAT_DATABASE_URL:-postgres://asn_chat:change_me@localhost:5432/chat_db_test}"
export BROKER_DATABASE_URL CHAT_DATABASE_URL

validate_test_database_url() {
  local label="$1"
  local url="$2"

  python3 - "$label" "$url" <<'PY'
import sys
from urllib.parse import urlparse

label, raw_url = sys.argv[1], sys.argv[2]
parsed = urlparse(raw_url)
host = (parsed.hostname or "").lower()
database = parsed.path.lstrip("/")

if parsed.scheme not in {"postgres", "postgresql"}:
    raise SystemExit(f"E2E FAIL: refusing {label}: URL scheme must be postgres")
if host not in {"localhost", "127.0.0.1", "::1"}:
    raise SystemExit(f"E2E FAIL: refusing {label}: database host must be loopback")
if not database.endswith("_test"):
    raise SystemExit(f"E2E FAIL: refusing {label}: database name must end in _test")
PY
}

validate_test_database_url "broker" "$BROKER_DATABASE_URL"
validate_test_database_url "chat" "$CHAT_DATABASE_URL"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/asn-e2e.XXXXXX")"
BROKER_LOG="$TMP_DIR/broker.log"
RELAY_LOG="$TMP_DIR/relay.log"
BROKER_PID=""
STATE_READY=0

cleanup() {
  local status=$?
  trap - EXIT INT TERM

  if [ -n "$BROKER_PID" ] && kill -0 "$BROKER_PID" 2>/dev/null; then
    kill "$BROKER_PID" 2>/dev/null || true
    wait "$BROKER_PID" 2>/dev/null || true
  fi

  if [ "$STATE_READY" = "1" ]; then
    psql "$BROKER_DATABASE_URL" -q -v ON_ERROR_STOP=1 -c \
      "TRUNCATE deliveries, subscriptions, service_credentials, audit_log, events CASCADE;" \
      >/dev/null 2>&1 || true
    psql "$CHAT_DATABASE_URL" -q -v ON_ERROR_STOP=1 -c \
      "TRUNCATE chat_devices, chat_users, outbox_events CASCADE;" \
      >/dev/null 2>&1 || true
  fi

  if [ "$status" -ne 0 ]; then
    for log in "$BROKER_LOG" "$RELAY_LOG"; do
      if [ -s "$log" ]; then
        echo "===== ${log} =====" >&2
        tail -n 200 "$log" >&2
      fi
    done
  fi

  rm -rf "$TMP_DIR"
  exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
  echo "E2E FAIL: $*" >&2
  exit 1
}

command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"
command -v psql >/dev/null 2>&1 || fail "psql is required"

PORT="${E2E_BROKER_PORT:-$(python3 - <<'PY'
import socket

with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)}"
BASE_URL="http://127.0.0.1:${PORT}"
ADMIN_TOKEN="e2e-admin-${RANDOM}"

echo "==> Migrate broker and chat test databases"
(
  cd "$REPO_ROOT/services/event-broker"
  mix ecto.create >/dev/null
  mix ecto.migrate >/dev/null
)
(
  cd "$REPO_ROOT/services/chat-service"
  mix ecto.create >/dev/null
  mix ecto.migrate >/dev/null
)

echo "==> Reset dedicated e2e test state"
psql "$BROKER_DATABASE_URL" -q -v ON_ERROR_STOP=1 -c \
  "TRUNCATE deliveries, subscriptions, service_credentials, audit_log, events CASCADE;" >/dev/null
psql "$CHAT_DATABASE_URL" -q -v ON_ERROR_STOP=1 -c \
  "TRUNCATE chat_devices, chat_users, outbox_events CASCADE;" >/dev/null
STATE_READY=1

echo "==> Boot the broker on port ${PORT}"
(
  cd "$REPO_ROOT/services/event-broker"
  exec env \
    BROKER_ADMIN_TOKEN="$ADMIN_TOKEN" \
    EVENT_BROKER_PORT="$PORT" \
    mix run --no-halt
) >"$BROKER_LOG" 2>&1 &
BROKER_PID=$!

for _ in $(seq 1 60); do
  if curl -sf "$BASE_URL/readyz" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

curl -sf "$BASE_URL/readyz" >/dev/null 2>&1 || fail "broker did not become ready"
echo "    broker ready"

echo "==> Issue an expiring chat-service credential through the admin API"
EXPIRES_AT="$(python3 - <<'PY'
from datetime import datetime, timedelta, timezone

expires = datetime.now(timezone.utc) + timedelta(hours=1)
print(expires.isoformat().replace("+00:00", "Z"))
PY
)"

CREDENTIALS_JSON="$(curl -sf -X POST "$BASE_URL/v1/credentials" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "content-type: application/json" \
  --data "$(python3 - "$EXPIRES_AT" <<'PY'
import json
import sys

print(json.dumps({
    "service_name": "chat-service",
    "scopes": ["publish", "consume"],
    "expires_at": sys.argv[1],
}))
PY
)")"

SERVICE_TOKEN="$(echo "$CREDENTIALS_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')"
[ -n "$SERVICE_TOKEN" ] || fail "credential issuance returned no token"

echo "==> Create the e2e subscription (admin)"
curl -sf -X POST "$BASE_URL/v1/subscriptions" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "content-type: application/json" \
  -d '{"name":"e2e-chat-relay","consumer":"chat-service"}' >/dev/null

echo "==> Register a real Chat device and record its transactional outbox event"
EVENT_ID="$(
  cd "$REPO_ROOT/services/chat-service"
  mix run --no-start "$REPO_ROOT/tests/e2e/seed_chat_device.exs" \
    | grep '^E2E_EVENT_ID=' \
    | cut -d= -f2
)"
[ -n "$EVENT_ID" ] || fail "Chat device seed did not return an event id"

echo "==> Run the relay (one batch) against the live broker"
(
  cd "$REPO_ROOT/services/chat-service"
  BROKER_BASE_URL="$BASE_URL" \
  BROKER_SERVICE_TOKEN="$SERVICE_TOKEN" \
    mix run --no-start -e '
      {:ok, _started} = Application.ensure_all_started(:ecto_sql)
      {:ok, _repo} = AsnChat.Repo.start_link()
      {:ok, published} = AsnChat.Events.Relay.publish_batch()
      IO.puts("PUBLISHED=" <> Enum.join(published, ","))
    ' >"$RELAY_LOG" 2>&1
)

grep -q "^PUBLISHED=" "$RELAY_LOG" || fail "relay produced no result"
PUBLISHED="$(grep -o 'PUBLISHED=.*' "$RELAY_LOG" | cut -d= -f2)"
[ "$PUBLISHED" = "$EVENT_ID" ] || fail "relay published [$PUBLISHED], expected [$EVENT_ID]"

echo "==> Claim the delivery as the owning consumer service"
CLAIM_JSON="$(curl -sf -X POST "$BASE_URL/v1/subscriptions/e2e-chat-relay/claims" \
  -H "Authorization: Bearer $SERVICE_TOKEN" \
  -H "content-type: application/json" \
  -d '{"max": 10, "wait_ms": 0}')"

CLAIM_JSON="$CLAIM_JSON" EXPECTED_EVENT_ID="$EVENT_ID" python3 - <<'PY'
import json
import os
import uuid

expected_event_id = os.environ["EXPECTED_EVENT_ID"]
assert uuid.UUID(expected_event_id).version == 7, expected_event_id
data = json.loads(os.environ["CLAIM_JSON"])
deliveries = data["deliveries"]
assert len(deliveries) == 1, f"expected exactly one delivery, got {len(deliveries)}"
delivery = deliveries[0]
assert delivery["event_id"] == expected_event_id, delivery["event_id"]
assert delivery["type"] == "chat.device.registered", delivery["type"]
assert delivery["aggregate_type"] == "device", delivery["aggregate_type"]
assert delivery["aggregate_id"] == delivery["payload"]["device_id"]
assert set(delivery["payload"]) == {
    "device_id",
    "user_id",
    "platform",
    "identity_key_fingerprint",
}
assert delivery["payload"]["user_id"]
assert delivery["payload"]["platform"] == "web"
assert delivery["payload"]["identity_key_fingerprint"]
assert delivery["lease_token"], "missing lease token"
print("claimed", delivery["delivery_id"], "with a contract-valid device envelope")
PY

DELIVERY_ID="$(echo "$CLAIM_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["deliveries"][0]["delivery_id"])')"
LEASE_TOKEN="$(echo "$CLAIM_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["deliveries"][0]["lease_token"])')"

echo "==> Ack it"
curl -sf -X POST "$BASE_URL/v1/deliveries/$DELIVERY_ID/ack" \
  -H "Authorization: Bearer $SERVICE_TOKEN" \
  -H "content-type: application/json" \
  -d "{\"lease_token\": \"$LEASE_TOKEN\"}" >/dev/null

echo "==> Metrics show the loop"
METRICS="$(curl -sf "$BASE_URL/metrics")"
echo "$METRICS" | grep -q 'asn_event_broker_publish_accepted_total' || fail "metrics missing publish counter"
echo "$METRICS" | grep -q 'asn_event_broker_acks_total' || fail "metrics missing ack counter"

echo ""
echo "E2E PASS: chat device outbox -> relay -> broker -> owning consumer -> ack -> metrics"
