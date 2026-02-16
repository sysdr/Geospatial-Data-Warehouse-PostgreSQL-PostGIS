#!/bin/bash
# Start PostGIS container and dashboard (run from day5/ or use full path)
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="Master_4326_vs_3857"
PROJECT_DIR="${SCRIPT_DIR}/${PROJECT_NAME}"
DOCKER_COMPOSE_FILE="docker-compose.yml"
SERVICE_NAME="postgis"
DB_PORT="5432"
DB_USER="user"
DB_PASSWORD="password"
DB_NAME="geospatial_db"
DASHBOARD_PORT="${DASHBOARD_PORT:-3005}"

if ! command -v docker &>/dev/null; then
    echo "Docker is not installed or not in PATH." >&2
    exit 1
fi
if command -v docker-compose &>/dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    DOCKER_COMPOSE_CMD="docker compose"
fi

if [ ! -d "${PROJECT_DIR}/docker" ] || [ ! -f "${PROJECT_DIR}/docker/${DOCKER_COMPOSE_FILE}" ]; then
    echo "Project not set up. Run ./build.sh or ./setup.sh first." >&2
    exit 1
fi

echo "[INFO] Starting PostGIS container..."
(cd "${PROJECT_DIR}/docker" && $DOCKER_COMPOSE_CMD up -d) || { echo "Failed to start Docker." >&2; exit 1; }

echo "[INFO] Starting dashboard..."
DASHBOARD_DIR="${PROJECT_DIR}/dashboard"
if [ -d "${DASHBOARD_DIR}" ] && [ -f "${DASHBOARD_DIR}/package.json" ]; then
    if command -v lsof &>/dev/null && lsof -i ":${DASHBOARD_PORT}" 2>/dev/null | grep -q LISTEN; then
        echo "[INFO] Dashboard already running on http://localhost:${DASHBOARD_PORT}"
    else
        [ ! -d "${DASHBOARD_DIR}/node_modules" ] && (cd "${DASHBOARD_DIR}" && npm install --silent)
        export DASHBOARD_PORT PGHOST="${PGHOST:-localhost}" PGPORT="${DB_PORT}" PGUSER="${DB_USER}" PGPASSWORD="${DB_PASSWORD}" PGDATABASE="${DB_NAME}"
        [ -x "${PROJECT_DIR}/venv/bin/python3" ] && export PYTHON_PATH="${PROJECT_DIR}/venv/bin/python3"
        (cd "${DASHBOARD_DIR}" && nohup node server.js >> dashboard.log 2>&1 &)
        sleep 2
        echo "[INFO] Dashboard started at http://localhost:${DASHBOARD_PORT}"
    fi
else
    echo "[WARN] Dashboard not found at ${DASHBOARD_DIR}; run ./build.sh first." >&2
fi

echo "[INFO] Done. Database: localhost:${DB_PORT}, Dashboard: http://localhost:${DASHBOARD_PORT}"
