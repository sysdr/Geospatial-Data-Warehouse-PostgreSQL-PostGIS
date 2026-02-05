#!/bin/bash
CONTAINER_NAME="postgis_geospatial_day1_container"
echo "Stopping and removing container: ${CONTAINER_NAME}"
docker stop "${CONTAINER_NAME}" 2>/dev/null && docker rm "${CONTAINER_NAME}" 2>/dev/null && echo "Done." || echo "Container not running or already removed."
