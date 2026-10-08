#!/bin/bash
# CC_PRE_RUN_HOOK: create the database schema on an empty database
set -euo pipefail

cd "$(dirname "$0")/.."
export REPOLOGY_CONFIG="$PWD/clevercloud/repology.conf"

schema_exists=$(python3 -c '
import os, psycopg2
with psycopg2.connect(os.environ["POSTGRESQL_ADDON_URI"]) as conn, conn.cursor() as cur:
    cur.execute("SELECT to_regclass(%s) IS NOT NULL", ("public.repositories",))
    print(cur.fetchone()[0])
')

# --initdb drops all tables, only run it when the schema does not exist yet
if [ "$schema_exists" = "False" ]; then
	echo "database schema not found, initializing"
	./repology-update.py --initdb

	# Fill the fresh database now instead of waiting for the weekly cron
	./clevercloud/update.sh || echo "initial update failed, database will be filled by the next cron run"
fi
