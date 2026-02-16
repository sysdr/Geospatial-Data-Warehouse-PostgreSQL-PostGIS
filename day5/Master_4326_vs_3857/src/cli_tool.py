import psycopg2
import sys
import os
from prettytable import PrettyTable

# Database connection details
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_NAME = os.getenv("DB_NAME", "geospatial_db")
DB_USER = os.getenv("DB_USER", "user")
DB_PASSWORD = os.getenv("DB_PASSWORD", "password")
DB_PORT = os.getenv("DB_PORT", "5432")

def get_db_connection():
    """Establishes and returns a database connection."""
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            port=DB_PORT
        )
        return conn
    except psycopg2.Error as e:
        print(f"Database connection error: {e}")
        sys.exit(1)

def init_db():
    """Initializes the database: creates PostGIS extension and tables."""
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        print("\n--- Initializing Database ---")
        cur.execute("CREATE EXTENSION IF NOT EXISTS postgis;")
        print("  PostGIS extension ensured.")

        # Table for SRID 4326 (WGS84 - Lat/Lon)
        cur.execute("""
            DROP TABLE IF EXISTS locations_4326;
            CREATE TABLE locations_4326 (
                id SERIAL PRIMARY KEY,
                name VARCHAR(100),
                geom GEOMETRY(Point, 4326),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """)
        print("  Table 'locations_4326' created.")

        # Table for SRID 3857 (Web Mercator - X/Y)
        cur.execute("""
            DROP TABLE IF EXISTS locations_3857;
            CREATE TABLE locations_3857 (
                id SERIAL PRIMARY KEY,
                name VARCHAR(100),
                geom GEOMETRY(Point, 3857),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """)
        print("  Table 'locations_3857' created.")
        conn.commit()
        print("Database initialization complete.")
    except psycopg2.Error as e:
        conn.rollback()
        print(f"Error during DB initialization: {e}")
    finally:
        cur.close()
        conn.close()

def add_point(name, lon, lat):
    """Adds a point to the 4326 table and its transformed version to the 3857 table."""
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        print(f"\n--- Adding Point: {name} (Lon: {lon}, Lat: {lat}) ---")
        # Insert into 4326 table
        cur.execute(
            "INSERT INTO locations_4326 (name, geom) VALUES (%s, ST_SetSRID(ST_MakePoint(%s, %s), 4326)) RETURNING id;",
            (name, lon, lat)
        )
        point_id_4326 = cur.fetchone()[0]
        print(f"  Added to locations_4326 (ID: {point_id_4326})")

        # Transform and insert into 3857 table
        cur.execute(
            """
            INSERT INTO locations_3857 (name, geom)
            SELECT %s, ST_Transform(ST_SetSRID(ST_MakePoint(%s, %s), 4326), 3857) RETURNING id;
            """,
            (name, lon, lat)
        )
        point_id_3857 = cur.fetchone()[0]
        print(f"  Transformed and added to locations_3857 (ID: {point_id_3857})")
        conn.commit()
        print("Point added successfully.")
    except psycopg2.Error as e:
        conn.rollback()
        print(f"Error adding point: {e}")
    finally:
        cur.close()
        conn.close()

def list_points(srid_type="all"):
    """Lists points from either 4326, 3857, or both tables."""
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        print(f"\n--- Listing Points ({srid_type.upper()}) ---")
        if srid_type == "4326" or srid_type == "all":
            cur.execute("SELECT id, name, ST_AsText(geom) FROM locations_4326;")
            rows_4326 = cur.fetchall()
            table_4326 = PrettyTable(["ID", "Name", "Geometry (4326)"])
            for row in rows_4326:
                table_4326.add_row(row)
            print("Locations (SRID 4326 - WGS84 Lat/Lon):")
            print(table_4326)

        if srid_type == "3857" or srid_type == "all":
            cur.execute("SELECT id, name, ST_AsText(geom) FROM locations_3857;")
            rows_3857 = cur.fetchall()
            table_3857 = PrettyTable(["ID", "Name", "Geometry (3857)"])
            for row in rows_3857:
                table_3857.add_row(row)
            print("\nLocations (SRID 3857 - Web Mercator X/Y):")
            print(table_3857)

    except psycopg2.Error as e:
        print(f"Error listing points: {e}")
    finally:
        cur.close()
        conn.close()

def transform_and_display(point_id_4326):
    """Retrieves a point from 4326, transforms it to 3857, and displays both."""
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        print(f"\n--- Transforming and Displaying Point (ID: {point_id_4326}) ---")
        cur.execute(
            """
            SELECT
                name,
                ST_AsText(geom) AS geom_4326_text,
                ST_X(geom) AS lon,
                ST_Y(geom) AS lat,
                ST_AsText(ST_Transform(geom, 3857)) AS geom_3857_text,
                ST_X(ST_Transform(geom, 3857)) AS x_3857,
                ST_Y(ST_Transform(geom, 3857)) AS y_3857
            FROM locations_4326
            WHERE id = %s;
            """,
            (point_id_4326,)
        )
        row = cur.fetchone()
        if row:
            name, geom_4326_text, lon, lat, geom_3857_text, x_3857, y_3857 = row
            print(f"  Name: {name}")
            print(f"  SRID 4326 (WGS84):")
            print(f"    Geometry: {geom_4326_text}")
            print(f"    Longitude (X): {lon:.6f}, Latitude (Y): {lat:.6f}")
            print(f"  SRID 3857 (Web Mercator):")
            print(f"    Geometry: {geom_3857_text}")
            print(f"    X: {x_3857:.2f}, Y: {y_3857:.2f}")
        else:
            print(f"  Point with ID {point_id_4326} not found in locations_4326.")
    except psycopg2.Error as e:
        print(f"Error transforming point: {e}")
    finally:
        cur.close()
        conn.close()

def demo_script():
    """Runs a demonstration sequence."""
    print("\n" + "="*50)
    print("  SRID 4326 vs 3857 Demonstration")
    print("="*50)

    init_db()

    # Add some points
    add_point("Eiffel Tower", 2.2945, 48.8584)         # Paris
    add_point("Statue of Liberty", -74.0445, 40.6892) # New York
    add_point("Sydney Opera House", 151.2153, -33.8568) # Sydney

    list_points("all")

    # Demonstrate transformation for a specific point
    print("\n--- Demonstrating Transformation for Eiffel Tower (ID 1) ---")
    transform_and_display(1)

    print("\n" + "="*50)
    print("  Demonstration Complete.")
    print("  Use 'python3 src/cli_tool.py --help' for more options.")
    print("="*50)


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 src/cli_tool.py <command> [args]")
        print("Commands:")
        print("  init_db                  - Initializes the database (creates tables).")
        print("  add <name> <lon> <lat>   - Adds a point to the DB (e.g., add 'My Spot' 10.0 20.0).")
        print("  list [4326|3857|all]     - Lists points (default: all).")
        print("  transform <id_4326>      - Transforms and displays a point from 4326 to 3857.")
        print("  demo                     - Runs a full demonstration sequence.")
        sys.exit(1)

    command = sys.argv[1]

    if command == "init_db":
        init_db()
    elif command == "add":
        if len(sys.argv) == 5:
            try:
                name = sys.argv[2]
                lon = float(sys.argv[3])
                lat = float(sys.argv[4])
                add_point(name, lon, lat)
            except ValueError:
                print("Error: Longitude and Latitude must be numbers.")
            except IndexError:
                print("Error: Missing arguments for 'add' command.")
        else:
            print("Usage: add <name> <lon> <lat>")
    elif command == "list":
        srid_type = sys.argv[2] if len(sys.argv) > 2 else "all"
        list_points(srid_type)
    elif command == "transform":
        if len(sys.argv) == 3:
            try:
                point_id = int(sys.argv[2])
                transform_and_display(point_id)
            except ValueError:
                print("Error: Point ID must be an integer.")
        else:
            print("Usage: transform <id_4326>")
    elif command == "demo":
        demo_script()
    else:
        print(f"Unknown command: {command}")
        print("Use 'python3 src/cli_tool.py --help' for available commands.")

if __name__ == "__main__":
    main()
