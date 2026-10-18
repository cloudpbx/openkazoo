-module(ecallmgr_fs_router_call_tests).

-spec test() -> 'ok'.

-include("src/ecallmgr.hrl").
-include_lib("eunit/include/eunit.hrl").

-spec interaction_props_keeps_existing_ccv_test() -> any().
interaction_props_keeps_existing_ccv_test() ->
    FSData = [{?GET_CCV(<<?CALL_INTERACTION_ID>>), <<"63959390461-7ff3e916">>}],
    ?assertEqual([], ecallmgr_fs_router_call:interaction_props('node', <<"call-id">>, FSData)).

-spec interaction_props_adopts_legacy_header_test() -> any().
interaction_props_adopts_legacy_header_test() ->
    FSData = [{?GET_CUSTOM_HEADER(<<"Call-Interaction-ID">>), <<"63959390461-legacy">>}],
    ?assertEqual([{?GET_CCV(<<?CALL_INTERACTION_ID>>), <<"63959390461-legacy">>}]
                 ,ecallmgr_fs_router_call:interaction_props('node', <<"call-id">>, FSData)
                 ).

-spec interaction_props_adopts_kazoo_header_test() -> any().
interaction_props_adopts_kazoo_header_test() ->
    FSData = [{?GET_CUSTOM_HEADER(<<"Kazoo-Interaction-ID">>), <<"63959390461-7ff3e916">>}],
    ?assertEqual([{?GET_CCV(<<?CALL_INTERACTION_ID>>), <<"63959390461-7ff3e916">>}]
                 ,ecallmgr_fs_router_call:interaction_props('node', <<"call-id">>, FSData)
                 ).

-spec interaction_props_legacy_header_wins_over_kazoo_header_test() -> any().
interaction_props_legacy_header_wins_over_kazoo_header_test() ->
    FSData = [{?GET_CUSTOM_HEADER(<<"Call-Interaction-ID">>), <<"63959390461-legacy">>}
             ,{?GET_CUSTOM_HEADER(<<"Kazoo-Interaction-ID">>), <<"63959390461-kazoo">>}
             ],
    ?assertEqual([{?GET_CCV(<<?CALL_INTERACTION_ID>>), <<"63959390461-legacy">>}]
                 ,ecallmgr_fs_router_call:interaction_props('node', <<"call-id">>, FSData)
                 ).

-spec interaction_props_mints_default_when_neither_present_test() -> any().
interaction_props_mints_default_when_neither_present_test() ->
    [{Key, Id}] = ecallmgr_fs_router_call:interaction_props('node', <<"call-id">>, []),
    ?assertEqual(?GET_CCV(<<?CALL_INTERACTION_ID>>), Key),
    ?assertMatch({'match', _}, re:run(Id, "^[0-9]+-[0-9a-f]{8}$")).
