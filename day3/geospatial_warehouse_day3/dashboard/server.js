const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const path = require('path');

const app = express();
const PORT = process.env.DASHBOARD_PORT || 3002;

const poolConfig = {
  host: process.env.PGHOST || 'localhost',
  port: parseInt(process.env.PGPORT || '5432', 10),
  user: process.env.PGUSER || 'user',
  password: process.env.PGPASSWORD || 'password',
  database: process.env.PGDATABASE || 'geospatial_warehouse_day3',
};
const pool = new Pool(poolConfig);

let lastDemoResult = { executionTimeMs: 0, rows: [] };

const DEMO_QUERY = `
  SELECT id, name, ST_AsText(geom) AS geom_text
  FROM public.locations
  WHERE ST_Intersects(
    geom,
    ST_Buffer(ST_SetSRID(ST_MakePoint(-122.405, 37.775), 4326)::geography, 500)::geometry
  )
  LIMIT 100
`;

app.use(cors());
app.use(express.json());

app.get('/api/health', (req, res) => {
  res.json({ ok: true, message: 'Day3 dashboard API', endpoints: ['GET /api/stats', 'POST /api/run-demo'] });
});

app.get('/api/stats', async (req, res) => {
  try {
    const locResult = await pool.query('SELECT COUNT(*) AS cnt FROM public.locations');
    const idxResult = await pool.query("SELECT indexname FROM pg_indexes WHERE tablename = 'locations' AND indexname = 'idx_locations_geom'");
    const locationsCount = parseInt(locResult.rows[0]?.cnt || 0, 10);
    res.json({
      locationsCount,
      pointsInBuffer: lastDemoResult.rows.length,
      indexName: idxResult.rows[0]?.indexname || 'idx_locations_geom',
      lastDemoExecutionMs: lastDemoResult.executionTimeMs,
      demoResults: lastDemoResult.rows,
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/api/run-demo', async (req, res) => {
  try {
    const explainResult = await pool.query(
      `EXPLAIN (ANALYZE, FORMAT TEXT) ${DEMO_QUERY}`
    );
    const text = explainResult.rows.map(r => r['QUERY PLAN']).join('\n');
    const execMatch = text.match(/Execution Time: ([\d.]+) ms/);
    const executionTimeMs = execMatch ? parseFloat(execMatch[1]) : 0;

    const result = await pool.query(DEMO_QUERY);
    const rows = result.rows.map(r => ({ id: r.id, name: r.name, geom_text: r.geom_text }));

    lastDemoResult = { executionTimeMs, rows };
    res.json({ executionTimeMs, rows });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/', (req, res) => res.sendFile(path.join(__dirname, 'public', 'index.html')));
app.use(express.static(path.join(__dirname, 'public')));

app.listen(PORT, '0.0.0.0', () => {
  console.log('Dashboard server running at http://localhost:' + PORT);
});
