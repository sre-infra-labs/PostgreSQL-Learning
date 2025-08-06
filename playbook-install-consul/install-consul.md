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


