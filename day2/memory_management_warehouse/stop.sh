#!/bin/bash
CONTAINER_NAME="geospatial_pg17"
echo "Stopping and removing container: ${CONTAINER_NAME}"
docker stop "${CONTAINER_NAME}" 2>/dev/null && docker rm "${CONTAINER_NAME}" 2>/dev/null && echo "Done." || echo "Container not running or already removed."
