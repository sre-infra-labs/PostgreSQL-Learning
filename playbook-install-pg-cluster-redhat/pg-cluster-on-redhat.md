# Install PostgreSQL Cluster (RHEL)
- [Patroni and pgBackRest combined](https://pgstef.github.io/2022/07/12/patroni_and_pgbackrest_combined.html)
> PostgreSQL 16 + Patroni + pgBackRest + Consul + SMB shared storage (posix repo)

## Architecture

| Component | DC1 (prod) | DC2 (dr) |
|-----------|-----------|---------|
| Consul / HAProxy | `pg-consul-rhel` (192.168.100.41) | — |
| Primary Cluster | `pg-cls2-prod0/1/2` (192.168.100.47-49) | — |
| Standby Cluster | — | `pg-cls2-dr0/1/2` (192.168.200.47-49) |
| Hypervisor / SMB host | `ryzen9` (192.168.100.1) | `ryzen9` (192.168.200.1) |
| SMB share path | `//192.168.100.1/share-stalestorage` | `//192.168.200.1/share-stalestorage` |
| Mount point | `/stale-storage/share-stalestorage` | `/stale-storage/share-stalestorage` |
| pgBackRest backup path | `/stale-storage/share-stalestorage/pgbackrest_backups` | same |
| pgBackRest stanza | `pg-cls2` | `pg-cls2` |
| pgBackRest repo type | `posix` (CIFS/SMB mount) | `posix` (CIFS/SMB mount) |

> **Note on cifs-utils:** RHEL nodes have no internet access. The RPM
> `cifs-utils-7.5-2.el9.x86_64.rpm` must be pre-downloaded on the Ansible controller
> at `/tmp/cifs-rpms/` before running the playbooks. Download it from:
> `https://mirror.stream.centos.org/9-stream/BaseOS/x86_64/os/Packages/cifs-utils-7.5-2.el9.x86_64.rpm`

# [Patroni - HA multi datacenter](https://patroni.readthedocs.io/en/latest/ha_multi_dc.html#asynchronous-replication)

![Patroni HA with multi datacenter - Architecture Diagram](../.images/patroni-multi-datacenter-ha-architecture.png)

![Patroni HA with multi datacenter - Result](../.images/patroni-multi-datacenter-ha-result.png)

![Patroni Services on Consul Server](../.images/patroni-services-on-consul-server.png)

## Does all replicas in multi dc cluster setup has same system identifier
```
ansible all -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "/usr/pgsql-16/bin/pg_controldata -D /var/lib/pgsql/16/data | grep system"
```

# pgBackRest — SMB / Posix Repository Setup

The cluster uses a CIFS/SMB share on the hypervisor (`ryzen9`) instead of S3.
Run `playbook-update-pgbackrest-smb.yml` to (re-)apply the configuration to a running cluster:

```bash
# Pre-requisite: RPM must exist on the controller
sudo mkdir -p /tmp/cifs-rpms
sudo curl -fsSL \
  https://mirror.stream.centos.org/9-stream/BaseOS/x86_64/os/Packages/cifs-utils-7.5-2.el9.x86_64.rpm \
  -o /tmp/cifs-rpms/cifs-utils-7.5-2.el9.x86_64.rpm

# Run the migration playbook
cd playbook-install-pg-cluster-redhat
ansible-playbook -i hosts__multi_datacenter.yml playbook-update-pgbackrest-smb.yml \
  --vault-password-file=vault-pass

# After the playbook succeeds — create the stanza on the primary leader
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "sudo -u postgres pgbackrest --stanza=pg-cls2 --log-level-console=info stanza-create"

# Take a full backup
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "sudo -u postgres pgbackrest --stanza=pg-cls2 --type=full backup"

# Verify
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
  -a "sudo -u postgres pgbackrest --stanza=pg-cls2 info"
```

# Failover from dc1 (`pg-cls2-prod`) to dc2 (`pg-cls2-dr`)
```
# Check present leaders on Clusters
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "patronictl -c /etc/patroni/patroni.yml list"
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "patronictl -c /etc/patroni/patroni.yml list"

# Failover to preferred leaders, and wait for healthy state (streaming, running), and timeline
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
    -a "patronictl -c /etc/patroni/patroni.yml failover pg-cls2-prod --candidate pg-cls2-prod1 --force"
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
    -a "patronictl -c /etc/patroni/patroni.yml failover pg-cls2-dr --candidate pg-cls2-dr1 --force"

# Put current Primary Cluster to maintenance mode
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
    -a "patronictl -c /etc/patroni/patroni.yml pause pg-cls2-prod --wait"

# On new Primary Cluster, remove standby_cluster config using patronictl
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
    -a "patronictl -c /etc/patroni/patroni.yml edit-config --set standby_cluster=null --force"

# Above step should should convert the old Standby Cluster to Primary Cluster. Verify using below command
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "patronictl -c /etc/patroni/patroni.yml list"

# IMPORTANT: Wait for new Primary Cluster to have "streaming" or "running" state

# Run below command if new leader is not correct
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
    -a "patronictl -c /etc/patroni/patroni.yml failover pg-cls2-dr --candidate pg-cls2-dr1 --force"

# Now, asssuming the old Primary comes up, and is still in Primary Cluster role

# On old Primary Cluster, to demote to Standby Cluster, add standby_cluster config using patronictl
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
    -a "patronictl -c /etc/patroni/patroni.yml edit-config --set standby_cluster='{host: pg-cls2-dr1, port: 5432}' --force"

# Above step should should convert the old Primary Cluster to Standby Cluster. Verify
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "patronictl -c /etc/patroni/patroni.yml list"

# Remove new Standby Cluster from maintenance mode
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "patronictl -c /etc/patroni/patroni.yml resume pg-cls2-prod --wait"

# With above steps, All the nodes are supposed to go have "in archive recovery" -> "streaming" state
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "patronictl -c /etc/patroni/patroni.yml list"

# Once New Standby Cluster leader node is back to "steaming" state, reinit other Standby Cluster nodes if taking time to have state transition from "in archive recovery" to "steaming"
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a \
    "patronictl -c /etc/patroni/patroni.yml reinit pg-cls2-prod pg-cls2-prod0 --force"
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a \
    "patronictl -c /etc/patroni/patroni.yml reinit pg-cls2-prod pg-cls2-prod2 --force"

# Failover to preferred leaders, and wait for healthy state (streaming, running), and timeline
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
    -a "patronictl -c /etc/patroni/patroni.yml failover pg-cls2-dr --candidate pg-cls2-dr1 --force"

# Validate both cluster together. Verify Role, State, and Timeline
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "patronictl -c /etc/patroni/patroni.yml list"
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "patronictl -c /etc/patroni/patroni.yml list"

# Validate backup on new Primary
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "sudo -iu postgres pgbackrest --stanza=pg-cls2 check"

  # Error: has a stanza-create been performed?
  ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "sudo -iu postgres pgbackrest --stanza=pg-cls2 stanza-create"
  ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "sudo -iu postgres pgbackrest --stanza=pg-cls2 backup"
  ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "sudo -iu postgres pgbackrest --stanza=pg-cls2 check"
  ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "sudo -iu postgres pgbackrest --stanza=pg-cls2 info"


```

# Failback to dc1 (`pg-cls2-prod`) from dc2 (`pg-cls2-dr`)
```
# Check present leaders on Clusters
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "patronictl -c /etc/patroni/patroni.yml list"
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "patronictl -c /etc/patroni/patroni.yml list"

# Failover to preferred leaders, and wait for healthy state (streaming, running), and timeline
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
    -a "patronictl -c /etc/patroni/patroni.yml failover pg-cls2-prod --candidate pg-cls2-prod1 --force"
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
    -a "patronictl -c /etc/patroni/patroni.yml failover pg-cls2-dr --candidate pg-cls2-dr1 --force"

# Put current Primary Cluster to maintenance mode
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
    -a "patronictl -c /etc/patroni/patroni.yml pause pg-cls2-dr --wait"

# On new Primary Cluster, remove standby_cluster config using patronictl
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
    -a "patronictl -c /etc/patroni/patroni.yml edit-config --set standby_cluster=null --force"

# Above step should should convert the old Standby Cluster to Primary Cluster. Verify using below command
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "patronictl -c /etc/patroni/patroni.yml list"

# IMPORTANT: Wait for new Primary Cluster to have "streaming" or "running" state

# Run below command if new leader is not correct
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
    -a "patronictl -c /etc/patroni/patroni.yml failover pg-cls2-prod --candidate pg-cls2-prod1 --force"

# Now, asssuming the old Primary comes up, and is still in Primary Cluster role

# On old Primary Cluster, to demote to Standby Cluster, add standby_cluster config using patronictl
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
    -a "patronictl -c /etc/patroni/patroni.yml edit-config --set standby_cluster='{host: pg-cls2-prod1, port: 5432}' --force"

# Above step should should convert the old Primary Cluster to Standby Cluster. Verify
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "patronictl -c /etc/patroni/patroni.yml list"

# Remove new Standby Cluster from maintenance mode
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "patronictl -c /etc/patroni/patroni.yml resume pg-cls2-dr --wait"

# With above steps, All the nodes are supposed to go have "in archive recovery" -> "streaming" state
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "patronictl -c /etc/patroni/patroni.yml list"

# Failover to preferred leaders, and wait for healthy state (streaming, running), and timeline
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell \
    -a "patronictl -c /etc/patroni/patroni.yml failover pg-cls2-dr --candidate pg-cls2-dr1 --force"

# Validate both cluster together. Verify Role, State, and Timeline
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "patronictl -c /etc/patroni/patroni.yml list"
ansible dc2_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "patronictl -c /etc/patroni/patroni.yml list"

# Validate backup on new Primary
ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "sudo -iu postgres pgbackrest --stanza=pg-cls2 check"

  # Error: has a stanza-create been performed?
  ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "sudo -iu postgres pgbackrest --stanza=pg-cls2 stanza-create"
  ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "sudo -iu postgres pgbackrest --stanza=pg-cls2 backup"
  ansible dc1_leader -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "sudo -iu postgres pgbackrest --stanza=pg-cls2 check"


```

# Troubleshooting

```
# check what is using port 8008
sudo ss -lntp | grep 8008

# check if master DNS is working
dig @192.168.100.41 -p 8600 master.pg-cls2-prod.service.consul
dig master.pg-cls2-prod.service.dc1.lab.com

# check consul config
sudo grep -B 2 -A 3 "agent" /etc/consul.d/consul.hcl

# create pgbackrest stanza (run on primary leader only)
sudo -u postgres pgbackrest --stanza=pg-cls2 --log-level-console=info stanza-create

# check pgbackrest archive and backup status
sudo -u postgres pgbackrest --stanza=pg-cls2 --log-level-console=info check
sudo -u postgres pgbackrest --stanza=pg-cls2 info

SELECT pid, client_addr, state, sync_state, write_lag, replay_lag
FROM pg_stat_replication;

# On Standby Cluster leader, Check for redo & checkpoint LSN, and whether they are moving forward
tail -n 1000 -f postgresql-Thu.log  | grep redo

# On Standby Cluster leader, Check what WAL it is waiting for
grep "requested" postgresql-Thu.log

# for consul error, its better to remove Key/Value for service in consul

# -------------------------------------------------------
# SMB share troubleshooting
# -------------------------------------------------------

# Check if the SMB share is mounted on a node
mount | grep stale-storage
df -h /stale-storage/share-stalestorage

# Re-mount if missing (DC1)
sudo mount -t cifs //192.168.100.1/share-stalestorage /stale-storage/share-stalestorage \
  -o guest,uid=$(id -u postgres),gid=$(id -g postgres),file_mode=0770,dir_mode=0770,mfsymlinks

# Re-mount if missing (DC2)
sudo mount -t cifs //192.168.200.1/share-stalestorage /stale-storage/share-stalestorage \
  -o guest,uid=$(id -u postgres),gid=$(id -g postgres),file_mode=0770,dir_mode=0770,mfsymlinks

# Test write access as postgres
sudo -u postgres touch /stale-storage/share-stalestorage/.write_test && echo "OK"

# List backup contents on the SMB share
ls -lh /stale-storage/share-stalestorage/pgbackrest_backups/backup/pg-cls2/
ls -lh /stale-storage/share-stalestorage/pgbackrest_backups/archive/pg-cls2/

# Clean up backup/archive on SMB share (use with caution!)
sudo rm -rf /stale-storage/share-stalestorage/pgbackrest_backups/backup/pg-cls2/
sudo rm -rf /stale-storage/share-stalestorage/pgbackrest_backups/archive/pg-cls2/

# -------------------------------------------------------
# Install cifs-utils offline (RHEL nodes have no internet)
# -------------------------------------------------------
# On the Ansible controller — download the RPM once:
sudo mkdir -p /tmp/cifs-rpms
sudo curl -fsSL \
  https://mirror.stream.centos.org/9-stream/BaseOS/x86_64/os/Packages/cifs-utils-7.5-2.el9.x86_64.rpm \
  -o /tmp/cifs-rpms/cifs-utils-7.5-2.el9.x86_64.rpm

# Push and install via Ansible:
ansible all -i hosts__multi_datacenter.yml -u ansible -b \
  -m copy -a "src=/tmp/cifs-rpms/cifs-utils-7.5-2.el9.x86_64.rpm dest=/tmp/ mode=0644"
ansible all -i hosts__multi_datacenter.yml -u ansible -b \
  -m shell -a "rpm -q cifs-utils || rpm -i /tmp/cifs-utils-7.5-2.el9.x86_64.rpm"

```

# Adhoc Ansible Command for Reset

```
# Help on ansible-doc
ansible-doc -l
ansible-doc file

# stop patroni on all servers. "-u" means remote user. "-b" means become.
ansible dc1 -i hosts__multi_datacenter.yml -m service -a "name=patroni state=stopped" -u ansible -b
ansible dc1 -i hosts__multi_datacenter.yml -m shell -a "rm -rf /var/lib/pgsql/16/data/* /var/spool/pgbackrest/*" -u ansible -b

sudo -u postgres pgbackrest --stanza=pg-cls2 --type=standby --target-timeline=22 restore --force
sudo -u postgres cat /var/lib/pgsql/16/data/postgresql.auto.conf


# on leader node, delete contents of pgdata directory
sudo rm -rf /var/lib/pgsql/16/data/*

# on leader node, restore pgdata using pgbackrest
sudo -u postgres pgbackrest --stanza=pg-cls2 --delta restore
    or
    # when error: "target timeline 17 forked from backup timeline 16 at 0/4e000000 which is before backup lsn of 0/50000028"
    pgbackrest --stanza=pg-cls2 restore --force --type=immediate
    or
    pgbackrest --stanza=pg-cls2 restore --force --archive-mode=off
    or
    # force timeline similar to Primary Cluster
    pgbackrest --stanza=pg-cls2 --type=standby --target-timeline=22 restore --force




# on leader node, start patroni
systemctl restart patroni
systemctl status patroni

# Ensure state for leader node should be in 'streaming' or 'in archive recovery'
# Ensure TL for Standby Cluster leader is matching with TL for Primary Cluster leader
# Once TL becomes same, then we can start patroni on other nodes. Then reinit other nodes

# start patroni on all servers. "-u" means remote user. "-b" means become.
ansible dc1 -i hosts__multi_datacenter.yml -m service -a "name=patroni state=started" -u ansible -b

# reinit command
patronictl -c /etc/patroni/patroni.yml reinit <cluster_name> <member_name> --force
patronictl -c /etc/patroni/patroni.yml list

# reboot hosts
ansible all -i hosts.yml -m reboot -u ansible -b


```

patronictl -c /etc/patroni/patroni.yml reinit pg-cls2-dr pg-cls2-dr2 --force
patronictl -c /etc/patroni/patroni.yml reinit pg-cls2-prod pg-cls2-prod2 --force

tail -f -n 100 /var/log/postgresql/postgresql-Fri.log

mkdir -p /var/spool/pgbackrest
chown postgres:postgres /var/spool/pgbackrest



