# Test Multi-Node TimeScale

Demonstrates defect with TimeScaleDB's copy chunk function when multiple calls to this function are executed concurrently.

## Setup

* Docker with docker compose
* Image: timescale/timescaledb:2.6.1-pg14
* Single access node
* 3 data nodes
* 5 distributed hypertable with a replication factor of 3 and chunk_interval of 1 hour
* Inserts 2 hrs worth of data for 50 different dev_ids into each table

## Test Case

* Setup environment as indicated above
* Detach and delete data node 3 (name: dn3, host: tsdb-data3)
* Readd and reattch data node 3 (name: dn3, host: tsdb-data3)
* Generate a plan to copy all under replicated chunks (all chunks in this case) from data nodes 1 and 2 to data node 3
* Use 8 workers to execute these commands concurrently
* Expected:
  * All chunks are present on data node 3
* Actual:
  * Some copy commands fail with the following error output from psql
  ```
  Copy for chunk: _timescaledb_internal._dist_hyper_6_36_chunk from: dn1 to: dn3 failed
  stdout: 
  stderr: ERROR:  [dn3]: query returned no rows
  DETAIL:  Chunk copy operation id: ts_copy_36_36.
  ```
  * Some errors present in pgdata/log/postgresql-*.log
  ```
  tsdb-data3  | 2022-04-18 16:50:24.321 UTC [136] LOG:  logical replication table synchronization worker for subscription "ts_copy_6_6", table "_dist_hyper_1_6_chunk" has finished
  tsdb-data3  | 2022-04-18 16:50:24.490 UTC [128] FATAL:  terminating logical replication worker due to administrator command
  tsdb-data3  | 2022-04-18 16:50:24.491 UTC [1] LOG:  background worker "logical replication worker" (PID 128) exited with exit code 1
  tsdb-data3  | 2022-04-18 16:50:24.503 UTC [130] FATAL:  terminating logical replication worker due to administrator command
  tsdb-data3  | 2022-04-18 16:50:24.504 UTC [1] LOG:  background worker "logical replication worker" (PID 130) exited with exit code 1
  tsdb-data3  | 2022-04-18 16:50:24.631 UTC [117] ERROR:  query returned no rows
  tsdb-data3  | 2022-04-18 16:50:24.631 UTC [117] CONTEXT:  PL/pgSQL function _timescaledb_internal.dimension_slice_get_constraint_sql(integer) line 9 at SQL statement
  tsdb-data3  |   PL/pgSQL function _timescaledb_internal.chunk_constraint_add_table_constraint(_timescaledb_catalog.chunk_constraint) line 16 at assignment
  tsdb-data3  | 2022-04-18 16:50:24.631 UTC [117] STATEMENT:  SELECT * FROM _timescaledb_internal.create_chunk($1, $2, $3, $4, $5)
  tsdb-data3  | 2022-04-18 16:50:29.760 UTC [142] LOG:  logical replication apply worker for subscription "ts_copy_10_7" has started
  tsdb-data3  | 2022-04-18 16:50:29.771 UTC [143] LOG:  logical replication apply worker for subscription "ts_copy_11_8" has started
  ```
  * Sometimes the run will just hang seemingly indefinitely
  * Chunk is actually copied to data node 3 and can be directly queried, but timescaledb_experimental.chunk_replication_status on the access node shows the chunk as not present on data node 3.

## Running

```
./run-test.sh
```

NOTE: The test will pause for user input before tearing down the environment so you can peek at the system.
