#!/bin/bash
# Run every 10 minutes by clevercloud/cron.json, and once by init-db.sh to fill
# a fresh database. The updater itself decides what to refresh: each repository
# is only fetched once its update_period has elapsed, only parsed when the
# fetched data changed, and only changed projects are pushed to the database
set -euo pipefail

cd "$(dirname "$0")/.."
export REPOLOGY_CONFIG="$PWD/clevercloud/repology.conf"

# Skip this run if the previous one is still going, so two updates never fetch
# or push concurrently. The lock lives on the instance and dies with it
exec 9>"$PWD/_update.lock"
if ! flock -n 9; then
	echo "previous update still running, skipping this run"
	exit 0
fi

start=$SECONDS
trap 'echo "update finished with status $? in $((SECONDS - start))s"' EXIT

if [ -d rules.d/.git ]; then
	git -C rules.d pull --quiet --ff-only
else
	rm -rf rules.d
	git clone --quiet --depth 1 https://github.com/repology/repology-rules.git rules.d
fi

# Local state (_state, _parsed) does not survive redeploys, while fetch/parse
# markers live in the database. A repository whose parsed data is missing
# locally must be fetched and parsed again, otherwise --database would push it
# as empty. Only reset markers for those, so runs on the same instance stay
# incremental and conditional HTTP requests keep working
python3 -c '
import os, psycopg2
with psycopg2.connect(os.environ["POSTGRESQL_ADDON_URI"]) as conn, conn.cursor() as cur:
    cur.execute("SELECT name FROM repositories")
    missing = [name for (name,) in cur.fetchall() if not os.path.isdir(os.path.join("_parsed", name + ".parsed"))]
    if missing:
        print("no local parsed data for " + ", ".join(sorted(missing)) + ", forcing fetch and parse")
        cur.execute("UPDATE repositories SET last_fetched = NULL, ruleset_hash = NULL WHERE name = ANY(%s)", (missing,))
'

# --fatal aborts before --database if any fetch or parse fails (including the
# minpackages safety check), leaving the database untouched
./repology-update.py --fatal --fetch --parse --database --postupdate
