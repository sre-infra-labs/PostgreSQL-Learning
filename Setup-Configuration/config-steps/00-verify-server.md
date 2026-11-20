## 0. Verify the server is up and find the config files

```bash
sudo systemctl status postgresql
sudo -u postgres psql -c 'SELECT version();'
sudo -u postgres psql -c 'SHOW config_file;'
sudo -u postgres psql -c 'SHOW hba_file;'
sudo -u postgres psql -c 'SHOW data_directory;'
```

Set a password for the `postgres` superuser (needed for TCP/password logins):

```sql
ALTER USER postgres PASSWORD 'newpassword';
```

Forgot the password? Connect through the local Unix socket as the OS `postgres` user (`sudo -u postgres psql`) and run the same `ALTER USER`. Source: https://askubuntu.com/a/594002

Create a superuser role named after your OS user (`$USER`) that can log in. `--pwprompt` asks for the password twice, so it is not stored in shell history or in this repo:

```bash
echo "$USER"
sudo -u postgres createuser --superuser --login --pwprompt "$USER"
```

Verify the role (should show `t` for `rolsuper` and `rolcanlogin`):

```bash
sudo -u postgres psql -c "SELECT rolname, rolsuper, rolcanlogin FROM pg_roles WHERE rolname = '$USER';"
```

Local logins as that OS user use peer authentication (no password). Password logins over TCP use the password you just set.
