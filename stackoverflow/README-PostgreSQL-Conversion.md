# PostgreSQL Conversion of Stack Overflow SQL Server Procedures

This directory contains the PostgreSQL conversion of the SQL Server procedures from `Setup-RandomQ.sql`.

## Files

1. **Setup-RandomQ-PostgreSQL.sql** - Main file with table creation and first batch of functions
   - Tags and PostTags table creation and population
   - make_parallel() helper function
   - rpt_TopUsers_ByLocation report function
   - First 6 query functions (usp_Q785, Q7521, Q36660, Q949, Q466, Q947, Q3160, Q6627)

2. **Setup-RandomQ-PostgreSQL-Part2.sql** - Additional query functions
   - usp_Q6772, Q6856, Q952, Q975, Q8116, Q4038

3. **Setup-RandomQ-PostgreSQL-Part3.sql** - More query functions  
   - usp_Q2357, Q951, Q1433, Q7672, Q1256, Q877, Q886

4. **Setup-RandomQ-PostgreSQL-Part4.sql** - Additional query functions
   - usp_Q946, Q6607, Q1080, Q6134, Q2777, Q1933, Q1181, Q10418

5. **Setup-RandomQ-PostgreSQL-Part5.sql** - Final functions and main dispatcher
   - usp_Q1075286, Q1075285
   - usp_RandomQ - Main dispatcher function

## Installation

Run the scripts in order on the PostgreSQL database `stackoverflow2013`:

```bash
# Create all functions
psql -d stackoverflow2013 -f Setup-RandomQ-PostgreSQL.sql
psql -d stackoverflow2013 -f Setup-RandomQ-PostgreSQL-Part2.sql
psql -d stackoverflow2013 -f Setup-RandomQ-PostgreSQL-Part3.sql
psql -d stackoverflow2013 -f Setup-RandomQ-PostgreSQL-Part4.sql
psql -d stackoverflow2013 -f Setup-RandomQ-PostgreSQL-Part5.sql
```

Or combine all scripts:

```bash
cat Setup-RandomQ-PostgreSQL*.sql | psql -d stackoverflow2013
```

## Usage

### Execute a specific query function

```sql
-- Get upvotes by tag for user 12345
SELECT * FROM dbo.usp_q785(12345);

-- Get top users by location
SELECT * FROM dbo.rpt_topusers_bylocation('Reading, United Kingdom', '2011-09-01'::DATE, '2011-10-01'::DATE);

-- Get most downvoted questions
SELECT * FROM dbo.usp_q36660();
```

### Execute random query

```sql
-- Execute a random query from the set
SELECT * FROM dbo.usp_randomq();
```

## Key Conversions from SQL Server to PostgreSQL

| SQL Server | PostgreSQL |
|-----------|-----------|
| `IDENTITY(1,1)` | `SERIAL` or `GENERATED ALWAYS AS IDENTITY` |
| `STRING_SPLIT()` | `STRING_TO_ARRAY() + UNNEST()` |
| `ISNULL()` | `COALESCE()` |
| `DATEPART()` | `EXTRACT()` |
| `FORMAT()` | `TO_CHAR()` |
| `DATEDIFF()` | Interval arithmetic |
| `TOP n` | `LIMIT n` |
| `FOR XML PATH` | `STRING_AGG()` |
| Temp tables (`#table`) | CTEs or temporary tables |
| Stored procedures | Functions (RETURNS TABLE) |
| `CREATE OR ALTER PROC` | `CREATE OR REPLACE FUNCTION` |

## Notes

- All functions are schema-qualified as `dbo.*` functions
- Functions use `LANGUAGE SQL STABLE` for better optimization
- Table-returning functions use `RETURNS TABLE` syntax
- Set operations properly use PostgreSQL conventions
- No transaction control needed; functions are atomic

## Testing

After installation, verify functions are created:

```sql
-- List all created functions
SELECT routine_name 
FROM information_schema.routines 
WHERE routine_schema = 'dbo' 
  AND routine_name LIKE 'usp_%' 
ORDER BY routine_name;

-- Count total procedures converted
SELECT COUNT(*) FROM information_schema.routines 
WHERE routine_schema = 'dbo' AND routine_name LIKE 'usp_%';
```

## Original Source

Converted from: `stackoverflow/Setup-RandomQ.sql`
Based on: https://github.com/BrentOzar/SqlQueryStress
Used for: Stack Overflow workload testing and analysis
