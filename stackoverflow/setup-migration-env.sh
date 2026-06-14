#!/bin/bash

# ============================================================================
# Environment Variables Setup for SQL Server to PostgreSQL Migration Scripts
# ============================================================================
#
# This script sets up all required environment variables for the migrate-*.py
# scripts that migrate data from SQL Server to PostgreSQL.
#
# Usage:
#   source setup-migration-env.sh
#   # Then run migration scripts:
#   python migrate-[badges]-table--mssql-2-postgresql.py
#
# ============================================================================

echo "========================================"
echo "Setting up Migration Environment Variables"
echo "========================================"
echo ""

# ============================================================================
# SQL SERVER (SOURCE) CONFIGURATION
# ============================================================================
# These variables define the SQL Server instance to migrate FROM

# SQL Server hostname or IP address
export SOURCE_MSSQLHOST="localhost"
# Uncomment and change if SQL Server is on a remote host:
# export SOURCE_MSSQLHOST="192.168.1.100"
# export SOURCE_MSSQLHOST="sqlserver.example.com"

# SQL Server database name (usually "StackOverflow2013")
export SOURCE_MSSQLDATABASE="StackOverflow2013"

# SQL Server login user
export SOURCE_MSSQLUSER="sa"

# SQL Server password (REQUIRED - no default)
# WARNING: For production, use a secure method (e.g., .env file, secrets manager)
export SOURCE_MSSQLPASSWORD="YourSQLServerPassword"

echo "✓ SQL Server (Source) Configuration:"
echo "  HOST:     $SOURCE_MSSQLHOST"
echo "  DATABASE: $SOURCE_MSSQLDATABASE"
echo "  USER:     $SOURCE_MSSQLUSER"
echo "  PASSWORD: [set]"
echo ""

# ============================================================================
# POSTGRESQL (TARGET) CONFIGURATION
# These variables define the PostgreSQL instance to migrate TO
# ============================================================================

# PostgreSQL hostname or IP address
export TARGET_PGHOST="localhost"
# Uncomment and change if PostgreSQL is on a remote host:
# export TARGET_PGHOST="192.168.1.50"
# export TARGET_PGHOST="postgres.example.com"

# PostgreSQL port (default: 5432)
export TARGET_PGPORT="5432"

# PostgreSQL database name
export TARGET_PGDATABASE="stackoverflow2013"

# PostgreSQL login user
export TARGET_PGUSER="postgres"

# PostgreSQL password (REQUIRED - no default)
# WARNING: For production, use a secure method (e.g., .env file, secrets manager)
export TARGET_PGPASSWORD="YourPostgreSQLPassword"

echo "✓ PostgreSQL (Target) Configuration:"
echo "  HOST:     $TARGET_PGHOST"
echo "  PORT:     $TARGET_PGPORT"
echo "  DATABASE: $TARGET_PGDATABASE"
echo "  USER:     $TARGET_PGUSER"
echo "  PASSWORD: [set]"
echo ""

# ============================================================================
# SUMMARY OF ALL ENVIRONMENT VARIABLES
# ============================================================================
echo "========================================"
echo "Environment Variables Set:"
echo "========================================"
echo ""
echo "SQL SERVER (SOURCE):"
echo "  SOURCE_MSSQLHOST=$SOURCE_MSSQLHOST"
echo "  SOURCE_MSSQLDATABASE=$SOURCE_MSSQLDATABASE"
echo "  SOURCE_MSSQLUSER=$SOURCE_MSSQLUSER"
echo "  SOURCE_MSSQLPASSWORD=[configured]"
echo ""
echo "POSTGRESQL (TARGET):"
echo "  TARGET_PGHOST=$TARGET_PGHOST"
echo "  TARGET_PGPORT=$TARGET_PGPORT"
echo "  TARGET_PGDATABASE=$TARGET_PGDATABASE"
echo "  TARGET_PGUSER=$TARGET_PGUSER"
echo "  TARGET_PGPASSWORD=[configured]"
echo ""
echo "========================================"
echo "Ready to run migration scripts!"
echo "========================================"
echo ""
