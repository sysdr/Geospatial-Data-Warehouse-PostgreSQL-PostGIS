#!/bin/bash
# Stop project containers and remove unused Docker resources.
# Optionally remove node_modules, venv, .pytest_cache, .pyc, __pycache__, Istio from this project.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

CONTAINER_NAME="pg_geospatial_day6"

echo "--- Stopping project container(s) ---"
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
  docker stop "${CONTAINER_NAME}" 2>/dev/null || true
  docker rm "${CONTAINER_NAME}" 2>/dev/null || true
  echo "Stopped and removed: ${CONTAINER_NAME}"
else
  echo "Container ${CONTAINER_NAME} not found; skipping."
fi

echo "--- Removing unused Docker resources ---"
docker container prune -f 2>/dev/null || true
docker volume prune -f 2>/dev/null || true
docker image prune -af 2>/dev/null || true
docker network prune -f 2>/dev/null || true
echo "Docker cleanup done."

echo "--- Removing node_modules, venv, .pytest_cache, .pyc, __pycache__, Istio from project ---"
rm -rf "${SCRIPT_DIR}/dashboard/node_modules" 2>/dev/null || true
rm -rf "${SCRIPT_DIR}/venv" "${SCRIPT_DIR}/.pytest_cache" 2>/dev/null || true
find "${SCRIPT_DIR}" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "${SCRIPT_DIR}" -type f -name "*.pyc" -delete 2>/dev/null || true
find "${SCRIPT_DIR}" -type d -iname "*istio*" -exec rm -rf {} + 2>/dev/null || true
find "${SCRIPT_DIR}" -type f -iname "*istio*" -delete 2>/dev/null || true
echo "Project cleanup done."

echo "--- Cleanup complete ---"
