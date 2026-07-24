%%%-----------------------------------------------------------------------------
%%% @doc Quickcall origination must be owner-gated when owner-authz is enforced:
%%% a restricted user may only quickcall a device they own / their own user.
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_quickcall_authz_tests).
-include_lib("eunit/include/eunit.hrl").

-define(ACCT, <<"account0000000000000000000000001">>).
-define(A1, <<"user00000000000000000000000000001">>).
-define(A2, <<"user00000000000000000000000000002">>).
-define(DEV, <<"device0000000000000000000000001">>).

device_quickcall_test_() ->
    {'setup', fun setup/0, fun cleanup/1,
     [ {"not enforced -> allow",
        ?_assertEqual('true', dev(#{enforced => 'false', owner => ?A2}))}
     , {"enforced, own device -> allow",
        ?_assertEqual('true', dev(#{enforced => 'true', owner => ?A1}))}
     , {"enforced, other's device -> stop 403",
        ?_assertMatch({'stop', _}, dev(#{enforced => 'true', owner => ?A2}))}
     , {"enforced, device not found -> stop 403 (fail-closed)",
        ?_assertMatch({'stop', _}, dev(#{enforced => 'true', owner => 'missing'}))}
     ]}.

user_quickcall_test_() ->
    {'setup', fun setup/0, fun cleanup/1,
     [ {"not enforced -> allow (true)",
        ?_assertEqual('true', usr(#{enforced => 'false', target => ?A2}))}
     , {"enforced, own user -> allow (true)",
        ?_assertEqual('true', usr(#{enforced => 'true', target => ?A1}))}
     , {"enforced, other user -> stop 403",
        ?_assertMatch({'stop', _}, usr(#{enforced => 'true', target => ?A2}))}
     ]}.

dev(#{enforced := Enf, owner := Owner}) ->
    meck:expect('crossbar_owner_authz', 'is_enforced', fun(_) -> Enf end),
    meck:expect('crossbar_owner_authz', 'doc_owner_id', fun(_) -> Owner end),
    meck:expect('cb_context', 'auth_user_id', fun(_) -> ?A1 end),
    meck:expect('cb_context', 'account_db', fun(_) -> <<"accountdb">> end),
    meck:expect('cb_context', 'add_system_error', fun('forbidden', _C) -> {'stop', 'forbidden_ctx'} end),
    OpenRet = case Owner of 'missing' -> {'error', 'not_found'}; _ -> {'ok', kz_json:new()} end,
    meck:expect('kz_datamgr', 'open_cache_doc', fun(_, _) -> OpenRet end),
    R = cb_devices_v2:authorize_quickcall('ctx', ?DEV),
    case R of {'stop', {'stop', 'forbidden_ctx'}} -> {'stop', 'x'}; _ -> R end.

usr(#{enforced := Enf, target := Target}) ->
    Nouns = [{<<"quickcall">>, [<<"1000">>]}, {<<"users">>, [Target]}, {<<"accounts">>, [?ACCT]}],
    meck:expect('crossbar_owner_authz', 'is_enforced', fun(_) -> Enf end),
    meck:expect('cb_context', 'req_nouns', fun(_) -> Nouns end),
    meck:expect('cb_context', 'req_verb', fun(_) -> <<"GET">> end),
    meck:expect('cb_context', 'auth_user_id', fun(_) -> ?A1 end),
    meck:expect('cb_context', 'auth_account_id', fun(_) -> ?ACCT end),
    meck:expect('cb_context', 'add_system_error', fun('forbidden', _C) -> {'stop', 'forbidden_ctx'} end),
    R = cb_users_v2:authorize('ctx'),
    case R of {'stop', {'stop', 'forbidden_ctx'}} -> {'stop', 'x'}; {'stop', _} -> {'stop', 'x'}; _ -> R end.

setup() ->
    meck:new('crossbar_owner_authz', ['non_strict']),
    meck:new('cb_context', ['non_strict']),
    meck:new('kz_datamgr', ['non_strict']),
    'ok'.
cleanup(_) ->
    meck:unload('crossbar_owner_authz'),
    meck:unload('cb_context'),
    meck:unload('kz_datamgr'),
    'ok'.
