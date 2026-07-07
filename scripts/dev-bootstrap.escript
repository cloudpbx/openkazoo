#!/usr/bin/env escript
%%! -name bootstrap@127.0.0.1 -setcookie change_me -hidden
%%
%% One-time dev bootstrap (idempotent): refresh DB views/schemas, create the
%% testco account (realm testco.local, admin/secret1234!), seed callflow 1000.
%%   escript /src/scripts/dev-bootstrap.escript

-define(NODE, 'kazoo_apps@127.0.0.1').
-define(REALM, <<"testco.local">>).
-define(NUMBER, <<"1000">>).

main(_) ->
    case net_adm:ping(?NODE) of
        'pong' -> 'ok';
        'pang' -> io:format(standard_error, "cannot reach ~p (is `make dev` running?)~n", [?NODE]), halt(1)
    end,
    io:format("==> refreshing system DBs (imports views/schemas; takes a few minutes)~n"),
    _ = rpc:call(?NODE, 'kapps_maintenance', 'refresh', [], 600000),
    io:format("==> refresh done~n"),
    AccountDb = ensure_account(),
    ensure_callflow(AccountDb, ?NUMBER),
    io:format("~nBootstrap complete. Call ~s@~s from the Erlang shell with a route_req.~n"
             ,[?NUMBER, ?REALM]).

ensure_account() ->
    case rpc:call(?NODE, 'kapps_util', 'get_account_by_realm', [?REALM]) of
        {'ok', Db} ->
            Id = rpc:call(?NODE, 'kz_util', 'format_account_id', [Db, 'raw']),
            io:format("==> account for ~s already exists: ~s~n", [?REALM, Id]),
            Db;
        _ ->
            io:format("==> creating master account 'testco' (realm ~s)~n", [?REALM]),
            R = rpc:call(?NODE, 'crossbar_maintenance', 'create_account'
                        ,[<<"testco">>, ?REALM, <<"admin">>, <<"secret1234!">>], 120000),
            io:format("==> create_account -> ~p~n", [R]),
            {'ok', Db} = rpc:call(?NODE, 'kapps_util', 'get_account_by_realm', [?REALM]),
            Db
    end.

ensure_callflow(Db, Number) ->
    New = rpc:call(?NODE, 'kz_json', 'new', []),
    Data = setv([{<<"code">>, <<"200">>}], New),
    Flow = setv([{<<"module">>, <<"response">>}, {<<"data">>, Data}, {<<"children">>, New}], New),
    Doc = setv([{<<"_id">>, <<"dev_cf_", Number/binary>>}
               ,{<<"pvt_type">>, <<"callflow">>}
               ,{<<"numbers">>, [Number]}
               ,{<<"flow">>, Flow}
               ], New),
    case rpc:call(?NODE, 'kz_datamgr', 'save_doc', [Db, Doc]) of
        {'ok', _} -> io:format("==> callflow for ~s: created~n", [Number]);
        {'error', 'conflict'} -> io:format("==> callflow for ~s: already exists~n", [Number]);
        E -> io:format("==> callflow for ~s: save error ~p~n", [Number, E])
    end.

setv(KVs, J) ->
    lists:foldl(fun({K, V}, Acc) -> rpc:call(?NODE, 'kz_json', 'set_value', [K, V, Acc]) end, J, KVs).
