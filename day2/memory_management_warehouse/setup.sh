#!/bin/bash
# Memory Management Warehouse (PostgreSQL/PostGIS work_mem demo)
# Run from project directory: memory_management_warehouse/
set -e

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PG_VERSION="17-3.5" # PostGIS 3.5 on PostgreSQL 17 (17-alpine not available on Docker Hub)
CONTAINER_NAME="geospatial_pg17"
PG_DATA_DIR="${SCRIPT_DIR}/pgdata"
POSTGRES_USER="pguser"
POSTGRES_PASSWORD="pgpassword"
POSTGRES_DB="gis_warehouse"
DEFAULT_WORK_MEM="4MB" # Default for baseline
TUNED_WORK_MEM="256MB" # Example tuned value for demonstration
POSTGRES_CONFIG_FILE="postgresql.conf"
cd "${SCRIPT_DIR}" || exit 1

# --- Functions ---

# Function to check if Docker is installed
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Docker is not installed. Please install Docker to run this script."
        echo "Refer to the Docker documentation for installation: https://docs.docker.com/get-docker/"
        exit 1
    fi
}

# Function to stop and remove existing container
stop_existing_container() {
    if docker ps -a --filter "name=${CONTAINER_NAME}" --format "{{.Names}}" | grep -q "${CONTAINER_NAME}"; then
        echo "Stopping and removing existing Docker container: ${CONTAINER_NAME}..."
        docker stop ${CONTAINER_NAME} > /dev/null
        docker rm ${CONTAINER_NAME} > /dev/null
    fi
}

# Function to generate a simple postgresql.conf
generate_config() {
    local work_mem_val=$1
    echo "Generating ${POSTGRES_CONFIG_FILE} with work_mem=${work_mem_val}..."
    rm -f "${SCRIPT_DIR}/${POSTGRES_CONFIG_FILE}" 2>/dev/null || true
    cat <<EOF > "${SCRIPT_DIR}/${POSTGRES_CONFIG_FILE}"
# Custom PostgreSQL Configuration for Geospatial Data Warehouse
listen_addresses = '*'
port = 5432
max_connections = 100
shared_buffers = 128MB # Example: Adjust based on your system RAM (e.g., 25% of RAM)
work_mem = ${work_mem_val} # Crucial for complex spatial operations
maintenance_work_mem = 64MB # For VACUUM, CREATE INDEX (adjust for large index builds)
wal_buffers = 16MB
effective_cache_size = 512MB # Tell planner about OS cache (e.g., 50-75% of RAM)
log_min_duration_statement = 100 # Log queries slower than 100ms
EOF
}

# Function to run PostgreSQL with Docker
# Do not mount config into data dir (would make dir non-empty and break initdb). Use -c for work_mem.
run_with_docker() {
    local work_mem_val=$1
    echo "Starting PostgreSQL 17 with PostGIS in Docker with work_mem=${work_mem_val}..."
    docker run -d \
        --name ${CONTAINER_NAME} \
        -p 5432:5432 \
        -e POSTGRES_USER=${POSTGRES_USER} \
        -e POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
        -e POSTGRES_DB=${POSTGRES_DB} \
        -v ${PG_DATA_DIR}:/var/lib/postgresql/data \
        postgis/postgis:${PG_VERSION} \
        -c work_mem=${work_mem_val} > /dev/null

    echo "Waiting for PostgreSQL to start..."
    sleep 10 # Give PostgreSQL time to initialize
    docker exec ${CONTAINER_NAME} psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "CREATE EXTENSION IF NOT EXISTS postgis;" > /dev/null
    echo "PostGIS extension enabled."
}

# Function to load sample geospatial data (write SQL to file so docker exec -i runs it reliably)
load_sample_data() {
    echo "Loading sample geospatial data..."
    local init_sql="${SCRIPT_DIR}/init_data.sql"
    cat > "${init_sql}" <<'SQLEOF'
DROP TABLE IF EXISTS public.places;
DROP TABLE IF EXISTS public.regions;

CREATE TABLE public.places (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255),
    category VARCHAR(100),
    geom GEOMETRY(Point, 4326)
);

CREATE TABLE public.regions (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255),
    population BIGINT,
    geom GEOMETRY(Polygon, 4326)
);

INSERT INTO public.places (name, category, geom) VALUES
('New York', 'City', ST_SetSRID(ST_MakePoint(-74.0060, 40.7128), 4326)),
('Los Angeles', 'City', ST_SetSRID(ST_MakePoint(-118.2437, 34.0522), 4326)),
('Chicago', 'City', ST_SetSRID(ST_MakePoint(-87.6298, 41.8781), 4326)),
('Houston', 'City', ST_SetSRID(ST_MakePoint(-95.3698, 29.7604), 4326)),
('Phoenix', 'City', ST_SetSRID(ST_MakePoint(-112.0740, 33.4484), 4326)),
('Philadelphia', 'City', ST_SetSRID(ST_MakePoint(-75.1652, 39.9526), 4326)),
('San Antonio', 'City', ST_SetSRID(ST_MakePoint(-98.4936, 29.4241), 4326)),
('San Diego', 'City', ST_SetSRID(ST_MakePoint(-117.1611, 32.7157), 4326)),
('Dallas', 'City', ST_SetSRID(ST_MakePoint(-96.7970, 32.7767), 4326)),
('San Jose', 'City', ST_SetSRID(ST_MakePoint(-121.8863, 37.3382), 4326));

INSERT INTO public.regions (name, population, geom) VALUES
('East Coast', 100000000, ST_SetSRID(ST_GeomFromText('POLYGON ((-78 45, -70 45, -70 35, -78 35, -78 45))'), 4326)),
('West Coast', 50000000, ST_SetSRID(ST_GeomFromText('POLYGON ((-125 45, -115 45, -115 30, -125 30, -125 45))'), 4326)),
('Central', 75000000, ST_SetSRID(ST_GeomFromText('POLYGON ((-105 50, -85 50, -85 25, -105 25, -105 50))'), 4326));

CREATE INDEX idx_places_geom ON public.places USING GIST (geom);
CREATE INDEX idx_regions_geom ON public.regions USING GIST (geom);
ANALYZE public.places;
ANALYZE public.regions;
SQLEOF
    docker exec -i ${CONTAINER_NAME} psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} < "${init_sql}"
    echo "Sample data loaded and indexes created."
}

# Function to run demo queries
run_demo_queries() {
    local query_type=$1
    echo -e "\n--- Running Demo Query ($query_type work_mem) ---"
    echo "Query: Find places within a region, sort by distance, and aggregate a property."

    # Complex spatial query involving join, sort, and aggregation
    DEMO_QUERY="
    SELECT
        r.name AS region_name,
        COUNT(p.id) AS num_places_in_region,
        ST_AsText(ST_Centroid(ST_Union(p.geom))) AS aggregated_centroid
    FROM
        regions r
    JOIN
        places p ON ST_Contains(r.geom, p.geom)
    GROUP BY
        r.name
    ORDER BY
        num_places_in_region DESC;
    "

    # Use EXPLAIN ANALYZE for detailed performance metrics
    docker exec ${CONTAINER_NAME} psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "EXPLAIN (ANALYZE, BUFFERS, SETTINGS, VERBOSE) ${DEMO_QUERY}"
}

# --- Generate stop.sh ---
generate_stop_script() {
    local stop_script="${SCRIPT_DIR}/stop.sh"
    echo "Generating ${stop_script}..."
    cat <<STOPEOF > "${stop_script}"
#!/bin/bash
CONTAINER_NAME="${CONTAINER_NAME}"
echo "Stopping and removing container: \${CONTAINER_NAME}"
docker stop "\${CONTAINER_NAME}" 2>/dev/null && docker rm "\${CONTAINER_NAME}" 2>/dev/null && echo "Done." || echo "Container not running or already removed."
STOPEOF
    chmod +x "${stop_script}"
    echo "Generated ${stop_script}"
}

# --- Generate test.sh ---
generate_test_script() {
    local test_script="${SCRIPT_DIR}/test.sh"
    echo "Generating ${test_script}..."
    cat <<TESTEOF > "${test_script}"
#!/bin/bash
set -e
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
cd "\${SCRIPT_DIR}"
CONTAINER_NAME="${CONTAINER_NAME}"
POSTGRES_USER="${POSTGRES_USER}"
POSTGRES_DB="${POSTGRES_DB}"
ERRORS=0
echo "[TEST] Checking generated files..."
for f in postgresql.conf stop.sh; do
  [ -f "\$f" ] && echo "  OK \$f" || { echo "  MISSING \$f"; ERRORS=\$((ERRORS+1)); }
done
[ -d "pgdata" ] && echo "  OK pgdata/" || { echo "  MISSING pgdata/"; ERRORS=\$((ERRORS+1)); }
echo "[TEST] Checking container..."
docker ps --format '{{.Names}}' | grep -q "^\${CONTAINER_NAME}\$" && echo "  OK Container running" || { echo "  FAIL Container not running"; ERRORS=\$((ERRORS+1)); }
echo "[TEST] Checking data (places and regions)..."
PLACES=\$(docker exec "\${CONTAINER_NAME}" psql -U "\${POSTGRES_USER}" -d "\${POSTGRES_DB}" -t -A -c "SELECT COUNT(*) FROM places;" 2>/dev/null || echo "0")
REGIONS=\$(docker exec "\${CONTAINER_NAME}" psql -U "\${POSTGRES_USER}" -d "\${POSTGRES_DB}" -t -A -c "SELECT COUNT(*) FROM regions;" 2>/dev/null || echo "0")
[ "\${PLACES}" = "10" ] && echo "  OK places count = 10" || { echo "  FAIL places count = \${PLACES} (expected 10)"; ERRORS=\$((ERRORS+1)); }
[ "\${REGIONS}" = "3" ] && echo "  OK regions count = 3" || { echo "  FAIL regions count = \${REGIONS} (expected 3)"; ERRORS=\$((ERRORS+1)); }
[ \${ERRORS} -eq 0 ] && echo "[TEST] All checks passed." || { echo "[TEST] \${ERRORS} check(s) failed."; exit 1; }
TESTEOF
    chmod +x "${test_script}"
    echo "Generated ${test_script}"
}

# --- Main Script Logic ---
check_docker

echo "--- Building Geospatial Data Warehouse: Memory Management Lesson ---"

# Ensure data directory exists
mkdir -p ${PG_DATA_DIR}
generate_stop_script
generate_test_script

# --- Phase 1: Baseline with Default work_mem ---
stop_existing_container
# Remove root-owned pgdata and postgresql.conf from previous failed runs so we can re-init
sudo rm -rf "${PG_DATA_DIR}" 2>/dev/null || true
sudo rm -f "${SCRIPT_DIR}/${POSTGRES_CONFIG_FILE}" 2>/dev/null || true
generate_config ${DEFAULT_WORK_MEM}
run_with_docker ${DEFAULT_WORK_MEM}
load_sample_data
echo -e "\n--- Verification (Baseline with work_mem=${DEFAULT_WORK_MEM}) ---"
docker exec ${CONTAINER_NAME} psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "SHOW work_mem;"
run_demo_queries "Baseline"

echo -e "\nPausing for 10 seconds. Observe the output for 'temp_bytes' or 'Sort Method: external merge'."
sleep 10

# --- Phase 2: Tuned work_mem ---
echo -e "\n--- Tuning work_mem to ${TUNED_WORK_MEM} ---"
# We'll use ALTER SYSTEM SET for dynamic tuning within the running container
# In a real scenario, you might regenerate the config and restart the container,
# but ALTER SYSTEM SET shows the dynamic capability and avoids recreating data.
docker exec ${CONTAINER_NAME} psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "ALTER SYSTEM SET work_mem = '${TUNED_WORK_MEM}';"
docker exec ${CONTAINER_NAME} psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "SELECT pg_reload_conf();"

echo -e "\n--- Verification (Tuned with work_mem=${TUNED_WORK_MEM}) ---"
docker exec ${CONTAINER_NAME} psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "SHOW work_mem;"
run_demo_queries "Tuned"

echo -e "\n--- Demo Complete ---"
echo "Observe the difference in 'Execution Time' and the absence of 'temp_bytes' or 'external merge' in the tuned run."
echo "You can connect to the database using: psql -h localhost -p 5432 -U ${POSTGRES_USER} -d ${POSTGRES_DB}"

# --- Run tests (full path) ---
TEST_SCRIPT="${SCRIPT_DIR}/test.sh"
if [ -x "${TEST_SCRIPT}" ]; then
    echo -e "\n--- Running tests ---"
    "${TEST_SCRIPT}" || { echo "Tests failed."; exit 1; }
    echo "Tests passed."
else
    echo "Test script not found or not executable: ${TEST_SCRIPT}"
fi

# --- Start dashboard (full path; avoid duplicate) ---
DASHBOARD_DIR="${SCRIPT_DIR}/dashboard"
DASHBOARD_PORT="${DASHBOARD_PORT:-3001}"
if [ -d "${DASHBOARD_DIR}" ] && [ -f "${DASHBOARD_DIR}/package.json" ]; then
    if ! (lsof -i ":${DASHBOARD_PORT}" 2>/dev/null | grep -q LISTEN); then
        echo -e "\n--- Starting dashboard ---"
        if [ ! -d "${DASHBOARD_DIR}/node_modules" ]; then
            (cd "${DASHBOARD_DIR}" && npm install --silent) || echo "Dashboard npm install failed."
        fi
        (cd "${DASHBOARD_DIR}" && DASHBOARD_PORT="${DASHBOARD_PORT}" PGHOST="${PGHOST:-localhost}" PGPORT="5432" PGUSER="${POSTGRES_USER}" PGPASSWORD="${POSTGRES_PASSWORD}" PGDATABASE="${POSTGRES_DB}" nohup node server.js > dashboard.log 2>&1 &)
        sleep 2
        echo "Dashboard server started at http://localhost:${DASHBOARD_PORT}"
    else
        echo "Dashboard already running on port ${DASHBOARD_PORT}; skipping."
    fi
else
    echo "Dashboard directory not found: ${DASHBOARD_DIR}; skipping."
fi

echo "To stop the environment, run: ${SCRIPT_DIR}/stop.sh"