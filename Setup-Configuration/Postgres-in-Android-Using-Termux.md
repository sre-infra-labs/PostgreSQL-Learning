# Install PostgreSQL On Android Mobile

## Using the SSH Server

Default SSH port in Termux is 8022.
Default User - u0_a432

```
# install package
pkg update
pkg upgrade
pkg install openssh

    /data/data/com.termux/files/usr/etc/ssh/ssh_host_rsa_key
    /data/data/com.termux/files/usr/etc/ssh/ssh_host_rsa_key.pub
    /data/data/com.termux/files/usr/etc/ssh/ssh_host_ecdsa_key
    /data/data/com.termux/files/usr/etc/ssh/ssh_host_ecdsa_key.pub
    /data/data/com.termux/files/usr/etc/ssh/ssh_host_ed25519_key
    /data/data/com.termux/files/usr/etc/ssh/ssh_host_ed25519_key.pub

# start sshd
sshd

# enable password less ssh
ssh-copy-id -p 8022 u0_a432@ajay-mobile

# take ssh
ssh -p 8022 u0_a432@ajay-mobile

```

## Setup Termux from f-droid
- pkg install postgresql

## Install postgresql on tuxmux
```
pkg update
pkg upgrade

# install
pkg install postgresql

# initialize
initdb $PREFIX/var/lib/pgsql

# start postgresql
pg_ctl -D $PREFIX/var/lib/pgsql start
or
pg_ctl -D /data/data/com.termux/files/usr/var/lib/pgsql -l logfile start

# check status
pg_ctl -D $PREFIX/var/lib/pgsql status

# connect to postgres
psql -d postgres

# Enable all interface connectivity
nano $PREFIX/var/lib/pgsql/postgresql.conf
    listen_addresses = '*'

# Enable all external clients
nano $PREFIX/var/lib/pgsql/pg_hba.conf
    #Added by Ajay
    host    all             all             0.0.0.0/0               scram-sha-256

# Restart postgresql
pg_ctl -D $PREFIX/var/lib/pgsql restart

# connect to ajay-mobile postgresql
psql -h ajay-mobile

# Backup stackoverflow2010 from main machine
pg_dump -h localhost stackoverflow2010 > /tmp/stackoverflow2010.sql

# Restore stackoverflow2010 from main machine
psql -h ajay-mobile stackoverflow2010 < /tmp/stackoverflow2010.sql


```