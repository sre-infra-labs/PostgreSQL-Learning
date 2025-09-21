import pyodbc
import psycopg2
from psycopg2.extras import execute_values
import os

# Parameters
BATCH_SIZE = 100000

# SQL Server connection
sql_conn_str = (
    f"DRIVER={{ODBC Driver 18 for SQL Server}};"
    f"SERVER={os.getenv('SOURCE_MSSQLHOST', 'localhost')};"
    f"DATABASE={os.getenv('SOURCE_MSSQLDATABASE', 'StackOverflow2013')};"
    f"UID={os.getenv('SOURCE_MSSQLUSER', 'sa')};"
    f"PWD={os.getenv('SOURCE_MSSQLPASSWORD')};"
    "TrustServerCertificate=yes;"
)
sql_conn = pyodbc.connect(sql_conn_str)
sql_cursor = sql_conn.cursor()

# PostgreSQL connection
pg_conn = psycopg2.connect(
    host=os.getenv("TARGET_PGHOST", "localhost"),
    dbname=os.getenv("TARGET_PGDATABASE", "stackoverflow2013"),
    user=os.getenv("TARGET_PGUSER", "postgres"),
    password=os.getenv("TARGET_PGPASSWORD"),
    sslmode="require"
)
pg_cursor = pg_conn.cursor()

# Get max Id from SQL Server
sql_cursor.execute("SELECT MAX(Id) FROM dbo.Comments")
max_id = sql_cursor.fetchone()[0]
print(f"Max Id in SQL Server: {max_id}")

insert_query = """
INSERT INTO public.comments (
    id, creationdate, postid, score, text, userid
)
OVERRIDING SYSTEM VALUE
VALUES %s
ON CONFLICT (id) DO NOTHING;
"""

# Process in batches
for offset in range(1, max_id + 1, BATCH_SIZE):
    upper = offset + BATCH_SIZE - 1
    print(f"Fetching records WHERE Id BETWEEN {offset} AND {upper}...")

    sql_cursor.execute(f"""
        SELECT Id, CreationDate, PostId, Score, Text, UserId
        FROM dbo.Comments
        WHERE Id BETWEEN ? AND ?
    """, offset, upper)

    rows = sql_cursor.fetchall()
    if not rows:
        continue

    values = [
        (
            row.Id,
            row.CreationDate,
            row.PostId,
            row.Score,
            row.Text[:600] if row.Text else None,
            row.UserId
        ) for row in rows
    ]

    execute_values(pg_cursor, insert_query, values)
    pg_conn.commit()
    print(f"Inserted batch ending at Id {upper}. Rows inserted: {len(values)}")

# Cleanup
sql_cursor.close()
sql_conn.close()
pg_cursor.close()
pg_conn.close()
print("Migration complete.")
