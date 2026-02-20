#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}"
DASHBOARD_PORT="${DASHBOARD_PORT:-3006}"
EXPECTED_REGIONS=3
EXPECTED_SENSORS=100000

log_info() { echo -e "\033[32m[INFO]\033[0m $1"; }
log_warn() { echo -e "\033[33m[WARN]\033[0m $1"; }
log_error() { echo -e "\033[31m[ERROR]\033[0m $1"; exit 1; }

echo "Starting Geospatial Data Warehouse setup..."

# --- 1. Check for Docker ---
if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Please install Docker to proceed."
    echo "Refer to https://docs.docker.com/get-docker/"
    exit 1
fi

echo "Docker found. Proceeding..."

# --- 2. Define Variables ---
DB_CONTAINER_NAME="pg_geospatial_day6"
DB_USER="postgres"
DB_PASSWORD="mysecretpassword"
DB_NAME="geospatial_dw"
DB_PORT="5432"

# --- 3. Stop and remove any existing container ---
echo "Stopping and removing any old container named $DB_CONTAINER_NAME..."
docker stop $DB_CONTAINER_NAME > /dev/null 2>&1 || true
docker rm $DB_CONTAINER_NAME > /dev/null 2>&1 || true
echo "Old container removed (if existed)."

# --- 4. Start PostgreSQL with PostGIS in Docker ---
echo "Starting PostgreSQL with PostGIS container ($DB_CONTAINER_NAME)..."
docker run --name $DB_CONTAINER_NAME \
  -e POSTGRES_USER=$DB_USER \
  -e POSTGRES_PASSWORD=$DB_PASSWORD \
  -p $DB_PORT:$DB_PORT \
  -d postgis/postgis:latest

echo "Waiting for PostgreSQL to start..."
# Wait for the database to be ready
until docker exec $DB_CONTAINER_NAME pg_isready -U $DB_USER > /dev/null 2>&1; do
  echo -n "."
  sleep 1
done
sleep 3
echo "PostgreSQL is up and running!"

# --- 5. Create Database and Enable PostGIS Extension ---
echo "Creating database '$DB_NAME' and enabling PostGIS extension..."
docker exec -u postgres $DB_CONTAINER_NAME psql -c "CREATE DATABASE $DB_NAME;" 2>/dev/null || true
docker exec -u postgres $DB_CONTAINER_NAME psql -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS postgis;" > /dev/null
sleep 2
echo "Database '$DB_NAME' created with PostGIS enabled."

# --- 6. Create Tables ---
echo "Creating 'regions' and 'sensors' tables..."
docker exec -u postgres $DB_CONTAINER_NAME psql -d $DB_NAME -c "
CREATE TABLE regions (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    geom GEOMETRY(Polygon, 4326)
);

CREATE TABLE sensors (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL,
    geom GEOMETRY(Point, 4326)
);
" > /dev/null
echo "Tables created."

# --- 7. Populate Data ---
echo "Populating 'regions' and 'sensors' tables with synthetic data..."

# Insert regions
docker exec -u postgres $DB_CONTAINER_NAME psql -d $DB_NAME -c "
INSERT INTO regions (name, geom) VALUES
('Region_A', ST_SetSRID(ST_MakePolygon(ST_GeomFromText('LINESTRING(-74.0 40.7, -73.9 40.7, -73.9 40.8, -74.0 40.8, -74.0 40.7)')), 4326)),
('Region_B', ST_SetSRID(ST_MakePolygon(ST_GeomFromText('LINESTRING(-74.1 40.6, -74.0 40.6, -74.0 40.7, -74.1 40.7, -74.1 40.6)')), 4326)),
('Region_C', ST_SetSRID(ST_MakePolygon(ST_GeomFromText('LINESTRING(-73.8 40.9, -73.7 40.9, -73.7 41.0, -73.8 41.0, -73.8 40.9)')), 4326));
" > /dev/null

# Insert sensors (100,000 points)
# Points will be mostly around the NYC area for realism
docker exec -u postgres $DB_CONTAINER_NAME psql -d $DB_NAME -c "
INSERT INTO sensors (name, status, geom)
SELECT
    'Sensor_' || generate_series(1, 100000)::text,
    CASE WHEN random() < 0.8 THEN 'active' ELSE 'inactive' END,
    ST_SetSRID(
        ST_MakePoint(
            -74.05 + (random() * 0.2),  -- Longitude range around NYC
            40.65 + (random() * 0.2)   -- Latitude range around NYC
        ),
        4326
    );
" > /dev/null
echo "Data populated for 3 regions and 100,000 sensors."

# --- 8. Create Indexes ---
echo "Creating spatial and status indexes..."
docker exec -u postgres $DB_CONTAINER_NAME psql -d $DB_NAME -c "
CREATE INDEX idx_regions_geom ON regions USING GIST (geom);
CREATE INDEX idx_sensors_geom ON sensors USING GIST (geom);
CREATE INDEX idx_sensors_status ON sensors (status);
" > /dev/null
echo "Indexes created."

# --- 9. Analyze tables for statistics ---
echo "Running ANALYZE to update table statistics for the planner..."
docker exec -u postgres $DB_CONTAINER_NAME psql -d $DB_NAME -c "ANALYZE regions; ANALYZE sensors;" > /dev/null
echo "Table statistics updated."

# --- 10. Run Demo Queries and Display EXPLAIN ANALYZE Output ---
echo ""
echo "--- DEMO: Query Plan for Non-MATERIALIZED CTE ---"
echo "Query: Count active sensors in Region_B using a non-materialized CTE."
echo "Running EXPLAIN (ANALYZE, VERBOSE, BUFFERS)..."
docker exec -u postgres $DB_CONTAINER_NAME psql -d $DB_NAME -c "
EXPLAIN (ANALYZE, VERBOSE, BUFFERS)
WITH target_region AS (
    SELECT id, name, geom FROM regions WHERE name = 'Region_B'
),
active_sensors_in_region AS (
    SELECT s.id, s.name, s.geom
    FROM sensors s, target_region tr
    WHERE ST_Intersects(s.geom, tr.geom)
      AND s.status = 'active'
)
SELECT COUNT(id) FROM active_sensors_in_region;
"

echo ""
echo "--- DEMO: Query Plan for MATERIALIZED CTE ---"
echo "Query: Count active sensors in Region_B using an explicitly MATERIALIZED CTE."
echo "Running EXPLAIN (ANALYZE, VERBOSE, BUFFERS)..."
docker exec -u postgres $DB_CONTAINER_NAME psql -d $DB_NAME -c "
EXPLAIN (ANALYZE, VERBOSE, BUFFERS)
WITH target_region AS (
    SELECT id, name, geom FROM regions WHERE name = 'Region_B'
),
active_sensors_in_region AS MATERIALIZED (
    SELECT s.id, s.name, s.geom
    FROM sensors s, target_region tr
    WHERE ST_Intersects(s.geom, tr.geom)
      AND s.status = 'active'
)
SELECT COUNT(id) FROM active_sensors_in_region;
"

# --- 10. Generate stop.sh, test.sh, start.sh, and dashboard ---
log_info "Generating stop.sh, test.sh, start.sh, and dashboard..."

generate_stop_script() {
  cat > "${PROJECT_DIR}/stop.sh" << 'STOPEOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="pg_geospatial_day6"
docker stop $CONTAINER_NAME 2>/dev/null || true
docker rm $CONTAINER_NAME 2>/dev/null || true
echo "Container stopped and removed. Done."
STOPEOF
  chmod +x "${PROJECT_DIR}/stop.sh"
  log_info "Generated stop.sh"
}

generate_test_script() {
  cat > "${PROJECT_DIR}/test.sh" << TESTEOF
#!/bin/bash
set -e
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
cd "\${SCRIPT_DIR}"
CONTAINER_NAME="${DB_CONTAINER_NAME}"
DB_USER="${DB_USER}"
DB_NAME="${DB_NAME}"
EXPECTED_REGIONS="${EXPECTED_REGIONS}"
EXPECTED_SENSORS="${EXPECTED_SENSORS}"
ERRORS=0
echo "[TEST] Checking generated files..."
for f in stop.sh start.sh dashboard/package.json dashboard/server.js dashboard/public/index.html; do
  [ -f "\$f" ] && echo "  OK \$f" || { echo "  MISSING \$f"; ERRORS=\$((ERRORS+1)); }
done
echo "[TEST] Checking container..."
docker ps --format '{{.Names}}' | grep -q "^\${CONTAINER_NAME}\$" && echo "  OK Container running" || { echo "  FAIL Container not running"; ERRORS=\$((ERRORS+1)); }
echo "[TEST] Checking data (regions and sensors count)..."
RCNT=\$(docker exec "\${CONTAINER_NAME}" psql -U "\${DB_USER}" -d "\${DB_NAME}" -t -A -c "SELECT COUNT(*) FROM public.regions;" 2>/dev/null || echo "0")
SCNT=\$(docker exec "\${CONTAINER_NAME}" psql -U "\${DB_USER}" -d "\${DB_NAME}" -t -A -c "SELECT COUNT(*) FROM public.sensors;" 2>/dev/null || echo "0")
[ "\${RCNT}" = "\${EXPECTED_REGIONS}" ] && echo "  OK regions count = \${EXPECTED_REGIONS}" || { echo "  FAIL regions = \${RCNT} (expected \${EXPECTED_REGIONS})"; ERRORS=\$((ERRORS+1)); }
[ "\${SCNT}" = "\${EXPECTED_SENSORS}" ] && echo "  OK sensors count = \${EXPECTED_SENSORS}" || { echo "  FAIL sensors = \${SCNT} (expected \${EXPECTED_SENSORS})"; ERRORS=\$((ERRORS+1)); }
[ \${ERRORS} -eq 0 ] && echo "[TEST] All checks passed." || { echo "[TEST] \${ERRORS} check(s) failed."; exit 1; }
TESTEOF
  chmod +x "${PROJECT_DIR}/test.sh"
  log_info "Generated test.sh"
}

generate_start_script() {
  cat > "${PROJECT_DIR}/start.sh" << STARTEOF
#!/bin/bash
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_DIR="\${SCRIPT_DIR}/dashboard"
DASHBOARD_PORT="\${DASHBOARD_PORT:-3006}"
# Avoid duplicate: kill existing process on port
if command -v lsof &>/dev/null; then
  PID=\$(lsof -ti ":\${DASHBOARD_PORT}" 2>/dev/null || true)
  [ -n "\$PID" ] && kill "\$PID" 2>/dev/null || true
fi
if [ ! -d "\${DASHBOARD_DIR}" ] || [ ! -f "\${DASHBOARD_DIR}/server.js" ]; then
  echo "Dashboard not found. Run setup.sh first."
  exit 1
fi
cd "\${DASHBOARD_DIR}"
export PGHOST="\${PGHOST:-localhost}"
export PGPORT="\${PGPORT:-5432}"
export PGUSER="postgres"
export PGPASSWORD="mysecretpassword"
export PGDATABASE="geospatial_dw"
export DASHBOARD_PORT="\${DASHBOARD_PORT}"
echo "Starting dashboard at http://localhost:\${DASHBOARD_PORT}"
exec node server.js
STARTEOF
  chmod +x "${PROJECT_DIR}/start.sh"
  log_info "Generated start.sh"
}

generate_dashboard() {
  mkdir -p "${PROJECT_DIR}/dashboard/public"
  log_info "Generating dashboard in ${PROJECT_DIR}/dashboard..."
  cat > "${PROJECT_DIR}/dashboard/package.json" << 'PKGEOF'
{
  "name": "geospatial-day6-dashboard",
  "version": "1.0.0",
  "description": "Dashboard for Geospatial Data Warehouse Day6 - CTE Materialized Demo",
  "main": "server.js",
  "scripts": { "start": "node server.js", "dev": "node server.js" },
  "dependencies": { "cors": "^2.8.5", "express": "^4.18.2", "pg": "^8.11.3" }
}
PKGEOF
  cat > "${PROJECT_DIR}/dashboard/server.js" << 'SRVEOF'
const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const path = require('path');

const app = express();
const PORT = process.env.DASHBOARD_PORT || 3006;

const poolConfig = {
  host: process.env.PGHOST || 'localhost',
  port: parseInt(process.env.PGPORT || '5432', 10),
  user: process.env.PGUSER || 'postgres',
  password: process.env.PGPASSWORD || 'mysecretpassword',
  database: process.env.PGDATABASE || 'geospatial_dw',
};
const pool = new Pool(poolConfig);

let lastDemoResult = {
  regionsCount: 0,
  sensorsCount: 0,
  activeSensorsCount: 0,
  activeInRegionB: 0,
  executionTimeMs: 0,
};

app.use(cors());
app.use(express.json());

function noCache(res) {
  res.set('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0');
  res.set('Pragma', 'no-cache');
  res.set('Expires', '0');
}

app.get('/api/health', (req, res) => {
  noCache(res);
  res.json({ ok: true, message: 'Day6 dashboard API', endpoints: ['GET /api/stats', 'POST /api/run-demo'] });
});

app.get('/api/stats', async (req, res) => {
  noCache(res);
  try {
    const rRegions = await pool.query('SELECT COUNT(*) AS cnt FROM public.regions');
    const rSensors = await pool.query('SELECT COUNT(*) AS cnt FROM public.sensors');
    const rActive = await pool.query("SELECT COUNT(*) AS cnt FROM public.sensors WHERE status = 'active'");
    const regionsCount = parseInt(rRegions.rows[0]?.cnt || 0, 10);
    const sensorsCount = parseInt(rSensors.rows[0]?.cnt || 0, 10);
    const activeSensorsCount = parseInt(rActive.rows[0]?.cnt || 0, 10);
    res.json({
      regionsCount,
      sensorsCount,
      activeSensorsCount,
      activeInRegionB: lastDemoResult.activeInRegionB,
      lastDemoExecutionMs: lastDemoResult.executionTimeMs,
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/api/run-demo', async (req, res) => {
  noCache(res);
  const start = Date.now();
  try {
    const r = await pool.query(`
      WITH target_region AS (
        SELECT id, name, geom FROM regions WHERE name = 'Region_B'
      ),
      active_sensors_in_region AS MATERIALIZED (
        SELECT s.id, s.name, s.geom
        FROM sensors s, target_region tr
        WHERE ST_Intersects(s.geom, tr.geom) AND s.status = 'active'
      )
      SELECT COUNT(id) AS cnt FROM active_sensors_in_region
    `);
    const executionTimeMs = Date.now() - start;
    const activeInRegionB = parseInt(r.rows[0]?.cnt || 0, 10);
    const rRegions = await pool.query('SELECT COUNT(*) AS cnt FROM public.regions');
    const rSensors = await pool.query('SELECT COUNT(*) AS cnt FROM public.sensors');
    const rActive = await pool.query("SELECT COUNT(*) AS cnt FROM public.sensors WHERE status = 'active'");
    lastDemoResult = {
      regionsCount: parseInt(rRegions.rows[0]?.cnt || 0, 10),
      sensorsCount: parseInt(rSensors.rows[0]?.cnt || 0, 10),
      activeSensorsCount: parseInt(rActive.rows[0]?.cnt || 0, 10),
      activeInRegionB,
      executionTimeMs,
    };
    res.json(lastDemoResult);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/', (req, res) => {
  noCache(res);
  res.set('Cache-Control', 'no-store, no-cache, must-revalidate, private, max-age=0');
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});
app.use(express.static(path.join(__dirname, 'public')));

app.listen(PORT, '0.0.0.0', () => {
  console.log('Dashboard server running at http://localhost:' + PORT);
});
SRVEOF
  cat > "${PROJECT_DIR}/dashboard/public/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate, max-age=0">
  <meta http-equiv="Pragma" content="no-cache">
  <meta http-equiv="Expires" content="0">
  <title>Geospatial Day 6 — CTE Materialized Demo Dashboard</title>
  <style>
    :root { --bg: #e8eef5; --card: #fff; --border: #e7e5e4; --text: #1c1917; --text-muted: #57534e; --primary: #2563eb; --success: #15803d; --shadow: 0 1px 3px rgba(0,0,0,.08); --radius: 10px; }
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
      <h1>Geospatial Day 6 — CTE Materialized Demo</h1>
      <p>Regions, sensors, active sensors, and active-in-Region_B (MATERIALIZED CTE). Run demo to update all metrics.</p>
    </header>
    <section class="goal">
      <strong>Metrics:</strong> Regions, Sensors, Active sensors, Active in Region_B (from demo), Last demo (ms). Auto-refresh every 2s. Use "Run demo" so values are non-zero.
    </section>
    <div class="live-badge">Last updated: <span id="last-updated">—</span></div>
    <div class="metrics">
      <div class="metric success"><div class="label">Regions</div><div class="value" id="metric-regions">—</div></div>
      <div class="metric success"><div class="label">Sensors</div><div class="value" id="metric-sensors">—</div></div>
      <div class="metric success"><div class="label">Active sensors</div><div class="value" id="metric-active">—</div></div>
      <div class="metric success"><div class="label">Active in Region_B</div><div class="value" id="metric-regionb">—</div></div>
      <div class="metric primary"><div class="label">Last demo</div><div class="value" id="metric-execms">—</div><div class="unit">ms</div></div>
    </div>
    <div class="card">
      <h2 style="margin-top:0;">Actions</h2>
      <button class="btn" id="btn-refresh">Refresh metrics</button>
      <button class="btn" id="btn-run-demo">Run demo (MATERIALIZED CTE query)</button>
    </div>
  </div>
  <div class="toast" id="toast"></div>
  <script>
    if (window.location.protocol === 'file:') {
      document.body.innerHTML = '<div style="padding:2rem;font-family:sans-serif;"><h2 style="color:#c00;">Wrong URL</h2><p>Open at <strong>http://localhost:3006/</strong></p></div>';
    } else {
    (function() {
      function showToast(msg) {
        var el = document.getElementById('toast');
        if (el) { el.textContent = msg; el.classList.add('show'); setTimeout(function() { el.classList.remove('show'); }, 2500); }
      }
      function fetchJSON(path, opts) {
        var url = path + (path.indexOf('?') === -1 ? '?' : '&') + '_=' + Date.now();
        var o = Object.assign({ cache: 'no-store', credentials: 'same-origin' }, opts || {});
        return fetch(url, o).then(function(r) { if (!r.ok) throw new Error(r.statusText); return r.json(); });
      }
      function formatNum(n) {
        return (n != null && !isNaN(Number(n))) ? Number(n).toLocaleString('en-US', { maximumFractionDigits: 0 }) : '—';
      }
      var state = { regionsCount: null, sensorsCount: null, activeSensorsCount: null, activeInRegionB: null, executionTimeMs: 0, lastUpdated: null };
      function render(flash) {
        var ids = ['metric-regions', 'metric-sensors', 'metric-active', 'metric-regionb', 'metric-execms'];
        var values = [
          formatNum(state.regionsCount),
          formatNum(state.sensorsCount),
          formatNum(state.activeSensorsCount),
          formatNum(state.activeInRegionB),
          (state.executionTimeMs > 0) ? (state.executionTimeMs + ' ms') : '—'
        ];
        for (var i = 0; i < ids.length; i++) {
          var el = document.getElementById(ids[i]);
          if (el) {
            el.textContent = values[i];
            if (flash) {
              el.classList.remove('updated');
              el.offsetHeight;
              el.classList.add('updated');
              (function(elem) { setTimeout(function() { elem.classList.remove('updated'); }, 400); })(el);
            }
          }
        }
        var el = document.getElementById('last-updated');
        if (el) el.textContent = state.lastUpdated ? state.lastUpdated.toLocaleTimeString() : '—';
      }
      function setState(next, flash) {
        if (next.regionsCount != null) state.regionsCount = next.regionsCount;
        if (next.sensorsCount != null) state.sensorsCount = next.sensorsCount;
        if (next.activeSensorsCount != null) state.activeSensorsCount = next.activeSensorsCount;
        if (next.activeInRegionB != null) state.activeInRegionB = next.activeInRegionB;
        var ms = next.executionTimeMs != null ? next.executionTimeMs : next.lastDemoExecutionMs;
        if (ms != null) state.executionTimeMs = ms;
        state.lastUpdated = new Date();
        render(flash);
      }
      var LIVE_MS = 1000, liveId = null;
      function loadStats(flash) {
        return fetchJSON('/api/stats').then(function(s) {
          setState({
            regionsCount: s.regionsCount,
            sensorsCount: s.sensorsCount,
            activeSensorsCount: s.activeSensorsCount,
            activeInRegionB: s.activeInRegionB,
            executionTimeMs: s.lastDemoExecutionMs
          }, !!flash);
          return s;
        }).catch(function(e) {
          console.error('loadStats', e);
          state.lastUpdated = new Date();
          render(false);
        });
      }
      function startLive() {
        if (liveId) return;
        liveId = setInterval(function() { loadStats(); }, LIVE_MS);
      }
      document.getElementById('btn-refresh').addEventListener('click', function() {
        loadStats(true).then(function() { showToast('Metrics updated.'); }).catch(function(e) { showToast('Error: ' + (e && e.message)); });
      });
      document.getElementById('btn-run-demo').addEventListener('click', function() {
        var btn = document.getElementById('btn-run-demo');
        btn.disabled = true;
        if (liveId) { clearInterval(liveId); liveId = null; }
        var runDemoUrl = '/api/run-demo?_=' + Date.now();
        fetch(runDemoUrl, { method: 'POST', headers: { 'Content-Type': 'application/json' }, cache: 'no-store' })
          .then(function(r) { if (!r.ok) throw new Error(r.statusText); return r.json(); })
          .then(function(r) {
            setState({
              regionsCount: r.regionsCount,
              sensorsCount: r.sensorsCount,
              activeSensorsCount: r.activeSensorsCount,
              activeInRegionB: r.activeInRegionB,
              executionTimeMs: r.executionTimeMs
            }, true);
            showToast('Demo ran in ' + r.executionTimeMs + ' ms. All metrics updated.');
            return loadStats(true);
          })
          .catch(function(e) { showToast('Error: ' + (e && e.message)); })
          .finally(function() { btn.disabled = false; startLive(); });
      });
      loadStats().then(startLive).catch(function() { startLive(); });
    })();
    }
  </script>
</body>
</html>
HTMLEOF
  log_info "Generated dashboard (package.json, server.js, public/index.html)"
}

generate_stop_script
generate_test_script
generate_start_script
generate_dashboard

# --- 11. Run tests (full path) ---
log_info "Running tests..."
TEST_SCRIPT="${PROJECT_DIR}/test.sh"
if [ -x "${TEST_SCRIPT}" ]; then
  "${TEST_SCRIPT}" || log_error "Tests failed."
  log_info "All tests passed."
else
  log_error "Test script not found or not executable: ${TEST_SCRIPT}"
fi

# --- 12. Install dashboard dependencies if needed ---
if [ ! -d "${PROJECT_DIR}/dashboard/node_modules" ]; then
  log_info "Installing dashboard dependencies..."
  (cd "${PROJECT_DIR}/dashboard" && npm install --silent) || log_warn "npm install failed; you may need to run it manually in dashboard/"
fi

# --- 13. Start dashboard (full path; avoid duplicate) ---
log_info "Starting dashboard..."
DASHBOARD_DIR="${PROJECT_DIR}/dashboard"
if command -v lsof &>/dev/null; then
  PID=$(lsof -ti ":${DASHBOARD_PORT}" 2>/dev/null || true)
  [ -n "$PID" ] && kill $PID 2>/dev/null || true
fi
(
  cd "${DASHBOARD_DIR}" && \
  PGHOST="${PGHOST:-localhost}" PGPORT="${PGPORT:-5432}" PGUSER="$DB_USER" PGPASSWORD="$DB_PASSWORD" PGDATABASE="$DB_NAME" DASHBOARD_PORT="$DASHBOARD_PORT" \
  nohup node server.js >> dashboard.log 2>&1 &
) || log_error "Failed to start dashboard."
sleep 2
log_info "Dashboard started at http://localhost:${DASHBOARD_PORT}"

# --- 14. Run demo once so dashboard metrics are non-zero ---
log_info "Running demo once to populate dashboard metrics..."
if command -v curl &>/dev/null; then
  curl -s -X POST "http://localhost:${DASHBOARD_PORT}/api/run-demo" >/dev/null && log_info "Demo executed; dashboard metrics updated." || log_warn "Demo request failed (dashboard may still be starting)."
else
  log_warn "curl not found; open dashboard and click 'Run demo' to update metrics."
fi

echo ""
echo "--- Verification ---"
echo "You can connect to the database manually to explore:"
echo "  psql -h localhost -p $DB_PORT -U $DB_USER -d $DB_NAME"
echo "  Password: $DB_PASSWORD"
echo ""
echo "To stop the container: ${PROJECT_DIR}/stop.sh"
echo "To run tests: ${PROJECT_DIR}/test.sh"
echo "To start dashboard: ${PROJECT_DIR}/start.sh"
echo "Dashboard: http://localhost:${DASHBOARD_PORT}"
echo "Setup and demo complete!"