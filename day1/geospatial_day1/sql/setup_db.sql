-- Enable PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis;

-- Create table for locations
CREATE TABLE locations (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    -- Localized geometry (Web Mercator for display)
    geom_local GEOMETRY(Point, 3857),
    -- Global geometry (WGS84 for raw lat/lon, planar calculations)
    geom_global GEOMETRY(Point, 4326),
    -- Global geography (WGS84 for raw lat/lon, spherical calculations)
    geog_global GEOGRAPHY(Point, 4326)
);

-- Add spatial indexes for performance (we'll cover these in detail later!)
CREATE INDEX idx_locations_geom_local ON locations USING GIST (geom_local);
CREATE INDEX idx_locations_geom_global ON locations USING GIST (geom_global);
CREATE INDEX idx_locations_geog_global ON locations USING GIST (geog_global);

