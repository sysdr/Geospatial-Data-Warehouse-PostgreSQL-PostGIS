#!/bin/bash
set -e

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="Master_4326_vs_3857"
PROJECT_DIR="${SCRIPT_DIR}/${PROJECT_NAME}"
DOCKER_COMPOSE_FILE="docker-compose.yml"
DB_NAME="geospatial_db"
DB_USER="user"
DB_PASSWORD="password"
DB_PORT="5432"
CONTAINER_NAME="postgis_container"
SERVICE_NAME="postgis"
PYTHON_CLI_APP="cli_tool.py"
EXPECTED_POINTS=3
DASHBOARD_PORT="${DASHBOARD_PORT:-3005}"

# --- Helper Functions ---
log_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

log_warn() {
    echo -e "\033[33m[WARN]\033[0m $1"
}

log_error() {
    echo -e "\033[31m[ERROR]\033[0m $1"
    exit 1
}

# --- Main Script ---

# 1. Create Project Directory and Structure
log_info "Creating project directory structure..."
mkdir -p "$PROJECT_DIR/src"
mkdir -p "$PROJECT_DIR/data"
mkdir -p "$PROJECT_DIR/docker"
cd "$PROJECT_DIR" || log_error "Failed to change to project directory."

# 2. Generate Docker Compose File
log_info "Generating Docker Compose file..."
cat <<EOF > docker/$DOCKER_COMPOSE_FILE
version: '3.8'

services:
  postgis:
    image: postgis/postgis:15-3.3
    container_name: $CONTAINER_NAME
    environment:
      POSTGRES_DB: $DB_NAME
      POSTGRES_USER: $DB_USER
      POSTGRES_PASSWORD: $DB_PASSWORD
    ports:
      - "$DB_PORT:5432"
    volumes:
      - ../data/pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $DB_USER -d $DB_NAME"]
      interval: 5s
      timeout: 5s
      retries: 5
    restart: unless-stopped
EOF

# 3. Generate Python CLI Source Code
log_info "Generating Python CLI application: $PYTHON_CLI_APP"
cat <<EOF > src/$PYTHON_CLI_APP
import psycopg2
import sys
import os
from prettytable import PrettyTable

# Database connection details
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_NAME = os.getenv("DB_NAME", "$DB_NAME")
DB_USER = os.getenv("DB_USER", "$DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD", "$DB_PASSWORD")
DB_PORT = os.getenv("DB_PORT", "$DB_PORT")

def get_db_connection():
    """Establishes and returns a database connection."""
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            port=DB_PORT
        )
        return conn
    except psycopg2.Error as e:
        print(f"Database connection error: {e}")
        sys.exit(1)

def init_db():
    """Initializes the database: creates PostGIS extension and tables."""
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        print("\n--- Initializing Database ---")
        cur.execute("CREATE EXTENSION IF NOT EXISTS postgis;")
        print("  PostGIS extension ensured.")

        # Table for SRID 4326 (WGS84 - Lat/Lon)
        cur.execute("""
            DROP TABLE IF EXISTS locations_4326;
            CREATE TABLE locations_4326 (
                id SERIAL PRIMARY KEY,
                name VARCHAR(100),
                geom GEOMETRY(Point, 4326),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """)
        print("  Table 'locations_4326' created.")

        # Table for SRID 3857 (Web Mercator - X/Y)
        cur.execute("""
            DROP TABLE IF EXISTS locations_3857;
            CREATE TABLE locations_3857 (
                id SERIAL PRIMARY KEY,
                name VARCHAR(100),
                geom GEOMETRY(Point, 3857),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """)
        print("  Table 'locations_3857' created.")
        conn.commit()
        print("Database initialization complete.")
    except psycopg2.Error as e:
        conn.rollback()
        print(f"Error during DB initialization: {e}")
    finally:
        cur.close()
        conn.close()

def add_point(name, lon, lat):
    """Adds a point to the 4326 table and its transformed version to the 3857 table."""
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        print(f"\n--- Adding Point: {name} (Lon: {lon}, Lat: {lat}) ---")
        # Insert into 4326 table
        cur.execute(
            "INSERT INTO locations_4326 (name, geom) VALUES (%s, ST_SetSRID(ST_MakePoint(%s, %s), 4326)) RETURNING id;",
            (name, lon, lat)
        )
        point_id_4326 = cur.fetchone()[0]
        print(f"  Added to locations_4326 (ID: {point_id_4326})")

        # Transform and insert into 3857 table
        cur.execute(
            """
            INSERT INTO locations_3857 (name, geom)
            SELECT %s, ST_Transform(ST_SetSRID(ST_MakePoint(%s, %s), 4326), 3857) RETURNING id;
            """,
            (name, lon, lat)
        )
        point_id_3857 = cur.fetchone()[0]
        print(f"  Transformed and added to locations_3857 (ID: {point_id_3857})")
        conn.commit()
        print("Point added successfully.")
    except psycopg2.Error as e:
        conn.rollback()
        print(f"Error adding point: {e}")
    finally:
        cur.close()
        conn.close()

def list_points(srid_type="all"):
    """Lists points from either 4326, 3857, or both tables."""
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        print(f"\n--- Listing Points ({srid_type.upper()}) ---")
        if srid_type == "4326" or srid_type == "all":
            cur.execute("SELECT id, name, ST_AsText(geom) FROM locations_4326;")
            rows_4326 = cur.fetchall()
            table_4326 = PrettyTable(["ID", "Name", "Geometry (4326)"])
            for row in rows_4326:
                table_4326.add_row(row)
            print("Locations (SRID 4326 - WGS84 Lat/Lon):")
            print(table_4326)

        if srid_type == "3857" or srid_type == "all":
            cur.execute("SELECT id, name, ST_AsText(geom) FROM locations_3857;")
            rows_3857 = cur.fetchall()
            table_3857 = PrettyTable(["ID", "Name", "Geometry (3857)"])
            for row in rows_3857:
                table_3857.add_row(row)
            print("\nLocations (SRID 3857 - Web Mercator X/Y):")
            print(table_3857)

    except psycopg2.Error as e:
        print(f"Error listing points: {e}")
    finally:
        cur.close()
        conn.close()

def transform_and_display(point_id_4326):
    """Retrieves a point from 4326, transforms it to 3857, and displays both."""
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        print(f"\n--- Transforming and Displaying Point (ID: {point_id_4326}) ---")
        cur.execute(
            """
            SELECT
                name,
                ST_AsText(geom) AS geom_4326_text,
                ST_X(geom) AS lon,
                ST_Y(geom) AS lat,
                ST_AsText(ST_Transform(geom, 3857)) AS geom_3857_text,
                ST_X(ST_Transform(geom, 3857)) AS x_3857,
                ST_Y(ST_Transform(geom, 3857)) AS y_3857
            FROM locations_4326
            WHERE id = %s;
            """,
            (point_id_4326,)
        )
        row = cur.fetchone()
        if row:
            name, geom_4326_text, lon, lat, geom_3857_text, x_3857, y_3857 = row
            print(f"  Name: {name}")
            print(f"  SRID 4326 (WGS84):")
            print(f"    Geometry: {geom_4326_text}")
            print(f"    Longitude (X): {lon:.6f}, Latitude (Y): {lat:.6f}")
            print(f"  SRID 3857 (Web Mercator):")
            print(f"    Geometry: {geom_3857_text}")
            print(f"    X: {x_3857:.2f}, Y: {y_3857:.2f}")
        else:
            print(f"  Point with ID {point_id_4326} not found in locations_4326.")
    except psycopg2.Error as e:
        print(f"Error transforming point: {e}")
    finally:
        cur.close()
        conn.close()

def demo_script():
    """Runs a demonstration sequence."""
    print("\n" + "="*50)
    print("  SRID 4326 vs 3857 Demonstration")
    print("="*50)

    init_db()

    # Add some points
    add_point("Eiffel Tower", 2.2945, 48.8584)         # Paris
    add_point("Statue of Liberty", -74.0445, 40.6892) # New York
    add_point("Sydney Opera House", 151.2153, -33.8568) # Sydney

    list_points("all")

    # Demonstrate transformation for a specific point
    print("\n--- Demonstrating Transformation for Eiffel Tower (ID 1) ---")
    transform_and_display(1)

    print("\n" + "="*50)
    print("  Demonstration Complete.")
    print("  Use 'python3 src/cli_tool.py --help' for more options.")
    print("="*50)


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 src/cli_tool.py <command> [args]")
        print("Commands:")
        print("  init_db                  - Initializes the database (creates tables).")
        print("  add <name> <lon> <lat>   - Adds a point to the DB (e.g., add 'My Spot' 10.0 20.0).")
        print("  list [4326|3857|all]     - Lists points (default: all).")
        print("  transform <id_4326>      - Transforms and displays a point from 4326 to 3857.")
        print("  demo                     - Runs a full demonstration sequence.")
        sys.exit(1)

    command = sys.argv[1]

    if command == "init_db":
        init_db()
    elif command == "add":
        if len(sys.argv) == 5:
            try:
                name = sys.argv[2]
                lon = float(sys.argv[3])
                lat = float(sys.argv[4])
                add_point(name, lon, lat)
            except ValueError:
                print("Error: Longitude and Latitude must be numbers.")
            except IndexError:
                print("Error: Missing arguments for 'add' command.")
        else:
            print("Usage: add <name> <lon> <lat>")
    elif command == "list":
        srid_type = sys.argv[2] if len(sys.argv) > 2 else "all"
        list_points(srid_type)
    elif command == "transform":
        if len(sys.argv) == 3:
            try:
                point_id = int(sys.argv[2])
                transform_and_display(point_id)
            except ValueError:
                print("Error: Point ID must be an integer.")
        else:
            print("Usage: transform <id_4326>")
    elif command == "demo":
        demo_script()
    else:
        print(f"Unknown command: {command}")
        print("Use 'python3 src/cli_tool.py --help' for available commands.")

if __name__ == "__main__":
    main()
EOF

# 4. Check for Docker and Docker Compose
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed. Please install Docker to proceed."
fi
if ! command -v docker-compose &> /dev/null; then
    log_warn "Docker Compose v1 not found. Attempting to use 'docker compose' (v2+)."
    DOCKER_COMPOSE_CMD="docker compose"
else
    DOCKER_COMPOSE_CMD="docker-compose"
fi

generate_stop_script() {
    local stop_script="${PROJECT_DIR}/stop.sh"
    log_info "Generating ${stop_script}..."
    cat <<STOPEOF > "${stop_script}"
#!/bin/bash
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
cd "\${SCRIPT_DIR}/docker" && $DOCKER_COMPOSE_CMD down 2>/dev/null || true
echo "PostGIS container stopped. Done."
STOPEOF
    chmod +x "${stop_script}"
    log_info "Generated stop.sh"
}

generate_test_script() {
    local test_script="${PROJECT_DIR}/test.sh"
    log_info "Generating ${test_script}..."
    cat <<TESTEOF > "${test_script}"
#!/bin/bash
set -e
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
cd "\${SCRIPT_DIR}"
CONTAINER_NAME="${CONTAINER_NAME}"
DB_USER="${DB_USER}"
DB_NAME="${DB_NAME}"
EXPECTED_COUNT="${EXPECTED_POINTS}"
ERRORS=0
echo "[TEST] Checking generated files..."
for f in docker/$DOCKER_COMPOSE_FILE src/$PYTHON_CLI_APP stop.sh dashboard/package.json dashboard/server.js dashboard/public/index.html; do
  [ -f "\$f" ] && echo "  OK \$f" || { echo "  MISSING \$f"; ERRORS=\$((ERRORS+1)); }
done
echo "[TEST] Checking container..."
docker ps --format '{{.Names}}' | grep -q "^\${CONTAINER_NAME}\$" && echo "  OK Container running" || { echo "  FAIL Container not running"; ERRORS=\$((ERRORS+1)); }
echo "[TEST] Checking data (locations_4326 and locations_3857 count)..."
C4326=\$(docker exec "\${CONTAINER_NAME}" psql -U "\${DB_USER}" -d "\${DB_NAME}" -t -A -c "SELECT COUNT(*) FROM public.locations_4326;" 2>/dev/null || echo "0")
C3857=\$(docker exec "\${CONTAINER_NAME}" psql -U "\${DB_USER}" -d "\${DB_NAME}" -t -A -c "SELECT COUNT(*) FROM public.locations_3857;" 2>/dev/null || echo "0")
[ "\${C4326}" = "\${EXPECTED_COUNT}" ] && echo "  OK locations_4326 count = \${EXPECTED_COUNT}" || { echo "  FAIL locations_4326 = \${C4326} (expected \${EXPECTED_COUNT})"; ERRORS=\$((ERRORS+1)); }
[ "\${C3857}" = "\${EXPECTED_COUNT}" ] && echo "  OK locations_3857 count = \${EXPECTED_COUNT}" || { echo "  FAIL locations_3857 = \${C3857} (expected \${EXPECTED_COUNT})"; ERRORS=\$((ERRORS+1)); }
[ \${ERRORS} -eq 0 ] && echo "[TEST] All checks passed." || { echo "[TEST] \${ERRORS} check(s) failed."; exit 1; }
TESTEOF
    chmod +x "${test_script}"
    log_info "Generated test.sh"
}

generate_dashboard() {
    mkdir -p "${PROJECT_DIR}/dashboard/public"
    log_info "Generating dashboard in ${PROJECT_DIR}/dashboard..."
    cat > "${PROJECT_DIR}/dashboard/package.json" <<'PKGEOF'
{
  "name": "geospatial-day5-dashboard",
  "version": "1.0.0",
  "description": "Dashboard for Geospatial Data Warehouse Day5 - SRID 4326 vs 3857",
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
const { execSync } = require('child_process');

const app = express();
const PORT = process.env.DASHBOARD_PORT || 3005;

const poolConfig = {
  host: process.env.PGHOST || 'localhost',
  port: parseInt(process.env.PGPORT || '5432', 10),
  user: process.env.PGUSER || 'user',
  password: process.env.PGPASSWORD || 'password',
  database: process.env.PGDATABASE || 'geospatial_db',
};
const pool = new Pool(poolConfig);

const projectRoot = path.join(__dirname, '..');

let lastDemoResult = {
  count4326: 0,
  count3857: 0,
  executionTimeMs: 0,
};

app.use(cors());
app.use(express.json());

app.get('/api/health', (req, res) => {
  res.json({ ok: true, message: 'Day5 dashboard API', endpoints: ['GET /api/stats', 'POST /api/run-demo'] });
});

app.get('/api/stats', async (req, res) => {
  res.set('Cache-Control', 'no-store, no-cache, must-revalidate');
  try {
    const r4326 = await pool.query('SELECT COUNT(*) AS cnt FROM public.locations_4326');
    const r3857 = await pool.query('SELECT COUNT(*) AS cnt FROM public.locations_3857');
    const count4326 = parseInt(r4326.rows[0]?.cnt || 0, 10);
    const count3857 = parseInt(r3857.rows[0]?.cnt || 0, 10);
    res.json({
      count4326,
      count3857,
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
    const pythonExe = process.env.PYTHON_PATH || 'python3';
    const env = {
      ...process.env,
      DB_HOST: poolConfig.host,
      DB_PORT: String(poolConfig.port),
      DB_NAME: poolConfig.database,
      DB_USER: poolConfig.user,
      DB_PASSWORD: poolConfig.password,
    };
    execSync(`${pythonExe} src/cli_tool.py demo`, { cwd: projectRoot, env, stdio: 'pipe' });
    const executionTimeMs = Date.now() - start;
    const r4326 = await pool.query('SELECT COUNT(*) AS cnt FROM public.locations_4326');
    const r3857 = await pool.query('SELECT COUNT(*) AS cnt FROM public.locations_3857');
    const count4326 = parseInt(r4326.rows[0]?.cnt || 0, 10);
    const count3857 = parseInt(r3857.rows[0]?.cnt || 0, 10);
    lastDemoResult = { count4326, count3857, executionTimeMs };
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
  <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
  <title>Geospatial Day 5 — SRID 4326 vs 3857 Dashboard</title>
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
      <h1>Geospatial Day 5 — SRID 4326 vs 3857</h1>
      <p>Points in locations_4326 (WGS84) and locations_3857 (Web Mercator). Run demo to update all metrics.</p>
    </header>
    <section class="goal">
      <strong>Metrics:</strong> Count 4326, Count 3857, Last demo (ms). Auto-refresh every 2s. Use "Run demo" so values are non-zero.
    </section>
    <div class="live-badge">Last updated: <span id="last-updated">—</span></div>
    <div class="metrics">
      <div class="metric success"><div class="label">Points (4326)</div><div class="value" id="metric-4326">—</div></div>
      <div class="metric success"><div class="label">Points (3857)</div><div class="value" id="metric-3857">—</div></div>
      <div class="metric primary"><div class="label">Last demo</div><div class="value" id="metric-execms">—</div><div class="unit">ms</div></div>
    </div>
    <div class="card">
      <h2 style="margin-top:0;">Actions</h2>
      <button class="btn" id="btn-refresh">Refresh metrics</button>
      <button class="btn" id="btn-run-demo">Run demo (init + add points)</button>
    </div>
  </div>
  <div class="toast" id="toast"></div>
  <script>
    if (window.location.protocol === 'file:') {
      document.body.innerHTML = '<div style="padding:2rem;font-family:sans-serif;"><h2 style="color:#c00;">Wrong URL</h2><p>Open at <strong>http://localhost:3005/</strong></p></div>';
    } else {
    (function() {
      function showToast(msg) {
        var el = document.getElementById('toast');
        if (el) { el.textContent = msg; el.classList.add('show'); setTimeout(function() { el.classList.remove('show'); }, 2500); }
      }
      function fetchJSON(path, opts) {
        var o = Object.assign({ cache: 'no-store' }, opts || {});
        return fetch(path, o).then(function(r) { if (!r.ok) throw new Error(r.statusText); return r.json(); });
      }
      function formatNum(n) {
        return (n != null && !isNaN(Number(n))) ? Number(n).toLocaleString('en-US', { maximumFractionDigits: 2, minimumFractionDigits: 0 }) : '—';
      }
      var state = { count4326: null, count3857: null, executionTimeMs: 0, lastUpdated: null };
      function render() {
        var el;
        el = document.getElementById('metric-4326'); if (el) el.textContent = formatNum(state.count4326);
        el = document.getElementById('metric-3857'); if (el) el.textContent = formatNum(state.count3857);
        el = document.getElementById('metric-execms'); if (el) el.textContent = (state.executionTimeMs > 0) ? (state.executionTimeMs + ' ms') : '—';
        el = document.getElementById('last-updated'); if (el) el.textContent = state.lastUpdated ? state.lastUpdated.toLocaleTimeString() : '—';
      }
      function setState(next) {
        if (next.count4326 != null) state.count4326 = next.count4326;
        if (next.count3857 != null) state.count3857 = next.count3857;
        var ms = next.executionTimeMs != null ? next.executionTimeMs : next.lastDemoExecutionMs;
        if (ms != null) state.executionTimeMs = ms;
        state.lastUpdated = new Date();
        render();
      }
      var LIVE_MS = 2000, liveId = null;
      function loadStats() {
        return fetchJSON('/api/stats').then(function(s) {
          setState({ count4326: s.count4326, count3857: s.count3857, executionTimeMs: s.lastDemoExecutionMs });
          return s;
        }).catch(function(e) { console.error('loadStats', e); });
      }
      function startLive() { if (!liveId) liveId = setInterval(loadStats, LIVE_MS); }
      document.getElementById('btn-refresh').addEventListener('click', function() {
        loadStats().then(function() { showToast('Metrics updated.'); }).catch(function(e) { showToast('Error: ' + (e && e.message)); });
      });
      document.getElementById('btn-run-demo').addEventListener('click', function() {
        var btn = document.getElementById('btn-run-demo');
        btn.disabled = true;
        if (liveId) { clearInterval(liveId); liveId = null; }
        fetchJSON('/api/run-demo', { method: 'POST', headers: { 'Content-Type': 'application/json' } })
          .then(function(r) {
            setState({ count4326: r.count4326, count3857: r.count3857, executionTimeMs: r.executionTimeMs });
            showToast('Demo ran in ' + r.executionTimeMs + ' ms.');
          })
          .catch(function(e) { showToast('Error: ' + (e && e.message)); })
          .finally(function() { btn.disabled = false; setTimeout(startLive, 500); });
      });
      loadStats().then(startLive).catch(startLive);
    })();
    }
  </script>
</body>
</html>
HTMLEOF
    log_info "Generated dashboard (package.json, server.js, public/index.html)"
}

# 5. Start Docker containers
log_info "Starting PostGIS container using Docker Compose..."
(cd docker && $DOCKER_COMPOSE_CMD up -d --build) || log_error "Failed to start Docker containers."

# 6. Wait for PostgreSQL to be ready
log_info "Waiting for PostGIS container to be healthy..."
for i in {1..20}; do
    CID=$($DOCKER_COMPOSE_CMD -f docker/$DOCKER_COMPOSE_FILE ps -q $SERVICE_NAME 2>/dev/null)
    HEALTH_STATUS=""
    [ -n "$CID" ] && HEALTH_STATUS=$(docker inspect -f '{{.State.Health.Status}}' "$CID" 2>/dev/null || true)
    if [ "$HEALTH_STATUS" == "healthy" ]; then
        log_info "PostGIS container is healthy!"
        break
    fi
    log_info "PostGIS health: ${HEALTH_STATUS:-starting}. Waiting... ($i/20)"
    sleep 5
    if [ $i -eq 20 ]; then
        log_error "PostGIS container did not become healthy in time."
    fi
done

# 7. Install Python dependencies (venv if available, else system pip)
PYTHON_CMD="python3"
log_info "Installing Python dependencies..."
if [ -d "venv" ] && [ ! -x "venv/bin/python3" ]; then
    rm -rf venv
fi
if [ -d "venv" ]; then
    ./venv/bin/pip install --quiet psycopg2-binary prettytable 2>/dev/null || true
    if ! ./venv/bin/python3 -c "import psycopg2" 2>/dev/null; then
        log_warn "venv exists but missing deps; removing and using system pip."
        rm -rf venv
    else
        PYTHON_CMD="./venv/bin/python3"
    fi
fi
if [ "$PYTHON_CMD" = "python3" ]; then
    if python3 -m venv venv 2>/dev/null; then
        ./venv/bin/pip install --quiet psycopg2-binary prettytable || log_error "Failed to install deps in venv."
        PYTHON_CMD="./venv/bin/python3"
    else
        log_warn "venv not available; trying system pip."
        python3 -m pip install --break-system-packages psycopg2-binary prettytable 2>/dev/null || \
        pip3 install --break-system-packages psycopg2-binary prettytable 2>/dev/null || \
        log_error "Could not install psycopg2-binary and prettytable. Install python3-venv (apt install python3.12-venv) or pip packages."
    fi
fi

# 8. Run the CLI application to initialize DB and run demo
log_info "Running the CLI application to initialize DB and perform a demo..."
$PYTHON_CMD src/$PYTHON_CLI_APP demo

# 9. Generate stop.sh, test.sh, and dashboard
log_info "Generating stop.sh, test.sh, and dashboard..."
generate_stop_script
generate_test_script
generate_dashboard

# 10. Run tests (full path)
log_info "Running tests..."
TEST_SCRIPT="${PROJECT_DIR}/test.sh"
if [ -x "${TEST_SCRIPT}" ]; then
    "${TEST_SCRIPT}" || log_error "Tests failed."
    log_info "All tests passed."
else
    log_error "Test script not found or not executable: ${TEST_SCRIPT}"
fi

# 11. Start dashboard (full path; avoid duplicate)
log_info "Starting dashboard..."
DASHBOARD_DIR="${PROJECT_DIR}/dashboard"
if [ -d "${DASHBOARD_DIR}" ] && [ -f "${DASHBOARD_DIR}/package.json" ]; then
    if command -v lsof &>/dev/null && lsof -i ":${DASHBOARD_PORT}" 2>/dev/null | grep -q LISTEN; then
        log_info "Dashboard already running on port ${DASHBOARD_PORT}; skipping start."
    else
        if [ ! -d "${DASHBOARD_DIR}/node_modules" ]; then
            (cd "${DASHBOARD_DIR}" && npm install --silent) || log_error "Dashboard npm install failed."
        fi
        export DASHBOARD_PORT="${DASHBOARD_PORT}" PGHOST="${PGHOST:-localhost}" PGPORT="${DB_PORT}" PGUSER="${DB_USER}" PGPASSWORD="${DB_PASSWORD}" PGDATABASE="${DB_NAME}"
        [ -x "${PROJECT_DIR}/venv/bin/python3" ] && export PYTHON_PATH="${PROJECT_DIR}/venv/bin/python3"
        (cd "${DASHBOARD_DIR}" && nohup node server.js >> dashboard.log 2>&1 &)
        sleep 4
        log_info "Dashboard started at http://localhost:${DASHBOARD_PORT}"
    fi
else
    log_error "Dashboard not found at ${DASHBOARD_DIR}"
fi

# 12. Run demo once so dashboard metrics are non-zero
log_info "Running demo once to populate dashboard metrics..."
if command -v curl &>/dev/null; then
    curl -s -X POST "http://localhost:${DASHBOARD_PORT}/api/run-demo" >/dev/null && log_info "Demo executed; dashboard metrics updated." || log_warn "Demo request failed (dashboard may still be starting)."
else
    log_warn "curl not found; open dashboard and click 'Run demo' to update metrics."
fi

# 13. Verification and Instructions
echo ""
echo "========================================================================"
echo "  GEOSPATIAL DATA WAREHOUSE: SRID DEMO READY!"
echo "========================================================================"
echo "  Database '$DB_NAME' is running in Docker on port $DB_PORT."
echo "  Project directory: ${PROJECT_DIR}"
echo "  Python CLI tool: ${PROJECT_DIR}/src/$PYTHON_CLI_APP"
echo "  Dashboard: http://localhost:${DASHBOARD_PORT}"
echo ""
echo "  To interact with the CLI tool (from project dir):"
echo "  ------------------------------------------------------------------------"
echo "  cd ${PROJECT_DIR}"
echo "  python3 src/$PYTHON_CLI_APP init_db"
echo "  python3 src/$PYTHON_CLI_APP add 'Golden Gate Bridge' -122.4783 37.8199"
echo "  python3 src/$PYTHON_CLI_APP list"
echo "  python3 src/$PYTHON_CLI_APP transform 1"
echo "  python3 src/$PYTHON_CLI_APP demo"
echo ""
echo "  To stop and clean up, run: ${PROJECT_DIR}/stop.sh"
echo "  To run tests: ${PROJECT_DIR}/test.sh"
echo "========================================================================"