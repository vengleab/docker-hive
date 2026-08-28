#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
  CREATE USER hive WITH PASSWORD 'hive';
  CREATE DATABASE metastore;
  GRANT ALL PRIVILEGES ON DATABASE metastore TO hive;

  \c metastore

  -- Postgres 15+ no longer grants CREATE on the public schema to all users by default,
  -- and the actual metastore schema is created by Hive's own schematool at container
  -- startup (see hive-metastore's command in docker-compose.yml), not seeded here, so it
  -- always matches the installed Hive version.
  GRANT ALL ON SCHEMA public TO hive;
EOSQL
