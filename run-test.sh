#!/bin/bash

# Tests Timescale's copy function and its ability to replicate multiple chunks in parallel
# This functionality is useful in the event of a node failure which causes a number of chunks
# to become under replciated.  After a new node is brought online we would like to quickly
# bring the under replicated chunks back up to fully replicated status quickly.
# To do this we build a "replication plan" which will have a source and destination node
# for each under replicated chunk.  The source nodes are chosen at random from amoungst
# the nodes that contain the chunks to provide a simple mechanism for spreading the work out.
# Running a single copy operation at a time allows the rereplication to complete.
# Running even one additional copy operation concurrently can lead to errors.  In fact
# as you increase the number of operations the chance of encountering an error increases.
# In addition running this scenario on actual hardware often leads to the entire process to
# hang without any error printed at all. Finally, even when it works replication is very slow
# it can take upward of a minute to replicate/copy 10's of MB's of data.
# 
# In this scenario we use 8 workers to execute copy
# commands which will garuntee an error to be produced.  Errors reported from running the
# command and in the postgres log file look like below.

# ...snip...
# tsdb-data3  | 2022-04-18 16:50:24.321 UTC [136] LOG:  logical replication table synchronization worker for subscription "ts_copy_6_6", table "_dist_hyper_1_6_chunk" has finished
# tsdb-data3  | 2022-04-18 16:50:24.490 UTC [128] FATAL:  terminating logical replication worker due to administrator command
# tsdb-data3  | 2022-04-18 16:50:24.491 UTC [1] LOG:  background worker "logical replication worker" (PID 128) exited with exit code 1
# tsdb-data3  | 2022-04-18 16:50:24.503 UTC [130] FATAL:  terminating logical replication worker due to administrator command
# tsdb-data3  | 2022-04-18 16:50:24.504 UTC [1] LOG:  background worker "logical replication worker" (PID 130) exited with exit code 1
# tsdb-data3  | 2022-04-18 16:50:24.631 UTC [117] ERROR:  query returned no rows
# tsdb-data3  | 2022-04-18 16:50:24.631 UTC [117] CONTEXT:  PL/pgSQL function _timescaledb_internal.dimension_slice_get_constraint_sql(integer) line 9 at SQL statement
# tsdb-data3  |   PL/pgSQL function _timescaledb_internal.chunk_constraint_add_table_constraint(_timescaledb_catalog.chunk_constraint) line 16 at assignment
# tsdb-data3  | 2022-04-18 16:50:24.631 UTC [117] STATEMENT:  SELECT * FROM _timescaledb_internal.create_chunk($1, $2, $3, $4, $5)
# tsdb-data3  | 2022-04-18 16:50:29.760 UTC [142] LOG:  logical replication apply worker for subscription "ts_copy_10_7" has started
# tsdb-data3  | 2022-04-18 16:50:29.771 UTC [143] LOG:  logical replication apply worker for subscription "ts_copy_11_8" has started
# ...snip...
#
# From psql
# Copy for chunk: _timescaledb_internal._dist_hyper_6_36_chunk from: dn1 to: dn3 failed
# stdout: 
# stderr: ERROR:  [dn3]: query returned no rows
# DETAIL:  Chunk copy operation id: ts_copy_36_36.


RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Wait for Postgres to accept connections
pg_ready() {
  until psql -U postgres -h localhost -p $1 -c '\q' &> /dev/null; do
    sleep 1s
  done
}

# Get the replication status of all chunks
get_replication_status() {
  psql -P pager=off -U postgres -h localhost -p 5433 -d testdb -c "SELECT * FROM timescaledb_experimental.chunk_replication_status;"
}

# Detach and then delete the given data node
# We delete because we can't simply reattach a data node that contains data
detach_node() {
  psql -U postgres -h localhost -p 5433 -d testdb -c "SELECT detach_data_node('$1', force => true);"
  psql -U postgres -h localhost -p 5433 -d testdb -c "SELECT delete_data_node('$1', force => true);"
}

# Drop the database on the data node
# adding the data node will recreate the database
# attach the data node to all metric tables
reattach_node() {
  psql -U postgres -h localhost -p $2 -c "DROP DATABASE testdb WITH(FORCE);"
  psql -U postgres -h localhost -p 5433 -d testdb -c "SELECT add_data_node('$1', host => '$3');"
  psql -U postgres -h localhost -p 5433 -d testdb -c "SELECT res.hypertable_id, res.node_hypertable_id, res.node_name, h.hypertable_name table_name FROM timescaledb_information.hypertables h CROSS JOIN LATERAL attach_data_node('$1'::name, h.hypertable_name::regclass) res WHERE h.is_distributed = true;"
}

# Color code output
print_info() {
  echo -e "${CYAN}"
  echo "$1"
  echo -e "${NC}"
}

print_success() {
  echo -e "${GREEN}"
  echo "$1"
  echo -e "${NC}"
}

print_fail() {
  echo -e "${RED}"
  echo "$1"
  echo -e "${NC}"
}

print_info "BEGIN TEST"

print_info "Bring up environment..."
docker-compose up -d

print_info "Wait for access node to be ready..."
pg_ready 5433

print_info "Setting up database..."
psql -U postgres -h localhost -p 5433 -d testdb -f setup-test.sql
echo

print_info "Database setup, metric0 table contains the following number of rows"
psql -U postgres -h localhost -p 5433 -d testdb -c 'SELECT COUNT(*) FROM metric0;'
print_info "Size of metric0 table chunks"
psql -P pager=off -U postgres -h localhost -p 5433 -d testdb -c "SELECT total_bytes FROM chunks_detailed_size('metric0')"
print_info "Current replication status"
get_replication_status
print_info "Forcibly removing tsdb-data3"
detach_node dn3
print_info "Readding tsdb-data3"
reattach_node dn3 5436 tsdb-data3
print_info "New replication status"
get_replication_status
print_info "Show replication plan"
psql -P pager=off -U postgres -h localhost -p 5433 -d testdb -c "SELECT get_chunk_repl_restore_plan()"
print_info "Execute replication plan..."
python parallel-rebalance.py
read -n 1 -p "test complete, press any key to tear down the environment:"
print_info "Tear down environment..."
docker-compose down -v
print_info "END TEST"
