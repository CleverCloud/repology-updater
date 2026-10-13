#!/bin/bash
# CC_PRE_RUN_HOOK: create the database schema and fill the database if empty
set -euo pipefail

cd "$(dirname "$0")/.."
export REPOLOGY_CONFIG="$PWD/clevercloud/repology.conf"

query() {
	python3 -c '
import os, sys, psycopg2
with psycopg2.connect(os.environ["POSTGRESQL_ADDON_URI"]) as conn, conn.cursor() as cur:
    cur.execute(sys.argv[1])
    print(cur.fetchone()[0])
' "$1"
}

# --initdb drops all tables, only run it when the schema does not exist yet
if [ "$(query "SELECT to_regclass('public.repositories') IS NOT NULL")" = "False" ]; then
	echo "database schema not found, initializing"
	./repology-update.py --initdb
fi

# Fill an empty database now instead of waiting for the next cron run; this is
# retried on every deploy until a run succeeds
if [ "$(query "SELECT NOT EXISTS (SELECT 1 FROM packages)")" = "True" ]; then
	echo "database is empty, running initial update"
	./clevercloud/update.sh || echo "initial update failed, will retry on next deploy or cron run"
fi
