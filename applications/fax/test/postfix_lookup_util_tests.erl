-module(postfix_lookup_util_tests).

-include_lib("eunit/include/eunit.hrl").

%% Regression tests for openkazoo/kazoo#17: the Postfix TCP lookup-table
%% protocol (https://www.postfix.org/tcp_table.5.html) is line-based, so a
%% client's trailing newline has to come off before the key is used for a
%% fax-domain lookup, and a non-email key has to fall back to itself rather
%% than crash.
trim_newline_test_() ->
    [{"strips a single trailing newline"
     ,?_assertEqual(<<"example.com">>, postfix_lookup_util:trim_newline(<<"example.com\n">>))
     }
    ,{"leaves a request with no trailing newline unchanged"
     ,?_assertEqual(<<"example.com">>, postfix_lookup_util:trim_newline(<<"example.com">>))
     }
    ].

domain_from_email_test_() ->
    [{"extracts the domain from an email address"
     ,?_assertEqual(<<"example.com">>, postfix_lookup_util:domain_from_email(<<"fax@example.com">>))
     }
    ,{"returns the input unchanged when there is no @ to split on"
     ,?_assertEqual(<<"example.com">>, postfix_lookup_util:domain_from_email(<<"example.com">>))
     }
    ].
