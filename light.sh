#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="docker-compose.yml"
SERVICE_NAME="celestia-light-node-test"
LIGHT_DIR="./light"

chmod +x "$0" 2>/dev/null || true

write_compose_file() {
  cat > "${COMPOSE_FILE}" <<'YAML'
services:
  celestia-light-node-test:
    image: ghcr.io/celestiaorg/celestia-node:v0.28.5-mocha
    container_name: celestia-light-node-test
    restart: unless-stopped
    user: "0:0"
    environment:
      - NODE_TYPE=light
      - P2P_NETWORK=private
    volumes:
      - ./light:/home/celestia
    ports:
      - "26762:26658"
    entrypoint: ["/bin/bash", "-c"]
    command:
      - |
        set -euo pipefail

        TRUSTED_PEERS="/ip4/103.67.203.71/tcp/2201/p2p/12D3KooWGKuJauY5bRWpL52Xa9JWBrHp1qdz3vNAFsRQnS7ZZexz,/ip4/131.153.224.169/tcp/2221/p2p/12D3KooWCWdAL61Ppf2S4SfQWtGsDjJnxAU39MW7Vj1iTHNkLZ2t"

        # Fix only permissions that Celestia actually requires.
        # Do not chmod everything to 777, because p2p-key must be 0600.
        mkdir -p /home/celestia
        chmod 700 /home/celestia || true

        if [ -f /home/celestia/keys/p2p-key ]; then
          chmod 600 /home/celestia/keys/p2p-key || true
        fi

        if [ ! -f /home/celestia/config.toml ]; then
          celestia light init \
            --p2p.network private \
            --rpc.addr 0.0.0.0
        fi

        if [ -f /home/celestia/keys/p2p-key ]; then
          chmod 600 /home/celestia/keys/p2p-key || true
        fi

        exec celestia light start \
          --p2p.network private \
          --rpc.addr 0.0.0.0 \
          --rpc.port 26658 \
          --core.ip 103.67.203.71 \
          --core.port 14090 \
          --headers.trusted-peers "$$TRUSTED_PEERS" \
          --p2p.mutual "$$TRUSTED_PEERS" \
          --metrics \
          --metrics.endpoint 103.67.203.71:4318 \
          --metrics.tls=false
YAML
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    echo "ERROR: Docker Compose is not available."
    exit 1
  fi
}

check_docker() {
  if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker is not running or this shell cannot access Docker."
    exit 1
  fi
}

prepare_light_dir() {
  mkdir -p "${LIGHT_DIR}"

  # Avoid recursive chmod 777. It breaks /home/celestia/keys/p2p-key.
  chmod 700 "${LIGHT_DIR}" 2>/dev/null || {
    if command -v sudo >/dev/null 2>&1; then
      sudo chmod 700 "${LIGHT_DIR}"
    else
      echo "WARN: Cannot chmod ${LIGHT_DIR}; continuing."
    fi
  }

  # If an old run already chmodded files to 777, repair key permissions.
  if [ -f "${LIGHT_DIR}/keys/p2p-key" ]; then
    chmod 600 "${LIGHT_DIR}/keys/p2p-key" 2>/dev/null || {
      if command -v sudo >/dev/null 2>&1; then
        sudo chmod 600 "${LIGHT_DIR}/keys/p2p-key"
      else
        echo "WARN: Cannot chmod ${LIGHT_DIR}/keys/p2p-key; continuing."
      fi
    }
  fi
}

safe_remove_light_dir() {
  if [ -e "${LIGHT_DIR}" ]; then
    rm -rf "${LIGHT_DIR}" 2>/dev/null || {
      if command -v sudo >/dev/null 2>&1; then
        sudo rm -rf "${LIGHT_DIR}"
      else
        echo "ERROR: Cannot remove ${LIGHT_DIR}, and sudo is not available."
        exit 1
      fi
    }
  fi
}

show_usage() {
  echo "Usage:"
  echo "  $0 up"
  echo "  $0 down"
  echo "  $0 restart"
  echo "  $0 logs"
  echo "  $0 ps"
  echo "  $0 pull"
  echo "  $0 config"
  echo "  $0 reset"
}

case "${1:-}" in
  up)
    check_docker
    prepare_light_dir
    write_compose_file
    compose_cmd -f "${COMPOSE_FILE}" up -d
    ;;

  down)
    check_docker
    write_compose_file
    compose_cmd -f "${COMPOSE_FILE}" down
    ;;

  restart)
    check_docker
    prepare_light_dir
    write_compose_file
    compose_cmd -f "${COMPOSE_FILE}" down
    compose_cmd -f "${COMPOSE_FILE}" up -d
    ;;

  logs)
    check_docker
    write_compose_file
    compose_cmd -f "${COMPOSE_FILE}" logs -f "${SERVICE_NAME}"
    ;;

  ps)
    check_docker
    write_compose_file
    compose_cmd -f "${COMPOSE_FILE}" ps
    ;;

  pull)
    check_docker
    write_compose_file
    compose_cmd -f "${COMPOSE_FILE}" pull
    ;;

  config)
    write_compose_file
    cat "${COMPOSE_FILE}"
    ;;

  reset)
    check_docker
    write_compose_file
    compose_cmd -f "${COMPOSE_FILE}" down || true
    safe_remove_light_dir
    prepare_light_dir
    compose_cmd -f "${COMPOSE_FILE}" up -d
    ;;

  *)
    show_usage
    exit 1
    ;;
esac
