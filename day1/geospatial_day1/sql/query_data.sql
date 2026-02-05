-- Display all locations and their WKT representation
SELECT
    id,
    name,
    ST_AsText(geom_local) AS geom_local_wkt,
    ST_AsText(geom_global) AS geom_global_wkt,
    ST_AsText(geog_global::GEOMETRY) AS geog_global_wkt -- Cast geography to geometry for AsText
FROM locations;

-- Calculate planar distance (GEOMETRY) between San Francisco and New York
SELECT
    'SF to NY (GEOMETRY - Planar)' AS description,
    ST_Distance(
        (SELECT geom_global FROM locations WHERE name = 'San Francisco Ferry Building'),
        (SELECT geom_global FROM locations WHERE name = 'New York Times Square')
    ) AS distance_degrees
FROM locations LIMIT 1;

-- Calculate spherical distance (GEOGRAPHY) between San Francisco and New York (in meters)
SELECT
    'SF to NY (GEOGRAPHY - Spherical)' AS description,
    ST_Distance(
        (SELECT geog_global FROM locations WHERE name = 'San Francisco Ferry Building'),
        (SELECT geog_global FROM locations WHERE name = 'New York Times Square')
    ) AS distance_meters
FROM locations LIMIT 1;

-- Calculate spherical distance (GEOGRAPHY) between London and Paris (in meters)
SELECT
    'London to Paris (GEOGRAPHY - Spherical)' AS description,
    ST_Distance(
        (SELECT geog_global FROM locations WHERE name = 'London Big Ben'),
        (SELECT geog_global FROM locations WHERE name = 'Eiffel Tower, Paris')
    ) AS distance_meters
FROM locations LIMIT 1;

-- Assignment Query: Calculate distance between SF and NY using geom_global after transforming to geography
SELECT
    'SF to NY (GEOMETRY converted to GEOGRAPHY)' AS description,
    ST_Distance(
        (SELECT geom_global FROM locations WHERE name = 'San Francisco Ferry Building')::GEOGRAPHY,
        (SELECT geom_global FROM locations WHERE name = 'New York Times Square')::GEOGRAPHY
    ) AS distance_meters
FROM locations LIMIT 1;

