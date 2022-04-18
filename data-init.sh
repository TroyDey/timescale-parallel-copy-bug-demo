#!/bin/sh
set -e

# Helper script that will be run as part of the Postgres docker container's init procedure
# Modifies the postgresql.conf file to enable multi-node TimeScaleDB

sed -ri "s/^#?(max_prepared_transactions)[[:space:]]*=.*/\1 = 150/;s/^#?(wal_level)[[:space:]]*=.*/\1 = logical/;s/^#?(max_logical_replication_workers)[[:space:]]*=.*/\1 = 20/;s/^#?(max_replication_slots)[[:space:]]*=.*/\1 = 20/;s/^#?(max_wal_senders)[[:space:]]*=.*/\1 = 20/" /var/lib/postgresql/data/postgresql.conf
