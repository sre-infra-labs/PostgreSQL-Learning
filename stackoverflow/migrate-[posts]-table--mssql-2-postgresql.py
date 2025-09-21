import pyodbc
import psycopg2
import os
from psycopg2.extras import execute_values

# Params
BATCH_SIZE = 10000

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
sql_conn = pyodbc.connect(sql_server_conn_str)
sql_cursor = sql_conn.cursor()

# --- PostgreSQL connection ---
pg_conn = psycopg2.connect(
    host=os.getenv("TARGET_PGHOST", "localhost"),
    dbname=os.getenv("TARGET_PGDATABASE", "stackoverflow2013"),
    user=os.getenv("TARGET_PGUSER", "postgres"),
    password=os.getenv("TARGET_PGPASSWORD"),
    sslmode="require"
)
pg_cursor = pg_conn.cursor()

# --- Get max id from SQL Server ---
sql_cursor.execute("SELECT MAX(Id) FROM dbo.Posts")
max_id = sql_cursor.fetchone()[0]
print(f"Max ID in dbo.Posts: {max_id}")

insert_query = """
INSERT INTO public.posts (
    id, posttypeid, acceptedanswerid, parentid, creationdate,
    deletiondate, score, viewcount, body, owneruserid,
    ownerdisplayname, lasteditoruserid, lasteditordisplayname,
    lasteditdate, lastactivitydate, title, tags, answercount,
    commentcount, favoritecount, closeddate, communityowneddate,
    contentlicense
)
OVERRIDING SYSTEM VALUE
VALUES %s
ON CONFLICT (id) DO NOTHING;
"""

inserted_count = 0
for start_id in range(1, max_id + 1, BATCH_SIZE):
    end_id = start_id + BATCH_SIZE - 1
    print(f"Fetching batch with Ids from {start_id} to {end_id}...")

    sql_cursor.execute(f"""
        SELECT
            Id, PostTypeId, AcceptedAnswerId, ParentId, CreationDate,
            NULL AS DeletionDate, Score, ViewCount, Body, OwnerUserId,
            NULL AS OwnerDisplayName, LastEditorUserId, LastEditorDisplayName,
            LastEditDate, LastActivityDate, Title, Tags, AnswerCount,
            CommentCount, FavoriteCount, ClosedDate, CommunityOwnedDate,
            NULL AS ContentLicense
        FROM dbo.Posts
        WHERE Id BETWEEN ? AND ?
    """, (start_id, end_id))

    rows = sql_cursor.fetchall()

    if not rows:
        continue

    values = [
        (
            row.Id,
            row.PostTypeId,
            row.AcceptedAnswerId,
            row.ParentId,
            row.CreationDate,
            row.DeletionDate,
            row.Score,
            row.ViewCount,
            row.Body,
            row.OwnerUserId,
            row.OwnerDisplayName,
            row.LastEditorUserId,
            row.LastEditorDisplayName,
            row.LastEditDate,
            row.LastActivityDate,
            row.Title,
            row.Tags,
            row.AnswerCount,
            row.CommentCount,
            row.FavoriteCount,
            row.ClosedDate,
            row.CommunityOwnedDate,
            row.ContentLicense
        )
        for row in rows
    ]

    execute_values(pg_cursor, insert_query, values)
    pg_conn.commit()
    inserted_count += len(values)
    print(f"Inserted and committed {inserted_count} records so far...")

print(f"Finished migrating {inserted_count} posts.")

# Cleanup
sql_cursor.close()
sql_conn.close()
pg_cursor.close()
pg_conn.close()
