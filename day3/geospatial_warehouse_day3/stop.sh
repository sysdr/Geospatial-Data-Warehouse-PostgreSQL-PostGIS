#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
echo "Stopping PostGIS stack..."
docker compose down 2>/dev/null || docker-compose down 2>/dev/null || true
echo "Done."
