-module(cf_destination_listmatch_tests).

-include_lib("eunit/include/eunit.hrl").

%% Regression tests for openkazoo/kazoo#11: cf_destination_listmatch branches
%% on the destination number the same way cf_cidlistmatch branches on the
%% source number. These cover the two pure building blocks: the list of
%% number prefixes checked against the prefix-match view, and the regexp
%% matcher checked against the regexp-match view.
build_keys_test_() ->
    [{"strips a leading + before building prefixes"
     ,?_assertEqual(cf_destination_listmatch:build_keys(<<"123">>), cf_destination_listmatch:build_keys(<<"+123">>))
     }
    ,{"builds every prefix of the number, longest first"
     ,?_assertEqual([<<"123">>, <<"12">>, <<"1">>], cf_destination_listmatch:build_keys(<<"123">>))
     }
    ].

match_regexps_test_() ->
    [{"matches when any pattern matches the number"
     ,?_assert(cf_destination_listmatch:match_regexps([<<"^666">>, <<"^555">>], <<"5551234567">>))
     }
    ,{"does not match when no pattern matches"
     ,?_assertNot(cf_destination_listmatch:match_regexps([<<"^666">>], <<"5551234567">>))
     }
    ,{"does not match an empty pattern list"
     ,?_assertNot(cf_destination_listmatch:match_regexps([], <<"5551234567">>))
     }
    ].
