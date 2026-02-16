#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
CONTAINER_NAME="postgis_day3_db"
DB_USER="user"
DB_NAME="geospatial_warehouse_day3"
EXPECTED_COUNT="5000"
ERRORS=0
echo "[TEST] Checking generated files..."
for f in docker-compose.yml explain_analyze_output.txt stop.sh; do
  [ -f "$f" ] && echo "  OK $f" || { echo "  MISSING $f"; ERRORS=$((ERRORS+1)); }
done
echo "[TEST] Checking container..."
docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" && echo "  OK Container running" || { echo "  FAIL Container not running"; ERRORS=$((ERRORS+1)); }
echo "[TEST] Checking data (locations count)..."
LOC_COUNT=$(docker exec "${CONTAINER_NAME}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -A -c "SELECT COUNT(*) FROM public.locations;" 2>/dev/null || echo "0")
[ "${LOC_COUNT}" = "${EXPECTED_COUNT}" ] && echo "  OK locations count = ${EXPECTED_COUNT}" || { echo "  FAIL locations count = ${LOC_COUNT} (expected ${EXPECTED_COUNT})"; ERRORS=$((ERRORS+1)); }
[ ${ERRORS} -eq 0 ] && echo "[TEST] All checks passed." || { echo "[TEST] ${ERRORS} check(s) failed."; exit 1; }
