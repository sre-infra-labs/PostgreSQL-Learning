# PgBouncer

## Install PgBouncer
```
sudo apt install pgbouncer -y

sudo dnf install pgbouncer -y
```

## Get configuration file location

```
dpkg -L pgbouncer | grep pgbouncer.ini
    /etc/pgbouncer/pgbouncer.ini
    /usr/share/doc/pgbouncer/examples/pgbouncer.ini

```

# Edit config file
```
sudo vim /etc/pgbouncer.ini

    [databases]
    stack2013 = host=localhost dbname=stackoverflow2013


sudo systemctl restart pgbouncer.service
```


