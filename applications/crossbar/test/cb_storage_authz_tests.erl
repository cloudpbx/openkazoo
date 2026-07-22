%%%-----------------------------------------------------------------------------
%%% @doc Regression tests for cb_storage owner-authz scope gating.
%%% cb_storage binds the GLOBAL `*.authorize' hook, so its authorize/N runs on
%%% every request. The owner deny must apply ONLY to storage scopes; a
%%% non-storage request must defer (`false'), not be hard-denied.
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_storage_authz_tests).
-include_lib("eunit/include/eunit.hrl").

-define(ACCT, <<"account0000000000000000000000001">>).

authorize_scope_gating_test_() ->
    {'setup', fun setup/0, fun cleanup/1,
     [ {"enforced + NON-storage request -> defer (false), not hard-deny",
        ?_assertEqual('false', authorize(non_storage_nouns(), 'true'))}
     , {"enforced + storage(account) request -> hard deny {stop,_}",
        ?_assertMatch({'stop', _}, authorize(storage_account_nouns(), 'true'))}
     , {"not enforced (admin/flag-off) + storage(account), same account -> allow (true)",
        ?_assertEqual('true', authorize(storage_account_nouns(), 'false'))}
     , {"not enforced + NON-storage request -> defer (false)",
        ?_assertEqual('false', authorize(non_storage_nouns(), 'false'))}
     ]}.

%% Drive cb_storage:authorize/1 with a chosen req_nouns and is_enforced value.
authorize(Nouns, Enforced) ->
    meck:expect('cb_context', 'req_nouns', fun(_) -> Nouns end),
    meck:expect('crossbar_owner_authz', 'is_enforced', fun(_) -> Enforced end),
    cb_storage:authorize('ctx').

non_storage_nouns() ->
    [{<<"devices">>, []}, {<<"accounts">>, [?ACCT]}].

storage_account_nouns() ->
    [{<<"storage">>, []}, {<<"accounts">>, [?ACCT]}].

setup() ->
    meck:new('cb_context', ['non_strict']),
    meck:new('crossbar_owner_authz', ['non_strict']),
    meck:new('kz_services_reseller', ['non_strict']),
    %% set_scope/1 helpers
    meck:expect('cb_context', 'setters', fun(C, _) -> C end),
    meck:expect('cb_context', 'set_account_db', fun(C, _) -> C end),
    meck:expect('cb_context', 'store', fun(_C, 'scope', V) -> erlang:put({'t', 'scope'}, V), 'ctx' end),
    meck:expect('cb_context', 'fetch', fun(_C, 'scope') -> erlang:get({'t', 'scope'}) end),
    %% do_authorize/2 for {account, Acct}
    meck:expect('cb_context', 'is_superduper_admin', fun(_) -> 'false' end),
    meck:expect('cb_context', 'auth_account_id', fun(_) -> ?ACCT end),
    meck:expect('kz_services_reseller', 'get_id', fun(_) -> <<"someresellerid">> end),
    %% deny path
    meck:expect('cb_context', 'add_system_error', fun('forbidden', _C) -> {'forbidden_ctx'} end),
    'ok'.

cleanup(_) ->
    meck:unload('cb_context'),
    meck:unload('crossbar_owner_authz'),
    catch meck:unload('kz_services_reseller'),
    'ok'.
