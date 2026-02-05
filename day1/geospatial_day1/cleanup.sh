#!/bin/bash
# Cleanup script for geospatial_day1: stop project containers and remove unused Docker resources.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

CONTAINER_NAME="postgis_geospatial_day1_container"

echo "Stopping project container: ${CONTAINER_NAME}"
docker stop "${CONTAINER_NAME}" 2>/dev/null || true
docker rm "${CONTAINER_NAME}" 2>/dev/null || true

echo "Removing unused Docker containers..."
docker container prune -f

echo "Removing unused Docker volumes..."
docker volume prune -f

echo "Removing unused Docker images (dangling and unreferenced)..."
docker image prune -af

echo "Removing unused Docker networks..."
docker network prune -f

echo "Cleanup complete."
