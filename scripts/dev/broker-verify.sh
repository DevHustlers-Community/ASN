#!/usr/bin/env bash
# Full local verification loop for the event broker.
# Starts PostgreSQL via compose, waits for health, then runs the same checks
# as CI: migrate, format, compile with warnings-as-errors, and tests.
set -euo pipefail

cd "$(dirname "$0")/../.."

echo "==> Starting PostgreSQL"
docker compose up -d postgres

echo "==> Waiting for health"
for i in $(seq 1 30); do
  if docker compose ps postgres | grep -q healthy; then
    break
  fi
  sleep 1
  if [ "$i" -eq 30 ]; then
    echo "PostgreSQL did not become healthy in time" >&2
    exit 1
  fi
done

cd services/event-broker

echo "==> mix deps.get"
mix deps.get

echo "==> mix ecto.create && mix ecto.migrate"
mix ecto.create
mix ecto.migrate

echo "==> mix format --check-formatted"
mix format --check-formatted

echo "==> mix compile --warnings-as-errors"
mix compile --warnings-as-errors

echo "==> mix test"
mix test

echo "==> Broker verification passed"
