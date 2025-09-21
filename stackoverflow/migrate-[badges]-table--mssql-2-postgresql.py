import pyodbc
import psycopg2
import os
from psycopg2.extras import execute_values

# Params
BULK_INSERT: bool = True
BATCH_SIZE: int = 10000

# --- SQL Server connection ---
MSSQLHOST = os.getenv("SOURCE_MSSQLHOST", "localhost")
MSSQLDATABASE = os.getenv("SOURCE_MSSQLDATABASE", "StackOverflow2013")
MSSQLUSER = os.getenv("SOURCE_MSSQLUSER", "sa")
MSSQLPASSWORD = os.getenv("SOURCE_MSSQLPASSWORD")
sql_server_conn_str = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    f"SERVER={MSSQLHOST};"
    f"DATABASE={MSSQLDATABASE};"
    f"UID={MSSQLUSER};"
    f"PWD={MSSQLPASSWORD};"
    "TrustServerCertificate=yes;"
)
print(f'sql_server_conn_str => \n\t{sql_server_conn_str}')
sql_conn = pyodbc.connect(sql_server_conn_str)
sql_cursor = sql_conn.cursor()

# --- PostgreSQL connection ---
print(f'making postgres connection..')
pg_conn = psycopg2.connect(
    host=os.getenv("TARGET_PGHOST", "localhost"),
    dbname=os.getenv("TARGET_PGDATABASE", "stackoverflow2013"),
    user=os.getenv("TARGET_PGUSER", "postgres"),
    password=os.getenv("TARGET_PGPASSWORD"),
    sslmode="require"
)
pg_cursor = pg_conn.cursor()

# --- Query to fetch from SQL Server ---
MSSQLQUERY = """
    SELECT Id, Name, UserId, Date FROM dbo.Badges
"""
print(f'execute MSSQL query => \n\t{MSSQLQUERY}\n..')
sql_cursor.execute(MSSQLQUERY)

rows = sql_cursor.fetchall()
print(f"Fetched {len(rows)} rows from SQL Server...")

# --- Insert into PostgreSQL ---
insert_query = """
INSERT INTO public.badges (
    id, name, userid, date
)
OVERRIDING SYSTEM VALUE
VALUES %s
ON CONFLICT (id) DO NOTHING;
"""

print(f"Bulk insert all {len(rows)} rows into PostgreSQL..")
total = len(rows)
inserted_count = 0

for i in range(0, total, BATCH_SIZE):
    batch = rows[i:i + BATCH_SIZE]
    values = [
        (
            row.Id,
            row.Name,
            row.UserId,
            row.Date
        )
        for row in batch
    ]

    execute_values(pg_cursor, insert_query, values)
    pg_conn.commit()
    inserted_count += len(batch)
    print(f"Committed {inserted_count}/{total} rows...")

print(f"Finished inserting {inserted_count} rows into PostgreSQL.")

# --- Cleanup ---
sql_cursor.close()
sql_conn.close()
pg_cursor.close()
pg_conn.close()
