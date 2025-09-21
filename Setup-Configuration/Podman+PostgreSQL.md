# Install PostgreSQL on Podman

## Pull image, and spin a container
```
# Pull postgres image from docker hub
podman pull postgres

# Create director on your local machine to mount the data directory or to make the data directory as persistence
sudo mkdir -p /var/lib/postgresql-podman/data

# Run the postgres docker container using podman. Tunnel podman port 5432 to host port 5431.
read -s -p "Enter Postgres Superuser Password: " postgres_superuser_password && export PGPASSWD="$postgres_superuser_password"
podman run --name postgres -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=${PGPASSWD} -p 5431:5432 -v /var/lib/postgresql-podman/data -d postgres

# Verify container
podman ps
podman ps -a
podman logs postgres

# Connect to Bash Shell of Container
podman exec -it postgres "bash"
  # as root
podman exec -u 0 -it postgres "bash"
  # as postgres user
podman exec -u postgres -it postgres "bash"

psql -h localhost -U postgres
psql
```

## Setup defaults for each connectivity
```
Add .pgpass entry
*:*:*:postgres:passwordHere

# Set default database
echo "export PGDATABASE=postgres" >> ~/.bashrc
source ~/.bashrc

# Connect to PostgreSQL Instance
psql -h localhost -p 5431 -U postgres

# Create other roles equivalent to current system username
create role saanvi with login password 'mystrongpasswordhere' superuser;

# Connect again without specifying username
psql -h localhost -p 5431

```

## If required, start container at system startup
```
# Generate a systemd Unit File for the Container
podman generate systemd --name postgres --files --new

# Move the Service File to systemd Directory
mkdir -p ~/.config/systemd/user
mv container-postgres.service ~/.config/systemd/user/

# Enable and Start the Service
systemctl --user enable container-postgres.service
systemctl --user start container-postgres.service

# If you want the user services to run on system boot, you might need to enable lingering:
loginctl enable-linger $USER

```


