#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
CONTAINER_NAME="postgis_geodebate_db"
DB_USER="admin"
DB_NAME="geospatial_warehouse"
EXPECTED_COUNT="3"
ERRORS=0
echo "[TEST] Checking generated files..."
for f in stop.sh dashboard/package.json dashboard/server.js dashboard/public/index.html; do
  [ -f "$f" ] && echo "  OK $f" || { echo "  MISSING $f"; ERRORS=$((ERRORS+1)); }
done
echo "[TEST] Checking container..."
docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" && echo "  OK Container running" || { echo "  FAIL Container not running"; ERRORS=$((ERRORS+1)); }
echo "[TEST] Checking data (landmarks count)..."
LANDMARKS_COUNT=$(docker exec "${CONTAINER_NAME}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -c "SELECT COUNT(*) FROM public.landmarks;" 2>/dev/null || echo "0")
[ "${LANDMARKS_COUNT}" = "${EXPECTED_COUNT}" ] && echo "  OK landmarks count = ${EXPECTED_COUNT}" || { echo "  FAIL landmarks count = ${LANDMARKS_COUNT} (expected ${EXPECTED_COUNT})"; ERRORS=$((ERRORS+1)); }
[ ${ERRORS} -eq 0 ] && echo "[TEST] All checks passed." || { echo "[TEST] ${ERRORS} check(s) failed."; exit 1; }
