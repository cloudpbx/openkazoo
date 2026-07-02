-module(bh_owner_authz_tests).
-include_lib("eunit/include/eunit.hrl").

-define(ACCT, <<"account0000000000000000000000001">>).
-define(USER, <<"user00000000000000000000000000001">>).

is_enforced_test_() ->
    {'setup', fun setup/0, fun cleanup/1, fun(_) ->
        [
            {"flag off -> not enforced",
                ?_assertEqual(
                    'false', enf(#{flag => 'false', sa => 'false', aa => 'false', user => ?USER})
                )},
            {"flag on, regular user -> enforced",
                ?_assertEqual(
                    'true', enf(#{flag => 'true', sa => 'false', aa => 'false', user => ?USER})
                )},
            {"flag on, superduper admin -> bypass",
                ?_assertEqual(
                    'false', enf(#{flag => 'true', sa => 'true', aa => 'false', user => ?USER})
                )},
            {"flag on, account admin -> bypass",
                ?_assertEqual(
                    'false', enf(#{flag => 'true', sa => 'false', aa => 'true', user => ?USER})
                )},
            {"flag on, no auth user -> not enforced",
                ?_assertEqual(
                    'false',
                    enf(#{flag => 'true', sa => 'false', aa => 'false', user => 'undefined'})
                )}
        ]
    end}.

should_deliver_test_() ->
    {'setup', fun setup/0, fun cleanup/1, fun(_) ->
        Mine = kz_json:from_list([{<<"owner_id">>, ?USER}]),
        Other = kz_json:from_list([{<<"owner_id">>, <<"someone_else">>}]),
        NoOwner = kz_json:from_list([{<<"event_name">>, <<"CHANNEL_CREATE">>}]),
        [
            {"not enforced -> always deliver",
                ?_assertEqual(
                    'true',
                    del(#{flag => 'false', sa => 'false', aa => 'false', user => ?USER}, Mine)
                )},
            {"enforced, owner matches -> deliver",
                ?_assertEqual(
                    'true',
                    del(#{flag => 'true', sa => 'false', aa => 'false', user => ?USER}, Mine)
                )},
            {"enforced, owner differs -> drop",
                ?_assertEqual(
                    'false',
                    del(#{flag => 'true', sa => 'false', aa => 'false', user => ?USER}, Other)
                )},
            {"enforced, no resolvable owner -> drop (fail-closed)",
                ?_assertEqual(
                    'false',
                    del(#{flag => 'true', sa => 'false', aa => 'false', user => ?USER}, NoOwner)
                )}
        ]
    end}.

enf(#{flag := F, sa := SA, aa := AA, user := U}) ->
    stub(F, SA, AA, U),
    bh_owner_authz:is_enforced('ctx').

del(#{flag := F, sa := SA, aa := AA, user := U}, JObj) ->
    stub(F, SA, AA, U),
    bh_owner_authz:should_deliver('ctx', JObj).

stub(F, SA, AA, U) ->
    meck:expect('bh_context', 'auth_account_id', fun(_) -> ?ACCT end),
    meck:expect('bh_context', 'auth_user_id', fun(_) -> U end),
    meck:expect('bh_context', 'is_superduper_admin', fun(_) -> SA end),
    meck:expect('bh_context', 'is_account_admin', fun(_) -> AA end),
    meck:expect(
        'kapps_account_config',
        'get_global',
        fun
            (_, _, <<"should_restrict_access_to_owner">>, _) -> F;
            (_, _, _, D) -> D
        end
    ).

setup() ->
    meck:new('bh_context', ['non_strict']),
    meck:new('kapps_account_config', ['non_strict']),
    'ok'.

cleanup(_) ->
    meck:unload('bh_context'),
    meck:unload('kapps_account_config'),
    'ok'.
