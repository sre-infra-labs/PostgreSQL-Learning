# https://medium.com/@pawanpg0963/run-postgresql-with-podman-as-docker-container-86ad392349d1

# Get all pods (running or not)
podman ps -a

# Connect to postgresql on podman pod
psql -h localhost -U postgres

# Connect to podman pod bash shell
podman exec -it <postgres_pod> bash


