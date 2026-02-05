#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
CONTAINER_NAME="geospatial_pg17"
POSTGRES_USER="pguser"
POSTGRES_DB="gis_warehouse"
ERRORS=0
echo "[TEST] Checking generated files..."
for f in postgresql.conf stop.sh; do
  [ -f "$f" ] && echo "  OK $f" || { echo "  MISSING $f"; ERRORS=$((ERRORS+1)); }
done
[ -d "pgdata" ] && echo "  OK pgdata/" || { echo "  MISSING pgdata/"; ERRORS=$((ERRORS+1)); }
echo "[TEST] Checking container..."
docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" && echo "  OK Container running" || { echo "  FAIL Container not running"; ERRORS=$((ERRORS+1)); }
echo "[TEST] Checking data (places and regions)..."
PLACES=$(docker exec "${CONTAINER_NAME}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -A -c "SELECT COUNT(*) FROM places;" 2>/dev/null || echo "0")
REGIONS=$(docker exec "${CONTAINER_NAME}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -A -c "SELECT COUNT(*) FROM regions;" 2>/dev/null || echo "0")
[ "${PLACES}" = "10" ] && echo "  OK places count = 10" || { echo "  FAIL places count = ${PLACES} (expected 10)"; ERRORS=$((ERRORS+1)); }
[ "${REGIONS}" = "3" ] && echo "  OK regions count = 3" || { echo "  FAIL regions count = ${REGIONS} (expected 3)"; ERRORS=$((ERRORS+1)); }
[ ${ERRORS} -eq 0 ] && echo "[TEST] All checks passed." || { echo "[TEST] ${ERRORS} check(s) failed."; exit 1; }
