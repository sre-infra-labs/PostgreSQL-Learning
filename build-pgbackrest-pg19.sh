#!/bin/bash
# Build pgbackrest from integration branch for PostgreSQL 19 Beta 1 support
# Run this as root inside the podpg-cls3-pg1 container

set -e

echo "=== Building pgbackrest from integration branch ==="
echo "Target: /tmp/pgbackrest/"

# Install build dependencies
apt-get update -qq 2>&1 | tail -1
apt-get install -y -qq meson ninja-build gcc libpq-dev libssl-dev libxml2-dev \
  pkg-config liblz4-dev libzstd-dev libbz2-dev zlib1g-dev libyaml-dev libssh2-1-dev git 2>&1 | tail -1

# Clone integration branch (better PG19 support)
PGBACKREST_SRC="/tmp/pgbackrest-src"
PGBACKREST_BUILD="/tmp/pgbackrest-build"
PGBACKREST_INSTALL="/tmp/pgbackrest-install"

rm -rf "$PGBACKREST_SRC" "$PGBACKREST_BUILD" "$PGBACKREST_INSTALL" 2>/dev/null || true
mkdir -p "$PGBACKREST_SRC" "$PGBACKREST_BUILD" "$PGBACKREST_INSTALL"

echo "Cloning integration branch..."
git clone --depth 1 -b integration https://github.com/pgbackrest/pgbackrest.git "$PGBACKREST_SRC" 2>&1 | tail -2

# Build using Meson
echo "Configuring with Meson..."
meson setup "$PGBACKREST_BUILD" "$PGBACKREST_SRC" --prefix="$PGBACKREST_INSTALL" 2>&1 | tail -5
echo "Building with Ninja..."
ninja -C "$PGBACKREST_BUILD" 2>&1 | tail -3
echo "Installing..."
ninja -C "$PGBACKREST_BUILD" install 2>&1 | tail -2

# Verify
echo "Verifying pgbackrest..."
$PGBACKREST_INSTALL/bin/pgbackrest --version

# Create tarball for distribution
mkdir -p /tmp/pgbackrest
tar czf /tmp/pgbackrest/pgbackrest-pg19.tar.gz -C "$PGBACKREST_INSTALL/bin" pgbackrest

echo "=== Build Complete ==="
ls -lh /tmp/pgbackrest/pgbackrest-pg19.tar.gz
echo "Binary: $PGBACKREST_INSTALL/bin/pgbackrest"
