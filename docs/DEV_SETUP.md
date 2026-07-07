# OpenKazoo — Local Dev Setup (Docker)

Runs Kazoo locally with the CI toolchain (OTP 27, rebar3 3.27.0) plus RabbitMQ
and CouchDB in containers. FreeSWITCH is not required — call events are AMQP
messages you can publish from the Erlang shell.

## Requirements

- Docker (Desktop or Engine). The Erlang toolchain lives in the image.
- Host ports: `8000` (crossbar), `5672`/`15672` (RabbitMQ + UI), `5984` (CouchDB).

## Start / stop

| Command | Action |
|---|---|
| `make dev` | Start RabbitMQ + CouchDB + `kazoo_apps`, tail kazoo logs. |
| `make dev-logs` | Re-attach to the kazoo log tail. |
| `make dev-shell` | bash shell in the running kazoo container. |
| `make dev-stop` | Stop containers, keep containers + volumes. |
| `make dev-down` | Remove containers, keep volumes. |
| `make dev-clean` | Remove containers and volumes. |

First `make dev` builds the image and compiles the tree (several minutes).
`Ctrl-C` while tailing stops the tail only; the stack keeps running.

## Bootstrap

Once, after the first `make dev` on empty CouchDB:

```bash
make dev-bootstrap
```

Runs `kapps_maintenance:refresh()` (imports views/schemas), creates the `testco`
account, and seeds a callflow. Idempotent.

## Seeded data

| Field | Value |
|---|---|
| Account name | `testco` |
| Realm | `testco.local` |
| Admin user / password | `admin` / `secret1234!` |
| Callflow number | `1000` |
| Role | master account |

The account id is generated per bootstrap. Resolve it from the realm:

```erlang
{ok, Db} = kapps_util:get_account_by_realm(<<"testco.local">>).
AccountId = kz_util:format_account_id(Db, 'raw').
```

## Erlang shell

Remote-shell into the running node (separate VM; does not affect the node):

```bash
docker compose exec kazoo erl -name debug@127.0.0.1 -setcookie change_me -remsh kazoo_apps@127.0.0.1
```

Exit with `Ctrl-C` then `a`. Do not call `q().`/`init:stop().` — those halt the node.

## Simulating a call

An inbound call is a `route_req` on the `callmgr` exchange (`Account-ID` in the
CCVs routes it to the account's callflow).

### Start

```erlang
{ok, Db} = kapps_util:get_account_by_realm(<<"testco.local">>).
AccountId = kz_util:format_account_id(Db, 'raw').
CCVs = kz_json:from_list([{<<"Account-ID">>, AccountId}]).
CallId = kz_binary:rand_hex(16).
Req = [{<<"To">>,                  <<"1000@testco.local">>}
      ,{<<"From">>,                <<"2000@testco.local">>}
      ,{<<"Request">>,             <<"1000@testco.local">>}
      ,{<<"Call-ID">>,             CallId}
      ,{<<"Caller-ID-Name">>,      <<"Dev Test">>}
      ,{<<"Caller-ID-Number">>,    <<"2000">>}
      ,{<<"Resource-Type">>,       <<"audio">>}
      ,{<<"Custom-Channel-Vars">>, CCVs}
       | kz_api:default_headers(<<"shell">>, <<"1.0">>)
      ].
{ok, Resp} = kz_amqp_worker:call(Req, fun kapi_route:publish_req/1, fun kapi_route:resp_v/1, 10000).
kz_json:get_value(<<"Method">>, Resp).      %% <<"park">>
```

Fire-and-forget (no wait for the response): `kapi_route:publish_req(Req).`
A number with no callflow returns `{error, timeout}` from `kz_amqp_worker:call/4`.

### End

`CHANNEL_DESTROY` call event on the `callevt` exchange for the `Call-ID`:

```erlang
EndEvt = [{<<"Call-ID">>,             CallId}
         ,{<<"Event-Name">>,          <<"CHANNEL_DESTROY">>}
         ,{<<"Hangup-Cause">>,        <<"NORMAL_CLEARING">>}
         ,{<<"Custom-Channel-Vars">>, CCVs}
          | kz_api:default_headers(<<"shell">>, <<"1.0">>)
         ].
kapi_call:publish_event(EndEvt).            %% ok
```

The `route_req` recipe does not send `route_win`, so no `cf_exe` is running to
consume the destroy; driving a full call also requires playing ecallmgr's role
(send `route_win`, then the channel events).

## Watch

- Logs: `make dev-logs`
- RabbitMQ UI: <http://localhost:15672> (guest/guest)
- CouchDB: <http://localhost:5984/_utils> (admin/password)
- crossbar: `curl -i http://localhost:8000/v2/api_auth` → `405` (PUT-only endpoint)

## Tests

eunit uses `kazoo_fixturedb` + mocked AMQP; no services needed:

```bash
make docker-test
docker compose run --rm --no-deps kazoo make format-check
```

## Files

- `Dockerfile` — OTP-27 toolchain image.
- `docker-compose.yml` — kazoo + rabbitmq + couchdb.
- `config/config-docker.ini` — points at the compose service names.
- `scripts/docker-entrypoint.sh` — inits CouchDB, boots `kazoo_apps`.
- `scripts/docker-couch-init.sh` — creates CouchDB system DBs.
- `scripts/dev-bootstrap.escript` — refresh + seed account/callflow.
