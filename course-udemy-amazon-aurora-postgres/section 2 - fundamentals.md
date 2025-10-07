# PostgreSQL Fundamentals

- Data is stored in filesystem in attached storage
  - Data is stored in one or more 1 gb files
  - Data files are read/written to in 8KB pages
  - Page a.k.a. Block or blk

## PostgreSQL Server Process
  - Parent of all processes related to DB cluster
  - For each client connection, PSP forks a backend process to handle client request
  - Max connection is controlled using max_connection setting which is set based on Server compute

![postgres-server-process](../.images/postgres-server-process.png)

## Query Processing
![query-processing](../.images/query-processing.png)

- Parser - parse tree is created
- Analyzer - Query tree is created
- Rewriter - Rules are applied
- Planner - Execution instructions are created
- Executor - Executes all instructions to produce results

## Query Processing: Planner | Optimizer

![query-processing-planner-stats-subsystem](../.images/query-processing-planner-stats-subsystem.png)

- Planner uses the PG stats subsystem to generate query plan
- Stats may be updated using the `ANALYZE` command
- Query plan may be inspected using the `EXPLAIN` command

## Query Processing: Executor

![query-processing-executor](../.images/query-processing-executor.png)

- Executor runs the instructions in the query plan to generate result set.
- Shared Buffers/Buffer pool helps in reducing disk subsystem IO by caching data pages
- Other memory segments are using used by Executor to carry out specific task
  - temp buffers -> 
  - work mem -> for sort or hash in queries
  - maintenance mem -> for maintenance task like analyze, reindexing

## Buffer cache hit ratio

- Ratio of requests served from buffer pool and total requests

`Hit Ratio = (Blks_hit) / (Blks_hit + Blks_read)`

- Size controlled using shared_buffers

