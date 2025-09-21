# Read active/enabled settings from postgresql.conf

# get postgresql.conf file path
ps -ef | grep post

# read active settings
grep -vE '^\s*#|^\s*$' /etc/postgresql/16/main/postgresql.conf

# create create another file in conf.d directory
sudo -u postgres vim /etc/postgresql/16/main/conf.d/dba.conf


/usr/lib/postgresql/16/bin/pg_ctl start -D /var/lib/postgresql/16/main -l /var/log/postgresql/postgresql-16-main.log 