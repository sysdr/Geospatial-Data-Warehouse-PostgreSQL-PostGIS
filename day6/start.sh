#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_DIR="${SCRIPT_DIR}/dashboard"
DASHBOARD_PORT="${DASHBOARD_PORT:-3006}"
# Avoid duplicate: kill existing process on port
if command -v lsof &>/dev/null; then
  PID=$(lsof -ti ":${DASHBOARD_PORT}" 2>/dev/null || true)
  if [ -n "$PID" ]; then
    kill "$PID" 2>/dev/null || true
    sleep 2
  fi
fi
if [ ! -d "${DASHBOARD_DIR}" ] || [ ! -f "${DASHBOARD_DIR}/server.js" ]; then
  echo "Dashboard not found. Run setup.sh first."
  exit 1
fi
cd "${DASHBOARD_DIR}"
export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="postgres"
export PGPASSWORD="mysecretpassword"
export PGDATABASE="geospatial_dw"
export DASHBOARD_PORT="${DASHBOARD_PORT}"
echo "Starting dashboard at http://localhost:${DASHBOARD_PORT}"
exec node server.js
