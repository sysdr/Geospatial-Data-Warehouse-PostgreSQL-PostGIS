#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
CONTAINER_NAME="postgis_geospatial_day1_container"
DB_USER="user"
DB_NAME="geospatial_warehouse_geospatial_day1"
ERRORS=0
echo "[TEST] Checking generated files..."
for f in sql/setup_db.sql sql/insert_data.sql sql/query_data.sql stop.sh; do
  [ -f "$f" ] && echo "  OK $f" || { echo "  MISSING $f"; ERRORS=$((ERRORS+1)); }
done
echo "[TEST] Checking container..."
docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" && echo "  OK Container running" || { echo "  FAIL Container not running"; ERRORS=$((ERRORS+1)); }
echo "[TEST] Checking data (row count and non-zero distances)..."
ROWS=$(docker exec "${CONTAINER_NAME}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -c "SELECT COUNT(*) FROM locations;" 2>/dev/null || echo "0")
[ "${ROWS}" = "4" ] && echo "  OK locations count = 4" || { echo "  FAIL locations count = ${ROWS} (expected 4)"; ERRORS=$((ERRORS+1)); }
DIST=$(docker exec "${CONTAINER_NAME}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -c "SELECT ST_Distance((SELECT geog_global FROM locations WHERE name = 'San Francisco Ferry Building'), (SELECT geog_global FROM locations WHERE name = 'New York Times Square'));" 2>/dev/null || echo "0")
[ -n "${DIST}" ] && awk "BEGIN {exit (${DIST} > 0) ? 0 : 1}" 2>/dev/null && echo "  OK SF-NY distance (m) = ${DIST}" || { echo "  FAIL distance not positive: ${DIST}"; ERRORS=$((ERRORS+1)); }
[ ${ERRORS} -eq 0 ] && echo "[TEST] All checks passed." || { echo "[TEST] ${ERRORS} check(s) failed."; exit 1; }
