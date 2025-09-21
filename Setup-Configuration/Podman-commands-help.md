## Use volumes for Persistent Data

# create a volume
podman volume create postgres_data

# Attach the volume to the container
podman run --name postgres \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD='DummyPassword' \
  -p 5432:5432 \
  -v postgres_data:/var/lib/postgresql/data \
  -d postgres

