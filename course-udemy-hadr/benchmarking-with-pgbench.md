# pgbench

> pgbench is native tool installed with postgresql that can be used for benchmarking postgresql database cluster.

```
# create required objects/tables in [dba] database
pgbench -i -p 5431 dba

    postgres@pgpoc:~$ pgbench -i -p 5431 dba
    dropping old tables...
    NOTICE:  table "pgbench_accounts" does not exist, skipping
    NOTICE:  table "pgbench_branches" does not exist, skipping
    NOTICE:  table "pgbench_history" does not exist, skipping
    NOTICE:  table "pgbench_tellers" does not exist, skipping
    creating tables...
    generating data (client-side)...
    100000 of 100000 tuples (100%) done (elapsed 0.06 s, remaining 0.00 s)
    vacuuming...
    creating primary keys...
    done in 0.19 s (drop tables 0.00 s, create tables 0.00 s, client-side generate 0.12 s, vacuum 0.03 s, primary keys 0.03 s).


# run pgbench with 8 client connections and 25k transactions for each client
pgbench -c 8 -t 25000 -p 5431 dba;

    postgres@pgpoc:~$ pgbench -c 8 -t 25000 -p 5431 dba;
    pgbench (16.9 (Ubuntu 16.9-0ubuntu0.24.04.1))
    starting vacuum...end.
    2025-09-06 20:20:26.417 IST [22374] LOG:  checkpoint starting: time

    transaction type: <builtin: TPC-B (sort of)>
    scaling factor: 1
    query mode: simple
    number of clients: 8
    number of threads: 1
    maximum number of tries: 1
    number of transactions per client: 25000
    number of transactions actually processed: 200000/200000
    number of failed transactions: 0 (0.000%)
    latency average = 4.715 ms
    initial connection time = 15.052 ms
    tps = 1696.668977 (without initial connection time)


psql -p 5431
-- Top top 10 long running queries
SELECT round((100 * total_exec_time / sum(total_exec_time)
           OVER ())::numeric, 2) percent,
           round(total_exec_time::numeric, 2) AS total,
           calls,
           round(mean_exec_time::numeric, 2) AS mean,
           substring(query, 1, 200)
 FROM  pg_stat_statements
           ORDER BY total_exec_time DESC
           LIMIT 10;

     percent |   total   | calls  | mean  |                                              substring
    ---------+-----------+--------+-------+------------------------------------------------------------------------------------------------------
       60.87 | 457144.32 | 200000 |  2.29 | UPDATE pgbench_branches SET bbalance = bbalance + $1 WHERE bid = $2
       38.26 | 287320.09 | 200000 |  1.44 | UPDATE pgbench_tellers SET tbalance = tbalance + $1 WHERE tid = $2
        0.51 |   3841.21 | 200000 |  0.02 | UPDATE pgbench_accounts SET abalance = abalance + $1 WHERE aid = $2
        0.18 |   1364.12 | 200000 |  0.01 | SELECT abalance FROM pgbench_accounts WHERE aid = $1
        0.14 |   1016.79 | 200000 |  0.01 | INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP)
        0.01 |     66.46 | 200001 |  0.00 | commit
        0.01 |     64.82 |      1 | 64.82 | copy pgbench_accounts from stdin with (freeze on)
        0.01 |     59.01 | 200001 |  0.00 | begin
        0.01 |     50.42 |      1 | 50.42 | create database dba
        0.00 |     31.44 |      1 | 31.44 | vacuum analyze pgbench_accounts
```