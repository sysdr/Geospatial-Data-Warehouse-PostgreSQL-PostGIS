#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
PG_CONTAINER_NAME="postgis_geodebate_db"
PG_PORT="5432"
PG_USER="admin"
PG_PASSWORD="password"
PG_DB="geospatial_warehouse"
POSTGIS_VERSION="16-3.4" # Using PostgreSQL 16 with PostGIS 3.4
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/Geom_vs_Geog_demo"
EXPECTED_LANDMARKS=3
DASHBOARD_PORT="${DASHBOARD_PORT:-3004}"

# --- Helper Functions ---
log() {
    echo -e "\n\033[1;34m>>> $1\033[0m"
}

error() {
    echo -e "\n\033[1;31m!!! ERROR: $1\033[0m" >&2
    exit 1
}

generate_stop_script() {
    local stop_script="${PROJECT_DIR}/stop.sh"
    log "Generating ${stop_script}..."
    cat <<STOPEOF > "${stop_script}"
#!/bin/bash
echo "Stopping PostGIS container..."
docker stop ${PG_CONTAINER_NAME} 2>/dev/null || true
docker rm ${PG_CONTAINER_NAME} 2>/dev/null || true
echo "Done."
STOPEOF
    chmod +x "${stop_script}"
    log "Generated stop.sh"
}

generate_test_script() {
    local test_script="${PROJECT_DIR}/test.sh"
    log "Generating ${test_script}..."
    cat <<TESTEOF > "${test_script}"
#!/bin/bash
set -e
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
cd "\${SCRIPT_DIR}"
CONTAINER_NAME="${PG_CONTAINER_NAME}"
DB_USER="${PG_USER}"
DB_NAME="${PG_DB}"
EXPECTED_COUNT="${EXPECTED_LANDMARKS}"
ERRORS=0
echo "[TEST] Checking generated files..."
for f in stop.sh dashboard/package.json dashboard/server.js dashboard/public/index.html; do
  [ -f "\$f" ] && echo "  OK \$f" || { echo "  MISSING \$f"; ERRORS=\$((ERRORS+1)); }
done
echo "[TEST] Checking container..."
docker ps --format '{{.Names}}' | grep -q "^\${CONTAINER_NAME}\$" && echo "  OK Container running" || { echo "  FAIL Container not running"; ERRORS=\$((ERRORS+1)); }
echo "[TEST] Checking data (landmarks count)..."
LANDMARKS_COUNT=\$(docker exec "\${CONTAINER_NAME}" psql -U "\${DB_USER}" -d "\${DB_NAME}" -t -A -c "SELECT COUNT(*) FROM public.landmarks;" 2>/dev/null || echo "0")
[ "\${LANDMARKS_COUNT}" = "\${EXPECTED_COUNT}" ] && echo "  OK landmarks count = \${EXPECTED_COUNT}" || { echo "  FAIL landmarks count = \${LANDMARKS_COUNT} (expected \${EXPECTED_COUNT})"; ERRORS=\$((ERRORS+1)); }
[ \${ERRORS} -eq 0 ] && echo "[TEST] All checks passed." || { echo "[TEST] \${ERRORS} check(s) failed."; exit 1; }
TESTEOF
    chmod +x "${test_script}"
    log "Generated test.sh"
}

generate_dashboard() {
    mkdir -p "${PROJECT_DIR}/dashboard/public"
    log "Generating dashboard in ${PROJECT_DIR}/dashboard..."
    cat > "${PROJECT_DIR}/dashboard/package.json" <<'PKGEOF'
{
  "name": "geospatial-day4-dashboard",
  "version": "1.0.0",
  "description": "Dashboard for Geospatial Data Warehouse Day4 - GEOMETRY vs GEOGRAPHY",
  "main": "server.js",
  "scripts": { "start": "node server.js", "dev": "node server.js" },
  "dependencies": { "cors": "^2.8.5", "express": "^4.18.2", "pg": "^8.11.3" }
}
PKGEOF
    cat > "${PROJECT_DIR}/dashboard/server.js" <<'SRVEOF'
const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const path = require('path');

const app = express();
const PORT = process.env.DASHBOARD_PORT || 3004;

const poolConfig = {
  host: process.env.PGHOST || 'localhost',
  port: parseInt(process.env.PGPORT || '5432', 10),
  user: process.env.PGUSER || 'admin',
  password: process.env.PGPASSWORD || 'password',
  database: process.env.PGDATABASE || 'geospatial_warehouse',
};
const pool = new Pool(poolConfig);

let lastDemoResult = {
  localDistGeometry: 0,
  localDistGeography: 0,
  globalDistGeometry: 0,
  globalDistGeography: 0,
  executionTimeMs: 0,
};

app.use(cors());
app.use(express.json());

app.get('/api/health', (req, res) => {
  res.json({ ok: true, message: 'Day4 dashboard API', endpoints: ['GET /api/stats', 'POST /api/run-demo'] });
});

app.get('/api/stats', async (req, res) => {
  res.set('Cache-Control', 'no-store, no-cache, must-revalidate');
  try {
    const countResult = await pool.query('SELECT COUNT(*) AS cnt FROM public.landmarks');
    const landmarksCount = parseInt(countResult.rows[0]?.cnt || 0, 10);
    res.json({
      landmarksCount,
      localDistGeometry: lastDemoResult.localDistGeometry,
      localDistGeography: lastDemoResult.localDistGeography,
      globalDistGeometry: lastDemoResult.globalDistGeometry,
      globalDistGeography: lastDemoResult.globalDistGeography,
      lastDemoExecutionMs: lastDemoResult.executionTimeMs,
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/api/run-demo', async (req, res) => {
  res.set('Cache-Control', 'no-store, no-cache, must-revalidate');
  const start = Date.now();
  try {
    const localQuery = `
      SELECT ST_Distance(t1.geom_3857, t2.geom_3857) AS d_geom,
             ST_Distance(t1.geog_4326, t2.geog_4326) AS d_geog
      FROM landmarks t1, landmarks t2
      WHERE t1.name = 'Eiffel Tower' AND t2.name = 'Arc de Triomphe'
    `;
    const globalQuery = `
      SELECT ST_Distance(t1.geom_3857, t2.geom_3857) AS d_geom,
             ST_Distance(t1.geog_4326, t2.geog_4326) AS d_geog
      FROM landmarks t1, landmarks t2
      WHERE t1.name = 'Eiffel Tower' AND t2.name = 'Statue of Liberty'
    `;
    const local = await pool.query(localQuery);
    const global = await pool.query(globalQuery);
    const countResult = await pool.query('SELECT COUNT(*) AS cnt FROM public.landmarks');
    const landmarksCount = parseInt(countResult.rows[0]?.cnt || 0, 10);
    const executionTimeMs = Date.now() - start;
    lastDemoResult = {
      landmarksCount,
      localDistGeometry: parseFloat(local.rows[0]?.d_geom) || 0,
      localDistGeography: parseFloat(local.rows[0]?.d_geog) || 0,
      globalDistGeometry: parseFloat(global.rows[0]?.d_geom) || 0,
      globalDistGeography: parseFloat(global.rows[0]?.d_geog) || 0,
      executionTimeMs,
    };
    res.json(lastDemoResult);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/', (req, res) => {
  res.set('Cache-Control', 'no-store, no-cache, must-revalidate, private');
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});
app.use(express.static(path.join(__dirname, 'public')));

app.listen(PORT, '0.0.0.0', () => {
  console.log('Dashboard server running at http://localhost:' + PORT);
});
SRVEOF
    cat > "${PROJECT_DIR}/dashboard/public/index.html" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Geospatial Day 4 — GEOMETRY vs GEOGRAPHY Dashboard</title>
  <style>
    :root { --bg: #fafaf9; --card: #fff; --border: #e7e5e4; --text: #1c1917; --text-muted: #57534e; --primary: #2563eb; --success: #15803d; --shadow: 0 1px 3px rgba(0,0,0,.08); --radius: 10px; }
    * { box-sizing: border-box; }
    body { margin: 0; font-family: system-ui, sans-serif; background: var(--bg); color: var(--text); line-height: 1.5; min-height: 100vh; }
    .container { max-width: 960px; margin: 0 auto; padding: 1.5rem; }
    header { background: linear-gradient(135deg, #1d4ed8 0%, #2563eb 100%); color: #fff; padding: 1.25rem; border-radius: var(--radius); margin-bottom: 1.5rem; }
    header h1 { margin: 0 0 0.25rem 0; font-size: 1.5rem; }
    header p { margin: 0; opacity: .95; font-size: 0.9rem; }
    .goal { background: var(--card); border: 1px solid var(--border); border-radius: var(--radius); padding: 1rem; margin-bottom: 1.5rem; color: var(--text-muted); font-size: 0.95rem; }
    .metrics { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 1rem; margin-bottom: 1.5rem; }
    .metric { background: var(--card); border: 1px solid var(--border); border-radius: var(--radius); padding: 1.25rem; box-shadow: var(--shadow); }
    .metric .label { font-size: 0.75rem; color: var(--text-muted); text-transform: uppercase; letter-spacing: .05em; margin-bottom: 0.35rem; }
    .metric .value { font-size: 1.35rem; font-weight: 700; color: var(--text); }
    .metric.primary .value { color: var(--primary); }
    .metric.success .value { color: var(--success); }
    .btn { padding: 0.6rem 1rem; border-radius: 8px; border: none; font-size: 0.9rem; font-weight: 500; cursor: pointer; background: var(--primary); color: #fff; }
    .btn:disabled { opacity: .6; cursor: not-allowed; }
    .card { background: var(--card); border: 1px solid var(--border); border-radius: var(--radius); padding: 1.25rem; margin-bottom: 1.5rem; }
    .toast { position: fixed; bottom: 1.5rem; right: 1.5rem; padding: 0.75rem 1.25rem; background: var(--text); color: #fff; border-radius: 8px; font-size: 0.9rem; z-index: 1000; opacity: 0; transition: opacity .2s; }
    .toast.show { opacity: 1; }
    .live-badge { font-size: 0.75rem; color: var(--primary); margin-bottom: 0.5rem; }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <h1>Geospatial Day 4 — GEOMETRY vs GEOGRAPHY</h1>
      <p>Landmarks count and distance demo (local + global). Run demo to update all metrics.</p>
    </header>
    <section class="goal">
      <strong>Metrics:</strong> Landmarks, Local distance (GEOM/GEOG), Global distance (GEOM/GEOG), Last demo ms. Auto-refresh every 2s. Use "Run demo" so values are non-zero.
    </section>
    <div class="live-badge">Last updated: <span id="last-updated">—</span></div>
    <div class="metrics">
      <div class="metric success"><div class="label">Landmarks</div><div class="value" id="metric-landmarks">—</div></div>
      <div class="metric"><div class="label">Local dist (GEOM 3857)</div><div class="value" id="metric-local-geom">—</div><div class="unit">m</div></div>
      <div class="metric"><div class="label">Local dist (GEOG 4326)</div><div class="value" id="metric-local-geog">—</div><div class="unit">m</div></div>
      <div class="metric"><div class="label">Global dist (GEOM 3857)</div><div class="value" id="metric-global-geom">—</div><div class="unit">m</div></div>
      <div class="metric"><div class="label">Global dist (GEOG 4326)</div><div class="value" id="metric-global-geog">—</div><div class="unit">m</div></div>
      <div class="metric primary"><div class="label">Last demo</div><div class="value" id="metric-execms">—</div><div class="unit">ms</div></div>
    </div>
    <div class="card">
      <h2 style="margin-top:0;">Actions</h2>
      <button class="btn" id="btn-refresh">Refresh metrics</button>
      <button class="btn" id="btn-run-demo">Run demo (distances)</button>
    </div>
  </div>
  <div class="toast" id="toast"></div>
  <script>
    function showToast(msg) { const el = document.getElementById('toast'); el.textContent = msg; el.classList.add('show'); setTimeout(function() { el.classList.remove('show'); }, 2500); }
    async function fetchJSON(path, opts) { var o = Object.assign({ cache: 'no-store' }, opts || {}); var r = await fetch(path, o); if (!r.ok) throw new Error(await r.text()); return r.json(); }
    function formatNum(n) { return (n != null && !isNaN(n)) ? Number(n).toLocaleString('en-US', { maximumFractionDigits: 2, minimumFractionDigits: 0 }) : '—'; }
    function setLastUpdated() { var el = document.getElementById('last-updated'); if (el) el.textContent = new Date().toLocaleTimeString(); }
    async function loadStats() {
      try {
        var s = await fetchJSON('/api/stats');
        document.getElementById('metric-landmarks').textContent = formatNum(s.landmarksCount);
        var d = (s.lastDemoExecutionMs > 0) ? s : lastDemoData;
        if (d) {
          document.getElementById('metric-local-geom').textContent = (d.localDistGeometry > 0) ? formatNum(d.localDistGeometry) : '—';
          document.getElementById('metric-local-geog').textContent = (d.localDistGeography > 0) ? formatNum(d.localDistGeography) : '—';
          document.getElementById('metric-global-geom').textContent = (d.globalDistGeometry > 0) ? formatNum(d.globalDistGeometry) : '—';
          document.getElementById('metric-global-geog').textContent = (d.globalDistGeography > 0) ? formatNum(d.globalDistGeography) : '—';
          document.getElementById('metric-execms').textContent = (d.lastDemoExecutionMs || d.executionTimeMs || 0) > 0 ? (d.lastDemoExecutionMs || d.executionTimeMs).toFixed(2) : '—';
        }
        setLastUpdated();
        return s;
      } catch (e) { console.error('loadStats', e); return null; }
    }
    var LIVE_MS = 2000, liveId = null, lastDemoData = null;
    function startLive() { if (!liveId) { liveId = setInterval(loadStats, LIVE_MS); } }
    function updateMetricsFromDemo(r) {
      document.getElementById('metric-landmarks').textContent = (r.landmarksCount != null) ? formatNum(r.landmarksCount) : '3';
      document.getElementById('metric-local-geom').textContent = (r.localDistGeometry > 0) ? formatNum(r.localDistGeometry) : '—';
      document.getElementById('metric-local-geog').textContent = (r.localDistGeography > 0) ? formatNum(r.localDistGeography) : '—';
      document.getElementById('metric-global-geom').textContent = (r.globalDistGeometry > 0) ? formatNum(r.globalDistGeometry) : '—';
      document.getElementById('metric-global-geog').textContent = (r.globalDistGeography > 0) ? formatNum(r.globalDistGeography) : '—';
      document.getElementById('metric-execms').textContent = (r.executionTimeMs > 0) ? r.executionTimeMs.toFixed(2) : '—';
      setLastUpdated();
    }
    document.getElementById('btn-refresh').addEventListener('click', function() { loadStats().then(function() { showToast('Metrics updated.'); }).catch(function(e) { showToast('Error: ' + e.message); }); });
    document.getElementById('btn-run-demo').addEventListener('click', function() {
      var btn = document.getElementById('btn-run-demo');
      btn.disabled = true;
      if (liveId) { clearInterval(liveId); liveId = null; }
      fetchJSON('/api/run-demo', { method: 'POST', headers: { 'Content-Type': 'application/json' } }).then(function(r) {
        lastDemoData = r;
        updateMetricsFromDemo(r);
        showToast('Demo ran in ' + r.executionTimeMs + ' ms.');
      }).catch(function(e) { showToast('Error: ' + e.message); }).finally(function() {
        btn.disabled = false;
        setTimeout(function() { startLive(); }, 500);
      });
    });
    loadStats().then(function() { startLive(); }).catch(function() { startLive(); });
  </script>
</body>
</html>
HTMLEOF
    log "Generated dashboard (package.json, server.js, public/index.html)"
}

# --- 1. Check for Docker ---
log "1. Checking for Docker installation..."
if ! command -v docker &> /dev/null; then
    error "Docker is not installed. Please install Docker to proceed.
    Instructions: https://docs.docker.com/get-docker/"
fi
log "Docker is installed."

# --- 2. Stop and remove any existing container ---
log "2. Stopping and removing any existing PostGIS container..."
if docker ps -a --format '{{.Names}}' | grep -q "^${PG_CONTAINER_NAME}$"; then
    docker stop "${PG_CONTAINER_NAME}" > /dev/null
    docker rm "${PG_CONTAINER_NAME}" > /dev/null
    log "Previous container '${PG_CONTAINER_NAME}' stopped and removed."
else
    log "No existing container '${PG_CONTAINER_NAME}' found."
fi

# --- 3. Start PostGIS Docker Container ---
log "3. Starting PostGIS Docker container..."
docker run --name "${PG_CONTAINER_NAME}" \
    -e POSTGRES_USER="${PG_USER}" \
    -e POSTGRES_PASSWORD="${PG_PASSWORD}" \
    -e POSTGRES_DB="${PG_DB}" \
    -p "${PG_PORT}:5432" \
    -d postgis/postgis:"${POSTGIS_VERSION}" > /dev/null

log "Waiting for PostGIS container to become ready..."
until docker exec "${PG_CONTAINER_NAME}" pg_isready -U "${PG_USER}" -d "${PG_DB}" &> /dev/null; do
    echo -n "."
    sleep 1
done
echo ""
log "PostGIS container is ready and running on port ${PG_PORT}."

# --- 4. Create PostGIS Extension ---
log "4. Enabling PostGIS extension in database '${PG_DB}'..."
docker exec "${PG_CONTAINER_NAME}" psql -U "${PG_USER}" -d "${PG_DB}" -c "CREATE EXTENSION IF NOT EXISTS postgis;" > /dev/null
log "PostGIS extension enabled."

# --- 5. Create Table and Insert Data ---
log "5. Creating 'landmarks' table and inserting data..."

# SQL commands for table creation and data insertion
SQL_SCRIPT=$(cat <<EOF
CREATE TABLE IF NOT EXISTS landmarks (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    geom_3857 GEOMETRY(Point, 3857), -- Planar, Web Mercator
    geog_4326 GEOGRAPHY(Point, 4326)  -- Spherical, WGS84
);

TRUNCATE TABLE landmarks; -- Clear data if table exists from previous run

INSERT INTO landmarks (name, geom_3857, geog_4326) VALUES
('Eiffel Tower', ST_Transform(ST_SetSRID(ST_MakePoint(2.2945, 48.8584), 4326), 3857), ST_SetSRID(ST_MakePoint(2.2945, 48.8584), 4326)::geography),
('Arc de Triomphe', ST_Transform(ST_SetSRID(ST_MakePoint(2.2950, 48.8738), 4326), 3857), ST_SetSRID(ST_MakePoint(2.2950, 48.8738), 4326)::geography),
('Statue of Liberty', ST_Transform(ST_SetSRID(ST_MakePoint(-74.0445, 40.6892), 4326), 3857), ST_SetSRID(ST_MakePoint(-74.0445, 40.6892), 4326)::geography);
EOF
)

docker exec "${PG_CONTAINER_NAME}" psql -U "${PG_USER}" -d "${PG_DB}" -c "${SQL_SCRIPT}" > /dev/null
log "Table 'landmarks' created and data inserted."

# --- 6. Run Demo Queries and Display Results ---
log "6. Running demo queries to compare GEOMETRY vs. GEOGRAPHY distances..."

# Fetch landmark IDs for queries
EIFFEL_ID=$(docker exec "${PG_CONTAINER_NAME}" psql -U "${PG_USER}" -d "${PG_DB}" -t -c "SELECT id FROM landmarks WHERE name = 'Eiffel Tower';" | xargs)
ARC_ID=$(docker exec "${PG_CONTAINER_NAME}" psql -U "${PG_USER}" -d "${PG_DB}" -t -c "SELECT id FROM landmarks WHERE name = 'Arc de Triomphe';" | xargs)
STATUE_ID=$(docker exec "${PG_CONTAINER_NAME}" psql -U "${PG_USER}" -d "${PG_DB}" -t -c "SELECT id FROM landmarks WHERE name = 'Statue of Liberty';" | xargs)

# Query 1: Local Distance (Eiffel Tower to Arc de Triomphe)
log "--- Local Distance: Eiffel Tower to Arc de Triomphe ---"
docker exec "${PG_CONTAINER_NAME}" psql -U "${PG_USER}" -d "${PG_DB}" -c "
SELECT
    'GEOMETRY (SRID 3857)' AS type,
    ST_Distance(t1.geom_3857, t2.geom_3857) AS distance_meters
FROM landmarks t1, landmarks t2
WHERE t1.id = ${EIFFEL_ID} AND t2.id = ${ARC_ID}
UNION ALL
SELECT
    'GEOGRAPHY (SRID 4326)' AS type,
    ST_Distance(t1.geog_4326, t2.geog_4326) AS distance_meters
FROM landmarks t1, landmarks t2
WHERE t1.id = ${EIFFEL_ID} AND t2.id = ${ARC_ID};
"

# Query 2: Global Distance (Eiffel Tower to Statue of Liberty)
log "--- Global Distance: Eiffel Tower to Statue of Liberty ---"
docker exec "${PG_CONTAINER_NAME}" psql -U "${PG_USER}" -d "${PG_DB}" -c "
SELECT
    'GEOMETRY (SRID 3857)' AS type,
    ST_Distance(t1.geom_3857, t2.geom_3857) AS distance_meters
FROM landmarks t1, landmarks t2
WHERE t1.id = ${EIFFEL_ID} AND t2.id = ${STATUE_ID}
UNION ALL
SELECT
    'GEOGRAPHY (SRID 4326)' AS type,
    ST_Distance(t1.geog_4326, t2.geog_4326) AS distance_meters
FROM landmarks t1, landmarks t2
WHERE t1.id = ${EIFFEL_ID} AND t2.id = ${STATUE_ID};
"

log "Demo complete. Observe the differences in distances, especially for global queries."

# --- 7. Verification ---
log "7. Verifying data integrity (showing first 2 records):"
docker exec "${PG_CONTAINER_NAME}" psql -U "${PG_USER}" -d "${PG_DB}" -c "SELECT id, name, ST_AsText(geom_3857) AS geom_wkt_3857, ST_AsText(geog_4326) AS geog_wkt_4326 FROM landmarks LIMIT 2;"

# --- 8. Generate stop.sh, test.sh, dashboard ---
log "8. Generating stop.sh, test.sh, and dashboard..."
generate_stop_script
generate_test_script
generate_dashboard

# --- 9. Run tests (full path) ---
log "9. Running tests..."
TEST_SCRIPT="${PROJECT_DIR}/test.sh"
if [ -x "${TEST_SCRIPT}" ]; then
    "${TEST_SCRIPT}" || error "Tests failed."
    log "All tests passed."
else
    error "Test script not found or not executable: ${TEST_SCRIPT}"
fi

# --- 10. Start dashboard (full path; avoid duplicate) ---
log "10. Starting dashboard..."
DASHBOARD_DIR="${PROJECT_DIR}/dashboard"
if [ -d "${DASHBOARD_DIR}" ] && [ -f "${DASHBOARD_DIR}/package.json" ]; then
    if command -v lsof &>/dev/null && lsof -i ":${DASHBOARD_PORT}" 2>/dev/null | grep -q LISTEN; then
        log "Dashboard already running on port ${DASHBOARD_PORT}; skipping start."
    else
        if [ ! -d "${DASHBOARD_DIR}/node_modules" ]; then
            (cd "${DASHBOARD_DIR}" && npm install --silent) || error "Dashboard npm install failed."
        fi
        (cd "${DASHBOARD_DIR}" && DASHBOARD_PORT="${DASHBOARD_PORT}" PGHOST="${PGHOST:-localhost}" PGPORT="${PG_PORT}" PGUSER="${PG_USER}" PGPASSWORD="${PG_PASSWORD}" PGDATABASE="${PG_DB}" nohup node server.js > dashboard.log 2>&1 &)
        sleep 2
        log "Dashboard started at http://localhost:${DASHBOARD_PORT}"
    fi
else
    error "Dashboard not found at ${DASHBOARD_DIR}"
fi

# --- 11. Run demo once so dashboard metrics are non-zero ---
log "11. Running demo once to populate dashboard metrics..."
if command -v curl &>/dev/null; then
    curl -s -X POST "http://localhost:${DASHBOARD_PORT}/api/run-demo" >/dev/null && log "Demo executed; dashboard metrics updated." || log "Demo request failed (dashboard may still be starting)."
else
    log "curl not found; open dashboard and click 'Run demo' to update metrics."
fi

log "Access your PostGIS database: psql -h localhost -p ${PG_PORT} -U ${PG_USER} -d ${PG_DB}"
log "To stop and clean up: ${PROJECT_DIR}/stop.sh"
log "Setup and demo finished successfully!"