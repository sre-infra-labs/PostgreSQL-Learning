# Single Node Consul Cluster Setup
- [Consul Deployment Guide](https://developer.hashicorp.com/consul/tutorials/production-vms/deployment-guide)
- [How To Setup Consul Cluster on CentOS / RHEL 7/8](https://computingpost.medium.com/how-to-setup-consul-cluster-on-centos-rhel-7-8-7c3122c5ed7)
- [How to Install Consul Server on Ubuntu](https://www.atlantic.net/vps-hosting/how-to-install-consul-server-on-ubuntu/)

## Install Consul package
```
# Configure Repo for Consul
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo

# install latest consul
sudo yum -y install consul

# verify installation
consul --version
```

## Bootstrap and start Consul cluster
```
## Create a consul system user/group
sudo groupadd --system consul
sudo useradd -s /sbin/nologin --system -g consul consul

## Create consul data and configurations directory and set ownership to consul user
sudo mkdir -p /var/lib/consul /etc/consul.d
sudo chown -R consul:consul /var/lib/consul /etc/consul.d
sudo chmod -R 775 /var/lib/consul /etc/consul.d

## Setup DNS or edit /etc/hosts file to configure hostnames for all servers ( set on all nodes).
sudo vim /etc/hosts

    192.168.100.41 pg-consul-rhel.lab.com pg-consul-rhel

## sudo vim /etc/systemd/system/consul.service

    # Consul systemd service unit file
    [Unit]
    Description=Consul Service Discovery Agent
    Documentation=https://www.consul.io/
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=simple
    User=consul
    Group=consul
    ExecStart=/usr/bin/consul agent -server -ui \
        -advertise=192.168.100.41 \
        -bind=192.168.100.41 \
        -data-dir=/var/lib/consul \
        -node=pg-consul-rhel \
        -config-dir=/etc/consul.d
    ExecReload=/bin/kill -HUP $MAINPID
    KillSignal=SIGINT
    TimeoutStopSec=5
    Restart=on-failure
    SyslogIdentifier=consul

    [Install]
    WantedBy=multi-user.target

## Update Consul Configuration for Single Node
# sudo vim /etc/consul.d/consul.hcl

# Added by Ajay
server = true
bootstrap_expect = 1
ui = true

bind_addr = "192.168.100.41"
client_addr = "0.0.0.0"

acl {
  enabled = true
  default_policy = "allow"
  enable_token_persistence = true
}


## Allow consul ports on the firewall
# TCP ports
sudo firewall-cmd --permanent --add-port=8300/tcp
sudo firewall-cmd --permanent --add-port=8301/tcp
sudo firewall-cmd --permanent --add-port=8302/tcp
sudo firewall-cmd --permanent --add-port=8400/tcp
sudo firewall-cmd --permanent --add-port=8500/tcp
sudo firewall-cmd --permanent --add-port=8600/tcp
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp

# UDP ports
sudo firewall-cmd --permanent --add-port=8301/udp
sudo firewall-cmd --permanent --add-port=8302/udp
sudo firewall-cmd --permanent --add-port=8600/udp

# Apply changes
sudo firewall-cmd --reload

# Now bootstrap ACLs
consul acl bootstrap

    [saanvi@pg-consul-rhel ~]consul acl bootstrapap
    AccessorID:       91e6xxxx-xxxx-xxxx-xxxx-xxxxxxx29044
    SecretID:         d0f2xxxx-xxxx-xxxx-xxxx-xxxxxxxba162
    Description:      Bootstrap Token (Global Management)
    Local:            false
    Create Time:      2025-05-14 11:29:23.1554547 +0530 IST
    Policies:
    00000000-0000-0000-0000-000000000001 - global-management

echo 'export CONSUL_HTTP_TOKEN="d0f2xxxx-xxxx-xxxx-xxxx-xxxxxxxba162"' >> ~/.bashrc


# Start consul service
sudo systemctl enable consul
sudo systemctl start consul
sudo systemctl status consul


# Verify
consul members
    Node            Address              Status  Type    Build   Protocol  DC   Partition  Segment
    pg-consul-rhel  192.168.100.41:8301  alive   server  1.21.0  2         dc1  default    <all>

# Get additional metadata
consul members -detailed

    [ansible@pg-consul-rhel ~]$ consul members -detailed
    Node            Address              Status  Tags
    pg-consul-rhel  192.168.100.41:8301  alive   acls=0,ap=default,build=1.21.0:4e96098f,dc=dc1,ft_fs=1,ft_si=1,grpc_tls_port=8503,id=7d203605-cebf-e7e7-aac2-f6fc6646253a,port=8300,raft_vsn=3,role=consul,segment=<all>,vsn=2,vsn_max=3,vsn_min=2,wan_join_port=8302

# Verify leader
curl http://127.0.0.1:8500/v1/status/leader

# Open website http://pg-consul-rhel:8500/ui/ from ryzen9 machine
Use CONSUL_HTTP_TOKEN for login

echo $CONSUL_HTTP_TOKEN

```

## Configure NGinx as a Reverse Proxy
```

apt-get install nginx -y
rm -rf /etc/nginx/sites-enabled/default

sudo nano /etc/nginx/sites-available/consul.conf

server {
listen 80 ;
server_name 192.168.100.41;
root /var/lib/consul;
location / {
proxy_pass http://127.0.0.1:8500;
proxy_set_header   X-Real-IP $remote_addr;
proxy_set_header   Host      $http_host;
}
}

sudo mkdir /etc/nginx/sites-enabled
sudo ln -s /etc/nginx/sites-available/consul.conf /etc/nginx/sites-enabled/

sudo nginx -t

sudo systemctl restart nginx
```

## Error/Fix: agent: startup error: error="refusing to rejoin cluster because server has been offline for more than the configured server_rejoin_age_max (168h0m0s) - consider wiping your data dir"
### Error =>
```
[ansible@pg-consul-rhel ~]$ 
[ansible@pg-consul-rhel ~]$ sudo systemctl status consul.service 
● consul.service - Consul Service Discovery Agent
     Loaded: loaded (/etc/systemd/system/consul.service; enabled; preset: disabled)
     Active: active (running) since Thu 2025-08-07 19:18:56 IST; 54s ago
       Docs: https://www.consul.io/
   Main PID: 1121 (consul)
      Tasks: 8 (limit: 48752)
     Memory: 101.7M
        CPU: 96ms
     CGroup: /system.slice/consul.service
             └─1121 /usr/bin/consul agent -server -ui -advertise=192.168.100.41 -bind=192.168.100.41 -data-dir=/var/lib/consul -node=pg-consul-rhel -config-dir=/etc/consul.d


Aug 07 19:19:57 pg-consul-rhel.lab.com consul[6293]: 2025-08-07T19:19:57.204+0530 [WARN]  agent: The 'ui' field is deprecated. Use the 'ui_config.enabled' field instead.
Aug 07 19:19:57 pg-consul-rhel.lab.com consul[6293]: 2025-08-07T19:19:57.204+0530 [WARN]  agent: BootstrapExpect is set to 1; this is the same as Bootstrap mode.
Aug 07 19:19:57 pg-consul-rhel.lab.com consul[6293]: 2025-08-07T19:19:57.204+0530 [WARN]  agent: bootstrap = true: do not enable unless necessary
Aug 07 19:19:57 pg-consul-rhel.lab.com consul[6293]: 2025-08-07T19:19:57.207+0530 [WARN]  agent.auto_config: skipping file /etc/consul.d/consul.env, extension must be .hcl or .json, or config format must be set
Aug 07 19:19:57 pg-consul-rhel.lab.com consul[6293]: 2025-08-07T19:19:57.207+0530 [WARN]  agent.auto_config: The 'ui' field is deprecated. Use the 'ui_config.enabled' field instead.
Aug 07 19:19:57 pg-consul-rhel.lab.com consul[6293]: 2025-08-07T19:19:57.207+0530 [WARN]  agent.auto_config: BootstrapExpect is set to 1; this is the same as Bootstrap mode.
Aug 07 19:19:57 pg-consul-rhel.lab.com consul[6293]: 2025-08-07T19:19:57.207+0530 [WARN]  agent.auto_config: bootstrap = true: do not enable unless necessary
Aug 07 19:19:57 pg-consul-rhel.lab.com consul[6293]: 2025-08-07T19:19:57.207+0530 [ERROR] agent: startup error: error="refusing to rejoin cluster because server has been offline for more than the configured server_rejoin_age_max (168h0m0s) - consider wiping your data dir"
Aug 07 19:20:07 pg-consul-rhel.lab.com consul[6293]: 2025-08-07T19:20:07.207+0530 [ERROR] agent: startup error: error="refusing to rejoin cluster because server has been offline for more than the configured server_rejoin_age_max (168h0m0s) - consider wiping your data dir"
Aug 07 19:20:17 pg-consul-rhel.lab.com consul[6293]: 2025-08-07T19:20:17.208+0530 [ERROR] agent: startup error: error="refusing to rejoin cluster because server has been offline for more than the configured server_rejoin_age_max (168h0m0s) - consider wiping your data dir"

```

### Fix
```
# find consul config directory
sudo systemctl cat consul | grep config

# create config file
sudo vim /etc/consul.d/server.json
    {
    "server": true,
    "server_rejoin_age_max": "8760h"
    }

sudo chown consul:consul /etc/consul.d/server.json
sudo chmod 0700 /etc/consul.d/server.json

# validate config file
sudo -u consul consul validate /etc/consul.d

# restart service
sudo systemctl restart consul
sudo systemctl status consul

# check web portal
pg-consul-rhel:8500/ui

```


# Consul Client setup - Steps to Install and Configure Consul Client on ryzen9

## Install consul binary
```
sudo scp ansible@pg-consul-rhel:/usr/bin/consul /usr/bin/
sudo chmod +x /usr/bin/consul
```

## Create required directories
```
sudo mkdir -p /etc/consul.d
sudo mkdir -p /var/lib/consul
sudo useradd --system --home /etc/consul.d --shell /bin/false consul
sudo chown -R consul:consul /etc/consul.d /var/lib/consul
```

## Create Consul client configuration file
```
sudo vim /etc/consul.d/client.hcl
sudo chown consul:consul /etc/consul.d/client.hcl
sudo chmod 0700 /etc/consul.d/client.hcl

datacenter = "dc1"
data_dir = "/var/lib/consul"
node_name = "ryzen9"                  # Name of client host
bind_addr = "192.168.100.1"         # IP of client host
advertise_addr = "192.168.100.1"    # IP of client host

client_addr = "0.0.0.0"
retry_join = ["192.168.100.41"]      # IP of Consul server

# Not a server
server = false

enable_script_checks = true
```

## Create systemd service file for Consul
```
sudo vim /etc/systemd/system/consul.service
sudo chmod 0755 /etc/systemd/system/consul.service

[Unit]
Description=Consul Agent
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target

[Service]
User=consul
Group=consul
ExecStart=/usr/bin/consul agent -config-dir=/etc/consul.d
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

## Start and enable the Consul client
```
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable consul
sudo systemctl start consul



(base) ----- [2025-Aug-08 07:10:10] saanvi@ryzen9 (PostgreSQL-Learning)
|------------$ sudo systemctl status consul
● consul.service - Consul Agent
     Loaded: loaded (/etc/systemd/system/consul.service; enabled; preset: enabled)
     Active: active (running) since Fri 2025-08-08 07:09:59 IST; 18s ago
       Docs: https://www.consul.io/
   Main PID: 1744092 (consul)
      Tasks: 33 (limit: 154376)
     Memory: 27.3M (peak: 31.6M)
        CPU: 134ms
     CGroup: /system.slice/consul.service
             └─1744092 /usr/bin/consul agent -config-dir=/etc/consul.d

Aug 08 07:09:59 ryzen9 consul[1744092]: 2025-08-08T07:09:59.943+0530 [INFO]  agent: (LAN) joining: lan_addresses=["192.168.100.41"]
Aug 08 07:09:59 ryzen9 consul[1744092]: 2025-08-08T07:09:59.943+0530 [INFO]  agent: started state syncer
Aug 08 07:09:59 ryzen9 consul[1744092]: 2025-08-08T07:09:59.943+0530 [INFO]  agent: Consul agent running!
Aug 08 07:09:59 ryzen9 consul[1744092]: 2025-08-08T07:09:59.943+0530 [WARN]  agent.router.manager: No servers available
Aug 08 07:09:59 ryzen9 consul[1744092]: 2025-08-08T07:09:59.943+0530 [ERROR] agent.anti_entropy: failed to sync remote state: error="No known Consul servers"
Aug 08 07:09:59 ryzen9 consul[1744092]: 2025-08-08T07:09:59.944+0530 [INFO]  agent.client.serf.lan: serf: EventMemberJoin: pg-consul-rhel 192.168.100.41
Aug 08 07:09:59 ryzen9 consul[1744092]: 2025-08-08T07:09:59.944+0530 [INFO]  agent: (LAN) joined: number_of_nodes=1
Aug 08 07:09:59 ryzen9 consul[1744092]: 2025-08-08T07:09:59.944+0530 [INFO]  agent: Join cluster completed. Synced with initial agents: cluster=LAN num_agents=1
Aug 08 07:09:59 ryzen9 consul[1744092]: 2025-08-08T07:09:59.944+0530 [INFO]  agent.client: adding server: server="pg-consul-rhel (Addr: tcp/192.168.100.41:8300) (DC: dc1)"
Aug 08 07:10:00 ryzen9 consul[1744092]: 2025-08-08T07:10:00.351+0530 [INFO]  agent: Synced node info
(base) ----- [2025-Aug-08 07:10:18] saanvi@ryzen9 (PostgreSQL-Learning)
```

## On Consul server `pg-consul-rhel`, Verify the Consul client is connected
```
consul members

[ansible@pg-consul-rhel ~]$ consul members
Node            Address              Status  Type    Build   Protocol  DC   Partition  Segment
pg-consul-rhel  192.168.100.41:8301  alive   server  1.21.3  2         dc1  default    <all>
ryzen9          192.168.100.1:8301   alive   client  1.21.3  2         dc1  default    <default>
[ansible@pg-consul-rhel ~]$ 
```

## On client `ryzen9`, Register PostgreSQL as a Service
```
# Register service on client
sudo vim /etc/consul.d/postgresql.json
sudo chown consul:consul /etc/consul.d/postgresql.json
sudo chmod 0700 /etc/consul.d/postgresql.json

# Reload consul on client
sudo consul reload



{
  "service": {
    "name": "postgresql-16-main",
    "port": 5432,
    "tags": ["primary", "db"],
    "check": {
      "id": "pgsql-tcp-check",
      "name": "PostgreSQL 16-main TCP on port 5432",
      "tcp": "localhost:5432",
      "interval": "10s",
      "timeout": "1s"
    }
  }
}
```

