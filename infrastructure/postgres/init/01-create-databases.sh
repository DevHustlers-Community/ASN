#!/bin/sh
set -eu

: "${ASN_DB_PASSWORD:?ASN_DB_PASSWORD must be set}"
: "${POSTGRES_USER:=postgres}"

psql_admin() {
  psql --username "$POSTGRES_USER" --dbname postgres --no-psqlrc --set ON_ERROR_STOP=1 "$@"
}

create_role() {
  role="$1"

  psql_admin --set=role="$role" --set=password="$ASN_DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'role', :'password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'role')
\gexec
SQL
}

create_database() {
  database="$1"
  owner="$2"

  psql_admin --set=db="$database" --set=owner="$owner" <<'SQL'
SELECT format('CREATE DATABASE %I OWNER %I', :'db', :'owner')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db')
\gexec
SQL

  psql_admin --set=db="$database" --set=owner="$owner" <<'SQL'
SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', :'db')
\gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', :'db', :'owner')
\gexec
SQL
}

create_role asn_social
create_role asn_chat
create_role asn_moderation
create_role asn_broker

create_database social_db asn_social
create_database chat_db asn_chat
create_database moderation_db asn_moderation
create_database broker_db asn_broker

create_database chat_db_test asn_chat
create_database broker_db_test asn_broker
