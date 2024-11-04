#! /usr/bin/env bash
set -x
set -eo pipefail

if ! [ -x "$(command -v sqlx)" ]; then
  echo >&2 "Error: sqlx is not installed."
  echo >&2 "Use:"
  echo >&2 "  cargo install --version='~0.8' sqlx-cli --no-default-features --features rustls,postgres"
  echo >&2 "to install it."
  exit 1
fi

# Check if a custom parameter has been set, otherwise use default values
DB_PORT="${POSTGRES_PORT:=5432}"
SUPERUSER="${SUPERUSER:=postgres}"
SUPERUSER_PWD="${SUPERUSER_PWD:=password}"
APP_USER="${APP_USER:=app}"
APP_USER_PWD="${APP_USER_PWD:=secret}"
APP_DB_NAME="${APP_DB_NAME:=newsletter}"

if [[ -z "${SKIP_PODMAN}" ]]
then
  # Network name to check
  NETWORK_NAME="postgres-network"

  # Check if network exists
  if podman network inspect "$NETWORK_NAME" &> /dev/null; then
    echo "Network '$NETWORK_NAME' exists."
  else
    podman network create $NETWORK_NAME
  fi

  # Launch postgres using podman
  CONTAINER_NAME="postgres"
  podman run \
    --env POSTGRES_USER="${SUPERUSER}" \
    --env POSTGRES_PASSWORD="${SUPERUSER_PWD}" \
    --publish "${DB_PORT}":5432 \
    --network postgres-network \
    --detach \
    --name "${CONTAINER_NAME}" \
    postgres -N 1000

  PGADMIN_CONTAINER_NAME="pgAdmin"
  podman run \
    --name "${PGADMIN_CONTAINER_NAME}" \
    -p 9000:80 \
    -v ./pgadmin:/var/lib/pgadmin \
    -e PGADMIN_DEFAULT_EMAIL=asdeoz@gmail.com \
    -e PGADMIN_DEFAULT_PASSWORD=secret \
    --network postgres-network \
    -d dpage/pgadmin4

  # Wait for the database to be ready
  # until [ \
  #   "$(podman inspect -f "{{.State.Health.Status}}" ${CONTAINER_NAME})" == "healthy" \
  # ]; do
  #   >&2 echo "Postgres is unavailable - sleeping"
  #   sleep 1
  # done

  sleep 10

  # >&2 echo "Postgres is up and running on port ${DB_PORT}!"

  CREATE_QUERY="CREATE USER ${APP_USER} WITH PASSWORD '${APP_USER_PWD}';"
  podman exec -it "${CONTAINER_NAME}" psql -U "${SUPERUSER}" -c "${CREATE_QUERY}"

  GRANT_QUERY="ALTER USER ${APP_USER} CREATEDB;"
  podman exec -it "${CONTAINER_NAME}" psql -U "${SUPERUSER}" -c "${GRANT_QUERY}"
fi

DATABASE_URL="postgresql://${APP_USER}:${APP_USER_PWD}@localhost:${DB_PORT}/${APP_DB_NAME}"
export DATABASE_URL
sqlx database create
sqlx migrate run

echo >&2 "Postgres has been migrated, ready to go!"