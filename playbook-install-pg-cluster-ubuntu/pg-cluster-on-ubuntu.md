# Install PostgreSQL Cluster
- [Patroni and pgBackRest combined](https://pgstef.github.io/2022/07/12/patroni_and_pgbackrest_combined.html)
> PostgreSQL + Patroni + pgBackRest + Conul + s3/local repo

# Troubleshooting

## Check cluster health
```
cd ~/GitHub/PostgreSQL-Learning/playbook-install-pg-cluster-ubuntu

# check patroni cluster health
ansible pg-cls1-prod1 -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "patronictl -c /etc/patroni/patroni.yml list"

# restart consul
ansible pg-cls1-prod* -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "systemctl restart consul"

# restart patroni
ansible pg-cls1-prod* -i hosts__multi_datacenter.yml -u ansible -b -m shell -a "systemctl restart patroni"
```

