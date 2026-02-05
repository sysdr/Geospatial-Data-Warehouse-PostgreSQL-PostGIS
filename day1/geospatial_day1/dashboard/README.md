# Geospatial Day 1 — Dashboard

Web dashboard for the geospatial_day1 PostGIS application.

## Start

1. Ensure PostGIS is running (run `../setup.sh` if needed).
2. From this folder: `npm start`
3. Open **http://localhost:3000**

## Options

- **DASHBOARD_PORT** — Port (default: 3000).
- **PGHOST**, **PGPORT**, **PGUSER**, **PGPASSWORD**, **PGDATABASE** — Override DB connection (defaults match setup.sh).

Example: `DASHBOARD_PORT=3001 npm start`
