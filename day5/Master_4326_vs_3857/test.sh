#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
CONTAINER_NAME="postgis_container"
DB_USER="user"
DB_NAME="geospatial_db"
EXPECTED_COUNT="3"
ERRORS=0
echo "[TEST] Checking generated files..."
for f in docker/docker-compose.yml src/cli_tool.py stop.sh dashboard/package.json dashboard/server.js dashboard/public/index.html; do
  [ -f "$f" ] && echo "  OK $f" || { echo "  MISSING $f"; ERRORS=$((ERRORS+1)); }
done
echo "[TEST] Checking container..."
docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" && echo "  OK Container running" || { echo "  FAIL Container not running"; ERRORS=$((ERRORS+1)); }
echo "[TEST] Checking data (locations_4326 and locations_3857 count)..."
C4326=$(docker exec "${CONTAINER_NAME}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -c "SELECT COUNT(*) FROM public.locations_4326;" 2>/dev/null || echo "0")
C3857=$(docker exec "${CONTAINER_NAME}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -c "SELECT COUNT(*) FROM public.locations_3857;" 2>/dev/null || echo "0")
[ "${C4326}" = "${EXPECTED_COUNT}" ] && echo "  OK locations_4326 count = ${EXPECTED_COUNT}" || { echo "  FAIL locations_4326 = ${C4326} (expected ${EXPECTED_COUNT})"; ERRORS=$((ERRORS+1)); }
[ "${C3857}" = "${EXPECTED_COUNT}" ] && echo "  OK locations_3857 count = ${EXPECTED_COUNT}" || { echo "  FAIL locations_3857 = ${C3857} (expected ${EXPECTED_COUNT})"; ERRORS=$((ERRORS+1)); }
[ ${ERRORS} -eq 0 ] && echo "[TEST] All checks passed." || { echo "[TEST] ${ERRORS} check(s) failed."; exit 1; }
