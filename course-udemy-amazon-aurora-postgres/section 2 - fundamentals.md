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

## Write Ahead Log (WAL)

- Commit success is sent after transaction log records are added to WAL
- Each WAL record contains the transaction log records (XLOG Record)
- Each XLOG has a unique Log Sequence Number (LSN)
- XLOG are managed in WAL segments (16 MB files)
- A transaction is marked committed only after write to WAL
- Crash recovery uses WAL to recreate state of DB

![wal-mechanism](../.images/wal-mechanism.png)

## Checkpointing - Checkpointer

- Initailly PSP (postres server process) writes DMS changes in shared_buffers & WAL.
- But eventually these dirty shared buffers are pushed to disk. This process is called "Checkpointing"
- The background process responsible for checkpointing is "Checkpointer"
- Checkpointer starts with adding a REDO point in memory.
  - This REDO point refers to the last transaction log that was included in last checkpointing.
- Checkpointer add a CHECKPOINT record to the WAL.
  - Now, all the WAL entries between REDO point and CHECKPOINT are candidates for data updates
  - In meantime, new wal records may come post CHECKPOINT, but they won't be part of current checkpointing operation
- Applies changes to data files
- Updates `pg_control` file with LSN of CHECKPOINT point
  - This file has all the information required for crash recovery

![checkpointing](../.images/checkpointing.png)

## Checkpoint Frequency

- Controlled by way of timeout & WAL log size
- May also be initiated using checkpoint command

```
show checkpoint_timeout # default 5 minutes
show max_wal_size; # default 1 gb

```

## WAL Archiver

- Archives the WAL files that are no more needed into set physical location on filesytem
  - Frees up the space
  - Archived wal(s) may be used for recreating the database

## Crash Recovery (REDO Process)

- After postgres process crash, a panic message is logged in error log
- Recovery process starts with applying the WAL/XLOGs after the last checkpoint
- For crash recovery, PSP reads `pg_control` file, and starts from last CHECKPOINT record
- Recovery time depends on number of pending XLOG

## Background writer

- Writes the dirty pages in pool to the persistent storage

![background-writer](../.images/background-writer.png)


