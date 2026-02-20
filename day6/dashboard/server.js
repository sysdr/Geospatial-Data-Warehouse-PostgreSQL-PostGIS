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
