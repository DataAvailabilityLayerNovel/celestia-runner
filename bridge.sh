#!/usr/bin/env bash
set -euo pipefail

# Join remote Celestia Bridge from prebuilt source archive.
# v2: fixes permission model correctly:
#   - chmod/chown is done on HOST before docker compose up
#   - no chmod is attempted inside the container
#   - p2p-key and key files are kept at 0600
#
# Usage:
#   SOURCE_HOST=ubuntu@103.67.203.71 bash bridge.sh up
#   bash bridge.sh logs
#   bash bridge.sh down
#   SOURCE_HOST=ubuntu@103.67.203.71 bash bridge.sh reset

chmod +x "$0" 2>/dev/null || true

SOURCE_HOST="${SOURCE_HOST:-}"
SOURCE_ARCHIVE="${SOURCE_ARCHIVE:-/home/ubuntu/bridge1-store-export.tar.gz}"
SSH_OPTS="${SSH_OPTS:--o StrictHostKeyChecking=accept-new}"

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.remote-bridge.yml}"
SERVICE_NAME="${SERVICE_NAME:-celestia-bridge-remote}"
CONTAINER_NAME="${CONTAINER_NAME:-celestia-bridge-remote}"
DATA_DIR="${DATA_DIR:-./bridge-remote}"
LOCAL_ARCHIVE="${LOCAL_ARCHIVE:-./bridge-store.tar.gz}"

IMAGE="${IMAGE:-ghcr.io/celestiaorg/celestia-node:v0.28.5-mocha}"

SERVER_IP="${SERVER_IP:-103.67.203.71}"
CORE_PORT="${CORE_PORT:-14090}"

HOST_RPC_PORT="${HOST_RPC_PORT:-26763}"
HOST_P2P_PORT="${HOST_P2P_PORT:-2205}"

ENABLE_METRICS="${ENABLE_METRICS:-false}"
METRICS_ENDPOINT="${METRICS_ENDPOINT:-103.67.203.71:4318}"

ENABLE_MUTUAL_PEER="${ENABLE_MUTUAL_PEER:-true}"
MUTUAL_PEER="${MUTUAL_PEER:-/ip4/103.67.203.71/tcp/2201/p2p/12D3KooWGKuJauY5bRWpL52Xa9JWBrHp1qdz3vNAFsRQnS7ZZexz}"

is_true() {
  case "${1:-}" in
    true|1|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  else
    docker-compose "$@"
  fi
}

check_local_tools() {
  command -v ssh >/dev/null 2>&1 || { echo "ERROR: ssh is required."; exit 1; }
  command -v scp >/dev/null 2>&1 || { echo "ERROR: scp is required."; exit 1; }

  if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker is not running or this shell cannot access Docker."
    exit 1
  fi

  if docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1; then
    return 0
  fi

  echo "ERROR: Docker Compose is not available."
  exit 1
}

check_source_host() {
  if [ -z "${SOURCE_HOST}" ]; then
    echo "ERROR: SOURCE_HOST is required."
    echo "Example:"
    echo "  SOURCE_HOST=ubuntu@103.67.203.71 bash $0 up"
    exit 1
  fi
}

get_image_uid_gid() {
  NODE_UID="$(docker run --rm --entrypoint id "${IMAGE}" -u 2>/dev/null || true)"
  NODE_GID="$(docker run --rm --entrypoint id "${IMAGE}" -g 2>/dev/null || true)"

  if [ -z "${NODE_UID}" ]; then NODE_UID="0"; fi
  if [ -z "${NODE_GID}" ]; then NODE_GID="0"; fi

  export NODE_UID NODE_GID
}

remove_local_data_dir() {
  if [ -e "${DATA_DIR}" ]; then
    rm -rf "${DATA_DIR}" 2>/dev/null || {
      if command -v sudo >/dev/null 2>&1; then
        sudo rm -rf "${DATA_DIR}"
      else
        echo "ERROR: Cannot remove ${DATA_DIR}; sudo is not available."
        exit 1
      fi
    }
  fi
}

repair_host_permissions() {
  get_image_uid_gid

  echo "Repairing local permissions for Docker image UID:GID = ${NODE_UID}:${NODE_GID}"

  # Remove stale locks from source store.
  find "${DATA_DIR}" -type f -name '.lock' -delete 2>/dev/null || sudo find "${DATA_DIR}" -type f -name '.lock' -delete

  # Make the container user own the store. This is the key difference from chmod -R 777.
  chown -R "${NODE_UID}:${NODE_GID}" "${DATA_DIR}" 2>/dev/null || sudo chown -R "${NODE_UID}:${NODE_GID}" "${DATA_DIR}"

  # Directories readable/traversable by owner.
  find "${DATA_DIR}" -type d -exec chmod 755 {} \; 2>/dev/null || sudo find "${DATA_DIR}" -type d -exec chmod 755 {} \;

  # Normal files readable by owner. Some databases need write access, owner has it.
  find "${DATA_DIR}" -type f -exec chmod 644 {} \; 2>/dev/null || sudo find "${DATA_DIR}" -type f -exec chmod 644 {} \;

  # Sensitive keys must be strict, otherwise celestia-node refuses to start.
  find "${DATA_DIR}" -type f \( \
      -name 'p2p-key' -o \
      -name '*key*' -o \
      -path '*/keys/*' -o \
      -path '*/keyring-*/*' \
    \) -exec chmod 600 {} \; 2>/dev/null || \
    sudo find "${DATA_DIR}" -type f \( \
      -name 'p2p-key' -o \
      -name '*key*' -o \
      -path '*/keys/*' -o \
      -path '*/keyring-*/*' \
    \) -exec chmod 600 {} \;

  echo "Permission repair completed."
}

clone_prebuilt_archive() {
  check_source_host

  echo "Checking source archive on ${SOURCE_HOST}: ${SOURCE_ARCHIVE}"
  ssh ${SSH_OPTS} "${SOURCE_HOST}" "test -r '${SOURCE_ARCHIVE}'"

  echo "Copying archive to local: ${LOCAL_ARCHIVE}"
  scp ${SSH_OPTS} "${SOURCE_HOST}:${SOURCE_ARCHIVE}" "${LOCAL_ARCHIVE}"

  echo "Cleaning local data dir: ${DATA_DIR}"
  remove_local_data_dir
  mkdir -p "${DATA_DIR}"

  echo "Extracting archive into ${DATA_DIR}"
  local tmp_extract="./.bridge-store-extract-tmp"
  rm -rf "${tmp_extract}"
  mkdir -p "${tmp_extract}"

  tar -xzf "${LOCAL_ARCHIVE}" -C "${tmp_extract}"

  local extracted_dir
  extracted_dir="$(find "${tmp_extract}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"

  if [ -z "${extracted_dir}" ]; then
    echo "ERROR: Archive did not contain a bridge store directory."
    rm -rf "${tmp_extract}"
    exit 1
  fi

  cp -a "${extracted_dir}/." "${DATA_DIR}/"
  rm -rf "${tmp_extract}"

  repair_host_permissions

  echo "Local bridge store is ready: ${DATA_DIR}"
}

write_compose_file() {
  local mutual_line=""
  local metrics_lines=""

  if is_true "${ENABLE_MUTUAL_PEER}" && [ -n "${MUTUAL_PEER}" ]; then
    mutual_line="          --p2p.mutual ${MUTUAL_PEER} \\"
  fi

  if is_true "${ENABLE_METRICS}"; then
    metrics_lines="          --metrics \\
          --metrics.endpoint ${METRICS_ENDPOINT} \\
          --metrics.tls=false \\"
  fi

  cat > "${COMPOSE_FILE}" <<YAML
services:
  ${SERVICE_NAME}:
    image: ${IMAGE}
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    environment:
      - NODE_TYPE=bridge
      - P2P_NETWORK=private
    volumes:
      - ${DATA_DIR}:/home/celestia
    ports:
      - "${HOST_RPC_PORT}:26658"
      - "${HOST_P2P_PORT}:2121"
    entrypoint: ["/bin/bash", "-c"]
    command:
      - |
        set -euo pipefail

        exec celestia bridge start \\
          --p2p.network private \\
          --core.ip ${SERVER_IP} \\
          --core.port ${CORE_PORT} \\
          --rpc.addr 0.0.0.0 \\
          --rpc.port 26658 \\
${mutual_line}
${metrics_lines}
          --rpc.skip-auth
YAML
}

show_info() {
  echo "Source archive config:"
  echo "  Source host:     ${SOURCE_HOST:-not set}"
  echo "  Source archive:  ${SOURCE_ARCHIVE}"
  echo
  echo "Local bridge config:"
  echo "  Core gRPC:       ${SERVER_IP}:${CORE_PORT}"
  echo "  Local RPC port:  ${HOST_RPC_PORT}"
  echo "  Local P2P port:  ${HOST_P2P_PORT}"
  echo "  Data dir:        ${DATA_DIR}"
  echo "  Metrics enabled: ${ENABLE_METRICS}"
  echo "  Mutual enabled:  ${ENABLE_MUTUAL_PEER}"
  echo "  Compose file:    ${COMPOSE_FILE}"
}

usage() {
  echo "Usage:"
  echo "  SOURCE_HOST=ubuntu@103.67.203.71 bash $0 up"
  echo "  SOURCE_HOST=ubuntu@103.67.203.71 bash $0 clone"
  echo "  bash $0 down"
  echo "  bash $0 logs"
  echo "  bash $0 ps"
  echo "  bash $0 config"
  echo "  SOURCE_HOST=ubuntu@103.67.203.71 bash $0 reset"
  echo "  bash $0 fix-perms"
}

case "${1:-}" in
  up)
    check_local_tools
    clone_prebuilt_archive
    write_compose_file
    show_info
    compose_cmd -f "${COMPOSE_FILE}" up -d
    ;;

  clone)
    check_local_tools
    clone_prebuilt_archive
    show_info
    ;;

  down)
    check_local_tools
    write_compose_file
    compose_cmd -f "${COMPOSE_FILE}" down
    ;;

  logs)
    check_local_tools
    write_compose_file
    compose_cmd -f "${COMPOSE_FILE}" logs -f "${SERVICE_NAME}"
    ;;

  ps)
    check_local_tools
    write_compose_file
    compose_cmd -f "${COMPOSE_FILE}" ps
    ;;

  config)
    write_compose_file
    cat "${COMPOSE_FILE}"
    ;;

  reset)
    check_local_tools
    write_compose_file
    compose_cmd -f "${COMPOSE_FILE}" down || true
    clone_prebuilt_archive
    show_info
    compose_cmd -f "${COMPOSE_FILE}" up -d
    ;;

  fix-perms)
    check_local_tools
    repair_host_permissions
    write_compose_file
    ;;

  info)
    show_info
    ;;

  *)
    usage
    exit 1
    ;;
esac
