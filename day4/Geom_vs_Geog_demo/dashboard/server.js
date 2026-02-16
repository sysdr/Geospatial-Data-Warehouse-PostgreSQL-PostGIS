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
