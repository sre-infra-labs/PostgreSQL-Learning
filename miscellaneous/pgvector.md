# [PGVector: Turn PostgreSQL Into a Vector Database](https://github.com/pgvector/pgvector)

## Install postgresql 16 dev package

```
# install dev package for correct version
sudo apt-get install postgresql-server-dev-16

# Use PostgreSQL 16’s pg_config explicitly
make clean
make PG_CONFIG=/usr/lib/postgresql/16/bin/pg_config
sudo make PG_CONFIG=/usr/lib/postgresql/16/bin/pg_config install

# Verify which Postgres your psql is connected to. It should show latest minor release
psql -c "select version();"

-- check config being used
/usr/lib/postgresql/16/bin/pg_config --version


CREATE EXTENSION vector;


```


## [Getting Started](https://github.com/pgvector/pgvector?tab=readme-ov-file#getting-started)

```
-- depending on the model being used, ensure to put correct value for embedding dimensions
  -- for ollama based gemma3:4b, it is 2560. for nomic-embed-text, its 768.
  -- ollama show gemma3:4b
  -- ollama show nomic-embed-text

\c vector
create table items (id serial primary key, content text, embedding vector(768));

```



