#!/bin/sh
set -e

# Allow trust access to all
sed -i '$ d' /var/lib/postgresql/data/pg_hba.conf
echo "host all all all trust" >>/var/lib/postgresql/data/pg_hba.conf

sed -ri "s!^#?(listen_addresses)\s*=.*!\1 = '*'!" /var/lib/postgresql/data/postgresql.conf