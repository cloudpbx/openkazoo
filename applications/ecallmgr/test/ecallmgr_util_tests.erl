-module(ecallmgr_util_tests).

-spec test() -> 'ok'.

-include_lib("eunit/include/eunit.hrl").

-define(FS_PATH_RE, <<";fs_path=sip:(.*):\\d*;?">>).

-spec fs_path_network_map_regex_test_() -> any().
fs_path_network_map_regex_test_() ->
    Options = ['ungreedy', {'capture', 'all_but_first', 'binary'}],
    WithTrailingParams = <<"sip:foo@bar;fs_path=sip:172.16.75.1:5060;transport=tcp">>,
    NoTrailingParams = <<"sip:foo@bar;fs_path=sip:172.16.75.1:5060">>,
    [{"fs_path followed by more invite parameters still matches"
     ,?_assertMatch({'match', [<<"172.16.75.1">>]}, re:run(WithTrailingParams, ?FS_PATH_RE, Options))
     }
    ,{"fs_path with no trailing semicolon now matches (regression: used to require one)"
     ,?_assertMatch({'match', [<<"172.16.75.1">>]}, re:run(NoTrailingParams, ?FS_PATH_RE, Options))
     }
    ].

-spec maybe_sanitize_fs_value_test_() -> any().
maybe_sanitize_fs_value_test_() ->
    UTF8Bin = <<"Bör1-Goes2$%^ To4 Škofja Loka"/utf8>>,
    Expected = <<"Bör1-Goes2 To4 Škofja Loka"/utf8>>,

    Keys = [<<"Outbound-Caller-ID-Name">>
           ,<<"Outbound-Callee-ID-Name">>
           ,<<"Caller-ID-Name">>
           ,<<"Callee-ID-Name">>
           ],
    TestMsg = fun(KeyStr) ->
                      lists:flatten(["When sanitizing "
                                    ,kz_term:to_list(KeyStr)
                                    ,"'s value it should allow utf8 characters"
                                    ])
              end,
    [{TestMsg(Key)
     ,?_assertEqual(Expected, ecallmgr_util:maybe_sanitize_fs_value(Key, UTF8Bin))
     }
     || Key <- Keys
    ].
