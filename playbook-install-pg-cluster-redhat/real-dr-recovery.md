1) Initial Situation
----------------------------
dc1 - pg-cls2-prod - primary - TL31
dc2 - pg-cls2-dr   - standby - T31

2) !! DISASTER !! happen
- all nodes of dc1 went offline
- Consul server reflecting dc1 cluster service went down

3) Promote dc2 cluster as new Primary
```
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
    -a "patronictl -c /etc/patroni/patroni.yml edit-config --set standby_cluster=null --force"
```
dc2 - pg-cls2-dr   - Primary - T32

4) Now, at present dc2 cluster is new primary, and dc1 cluster which is offline was in primary when it went offline

5) On new dc2 primary cluster, do some database stuff
```
create database dba2 with owner postgres;
\c dba2
create table person (name varchar(50), city varchar(50));
insert into person select 'Ajay', 'Nagpur';
insert into person select 'Raj', 'Bangalore';
```
6) At this point in time, below are timelines
dc1 cluster - old primary - TL 31
dc2 cluster - new primary - TL 32

7) Old dc1 cluster that was old primary comes online

8) Now, we have 2 primary cluster one on each dc1 and dc2 with below timeline
dc1 cluster - primary - TL 33
dc2 cluster - primary - TL 32

!! SPLIT BRAIN !! Happened

Solutions from here
--------------------
s1) Demote old primary dc1 cluster to Standby cluster
s2) Demote new primary dc2 cluster to Standby cluster. `pg_rewind` is supposed

Solution s1
---------------------

s1.1) Demote old dc1 Primary cluster to Standby cluster
```
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
    -a "patronictl -c /etc/patroni/patroni.yml failover pg-cls2-dr --candidate pg-cls2-dr1 --force"

After change leader node to node1, dc2 is TL32-->TL34.

ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
    -a "patronictl -c /etc/patroni/patroni.yml edit-config --set standby_cluster='{host: pg-cls2-dr1, port: 5432}' --force"

After converting dc1 to standby, dc1 is TL33-->TL34.

At this point, leader node of dc1 which is new standby is in "streaming" state.
We validated all dbs for any data loss.
NO data loss found.

```

s1.2) Since other 2 nodes of dc2 cluster, new standby cluster, still have "in archive recovery" state, reinit them
```
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a \
    "patronictl -c /etc/patroni/patroni.yml reinit pg-cls2-prod pg-cls2-prod0 --force"
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a \
    "patronictl -c /etc/patroni/patroni.yml reinit pg-cls2-prod pg-cls2-prod1 --force"

```

