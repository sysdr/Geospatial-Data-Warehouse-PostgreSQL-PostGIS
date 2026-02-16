#!/bin/bash
echo "Stopping PostGIS container..."
docker stop postgis_geodebate_db 2>/dev/null || true
docker rm postgis_geodebate_db 2>/dev/null || true
echo "Done."
