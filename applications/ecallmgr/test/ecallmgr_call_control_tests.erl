-module(ecallmgr_call_control_tests).

-spec test() -> 'ok'.

-include("src/ecallmgr.hrl").
-include_lib("eunit/include/eunit.hrl").

%% Only the CCVs-already-present branch is covered here: the fallback branch
%% reads ecallmgr_fs_channel's ETS table, which only exists once the
%% ecallmgr app is running, not under bare eunit.
-spec call_interaction_id_prefers_ccvs_test() -> any().
call_interaction_id_prefers_ccvs_test() ->
    CCVs = kz_json:from_list([{<<?CALL_INTERACTION_ID>>, <<"63959390461-7ff3e916">>}]),
    ?assertEqual(<<"63959390461-7ff3e916">>
                ,ecallmgr_call_control:call_interaction_id(<<"call-id">>, CCVs)
                ).
