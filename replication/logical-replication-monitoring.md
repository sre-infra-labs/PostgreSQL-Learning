# Monitoring Logical Replication

## On publisher
```
\x

\c db_source

select * from pg_stat_replication;

select * from pg_publication;

```

## On subscriber
```
\x

\c db_destination

select * from pg_subscription;
```

## Reset Subscription
```
\c db_destination

drop subscription sub_all_tables;

truncate t1;

# create subscription
create subscription sub_all_tables connection 'user=replication password=LearnPostgreSQL host=pg-pub port=5432 dbname=db_source' publication all_tables_pub;
```

## How to Drop Subscription In case Publisher not available
```
\c destination_db

alter subscription sub_all_tables disable;

alter subscription sub_all_tables set (slot_name = NONE);

drop subscription sub_all_tables;
```



