#!/bin/bash

# Define colors for better console output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}  Geospatial Data Warehouse - geospatial_day1       ${NC}"
echo -e "${BLUE}  Spatial Types (Day 1)                             ${NC}"
echo -e "${BLUE}=====================================================${NC}"

# --- Configuration ---
DB_NAME="geospatial_warehouse_geospatial_day1"
DB_USER="user"
DB_PASSWORD="password"
DB_PORT="5432"
CONTAINER_NAME="postgis_geospatial_day1_container"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="${SCRIPT_DIR}/sql"
SQL_SETUP_FILE="${SQL_DIR}/setup_db.sql"
SQL_DATA_FILE="${SQL_DIR}/insert_data.sql"
SQL_QUERY_FILE="${SQL_DIR}/query_data.sql"

# --- Functions ---
log_info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

log_error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# --- Project Setup ---
log_info "Creating project directory structure..."
mkdir -p "${SQL_DIR}" || log_error "Failed to create SQL directory."
cd "${SCRIPT_DIR}" || log_error "Failed to change to script directory."
log_success "Directory structure created: ${SQL_DIR}"

# --- Generate SQL Files ---
log_info "Generating SQL setup file: ${SQL_SETUP_FILE}"
cat <<EOF > "${SQL_SETUP_FILE}"
-- Enable PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis;

-- Create table for locations
CREATE TABLE locations (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    -- Localized geometry (Web Mercator for display)
    geom_local GEOMETRY(Point, 3857),
    -- Global geometry (WGS84 for raw lat/lon, planar calculations)
    geom_global GEOMETRY(Point, 4326),
    -- Global geography (WGS84 for raw lat/lon, spherical calculations)
    geog_global GEOGRAPHY(Point, 4326)
);

-- Add spatial indexes for performance (we'll cover these in detail later!)
CREATE INDEX idx_locations_geom_local ON locations USING GIST (geom_local);
CREATE INDEX idx_locations_geom_global ON locations USING GIST (geom_global);
CREATE INDEX idx_locations_geog_global ON locations USING GIST (geog_global);

EOF
log_success "Generated ${SQL_SETUP_FILE}"

log_info "Generating SQL data insertion file: ${SQL_DATA_FILE}"
cat <<EOF > "${SQL_DATA_FILE}"
-- Insert sample data (geom_local: Web Mercator 3857, geom_global/geog_global: WGS84 4326)
INSERT INTO locations (name, geom_local, geom_global, geog_global) VALUES
('San Francisco Ferry Building',
 ST_Transform(ST_SetSRID(ST_MakePoint(-122.3934, 37.7955), 4326), 3857),
 ST_SetSRID(ST_MakePoint(-122.3934, 37.7955), 4326),
 ST_SetSRID(ST_MakePoint(-122.3934, 37.7955), 4326)::GEOGRAPHY),

('New York Times Square',
 ST_Transform(ST_SetSRID(ST_MakePoint(-73.9855, 40.7580), 4326), 3857),
 ST_SetSRID(ST_MakePoint(-73.9855, 40.7580), 4326),
 ST_SetSRID(ST_MakePoint(-73.9855, 40.7580), 4326)::GEOGRAPHY),

('London Big Ben',
 ST_Transform(ST_SetSRID(ST_MakePoint(-0.1247, 51.5007), 4326), 3857),
 ST_SetSRID(ST_MakePoint(-0.1247, 51.5007), 4326),
 ST_SetSRID(ST_MakePoint(-0.1247, 51.5007), 4326)::GEOGRAPHY),

('Eiffel Tower, Paris',
 ST_Transform(ST_SetSRID(ST_MakePoint(2.2945, 48.8584), 4326), 3857),
 ST_SetSRID(ST_MakePoint(2.2945, 48.8584), 4326),
 ST_SetSRID(ST_MakePoint(2.2945, 48.8584), 4326)::GEOGRAPHY);

EOF
log_success "Generated ${SQL_DATA_FILE}"

log_info "Generating SQL query file: ${SQL_QUERY_FILE}"
cat <<EOF > "${SQL_QUERY_FILE}"
-- Display all locations and their WKT representation
SELECT
    id,
    name,
    ST_AsText(geom_local) AS geom_local_wkt,
    ST_AsText(geom_global) AS geom_global_wkt,
    ST_AsText(geog_global::GEOMETRY) AS geog_global_wkt -- Cast geography to geometry for AsText
FROM locations;

-- Calculate planar distance (GEOMETRY) between San Francisco and New York
SELECT
    'SF to NY (GEOMETRY - Planar)' AS description,
    ST_Distance(
        (SELECT geom_global FROM locations WHERE name = 'San Francisco Ferry Building'),
        (SELECT geom_global FROM locations WHERE name = 'New York Times Square')
    ) AS distance_degrees
FROM locations LIMIT 1;

-- Calculate spherical distance (GEOGRAPHY) between San Francisco and New York (in meters)
SELECT
    'SF to NY (GEOGRAPHY - Spherical)' AS description,
    ST_Distance(
        (SELECT geog_global FROM locations WHERE name = 'San Francisco Ferry Building'),
        (SELECT geog_global FROM locations WHERE name = 'New York Times Square')
    ) AS distance_meters
FROM locations LIMIT 1;

-- Calculate spherical distance (GEOGRAPHY) between London and Paris (in meters)
SELECT
    'London to Paris (GEOGRAPHY - Spherical)' AS description,
    ST_Distance(
        (SELECT geog_global FROM locations WHERE name = 'London Big Ben'),
        (SELECT geog_global FROM locations WHERE name = 'Eiffel Tower, Paris')
    ) AS distance_meters
FROM locations LIMIT 1;

-- Assignment Query: Calculate distance between SF and NY using geom_global after transforming to geography
SELECT
    'SF to NY (GEOMETRY converted to GEOGRAPHY)' AS description,
    ST_Distance(
        (SELECT geom_global FROM locations WHERE name = 'San Francisco Ferry Building')::GEOGRAPHY,
        (SELECT geom_global FROM locations WHERE name = 'New York Times Square')::GEOGRAPHY
    ) AS distance_meters
FROM locations LIMIT 1;

EOF
log_success "Generated ${SQL_QUERY_FILE}"

# --- Generate stop.sh ---
STOP_SCRIPT="${SCRIPT_DIR}/stop.sh"
log_info "Generating stop script: ${STOP_SCRIPT}"
cat <<STOPEOF > "${STOP_SCRIPT}"
#!/bin/bash
CONTAINER_NAME="${CONTAINER_NAME}"
echo "Stopping and removing container: \${CONTAINER_NAME}"
docker stop "\${CONTAINER_NAME}" 2>/dev/null && docker rm "\${CONTAINER_NAME}" 2>/dev/null && echo "Done." || echo "Container not running or already removed."
STOPEOF
chmod +x "${STOP_SCRIPT}"
log_success "Generated ${STOP_SCRIPT}"

# --- Generate test.sh ---
TEST_SCRIPT="${SCRIPT_DIR}/test.sh"
log_info "Generating test script: ${TEST_SCRIPT}"
cat <<TESTEOF > "${TEST_SCRIPT}"
#!/bin/bash
set -e
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
cd "\${SCRIPT_DIR}"
CONTAINER_NAME="${CONTAINER_NAME}"
DB_USER="${DB_USER}"
DB_NAME="${DB_NAME}"
ERRORS=0
echo "[TEST] Checking generated files..."
for f in sql/setup_db.sql sql/insert_data.sql sql/query_data.sql stop.sh; do
  [ -f "\$f" ] && echo "  OK \$f" || { echo "  MISSING \$f"; ERRORS=\$((ERRORS+1)); }
done
echo "[TEST] Checking container..."
docker ps --format '{{.Names}}' | grep -q "^\${CONTAINER_NAME}\$" && echo "  OK Container running" || { echo "  FAIL Container not running"; ERRORS=\$((ERRORS+1)); }
echo "[TEST] Checking data (row count and non-zero distances)..."
ROWS=\$(docker exec "\${CONTAINER_NAME}" psql -U "\${DB_USER}" -d "\${DB_NAME}" -t -A -c "SELECT COUNT(*) FROM locations;" 2>/dev/null || echo "0")
[ "\${ROWS}" = "4" ] && echo "  OK locations count = 4" || { echo "  FAIL locations count = \${ROWS} (expected 4)"; ERRORS=\$((ERRORS+1)); }
DIST=\$(docker exec "\${CONTAINER_NAME}" psql -U "\${DB_USER}" -d "\${DB_NAME}" -t -A -c "SELECT ST_Distance((SELECT geog_global FROM locations WHERE name = 'San Francisco Ferry Building'), (SELECT geog_global FROM locations WHERE name = 'New York Times Square'));" 2>/dev/null || echo "0")
[ -n "\${DIST}" ] && awk "BEGIN {exit (\${DIST} > 0) ? 0 : 1}" 2>/dev/null && echo "  OK SF-NY distance (m) = \${DIST}" || { echo "  FAIL distance not positive: \${DIST}"; ERRORS=\$((ERRORS+1)); }
[ \${ERRORS} -eq 0 ] && echo "[TEST] All checks passed." || { echo "[TEST] \${ERRORS} check(s) failed."; exit 1; }
TESTEOF
chmod +x "${TEST_SCRIPT}"
log_success "Generated ${TEST_SCRIPT}"

# --- Docker Operations ---
log_info "Checking for existing Docker container '${CONTAINER_NAME}'..."
if docker ps -a --format '{{.Names}}' | grep -q "${CONTAINER_NAME}"; then
    log_warn "Container '${CONTAINER_NAME}' already exists. Attempting to stop and remove..."
    docker stop "${CONTAINER_NAME}" > /dev/null 2>&1
    docker rm "${CONTAINER_NAME}" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log_error "Failed to stop/remove existing container. Please remove it manually: docker rm -f ${CONTAINER_NAME}"
    fi
    log_success "Existing container removed."
fi

log_info "Starting PostGIS Docker container..."
docker run --name "${CONTAINER_NAME}" \
           -e POSTGRES_USER="${DB_USER}" \
           -e POSTGRES_PASSWORD="${DB_PASSWORD}" \
           -e POSTGRES_DB="${DB_NAME}" \
           -p "${DB_PORT}:${DB_PORT}" \
           --health-cmd="pg_isready -U ${DB_USER} -d ${DB_NAME}" \
           --health-interval=5s \
           --health-timeout=5s \
           --health-retries=5 \
           -d postgis/postgis:16-3.4

if [ $? -ne 0 ]; then
    log_error "Failed to start PostGIS Docker container."
fi
log_success "PostGIS container '${CONTAINER_NAME}' started on port ${DB_PORT}."

log_info "Waiting for database to become healthy..."
MAX_RETRIES=20
RETRY_COUNT=0
until docker inspect --format='{{.State.Health.Status}}' "${CONTAINER_NAME}" | grep -q "healthy"; do
    if [ ${RETRY_COUNT} -eq ${MAX_RETRIES} ]; then
        log_error "Database did not become healthy after multiple retries. Check container logs."
    fi
    echo -n "."
    sleep 3
    RETRY_COUNT=$((RETRY_COUNT+1))
done
echo ""
log_success "Database is healthy and ready!"

# --- Database Setup and Data Insertion ---
log_info "Applying database setup from ${SQL_SETUP_FILE}..."
docker exec -i "${CONTAINER_NAME}" psql -U "${DB_USER}" -d "${DB_NAME}" < "${SQL_SETUP_FILE}"
if [ $? -ne 0 ]; then
    log_error "Failed to apply database setup."
fi
log_success "Database schema and PostGIS extension configured."

log_info "Inserting sample data from ${SQL_DATA_FILE}..."
docker exec -i "${CONTAINER_NAME}" psql -U "${DB_USER}" -d "${DB_NAME}" < "${SQL_DATA_FILE}"
if [ $? -ne 0 ]; then
    log_error "Failed to insert sample data."
fi
log_success "Sample data inserted successfully."

# --- Demo and Verify Functionality ---
log_info "Running queries to demonstrate spatial data types and distances..."
echo -e "${YELLOW}=====================================================${NC}"
echo -e "${YELLOW}           Query Results & Verification              ${NC}"
echo -e "${YELLOW}=====================================================${NC}"

docker exec -i "${CONTAINER_NAME}" psql -U "${DB_USER}" -d "${DB_NAME}" -P pager=off -P footer=off -x < "${SQL_QUERY_FILE}"
if [ $? -ne 0 ]; then
    log_error "Failed to execute verification queries."
fi

echo -e "${YELLOW}=====================================================${NC}"
log_success "Demo and verification complete!"

# --- Run tests ---
log_info "Running tests..."
if [ -x "${TEST_SCRIPT}" ]; then
    "${TEST_SCRIPT}" || log_error "Tests failed."
else
    log_warn "Test script not found or not executable: ${TEST_SCRIPT}"
fi

# --- Start dashboard server ---
DASHBOARD_DIR="${SCRIPT_DIR}/dashboard"
DASHBOARD_PORT="${DASHBOARD_PORT:-3000}"
if [ -d "${DASHBOARD_DIR}" ] && [ -f "${DASHBOARD_DIR}/package.json" ]; then
    log_info "Setting up and starting dashboard server..."
    if [ ! -d "${DASHBOARD_DIR}/node_modules" ]; then
        (cd "${DASHBOARD_DIR}" && npm install --silent) || log_warn "Dashboard npm install failed; dashboard may not start."
    fi
    (cd "${DASHBOARD_DIR}" && DASHBOARD_PORT="${DASHBOARD_PORT}" PGHOST="${PGHOST:-localhost}" PGPORT="${DB_PORT}" PGUSER="${DB_USER}" PGPASSWORD="${DB_PASSWORD}" PGDATABASE="${DB_NAME}" nohup node server.js > dashboard.log 2>&1 &)
    sleep 1
    log_success "Dashboard server started at http://localhost:${DASHBOARD_PORT}"
else
    log_warn "Dashboard directory not found: ${DASHBOARD_DIR}; skipping dashboard."
fi

log_info "You can connect to the database using: psql -h localhost -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME}"
log_info "To stop the environment, run: ${STOP_SCRIPT}"
echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}  geospatial_day1: Spatial Data Types - COMPLETED!   ${NC}"
echo -e "${BLUE}=====================================================${NC}"