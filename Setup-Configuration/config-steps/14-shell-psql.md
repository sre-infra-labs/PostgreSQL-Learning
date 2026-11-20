## 14. Shell and psql conveniences

Make `sudo -u postgres` sessions show the host and time:

Add to `~postgres/.bashrc` (and make sure `~postgres/.profile` sources it):

```bash
GREEN='\[\033[32m\]'
RED='\[\033[31m\]'
YELLOW='\[\033[33m\]'
BLUE='\[\033[34m\]'
RESET='\[\033[0m\]'
NEWLINE='\n'

PS1="----- ${GREEN}[\$(date +'%Y-%b-%d %H:%M:%S')]${RESET} ${RED}\u${RESET}@${YELLOW}\h${RESET} ${BLUE}(\$(pwd | sed -e 's|.*/||'))${RESET}${NEWLINE}|------------\$ "
unset color_prompt force_color_prompt
```

```bash
# ~postgres/.profile
if [ -f ~/.bashrc ]; then . ~/.bashrc; fi
```

Add to `~/.psqlrc` (see `Setup-Configuration/psql-prompt.sh`):

```text
\set PROMPT1 '%[%033[96m%]%n@%[%033[95m%]%m %[%033[39m%][%`date +%H:%M:%S`] %[%033[92m%](%/) \n%[%033[1;33m%]%R%#%]%[%033[0;39m%]%] '
\set PROMPT2 '%[%033[1;33m%]%R%#%]%[%033[0;39m%]%] '
```

Client tools (make `pg_dump` match the server version):

```bash
sudo apt install -y postgresql-client-<ver>
sudo ln -sfn /usr/lib/postgresql/<ver>/bin/pg_dump /usr/bin/pg_dump
```

Environment variables (`~/.bashrc`):

```bash
export EDITOR=nano
export PGDATABASE=postgres_air
export PGSERVICEFILE=~/.pg_service.conf
export PGPASSWORD='<password>'      # prefer ~/.pgpass (chmod 600) instead
```
