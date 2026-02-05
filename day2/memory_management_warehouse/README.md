# Memory Management Warehouse

PostgreSQL/PostGIS demo for work_mem and spatial queries (Day 2 – Memory Management).

## Project directory

All scripts and the dashboard run from this directory: `memory_management_warehouse/`. Paths are relative to this folder.

## Quick start

From this directory (or using full path):

```bash
# Setup: start PostGIS container, load data, run demo, start dashboard
./setup.sh

# Stop container
./stop.sh

# Run tests
./test.sh

# Cleanup: stop container, remove node_modules/cache, prune Docker
./cleanup.sh
```

## Contents

- `setup.sh` – Start PostgreSQL 17 + PostGIS, load places/regions, run demo, start dashboard
- `stop.sh` – Stop and remove the `geospatial_pg17` container
- `test.sh` – Check files, container, and data (10 places, 3 regions)
- `cleanup.sh` – Stop container, remove node_modules/venv/cache, Docker prune
- `dashboard/` – Node.js dashboard (work_mem, places, regions, demo query)
- `init_data.sql` – Sample data (generated/used by setup)
- `postgresql.conf` – Generated config (reference)

## Dashboard

After setup, open http://localhost:3001 (or `DASHBOARD_PORT`). Use “Apply tuned work_mem (256MB)”, “Run demo”, “Add sample place”, etc.; all metrics refresh after each action.
