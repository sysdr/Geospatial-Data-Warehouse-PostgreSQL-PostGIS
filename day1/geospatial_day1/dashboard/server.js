const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const path = require('path');

const app = express();
const PORT = process.env.DASHBOARD_PORT || 3000;

const pool = new Pool({
  host: process.env.PGHOST || 'localhost',
  port: parseInt(process.env.PGPORT || '5432', 10),
  user: process.env.PGUSER || 'user',
  password: process.env.PGPASSWORD || 'password',
  database: process.env.PGDATABASE || 'geospatial_warehouse_geospatial_day1',
});

app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// GET /api/locations - id, name, lon, lat for map
app.get('/api/locations', async (req, res) => {
  try {
    const r = await pool.query(`
      SELECT id, name,
             ST_X(geom_global) AS lon, ST_Y(geom_global) AS lat
      FROM locations ORDER BY id
    `);
    res.json(r.rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// GET /api/distances - for charts and metrics
app.get('/api/distances', async (req, res) => {
  try {
    const r = await pool.query(`
      SELECT 'SF to NY (Spherical)' AS label,
             ST_Distance(
               (SELECT geog_global FROM locations WHERE name = 'San Francisco Ferry Building'),
               (SELECT geog_global FROM locations WHERE name = 'New York Times Square')
             ) AS meters
      UNION ALL
      SELECT 'London to Paris (Spherical)',
             ST_Distance(
               (SELECT geog_global FROM locations WHERE name = 'London Big Ben'),
               (SELECT geog_global FROM locations WHERE name = 'Eiffel Tower, Paris')
             )
    `);
    res.json(r.rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// GET /api/stats - location count and summary
app.get('/api/stats', async (req, res) => {
  try {
    const countResult = await pool.query('SELECT COUNT(*) AS total FROM locations');
    const sfNy = await pool.query(`
      SELECT ST_Distance(
        (SELECT geog_global FROM locations WHERE name = 'San Francisco Ferry Building'),
        (SELECT geog_global FROM locations WHERE name = 'New York Times Square')
      ) AS meters
    `);
    const londonParis = await pool.query(`
      SELECT ST_Distance(
        (SELECT geog_global FROM locations WHERE name = 'London Big Ben'),
        (SELECT geog_global FROM locations WHERE name = 'Eiffel Tower, Paris')
      ) AS meters
    `);
    res.json({
      totalLocations: parseInt(countResult.rows[0].total, 10),
      sfNyMeters: parseFloat(sfNy.rows[0].meters),
      londonParisMeters: parseFloat(londonParis.rows[0].meters),
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// POST /api/refresh - no-op; frontend will refetch. Kept for "operation" that triggers refetch.
app.post('/api/refresh', (req, res) => {
  res.json({ ok: true, message: 'Use GET /api/stats and /api/locations to refresh.' });
});

// POST /api/add-location - add a sample location (Tokyo) so metrics update in real time
app.post('/api/add-location', async (req, res) => {
  const name = req.body.name || 'Tokyo Tower';
  const lon = parseFloat(req.body.lon) || 139.7454;
  const lat = parseFloat(req.body.lat) || 35.6586;
  try {
    await pool.query(
      `INSERT INTO locations (name, geom_local, geom_global, geog_global)
       VALUES ($1,
         ST_Transform(ST_SetSRID(ST_MakePoint($2, $3), 4326), 3857),
         ST_SetSRID(ST_MakePoint($2, $3), 4326),
         ST_SetSRID(ST_MakePoint($2, $3), 4326)::GEOGRAPHY)`,
      [name, lon, lat]
    );
    res.json({ ok: true, message: `Added location: ${name}` });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// POST /api/reset-locations - reset to original 4 locations (for demo)
app.post('/api/reset-locations', async (req, res) => {
  try {
    await pool.query('DELETE FROM locations WHERE id > 4');
    await pool.query("SELECT setval(pg_get_serial_sequence('locations', 'id'), 4)");
    res.json({ ok: true, message: 'Reset to original 4 locations.' });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Dashboard server running at http://localhost:${PORT}`);
});
