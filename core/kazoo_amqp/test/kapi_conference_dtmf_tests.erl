-module(kapi_conference_dtmf_tests).

-include_lib("eunit/include/eunit.hrl").

%% Regression tests for openkazoo/kazoo#23: the conference DTMF command,
%% the dialplan equivalent of send_dtmf for a conference participant.
is_valid_dtmf_test_() ->
    [{"accepts standard touch-tone digits"
     ,?_assert(kapi_conference:is_valid_dtmf(<<"123*#">>))
     }
    ,{"accepts the A-D DTMF tones, either case"
     ,?_assert(kapi_conference:is_valid_dtmf(<<"abcdABCD">>))
     }
    ,{"accepts a number by coercing it to a binary first"
     ,?_assert(kapi_conference:is_valid_dtmf(1234))
     }
    ,{"rejects a string with no valid DTMF characters at all"
     ,?_assertNot(kapi_conference:is_valid_dtmf(<<"hello">>))
     }
    ,{"rejects an empty binary"
     ,?_assertNot(kapi_conference:is_valid_dtmf(<<>>))
     }
    ,{"rejects a non-binary, non-number term"
     ,?_assertNot(kapi_conference:is_valid_dtmf('not_dtmf'))
     }
    ].

dtmf_v_test_() ->
    Valid = [{<<"Application-Name">>, <<"dtmf">>}
            ,{<<"Conference-ID">>, <<"conference0000000000000000000001">>}
            ,{<<"Digits">>, <<"123">>}
            ,{<<"Msg-ID">>, <<"msg0000000000000000000000000001">>}
             | kz_api:default_headers(<<"conference">>, <<"command">>, <<"myapp">>, <<"1.0.0">>)
            ],
    [{"a well-formed dtmf command validates"
     ,?_assert(kapi_conference:dtmf_v(Valid))
     }
    ,{"an invalid Digits value fails validation"
     ,?_assertNot(kapi_conference:dtmf_v(lists:keyreplace(<<"Digits">>, 1, Valid, {<<"Digits">>, <<"xyz">>})))
     }
    ,{"a missing required header fails validation"
     ,?_assertNot(kapi_conference:dtmf_v(lists:keydelete(<<"Conference-ID">>, 1, Valid)))
     }
    ].
