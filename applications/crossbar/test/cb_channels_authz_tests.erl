%%%-----------------------------------------------------------------------------
%%% @doc Owner-authz for cb_channels: when enforced, a restricted user may only
%%% see/act on their own channels. Account-wide list scoped (filter) / denied
%%% (reject); user/device/group channel lists gated to owned; a specific channel
%%% (read + actions) denied at validate/2.
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_channels_authz_tests).
-include_lib("eunit/include/eunit.hrl").

-define(ACCT, <<"account0000000000000000000000001">>).
-define(A1, <<"user00000000000000000000000000001">>).
-define(A2, <<"user00000000000000000000000000002">>).
-define(DEV, <<"device0000000000000000000000001">>).
-define(GRP, <<"group00000000000000000000000001">>).

acct(N) -> [{<<"channels">>, []}, {<<"accounts">>, [?ACCT]} | N].
uchan(U) -> [{<<"channels">>, []}, {<<"users">>, [U]}, {<<"accounts">>, [?ACCT]}].
dchan() -> [{<<"channels">>, []}, {<<"devices">>, [?DEV]}, {<<"accounts">>, [?ACCT]}].
gchan() -> [{<<"channels">>, []}, {<<"groups">>, [?GRP]}, {<<"accounts">>, [?ACCT]}].

authorize_test_() ->
    {'setup', fun setup/0, fun cleanup/1,
     [ {"not enforced -> defer", ?_assertEqual('false', az(#{enf=>'false', nouns=>acct([])}))}
     , {"account-wide filter -> defer(scoped later)", ?_assertEqual('false', az(#{enf=>'true', mode=><<"filter">>, nouns=>acct([])}))}
     , {"account-wide reject -> stop", ?_assertEqual('stop', az(#{enf=>'true', mode=><<"reject">>, nouns=>acct([])}))}
     , {"users self -> allow", ?_assertEqual('false', az(#{enf=>'true', nouns=>uchan(?A1)}))}
     , {"users other -> stop", ?_assertEqual('stop', az(#{enf=>'true', nouns=>uchan(?A2)}))}
     , {"device owned -> allow", ?_assertEqual('false', az(#{enf=>'true', nouns=>dchan(), owner=>?A1}))}
     , {"device other -> stop", ?_assertEqual('stop', az(#{enf=>'true', nouns=>dchan(), owner=>?A2}))}
     , {"group member -> allow", ?_assertEqual('false', az(#{enf=>'true', nouns=>gchan(), doc=>grp_doc('true')}))}
     , {"group non-member -> stop", ?_assertEqual('stop', az(#{enf=>'true', nouns=>gchan(), doc=>grp_doc('false')}))}
     , {"non-channels request -> defer", ?_assertEqual('false', az(#{enf=>'true', nouns=>[{<<"devices">>, []}, {<<"accounts">>, [?ACCT]}]}))}
     ]}.

validate_specific_test_() ->
    {'setup', fun setup/0, fun cleanup/1,
     [ {"enforced -> specific channel denied (forbidden)",
        ?_assertEqual('denied', begin
                                    meck:expect('crossbar_owner_authz', 'is_enforced', fun(_) -> 'true' end),
                                    meck:expect('cb_context', 'add_system_error', fun('forbidden', _C) -> 'denied' end),
                                    cb_channels:validate('ctx', <<"callid">>)
                                end)}
     ]}.

grp_doc('true')  -> kz_json:from_list([{<<"endpoints">>, kz_json:from_list([{?A1, kz_json:new()}])}]);
grp_doc('false') -> kz_json:from_list([{<<"endpoints">>, kz_json:from_list([{?A2, kz_json:new()}])}]).

az(M) ->
    meck:expect('crossbar_owner_authz', 'is_enforced', fun(_) -> maps:get('enf', M) end),
    meck:expect('crossbar_owner_authz', 'general_endpoint_mode', fun(_) -> maps:get('mode', M, <<"filter">>) end),
    meck:expect('crossbar_owner_authz', 'doc_owner_id', fun(_) -> maps:get('owner', M, ?A1) end),
    meck:expect('cb_context', 'req_nouns', fun(_) -> maps:get('nouns', M) end),
    meck:expect('cb_context', 'auth_user_id', fun(_) -> ?A1 end),
    meck:expect('cb_context', 'auth_account_id', fun(_) -> ?ACCT end),
    meck:expect('cb_context', 'account_db', fun(_) -> <<"db">> end),
    meck:expect('cb_context', 'add_system_error', fun('forbidden', _C) -> {'stop', 'x'} end),
    meck:expect('kz_datamgr', 'open_cache_doc', fun(_, _) -> {'ok', maps:get('doc', M, kz_json:new())} end),
    case cb_channels:authorize('ctx') of
        'false' -> 'false';
        'true' -> 'true';
        {'stop', _} -> 'stop';
        O -> {'other', O}
    end.

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
