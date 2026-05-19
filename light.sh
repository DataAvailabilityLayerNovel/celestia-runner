#!/usr/bin/env bash
set -euo pipefail

# Celestia Light Node helper for WSL/Linux
#
# One-command usage:
#   bash light.sh up
#
# Other commands:
#   bash light.sh down
#   bash light.sh logs
#   bash light.sh restart
#   bash light.sh reset
#   bash light.sh ps
#   bash light.sh pull
#   bash light.sh config
#
# This script:
#   - generates docker-compose.yml automatically
#   - creates ./light automatically
#   - fixes ./light permissions automatically for bind mount
#   - starts/stops the Celestia node via Docker Compose

chmod +x "$0" 2>/dev/null || true

COMPOSE_FILE="docker-compose.yml"
SERVICE_NAME="celestia-light-node-test"
LIGHT_DIR="./light"

write_compose_file() {
  cat > "${COMPOSE_FILE}" <<'YAML'
services:
  celestia-light-node-test:
    image: ghcr.io/celestiaorg/celestia-node:v0.28.5-mocha
    container_name: celestia-light-node-test
    restart: unless-stopped
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

        if [ ! -f /home/celestia/config.toml ]; then
          celestia light init \
            --p2p.network private \
            --rpc.addr 0.0.0.0
        fi

        exec celestia light start \
          --p2p.network private \
          --rpc.addr 0.0.0.0 \
          --rpc.port 26658 \
          --core.ip 103.67.203.71 \
          --core.port 14090 \
          --headers.trusted-peers /ip4/103.67.203.71/tcp/2201/p2p/12D3KooWGKuJauY5bRWpL52Xa9JWBrHp1qdz3vNAFsRQnS7ZZexz \
          --p2p.mutual /ip4/103.67.203.71/tcp/2201/p2p/12D3KooWGKuJauY5bRWpL52Xa9JWBrHp1qdz3vNAFsRQnS7ZZexz \
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
    echo "Install Docker Desktop and enable WSL integration, or install Docker Compose on Linux."
    exit 1
  fi
}

check_docker() {
  if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker is not running or this shell cannot access Docker."
    echo "On WSL: open Docker Desktop and enable WSL integration."
    echo "On Linux server: start Docker with: sudo systemctl start docker"
    exit 1
  fi
}

run_chmod() {
  local target="$1"

  if chmod 777 "$target" 2>/dev/null; then
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo chmod 777 "$target"
    return 0
  fi

  echo "ERROR: Cannot chmod 777 ${target}, and sudo is not available."
  exit 1
}

prepare_light_dir() {
  mkdir -p "${LIGHT_DIR}"
  run_chmod "${LIGHT_DIR}"

  # Also try to fix existing content if the directory was created by Docker/root before.
  if [ -d "${LIGHT_DIR}" ]; then
    chmod -R 777 "${LIGHT_DIR}" 2>/dev/null || {
      if command -v sudo >/dev/null 2>&1; then
        sudo chmod -R 777 "${LIGHT_DIR}"
      else
        echo "WARN: Cannot chmod -R ${LIGHT_DIR}; continuing."
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
  echo "  bash light.sh up        # generate compose, prepare ./light, start node"
  echo "  bash light.sh down      # stop and remove compose container/network"
  echo "  bash light.sh restart   # restart node"
  echo "  bash light.sh logs      # follow logs"
  echo "  bash light.sh ps        # show status"
  echo "  bash light.sh pull      # pull image"
  echo "  bash light.sh config    # print generated docker-compose.yml"
  echo "  bash light.sh reset     # stop, delete ./light, recreate it, start from scratch"
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
