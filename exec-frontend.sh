#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="rikkei-frontend-qa"
IMAGE="nginx:latest"
ENV_NAME="API_ENDPOINT"
ENV_VALUE="https://qa-api.rikkei.edu.vn"
SETUP_ONLY=0

if [ "${1:-}" = "--setup-only" ]; then
  SETUP_ONLY=1
elif [ "$#" -gt 0 ]; then
  echo "Usage: $0 [--setup-only]" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker command not found." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Error: Docker daemon is not available." >&2
  exit 1
fi

container_exists() {
  docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1
}

image_is_compatible() {
  local image="$1"
  case "${image#docker.io/}" in
    nginx|nginx:latest) return 0 ;;
    *) return 1 ;;
  esac
}

env_is_compatible() {
  local env_lines count
  env_lines="$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER_NAME")"
  count="$(grep -c "^${ENV_NAME}=" <<< "$env_lines" || true)"
  [ "$count" -eq 1 ] || return 1
  grep -Fxq "${ENV_NAME}=${ENV_VALUE}" <<< "$env_lines"
}

if container_exists; then
  current_image="$(docker inspect --format '{{.Config.Image}}' "$CONTAINER_NAME")"
  if ! image_is_compatible "$current_image"; then
    echo "Error: existing container '${CONTAINER_NAME}' uses incompatible image '${current_image}'." >&2
    echo "Expected image: ${IMAGE}." >&2
    echo "Refusing to delete or recreate the existing container." >&2
    exit 1
  fi

  if ! env_is_compatible; then
    echo "Error: existing container '${CONTAINER_NAME}' has an incorrect ${ENV_NAME}." >&2
    echo "Expected: ${ENV_NAME}=${ENV_VALUE}" >&2
    echo "Refusing to delete or recreate the existing container." >&2
    docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER_NAME" >&2 || true
    exit 1
  fi

  if [ "$(docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME")" = "true" ]; then
    echo "Reusing running container: ${CONTAINER_NAME}"
  else
    echo "Starting existing container: ${CONTAINER_NAME}"
    if ! docker start "$CONTAINER_NAME" >/dev/null; then
      echo "Error: failed to start existing container '${CONTAINER_NAME}'." >&2
      exit 1
    fi
  fi
else
  echo "Creating container: ${CONTAINER_NAME}"
  if ! docker run -d \
    --name "$CONTAINER_NAME" \
    -e "${ENV_NAME}=${ENV_VALUE}" \
    "$IMAGE"; then
    echo "Error: failed to create container '${CONTAINER_NAME}'." >&2
    exit 1
  fi
fi

if [ "$(docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME")" != "true" ]; then
  echo "Error: container '${CONTAINER_NAME}' is not running." >&2
  docker ps -a --filter "name=^/${CONTAINER_NAME}$" >&2 || true
  exit 1
fi

current_image="$(docker inspect --format '{{.Config.Image}}' "$CONTAINER_NAME")"
if ! image_is_compatible "$current_image"; then
  echo "Error: container '${CONTAINER_NAME}' is running with unexpected image '${current_image}'." >&2
  exit 1
fi

if ! env_is_compatible; then
  echo "Error: container '${CONTAINER_NAME}' does not have the exact required ${ENV_NAME}." >&2
  echo "Expected: ${ENV_NAME}=${ENV_VALUE}" >&2
  exit 1
fi

echo "Container: ${CONTAINER_NAME}"
echo "Image: ${current_image}"
echo "Status: $(docker inspect --format '{{.State.Status}}' "$CONTAINER_NAME")"
echo "${ENV_NAME}: ${ENV_VALUE}"
echo "Verification successful."

if [ "$SETUP_ONLY" -eq 0 ]; then
  exec docker exec -it "$CONTAINER_NAME" bash
fi
