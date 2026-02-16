#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/docker" && docker-compose down 2>/dev/null || true
echo "PostGIS container stopped. Done."
