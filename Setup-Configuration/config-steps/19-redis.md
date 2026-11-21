## 19. Configure Redis cache server (ryzen9, localhost)

Redis runs on this host as a cache for applications that use the local PostgreSQL server. It listens on localhost only, requires a password, caps its memory, and does not write data to disk by default, so it behaves as a pure cache. If you need Redis data to survive a restart, see 19.6.

Reference: https://redis.io/docs/latest/operate/oss_and_stack/management/config/

### 19.1 Install

```bash
sudo apt update && sudo apt install -y redis-server      # Ubuntu/Debian
sudo dnf install -y redis                                # RHEL/Fedora
redis-server --version
```

Config file: `/etc/redis/redis.conf` (Ubuntu/Debian) or `/etc/redis.conf` (RHEL/Fedora). The service is `redis-server` on Ubuntu/Debian and `redis` on RHEL/Fedora.

### 19.2 Back up the default config

```bash
sudo cp /etc/redis/redis.conf /etc/redis/redis.conf.orig
```

### 19.3 Set the cache options

Apply these to `/etc/redis/redis.conf`. Each `sed` replaces the directive that ships in the default file. The last command checks the result.

```bash
# Listen on localhost only, never on the LAN
sudo sed -i -E 's/^bind .*/bind 127.0.0.1 -::1/' /etc/redis/redis.conf

# Keep protected mode on (default)
sudo sed -i -E 's/^protected-mode .*/protected-mode yes/' /etc/redis/redis.conf

# Cap memory and evict least-recently-used keys when full
sudo sed -i -E 's/^# *maxmemory .*/maxmemory 1gb/' /etc/redis/redis.conf
sudo sed -i -E 's/^# *maxmemory-policy .*/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf

# Pure cache: no RDB snapshots, no AOF
sudo sed -i -E '/^save /d' /etc/redis/redis.conf
echo 'save ""' | sudo tee -a /etc/redis/redis.conf > /dev/null
sudo sed -i -E 's/^appendonly .*/appendonly no/' /etc/redis/redis.conf

# Keep idle client connections from piling up
sudo sed -i -E 's/^timeout .*/timeout 300/' /etc/redis/redis.conf

# Check the values that matter
grep -E '^(bind|protected-mode|maxmemory|maxmemory-policy|save|appendonly|timeout) ' /etc/redis/redis.conf
```

Change `maxmemory` to suit the host. `1gb` is a starting point, not a recommendation for every machine. Check free memory with `free -h` first.

### 19.4 Set a password

Generate a strong password, put it in the config, and keep a copy somewhere safe. Clients need it. Do not commit it to this repo.

```bash
PW=$(openssl rand -base64 32)
sudo sed -i -E "s|^# *requirepass .*|requirepass $PW|" /etc/redis/redis.conf
grep -c '^requirepass ' /etc/redis/redis.conf      # must print 1
echo "$PW"                                           # copy to your password manager, then clear the screen
unset PW
```

If `grep` prints `0`, the config has no `requirepass` line. Add `requirepass <password>` by hand.

### 19.5 Start and enable

```bash
sudo systemctl enable --now redis-server            # RHEL/Fedora: redis
sudo systemctl restart redis-server
systemctl status redis-server --no-pager
```

### 19.6 Persistence (optional)

Skip this section if the cache can be rebuilt after a restart. If you need data to survive a restart, turn on RDB snapshots and undo the `save ""` line from 19.3:

```bash
sudo sed -i -E '/^save ""$/d' /etc/redis/redis.conf
echo 'save 900 1' | sudo tee -a /etc/redis/redis.conf > /dev/null
echo 'save 300 10' | sudo tee -a /etc/redis/redis.conf > /dev/null
sudo systemctl restart redis-server
```

### 19.7 Verify

Set the password for `redis-cli` without putting it on the command line, which would show in `ps` output:

```bash
read -rs -p "Redis password: " REDISCLI_AUTH && export REDISCLI_AUTH
redis-cli ping                                       # PONG
redis-cli CONFIG GET bind
redis-cli CONFIG GET maxmemory-policy
redis-cli INFO memory | grep -E 'used_memory_human|maxmemory_human'
unset REDISCLI_AUTH
```

Check the listening address. Only `127.0.0.1` and `::1` should appear, with port 6379:

```bash
ss -ltn | grep 6379
```

Check that a client without the password is refused:

```bash
redis-cli -h 127.0.0.1 ping                          # NOAUTH error expected
```

Check from another host that the port is closed. Run this from a LAN machine, not from this one:

```bash
nc -zv <ryzen9-lan-ip> 6379                          # connection refused or timed out expected
```

### 19.8 Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `NOAUTH Authentication required` | Client has no password | Set `REDISCLI_AUTH` or pass the password in the client config. |
| `WRONGPASS` | Wrong password | Compare with the value in `requirepass`. |
| `Connection refused` on localhost | Service not running, or wrong port | `systemctl status redis-server`, `ss -ltn \| grep 6379`. |
| Service fails to start after editing the config | Syntax error or bad path | `sudo journalctl -u redis-server -n 30 --no-pager`. Restore `/etc/redis/redis.conf.orig` if needed. |
| `OOM command not allowed when used memory > 'maxmemory'` | `noeviction` policy, or a key that can't be evicted | Check `maxmemory-policy` is `allkeys-lru`. Raise `maxmemory` if the cache is too small. |
| `Failed to bind to port` in the log | Another process uses 6379 | `sudo ss -ltnp \| grep 6379`, then stop that process or change `port`. |
| Data lost after reboot | Expected with `save ""` and `appendonly no` | Use 19.6 if you need persistence. |
| Clients on other hosts can't connect | `bind` is localhost only, by design | Connect through an SSH tunnel, or change `bind` deliberately and open the firewall. This is not recommended for a cache. |

### 19.9 Rollback

```bash
sudo cp /etc/redis/redis.conf.orig /etc/redis/redis.conf
sudo systemctl restart redis-server
```
