-module(ecallmgr_fs_bridge_tests).

-spec test() -> 'ok'.

-include("src/ecallmgr.hrl").
-include_lib("eunit/include/eunit.hrl").

-spec with_interaction_id(kz_term:ne_binary()) -> kz_json:object().
with_interaction_id(Id) ->
    kz_json:from_list([{<<"Custom-Channel-Vars">>
                       ,kz_json:from_list([{<<?CALL_INTERACTION_ID>>, Id}])
                       }
                      ]).

-spec carrier_endpoint() -> kz_json:object().
carrier_endpoint() ->
    kz_json:from_list([{<<"Invite-Format">>, <<"route">>}
                      ,{<<"Route">>, <<"sip:+15551234567@carrier.example.com">>}
                      ]).

-spec device_endpoint() -> kz_json:object().
device_endpoint() ->
    kz_json:from_list([{<<"Invite-Format">>, <<"username">>}
                      ,{<<"To-User">>, <<"to_user">>}
                      ,{<<"To-Realm">>, <<"to_realm">>}
                      ]).

-spec maybe_strip_interaction_id_strips_for_carrier_only_test() -> any().
maybe_strip_interaction_id_strips_for_carrier_only_test() ->
    JObj = with_interaction_id(<<"63959390461-7ff3e916">>),
    Stripped = ecallmgr_fs_bridge:maybe_strip_interaction_id([carrier_endpoint()], JObj),
    ?assertEqual('undefined'
                ,kz_json:get_ne_binary_value([<<"Custom-Channel-Vars">>, <<?CALL_INTERACTION_ID>>], Stripped)
                ).

-spec maybe_strip_interaction_id_keeps_for_device_test() -> any().
maybe_strip_interaction_id_keeps_for_device_test() ->
    JObj = with_interaction_id(<<"63959390461-7ff3e916">>),
    Kept = ecallmgr_fs_bridge:maybe_strip_interaction_id([device_endpoint()], JObj),
    ?assertEqual(<<"63959390461-7ff3e916">>
                ,kz_json:get_ne_binary_value([<<"Custom-Channel-Vars">>, <<?CALL_INTERACTION_ID>>], Kept)
                ).

-spec maybe_strip_interaction_id_keeps_for_mixed_test() -> any().
maybe_strip_interaction_id_keeps_for_mixed_test() ->
    JObj = with_interaction_id(<<"63959390461-7ff3e916">>),
    Kept = ecallmgr_fs_bridge:maybe_strip_interaction_id([carrier_endpoint(), device_endpoint()], JObj),
    ?assertEqual(<<"63959390461-7ff3e916">>
                ,kz_json:get_ne_binary_value([<<"Custom-Channel-Vars">>, <<?CALL_INTERACTION_ID>>], Kept)
                ).

-spec maybe_strip_interaction_id_no_endpoints_test() -> any().
maybe_strip_interaction_id_no_endpoints_test() ->
    JObj = with_interaction_id(<<"63959390461-7ff3e916">>),
    ?assertEqual(JObj, ecallmgr_fs_bridge:maybe_strip_interaction_id([], JObj)).
