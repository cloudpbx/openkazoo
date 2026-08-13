-module(crossbar_owner_authz_tests).
-include_lib("eunit/include/eunit.hrl").

-define(ACCT, <<"account0000000000000000000000001">>).
-define(USER, <<"user00000000000000000000000000001">>).

is_enforced_test_() ->
    {'setup', fun setup/0, fun cleanup/1, fun(_) ->
        [
            {"off by default -> not enforced",
                ?_assertEqual(
                    'false',
                    with(
                        #{flag => 'false', sa => 'false', aa => 'false', user => ?USER},
                        fun crossbar_owner_authz:is_enforced/1
                    )
                )},
            {"flag on, regular user -> enforced",
                ?_assertEqual(
                    'true',
                    with(
                        #{flag => 'true', sa => 'false', aa => 'false', user => ?USER},
                        fun crossbar_owner_authz:is_enforced/1
                    )
                )},
            {"flag on, superduper admin -> bypass",
                ?_assertEqual(
                    'false',
                    with(
                        #{flag => 'true', sa => 'true', aa => 'false', user => ?USER},
                        fun crossbar_owner_authz:is_enforced/1
                    )
                )},
            {"flag on, account admin -> bypass",
                ?_assertEqual(
                    'false',
                    with(
                        #{flag => 'true', sa => 'false', aa => 'true', user => ?USER},
                        fun crossbar_owner_authz:is_enforced/1
                    )
                )},
            {"flag on, no auth user -> not enforced",
                ?_assertEqual(
                    'false',
                    with(
                        #{flag => 'true', sa => 'false', aa => 'false', user => 'undefined'},
                        fun crossbar_owner_authz:is_enforced/1
                    )
                )},
            %% Undefined auth_account_id path: get_global is stubbed to return the
            %% flag value 'false' for an undefined account (no per-account config),
            %% so restrict_to_owner/1 short-circuits and is_enforced/1 returns
            %% 'false' without crashing. Exercises the undefined-account branch.
            {"undefined auth account -> not enforced (total, no crash)",
                ?_assertEqual(
                    'false',
                    with(
                        #{
                            flag => 'false',
                            sa => 'false',
                            aa => 'false',
                            user => ?USER,
                            acct => 'undefined'
                        },
                        fun crossbar_owner_authz:is_enforced/1
                    )
                )}
        ]
    end}.

%% Build a fake context and stub cb_context + kapps_account_config for one call.
%% `acct' is optional and overrides the stubbed auth_account_id (default ?ACCT).
with(#{flag := Flag, sa := SA, aa := AA, user := User} = Args, Fun) ->
    Acct = maps:get('acct', Args, ?ACCT),
    meck:expect('cb_context', 'auth_account_id', fun(_) -> Acct end),
    meck:expect('cb_context', 'auth_user_id', fun(_) -> User end),
    meck:expect('cb_context', 'is_superduper_admin', fun(_) -> SA end),
    meck:expect('cb_context', 'is_account_admin', fun(_) -> AA end),
    meck:expect(
        'kapps_account_config',
        'get_global',
        fun
            (_A, _C, <<"should_restrict_access_to_owner">>, _D) -> Flag;
            (_A, _C, _K, D) -> D
        end
    ),
    Fun('fake_context').

authorize_collection_test_() ->
    {'setup', fun setup/0, fun cleanup/1, fun(_) ->
        [
            {"not enforced -> defer (false)",
                ?_assertEqual(
                    'false',
                    col(#{
                        flag => 'false',
                        mode => <<"filter">>,
                        user => ?USER,
                        nouns => [{<<"cdrs">>, []}, {<<"accounts">>, [?ACCT]}]
                    })
                )},
            {"enforced account-wide, filter mode -> defer (false)",
                ?_assertEqual(
                    'false',
                    col(#{
                        flag => 'true',
                        mode => <<"filter">>,
                        user => ?USER,
                        nouns => [{<<"cdrs">>, []}, {<<"accounts">>, [?ACCT]}]
                    })
                )},
            {"enforced account-wide, reject mode -> stop",
                ?_assertMatch(
                    {'stop', _},
                    col(#{
                        flag => 'true',
                        mode => <<"reject">>,
                        user => ?USER,
                        nouns => [{<<"cdrs">>, []}, {<<"accounts">>, [?ACCT]}]
                    })
                )},
            {"enforced /users/self -> allow (true)",
                ?_assertEqual(
                    'true',
                    col(#{
                        flag => 'true',
                        mode => <<"filter">>,
                        user => ?USER,
                        nouns => [
                            {<<"cdrs">>, []}, {<<"users">>, [?USER]}, {<<"accounts">>, [?ACCT]}
                        ]
                    })
                )},
            {"enforced /users/other -> stop",
                ?_assertMatch(
                    {'stop', _},
                    col(#{
                        flag => 'true',
                        mode => <<"filter">>,
                        user => ?USER,
                        nouns => [
                            {<<"cdrs">>, []},
                            {<<"users">>, [<<"other">>]},
                            {<<"accounts">>, [?ACCT]}
                        ]
                    })
                )},
            {"superduper admin, reject mode, account-wide -> defer (false), never blocked",
                ?_assertEqual(
                    'false',
                    col(#{
                        flag => 'true',
                        mode => <<"reject">>,
                        user => ?USER,
                        sa => 'true',
                        nouns => [{<<"cdrs">>, []}, {<<"accounts">>, [?ACCT]}]
                    })
                )},
            {"account admin, reject mode, /users/other -> defer (false), never blocked",
                ?_assertEqual(
                    'false',
                    col(#{
                        flag => 'true',
                        mode => <<"reject">>,
                        user => ?USER,
                        aa => 'true',
                        nouns => [
                            {<<"cdrs">>, []},
                            {<<"users">>, [<<"other">>]},
                            {<<"accounts">>, [?ACCT]}
                        ]
                    })
                )}
        ]
    end}.

col(#{flag := Flag, mode := Mode, user := User, nouns := Nouns} = Args) ->
    SA = maps:get('sa', Args, 'false'),
    AA = maps:get('aa', Args, 'false'),
    meck:expect('cb_context', 'auth_account_id', fun(_) -> ?ACCT end),
    meck:expect('cb_context', 'auth_user_id', fun(_) -> User end),
    meck:expect('cb_context', 'is_superduper_admin', fun(_) -> SA end),
    meck:expect('cb_context', 'is_account_admin', fun(_) -> AA end),
    meck:expect('cb_context', 'req_nouns', fun(_) -> Nouns end),
    meck:expect('cb_context', 'add_system_error', fun('forbidden', _C) -> {'forbidden_ctx'} end),
    meck:expect(
        'kapps_account_config',
        'get_global',
        fun
            (_A, _C, <<"should_restrict_access_to_owner">>, _D) -> Flag;
            (_A, _C, <<"general_endpoint_mode">>, _D) -> Mode;
            (_A, _C, _K, D) -> D
        end
    ),
    crossbar_owner_authz:authorize_collection('fake_context').

authorize_doc_test_() ->
    {'setup', fun setup/0, fun cleanup/1, fun(_) ->
        [
            {"not enforced -> context unchanged",
                ?_assertEqual(
                    'ctx',
                    doc(#{flag => 'false', unowned => 'false', user => ?USER, owner => <<"other">>})
                )},
            {"owner matches auth user -> unchanged",
                ?_assertEqual(
                    'ctx', doc(#{flag => 'true', unowned => 'false', user => ?USER, owner => ?USER})
                )},
            {"owner differs -> forbidden",
                ?_assertEqual(
                    {'forbidden_ctx'},
                    doc(#{flag => 'true', unowned => 'false', user => ?USER, owner => <<"other">>})
                )},
            {"unowned, restrict_unowned off -> unchanged",
                ?_assertEqual(
                    'ctx',
                    doc(#{flag => 'true', unowned => 'false', user => ?USER, owner => 'undefined'})
                )},
            {"unowned, restrict_unowned on -> forbidden",
                ?_assertEqual(
                    {'forbidden_ctx'},
                    doc(#{flag => 'true', unowned => 'true', user => ?USER, owner => 'undefined'})
                )},
            {"unowned, restrict_unowned UNSET -> forbidden (fail-closed default)",
                ?_assertEqual(
                    {'forbidden_ctx'},
                    doc_default(#{flag => 'true', user => ?USER, owner => 'undefined'})
                )}
        ]
    end}.

%% Like doc/1 but does NOT stub should_restrict_access_to_unowned, so the code's
%% own default governs. Locks the fail-closed default.
doc_default(#{flag := Flag, user := User, owner := Owner}) ->
    meck:expect('cb_context', 'auth_account_id', fun(_) -> ?ACCT end),
    meck:expect('cb_context', 'auth_user_id', fun(_) -> User end),
    meck:expect('cb_context', 'is_superduper_admin', fun(_) -> 'false' end),
    meck:expect('cb_context', 'is_account_admin', fun(_) -> 'false' end),
    meck:expect('cb_context', 'add_system_error', fun('forbidden', _C) -> {'forbidden_ctx'} end),
    meck:expect(
        'kapps_account_config',
        'get_global',
        fun
            (_A, _C, <<"should_restrict_access_to_owner">>, _D) -> Flag;
            (_A, _C, _K, D) -> D
        end
    ),
    crossbar_owner_authz:authorize_doc('ctx', Owner).

doc(#{flag := Flag, unowned := Unowned, user := User, owner := Owner}) ->
    meck:expect('cb_context', 'auth_account_id', fun(_) -> ?ACCT end),
    meck:expect('cb_context', 'auth_user_id', fun(_) -> User end),
    meck:expect('cb_context', 'is_superduper_admin', fun(_) -> 'false' end),
    meck:expect('cb_context', 'is_account_admin', fun(_) -> 'false' end),
    meck:expect('cb_context', 'add_system_error', fun('forbidden', _C) -> {'forbidden_ctx'} end),
    meck:expect(
        'kapps_account_config',
        'get_global',
        fun
            (_A, _C, <<"should_restrict_access_to_owner">>, _D) -> Flag;
            (_A, _C, <<"should_restrict_access_to_unowned">>, _D) -> Unowned;
            (_A, _C, _K, D) -> D
        end
    ),
    crossbar_owner_authz:authorize_doc('ctx', Owner).

maybe_scope_nouns_test_() ->
    {'setup', fun setup/0, fun cleanup/1, fun(_) ->
        AcctNouns = [{<<"cdrs">>, []}, {<<"accounts">>, [?ACCT]}],
        ScopedNouns = [{<<"cdrs">>, []}, {<<"users">>, [?USER]}, {<<"accounts">>, [?ACCT]}],
        IntAcct = [{<<"cdrs">>, [<<"interaction">>]}, {<<"accounts">>, [?ACCT]}],
        IntScoped = [
            {<<"cdrs">>, [<<"interaction">>]}, {<<"users">>, [?USER]}, {<<"accounts">>, [?ACCT]}
        ],
        [
            {"not enforced -> nouns unchanged",
                ?_assertEqual(
                    AcctNouns,
                    scope(#{flag => 'false', mode => <<"filter">>, user => ?USER}, AcctNouns)
                )},
            {"reject mode -> nouns unchanged",
                ?_assertEqual(
                    AcctNouns,
                    scope(#{flag => 'true', mode => <<"reject">>, user => ?USER}, AcctNouns)
                )},
            {"filter mode, account-wide -> inject users noun",
                ?_assertEqual(
                    ScopedNouns,
                    scope(#{flag => 'true', mode => <<"filter">>, user => ?USER}, AcctNouns)
                )},
            {"filter mode, interaction account-wide -> inject users noun",
                ?_assertEqual(
                    IntScoped,
                    scope(#{flag => 'true', mode => <<"filter">>, user => ?USER}, IntAcct)
                )},
            {"filter mode, already users-scoped -> unchanged",
                ?_assertEqual(
                    ScopedNouns,
                    scope(#{flag => 'true', mode => <<"filter">>, user => ?USER}, ScopedNouns)
                )}
        ]
    end}.

scope(#{flag := Flag, mode := Mode, user := User}, Nouns) ->
    meck:expect('cb_context', 'auth_account_id', fun(_) -> ?ACCT end),
    meck:expect('cb_context', 'auth_user_id', fun(_) -> User end),
    meck:expect('cb_context', 'is_superduper_admin', fun(_) -> 'false' end),
    meck:expect('cb_context', 'is_account_admin', fun(_) -> 'false' end),
    meck:expect(
        'kapps_account_config',
        'get_global',
        fun
            (_A, _C, <<"should_restrict_access_to_owner">>, _D) -> Flag;
            (_A, _C, <<"general_endpoint_mode">>, _D) -> Mode;
            (_A, _C, _K, D) -> D
        end
    ),
    crossbar_owner_authz:maybe_scope_nouns('fake_context', Nouns).

filter_owned_test_() ->
    {'setup', fun setup/0, fun cleanup/1, fun(_) ->
        Mine = kz_json:from_list([{<<"owner_id">>, ?USER}, {<<"leg">>, <<"a">>}]),
        Bridged = kz_json:from_list([{<<"owner_id">>, <<"other">>}, {<<"leg">>, <<"b">>}]),
        Unowned = kz_json:from_list([{<<"leg">>, <<"c">>}]),
        MineCcv = kz_json:from_list([
            {<<"custom_channel_vars">>, kz_json:from_list([{<<"owner_id">>, ?USER}])},
            {<<"leg">>, <<"d">>}
        ]),
        BridgedCcv = kz_json:from_list([
            {<<"custom_channel_vars">>, kz_json:from_list([{<<"owner_id">>, <<"other">>}])},
            {<<"leg">>, <<"e">>}
        ]),
        [
            {"not enforced -> all legs",
                ?_assertEqual(
                    [Mine, Bridged, Unowned],
                    fo(#{flag => 'false', unowned => 'false', user => ?USER}, [
                        Mine, Bridged, Unowned
                    ])
                )},
            {"enforced -> only my legs, bridged dropped",
                ?_assertEqual(
                    [Mine, Unowned],
                    fo(#{flag => 'true', unowned => 'false', user => ?USER}, [
                        Mine, Bridged, Unowned
                    ])
                )},
            {"enforced + restrict_unowned -> only my legs",
                ?_assertEqual(
                    [Mine],
                    fo(#{flag => 'true', unowned => 'true', user => ?USER}, [Mine, Bridged, Unowned])
                )},
            %% Regression: real CDR legs carry the owner under
            %% custom_channel_vars.owner_id, not a top-level owner_id.
            {"enforced -> ccv.owner_id legs attributed correctly (regression)",
                ?_assertEqual(
                    [MineCcv],
                    fo(#{flag => 'true', unowned => 'false', user => ?USER}, [MineCcv, BridgedCcv])
                )}
        ]
    end}.

fo(#{flag := Flag, unowned := Unowned, user := User}, JObjs) ->
    meck:expect('cb_context', 'auth_account_id', fun(_) -> ?ACCT end),
    meck:expect('cb_context', 'auth_user_id', fun(_) -> User end),
    meck:expect('cb_context', 'is_superduper_admin', fun(_) -> 'false' end),
    meck:expect('cb_context', 'is_account_admin', fun(_) -> 'false' end),
    meck:expect(
        'kapps_account_config',
        'get_global',
        fun
            (_A, _C, <<"should_restrict_access_to_owner">>, _D) -> Flag;
            (_A, _C, <<"should_restrict_access_to_unowned">>, _D) -> Unowned;
            (_A, _C, _K, D) -> D
        end
    ),
    crossbar_owner_authz:filter_owned('fake_context', JObjs).

setup() ->
    meck:new('cb_context', ['non_strict']),
    meck:new('kapps_account_config', ['non_strict']),
    'ok'.

cleanup(_) ->
    meck:unload('cb_context'),
    meck:unload('kapps_account_config'),
    'ok'.
