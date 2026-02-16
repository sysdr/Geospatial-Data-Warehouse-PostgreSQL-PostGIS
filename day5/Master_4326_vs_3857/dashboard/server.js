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
