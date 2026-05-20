# [Proper PostgreSQL Parameters to Prevent Poor Performance | Greg Dostatni | Postgres World Webinars](https://youtu.be/CYJvZJP_lZA?feature=shared)

## Workloads and Data
![Type of Workloads and Data](images--pg-parameters-to-prevent-poor-performance/workload-and-data.png)

## OLTP vs OLAP?
  - How much data a user query processes?
- OLTP - 20 ms
- Medium analytical query - 20 seconds
- Datawarehouse - 20 hours

## Reading of Data
![Reading of Data](images--pg-parameters-to-prevent-poor-performance/reading-of-data-components.png)

## Writing of Data
![Writing of Data](images--pg-parameters-to-prevent-poor-performance/writing-of-data-components.png)

> Keep IO for Writes as Read can be satisfied from Shared Buffers if planned properly

## Parameters
![Parameters](images--pg-parameters-to-prevent-poor-performance/parameters.png)

## shared_buffers
- A global memory pool allocated once at PostreSQL startup
- Used for caching table and index pages shared across all sessions

![shared_buffers](images--pg-parameters-to-prevent-poor-performance/shared_buffers.png)

## work_mem
- A per-operation, per-query memory allocation
- Used for sorting, hashing, materialization, not from `shared_buffers`.

![work_mem](images--pg-parameters-to-prevent-poor-performance/work_mem.png)

## max_connections
![max_connections](images--pg-parameters-to-prevent-poor-performance/max_connections.png)

## effective_cache_size

- It is not a memory allocation parameter.
- Instead, it is a query planner hint that tells PostgreSQL how much memory is available for caching data across:
    - PostgreSQL shared_buffers
    - OS file system cache

![effective_cache_size](images--pg-parameters-to-prevent-poor-performance/effective_cache_size.png)

## What If?

### What is OOM Killer (Out of Memory Killer)?
  - > Check point 5 below

![What If?](images--pg-parameters-to-prevent-poor-performance/what_if.png)

## Vacuum

![vacuum](images--pg-parameters-to-prevent-poor-performance/vacuum.png)

## random_page_cost

![random_page_cost](images--pg-parameters-to-prevent-poor-performance/random_page_cost.png)

## Indexes

![Indexes](images--pg-parameters-to-prevent-poor-performance/indexes.png)

## Connection pooling

![Connection pooling](images--pg-parameters-to-prevent-poor-performance/connection_pooling.png)

## Caching

> Best work is the work you can avoid!

![caching](images--pg-parameters-to-prevent-poor-performance/caching.png)




