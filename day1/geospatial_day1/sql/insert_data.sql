-- Insert sample data (geom_local: Web Mercator 3857, geom_global/geog_global: WGS84 4326)
INSERT INTO locations (name, geom_local, geom_global, geog_global) VALUES
('San Francisco Ferry Building',
 ST_Transform(ST_SetSRID(ST_MakePoint(-122.3934, 37.7955), 4326), 3857),
 ST_SetSRID(ST_MakePoint(-122.3934, 37.7955), 4326),
 ST_SetSRID(ST_MakePoint(-122.3934, 37.7955), 4326)::GEOGRAPHY),

('New York Times Square',
 ST_Transform(ST_SetSRID(ST_MakePoint(-73.9855, 40.7580), 4326), 3857),
 ST_SetSRID(ST_MakePoint(-73.9855, 40.7580), 4326),
 ST_SetSRID(ST_MakePoint(-73.9855, 40.7580), 4326)::GEOGRAPHY),

('London Big Ben',
 ST_Transform(ST_SetSRID(ST_MakePoint(-0.1247, 51.5007), 4326), 3857),
 ST_SetSRID(ST_MakePoint(-0.1247, 51.5007), 4326),
 ST_SetSRID(ST_MakePoint(-0.1247, 51.5007), 4326)::GEOGRAPHY),

('Eiffel Tower, Paris',
 ST_Transform(ST_SetSRID(ST_MakePoint(2.2945, 48.8584), 4326), 3857),
 ST_SetSRID(ST_MakePoint(2.2945, 48.8584), 4326),
 ST_SetSRID(ST_MakePoint(2.2945, 48.8584), 4326)::GEOGRAPHY);

