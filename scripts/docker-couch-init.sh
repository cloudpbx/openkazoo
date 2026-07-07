#!/usr/bin/env bash
# Create the CouchDB system databases (idempotent).
# Override target: COUCH_URL=http://admin:password@127.0.0.1:5984
set -euo pipefail

COUCH_URL="${COUCH_URL:-http://admin:password@couchdb:5984}"

for _ in $(seq 1 60); do
    curl -fs -o /dev/null "${COUCH_URL}/_up" && break
    sleep 1
done

for db in _users _replicator _global_changes; do
    curl -fsS -X PUT "${COUCH_URL}/${db}?n=1&q=1" || true
done
