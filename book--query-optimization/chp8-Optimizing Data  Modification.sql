/* Optimizing Data Modification
**
** DDL - data definition language
** DML - data manipulation language
**
** Postgres used Read Committed Snapshot Isolation for MVCC
**
** WAL is used to ensure durability (ACID)
** All triggers & constraints are maintained in transaction to ensure consistency (ACID)
**
** Postgres stores Pointers in indexes that references to blocks of HEAP.
    This is constrast to SQLServer. In SQLServer, pointers in indexes point to data rows (row locator).
**
** Postgres uses B-Tree structure whereas SQLServer used B+ Tree structure
**
** Postgres does not perform In-Place update. Rather insert a new version of row, 
    and marks the old tuple as delete/dead.
** With this approach, with significant DML operation, relation could end up with lot of dead tuples.
    Dead tuples occupying space bloat the buffers. This lead to IO operations reading more buffers.
** To reduce this negative effect, Postgres uses a technique that sometimes is referred to as HOT (heap only tuples)
    An attempt is made to insert the new version into the same block.
    If the block has sufficient free space and the update does not involve modifying any
    indexed columns, then there is no need to modify any indexes.
**
** WAL - Write Ahead Logging
    The WAL is written sequentially, and on slow rotating drives, sequential
    reads and writes are two orders of magnitude faster than random reads and writes. This
    difference is negligible on SSDs. Although there is no need to wait until all changes are
    written from the cache to the database, commits still must wait until the WAL is flushed.
    As result, committing too frequently can significantly slow down processing.
**
** Even with MVCC, Writers block Writers.
** To get rid of dead tuples, auto vaccuum process is utilized to reutilize the dead tuple space.
**
** VACUUM can cause a substantial increase in I/O activity that might cause poor
    performance for other active sessions. Vacuum can be tuned to spread its impact over
    time, which will reduce the amount of drastic I/O spikes. However, as a result, the VACUUM
    operation will take longer to complete.
**
** It is worth mentioning that the CREATE INDEX operation in PostgreSQL puts an exclusive lock on the table, 
    which can affect other operations. CREATE INDEX CONCURRENTLY takes longer to complete but leaves the table
    accessible to other processes.
**
** The percentage of free space in table blocks can be set using the fillfactor storage
    parameter in the WITH clause of the CREATE TABLE statement. By default, the value of this
    parameter is 100, which tells PostgreSQL to fit as many rows as possible and minimize
    the size of free space in every block.
**
** Referential Integrity and Triggers
** Referential integrity and triggers might slow data manipulation operations is that for each INSERT/UPDATE
    operation on a table with integrity constraints, the database engine has to check whether
    the new values of the constrained columns are present in the respective parent tables,
    thus executing additional implicit SELECT statements.
** If the parent table size is comparable with the size of the child table, the overhead may be more noticeable.
** 
*/