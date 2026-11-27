%%%-----------------------------------------------------------------------------
%%% @doc Guard: an owner-restricted (non-admin) user may only write devices owned
%%% by themselves. Covers create, POST and PATCH via the one validated-doc check.
%%% See cb_devices_v2:maybe_deny_owner_change/1.
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_devices_v2_owner_tests).
-include_lib("eunit/include/eunit.hrl").

-define(ALICE, <<"user0000000000000000000000000001">>).
-define(BOB, <<"user0000000000000000000000000002">>).

owner_guard_test_() ->
    {'setup', fun setup/0, fun cleanup/1,
     [ {"restricted user, owner_id omitted -> stamped with auth user"
       ,?_assertEqual({'doc', ?ALICE}, run(#{enforced => 'true', owner => 'undefined'}))}
     , {"restricted user, owner_id = self -> allowed unchanged"
       ,?_assertEqual('ctx', run(#{enforced => 'true', owner => ?ALICE}))}
     , {"restricted user, owner_id = another user -> DENIED"
       ,?_assertEqual('denied', run(#{enforced => 'true', owner => ?BOB}))}
     , {"not enforced (admin or flag off), owner_id = another user -> allowed"
       ,?_assertEqual('ctx', run(#{enforced => 'false', owner => ?BOB}))}
     , {"not enforced, owner_id omitted -> NOT stamped (stock behaviour)"
       ,?_assertEqual('ctx', run(#{enforced => 'false', owner => 'undefined'}))}
     , {"context already has errors -> skipped, validation error wins"
       ,?_assertEqual('ctx', run(#{enforced => 'true', owner => ?BOB, errors => 'true'}))}
     ]}.

run(M) ->
    Enforced = maps:get('enforced', M),
    Owner = maps:get('owner', M),
    Errors = maps:get('errors', M, 'false'),
    Doc = case Owner of
              'undefined' -> kz_json:new();
              _ -> kz_json:from_list([{<<"owner_id">>, Owner}])
          end,
    meck:expect('cb_context', 'has_errors', fun(_) -> Errors end),
    meck:expect('cb_context', 'auth_user_id', fun(_) -> ?ALICE end),
    meck:expect('cb_context', 'doc', fun(_) -> Doc end),
    meck:expect('cb_context', 'set_doc', fun(_C, D) -> {'doc', kzd_devices:owner_id(D)} end),
    meck:expect('cb_context', 'add_system_error', fun('forbidden', _Msg, _C) -> 'denied' end),
    meck:expect('crossbar_owner_authz', 'is_enforced', fun(_) -> Enforced =:= 'true' end),
    cb_devices_v2:maybe_deny_owner_change('ctx').

setup() ->
    meck:new('cb_context', ['non_strict']),
    meck:new('crossbar_owner_authz', ['non_strict']),
    'ok'.

cleanup(_) ->
    meck:unload('cb_context'),
    meck:unload('crossbar_owner_authz'),
    'ok'.
