#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
CONTAINER_NAME="pg_geospatial_day6"
DB_USER="postgres"
DB_NAME="geospatial_dw"
EXPECTED_REGIONS="3"
EXPECTED_SENSORS="100000"
ERRORS=0
echo "[TEST] Checking generated files..."
for f in stop.sh start.sh dashboard/package.json dashboard/server.js dashboard/public/index.html; do
  [ -f "$f" ] && echo "  OK $f" || { echo "  MISSING $f"; ERRORS=$((ERRORS+1)); }
done
echo "[TEST] Checking container..."
docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" && echo "  OK Container running" || { echo "  FAIL Container not running"; ERRORS=$((ERRORS+1)); }
echo "[TEST] Checking data (regions and sensors count)..."
RCNT=$(docker exec "${CONTAINER_NAME}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -c "SELECT COUNT(*) FROM public.regions;" 2>/dev/null || echo "0")
SCNT=$(docker exec "${CONTAINER_NAME}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -c "SELECT COUNT(*) FROM public.sensors;" 2>/dev/null || echo "0")
[ "${RCNT}" = "${EXPECTED_REGIONS}" ] && echo "  OK regions count = ${EXPECTED_REGIONS}" || { echo "  FAIL regions = ${RCNT} (expected ${EXPECTED_REGIONS})"; ERRORS=$((ERRORS+1)); }
[ "${SCNT}" = "${EXPECTED_SENSORS}" ] && echo "  OK sensors count = ${EXPECTED_SENSORS}" || { echo "  FAIL sensors = ${SCNT} (expected ${EXPECTED_SENSORS})"; ERRORS=$((ERRORS+1)); }
[ ${ERRORS} -eq 0 ] && echo "[TEST] All checks passed." || { echo "[TEST] ${ERRORS} check(s) failed."; exit 1; }
