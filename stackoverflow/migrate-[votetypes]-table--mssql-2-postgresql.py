import pyodbc
import psycopg2
import os
from psycopg2.extras import execute_values

# --- Parameters ---
BATCH_SIZE = 1000

# --- SQL Server Connection ---
sql_server_conn_str = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    f"SERVER={os.getenv('SOURCE_MSSQLHOST', 'localhost')};"
    f"DATABASE={os.getenv('SOURCE_MSSQLDATABASE', 'StackOverflow2013')};"
    f"UID={os.getenv('SOURCE_MSSQLUSER', 'sa')};"
    f"PWD={os.getenv('SOURCE_MSSQLPASSWORD')};"
    "TrustServerCertificate=yes;"
)
print(f"Connecting to SQL Server...\n\t{sql_server_conn_str}")
sql_conn = pyodbc.connect(sql_server_conn_str)
sql_cursor = sql_conn.cursor()

# --- PostgreSQL Connection ---
print("Connecting to PostgreSQL...")
pg_conn = psycopg2.connect(
    host=os.getenv("TARGET_PGHOST", "localhost"),
    dbname=os.getenv("TARGET_PGDATABASE", "stackoverflow2013"),
    user=os.getenv("TARGET_PGUSER", "postgres"),
    password=os.getenv("TARGET_PGPASSWORD"),
    sslmode="require"
)
pg_cursor = pg_conn.cursor()

# --- Fetch from SQL Server ---
sql_query = "SELECT Id, Name FROM dbo.VoteTypes ORDER BY Id;"
print(f"Executing MSSQL query:\n\t{sql_query}")
sql_cursor.execute(sql_query)
rows = sql_cursor.fetchall()
print(f"Fetched {len(rows)} rows from SQL Server...")

# --- Insert into PostgreSQL ---
insert_query = """
    INSERT INTO public.votetypes (id, name)
    OVERRIDING SYSTEM VALUE
    VALUES %s
    ON CONFLICT (id) DO NOTHING;
"""

# --- Bulk Insert in Batches ---
inserted = 0
for i in range(0, len(rows), BATCH_SIZE):
    batch = rows[i:i+BATCH_SIZE]
    values = [(row.Id, row.Name) for row in batch]
    execute_values(pg_cursor, insert_query, values)
    pg_conn.commit()
    inserted += len(batch)
    print(f"Inserted {inserted}/{len(rows)} rows...")

# --- Cleanup ---
sql_cursor.close()
sql_conn.close()
pg_cursor.close()
pg_conn.close()
print("Data migration completed.")
