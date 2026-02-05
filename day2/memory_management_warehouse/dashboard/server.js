const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const path = require('path');

const app = express();
const PORT = process.env.DASHBOARD_PORT || 3001;

const poolConfig = {
  host: process.env.PGHOST || 'localhost',
  port: parseInt(process.env.PGPORT || '5432', 10),
  user: process.env.PGUSER || 'pguser',
  password: process.env.PGPASSWORD || 'pgpassword',
  database: process.env.PGDATABASE || 'gis_warehouse',
};
let pool = new Pool(poolConfig);

// Store last demo result so dashboard shows non-zero after run
let lastDemoResult = { executionTimeMs: 0, rows: [] };
// Store last user-selected work_mem (Docker was started with -c work_mem=4MB, so ALTER SYSTEM is overridden; we track selection so the metric updates on click)
let lastWorkMem = null;

app.use(cors());
app.use(express.json());

// Mount all API routes on /api via a Router (avoids any static-file or ordering issues)
const api = express.Router();

// GET /api/health - verify server has API (open in browser: http://localhost:3001/api/health)
api.get('/health', (req, res) => {
  res.json({ ok: true, message: 'Day2 dashboard API', endpoints: ['GET /api/stats', 'POST /api/run-demo', 'POST /api/set-work-mem', 'POST /api/add-place', 'POST /api/reset-data'] });
});

// GET /api/stats - work_mem, places count, regions count, last demo result
api.get('/stats', async (req, res) => {
  try {
    const workMemResult = await pool.query('SHOW work_mem');
    const dbWorkMem = workMemResult.rows[0] && workMemResult.rows[0].work_mem;
    const placesResult = await pool.query('SELECT COUNT(*) AS cnt FROM public.places');
    const regionsResult = await pool.query('SELECT COUNT(*) AS cnt FROM public.regions');
    res.json({
      workMem: lastWorkMem !== null ? lastWorkMem : (dbWorkMem || '—'),
      placesCount: parseInt(placesResult.rows[0]?.cnt || 0, 10),
      regionsCount: parseInt(regionsResult.rows[0]?.cnt || 0, 10),
      lastDemoExecutionMs: lastDemoResult.executionTimeMs,
      demoResults: lastDemoResult.rows,
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

const DEMO_QUERY = `
  SELECT
    r.name AS region_name,
    COUNT(p.id) AS num_places_in_region,
    ST_AsText(ST_Centroid(ST_Union(p.geom))) AS aggregated_centroid
  FROM public.regions r
  JOIN public.places p ON ST_Contains(r.geom, p.geom)
  GROUP BY r.name
  ORDER BY num_places_in_region DESC
`;

// POST /api/run-demo - run demo query, capture execution time, return rows
api.post('/run-demo', async (req, res) => {
  try {
    const explainResult = await pool.query(
      `EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) ${DEMO_QUERY}`
    );
    const text = explainResult.rows.map(r => r['QUERY PLAN']).join('\n');
    const execMatch = text.match(/Execution Time: ([\d.]+) ms/);
    const executionTimeMs = execMatch ? parseFloat(execMatch[1]) : 0;

    const result = await pool.query(DEMO_QUERY);
    const rows = result.rows.map(r => ({
      region_name: r.region_name,
      num_places_in_region: parseInt(r.num_places_in_region, 10),
      aggregated_centroid: r.aggregated_centroid,
    }));

    lastDemoResult = { executionTimeMs, rows };
    res.json({ executionTimeMs, rows });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// POST /api/set-work-mem - change work_mem and reload config (updates work_mem metric)
// ALTER SYSTEM + pg_reload_conf() only affect *new* connections; pool keeps old ones, so we
// recreate the pool so the next GET /api/stats uses a new connection and SHOW work_mem returns the new value.
api.post('/set-work-mem', async (req, res) => {
  const value = (req.body && req.body.value) || '256MB';
  const allowed = ['4MB', '8MB', '16MB', '32MB', '64MB', '128MB', '256MB'];
  if (!allowed.includes(value)) {
    return res.status(400).json({ error: 'Invalid work_mem; use one of: ' + allowed.join(', ') });
  }
  try {
    await pool.query(`ALTER SYSTEM SET work_mem = '${value}'`);
    await pool.query('SELECT pg_reload_conf()');
    await pool.end();
    pool = new Pool(poolConfig);
    lastWorkMem = value;
    res.json({ ok: true, workMem: value, message: `work_mem set to ${value}; metric updated.` });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// POST /api/add-place - insert one sample place (updates Places count)
api.post('/add-place', async (req, res) => {
  const name = (req.body && req.body.name) || 'Seattle';
  const lon = parseFloat((req.body && req.body.lon) || -122.3321);
  const lat = parseFloat((req.body && req.body.lat) || 47.6062);
  try {
    await pool.query(
      `INSERT INTO public.places (name, category, geom) VALUES ($1, 'City', ST_SetSRID(ST_MakePoint($2, $3), 4326))`,
      [name, lon, lat]
    );
    const countResult = await pool.query('SELECT COUNT(*) AS cnt FROM public.places');
    const count = parseInt(countResult.rows[0].cnt, 10);
    res.json({ ok: true, placesCount: count, message: `Added "${name}"; Places count is now ${count}.` });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// POST /api/reset-data - reset to 10 places, 3 regions (clears last demo result so user re-runs demo)
api.post('/reset-data', async (req, res) => {
  try {
    await pool.query('DROP TABLE IF EXISTS public.places');
    await pool.query('DROP TABLE IF EXISTS public.regions');
    await pool.query(`
      CREATE TABLE public.places (
        id SERIAL PRIMARY KEY, name VARCHAR(255), category VARCHAR(100), geom GEOMETRY(Point, 4326)
      );
    `);
    await pool.query(`
      CREATE TABLE public.regions (
        id SERIAL PRIMARY KEY, name VARCHAR(255), population BIGINT, geom GEOMETRY(Polygon, 4326)
      );
    `);
    await pool.query(`
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
      ('San Jose', 'City', ST_SetSRID(ST_MakePoint(-121.8863, 37.3382), 4326))
    `);
    await pool.query(`
      INSERT INTO public.regions (name, population, geom) VALUES
      ('East Coast', 100000000, ST_SetSRID(ST_GeomFromText('POLYGON ((-78 45, -70 45, -70 35, -78 35, -78 45))'), 4326)),
      ('West Coast', 50000000, ST_SetSRID(ST_GeomFromText('POLYGON ((-125 45, -115 45, -115 30, -125 30, -125 45))'), 4326)),
      ('Central', 75000000, ST_SetSRID(ST_GeomFromText('POLYGON ((-105 50, -85 50, -85 25, -105 25, -105 50))'), 4326))
    `);
    await pool.query('CREATE INDEX idx_places_geom ON public.places USING GIST (geom)');
    await pool.query('CREATE INDEX idx_regions_geom ON public.regions USING GIST (geom)');
    await pool.query('ANALYZE public.places');
    await pool.query('ANALYZE public.regions');
    lastDemoResult = { executionTimeMs: 0, rows: [] };
    res.json({ ok: true, message: 'Data reset to 10 places, 3 regions. Run the demo again to see execution time.' });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.use('/api', api);

app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Static files (after API and / so /api/* and / are handled first)
app.use(express.static(path.join(__dirname, 'public')));

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Dashboard server running at http://localhost:${PORT}`);
});
