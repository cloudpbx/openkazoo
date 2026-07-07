#!/usr/bin/env bash
# Init CouchDB system DBs, then boot kazoo_apps.
# Boots with erl, not `rebar3 shell` (Kazoo sets relx sys_config=false).
set -euo pipefail

./scripts/docker-couch-init.sh || echo "WARN: couch init failed; continuing"

rebar3 compile

export ERL_LIBS="/src/_build/default/lib"
export KAZOO_APPS="${KAZOO_APPS:-sysconf,crossbar,callflow,ecallmgr,registrar,jonny5,teletype,webhooks,tasks,conference,media_mgr}"

exec erl -name 'kazoo_apps@127.0.0.1' -setcookie 'change_me' \
     -eval 'application:ensure_all_started(kazoo_apps).'
