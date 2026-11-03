# PostgreSQL Multi-Region PostgreSQL Cluster

# Technologies/Tools to use
- Cloud provider - AWS
- Cloud region - ap-south-1 as primary datacenter (3 patroni nodes forming three node primary patroni cluster)
- Cloud region - us-east-1 as secondary datacenter (1 patroni node forming single node secondary patroni cluster)
- PostgreSQL Replication tools - PostgreSQL 17, Patroni (latest), etcd (on each node), pgbackrest (backup on s3 bucket of current primary region)
- Secondary patroni cluster connected to Primary patroni cluster in cascaded replication setup of patroni (standby_cluster config)
- Writer Endpoint through aws ELB always pointing to leader replica of primary cluster
- Reader Endpoint through aws ELK always pointing to sync_standby replica of primary cluster
- The Writer & Reader Endpoint should you Route 53 dns ajaydwivedi.in that I have already added.
- Then access this writer & reader endpoint from my local network from a docker container running flask app each.
- Create daily expense management tool on this postgresql cluster.
- The writer endpoint to be used by backend for write operation of DBA Inventory.
- The reader container backend will be used for read operation, and building analytical reports
- Build one AI agent on top of this using AWS service that would answer any expense related query.
- 


