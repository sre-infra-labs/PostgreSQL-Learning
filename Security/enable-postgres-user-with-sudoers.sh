#> sudo visudo -f /etc/sudoers.d/postgres

# Allow postgres user to execute any command
postgres ALL=(ALL:ALL) NOPASSWD:ALL

