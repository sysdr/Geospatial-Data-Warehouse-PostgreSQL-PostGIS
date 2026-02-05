#!/bin/bash
# Cleanup script: stop project containers, remove unused Docker resources, and remove node_modules/venv/cache/vendor/rr from project.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

CONTAINER_NAME="geospatial_pg17"

echo "--- Removing node_modules, venv, .pytest_cache, vendor, Istio, .pyc, .rr from project ---"
rm -rf "${SCRIPT_DIR}/dashboard/node_modules" 2>/dev/null || true
rm -rf "${SCRIPT_DIR}/venv" "${SCRIPT_DIR}/.pytest_cache" "${SCRIPT_DIR}/vendor" 2>/dev/null || true
find "${SCRIPT_DIR}" -maxdepth 4 -type d -iname "*istio*" -exec rm -rf {} + 2>/dev/null || true
find "${SCRIPT_DIR}" -maxdepth 4 -type f -name "*.pyc" -delete 2>/dev/null || true
find "${SCRIPT_DIR}" -maxdepth 4 -type f -name "*.rr" -delete 2>/dev/null || true
find "${SCRIPT_DIR}" -maxdepth 4 -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
echo "Project cleanup done."

echo "--- Stopping project container(s) ---"
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  docker stop "${CONTAINER_NAME}" 2>/dev/null || true
  docker rm "${CONTAINER_NAME}" 2>/dev/null || true
  echo "Stopped and removed: ${CONTAINER_NAME}"
else
  echo "Container ${CONTAINER_NAME} not found; skipping."
fi

echo "--- Removing unused Docker resources ---"
docker container prune -f
docker volume prune -f
docker image prune -af
docker network prune -f 2>/dev/null || true
echo "Docker cleanup done."

echo "--- Cleanup complete ---"
