#!/bin/bash
# Run by clevercloud/cron.json, and once by init-db.sh to fill a fresh database
set -euo pipefail

cd "$(dirname "$0")/.."
export REPOLOGY_CONFIG="$PWD/clevercloud/repology.conf"

rm -rf rules.d
git clone --quiet --depth 1 https://github.com/repology/repology-rules.git rules.d

# Forget fetch/parse markers so every run fetches and parses from scratch. Local
# state does not survive redeploys, and skipping a fetch because the database
# says it is recent would make --database push repositories as empty
python3 -c '
import os, psycopg2
with psycopg2.connect(os.environ["POSTGRESQL_ADDON_URI"]) as conn, conn.cursor() as cur:
    cur.execute("UPDATE repositories SET last_fetched = NULL, ruleset_hash = NULL")
'

# --fatal aborts before --database if any fetch or parse fails (including the
# minpackages safety check), leaving the database untouched
./repology-update.py --fatal --fetch --parse --database --postupdate
