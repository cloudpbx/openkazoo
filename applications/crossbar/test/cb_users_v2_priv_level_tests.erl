%%%-----------------------------------------------------------------------------
%%% @doc Guard: only an admin may set/change a user's priv_level. A non-admin
%%% (e.g. self-PATCH to `admin') must be denied, else owner-authz / the account
%%% boundary is trivially bypassable. See cb_users_v2:maybe_deny_priv_level_change/3.
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_users_v2_priv_level_tests).
-include_lib("eunit/include/eunit.hrl").

-define(A1, <<"user0000000000000000000000000001">>).

priv_level_guard_test_() ->
    {'setup', fun setup/0, fun cleanup/1,
     [ {"non-admin, priv_level unchanged -> allowed",
        ?_assertEqual('ctx', run(#{admin => 'none', current => <<"user">>, requested => <<"user">>, uid => ?A1}))}
     , {"non-admin, user->admin -> DENIED",
        ?_assertEqual('denied', run(#{admin => 'none', current => <<"user">>, requested => <<"admin">>, uid => ?A1}))}
     , {"account-admin, user->admin -> allowed",
        ?_assertEqual('ctx', run(#{admin => 'account', current => <<"user">>, requested => <<"admin">>, uid => ?A1}))}
     , {"super-duper admin, user->admin -> allowed",
        ?_assertEqual('ctx', run(#{admin => 'super', current => <<"user">>, requested => <<"admin">>, uid => ?A1}))}
     , {"create (undefined), non-admin, priv_level=admin -> DENIED",
        ?_assertEqual('denied', run(#{admin => 'none', requested => <<"admin">>, uid => 'undefined'}))}
     , {"create (undefined), non-admin, priv_level=user -> allowed",
        ?_assertEqual('ctx', run(#{admin => 'none', requested => <<"user">>, uid => 'undefined'}))}
     , {"context already has errors -> skip (unchanged)",
        ?_assertEqual('ctx', run(#{admin => 'none', current => <<"user">>, requested => <<"admin">>, uid => ?A1, errors => 'true'}))}
     ]}.

run(M) ->
    Admin = maps:get('admin', M, 'none'),
    Current = maps:get('current', M, <<"user">>),
    Requested = maps:get('requested', M),
    Uid = maps:get('uid', M),
    Errors = maps:get('errors', M, 'false'),
    meck:expect('cb_context', 'has_errors', fun(_) -> Errors end),
    meck:expect('cb_context', 'is_account_admin', fun(_) -> Admin =:= 'account' end),
    meck:expect('cb_context', 'is_superduper_admin', fun(_) -> Admin =:= 'super' end),
    meck:expect('cb_context', 'account_db', fun(_) -> <<"accountdb">> end),
    meck:expect('cb_context', 'add_system_error', fun('forbidden', _Msg, _C) -> 'denied' end),
    meck:expect('kz_datamgr', 'open_cache_doc', fun(_, _) -> {'ok', kz_json:from_list([{<<"priv_level">>, Current}])} end),
    ValidatedDoc = kz_json:from_list([{<<"priv_level">>, Requested}]),
    cb_users_v2:maybe_deny_priv_level_change(Uid, ValidatedDoc, 'ctx').

setup() ->
    meck:new('cb_context', ['non_strict']),
    meck:new('kz_datamgr', ['non_strict']),
    'ok'.

cleanup(_) ->
    meck:unload('cb_context'),
    meck:unload('kz_datamgr'),
    'ok'.
