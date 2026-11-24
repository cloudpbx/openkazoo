-module(cb_context_tests).

-include_lib("eunit/include/eunit.hrl").

-spec path_tokens_test_() -> [tuple()].
path_tokens_test_() ->
    [{"Preserve literal plus in path segment"
     ,?_assertEqual(<<"+12223334444">>, last_path_token(<<"/+12223334444">>))
     }
    ,{"Preserve encoded plus in path segment"
     ,?_assertEqual(<<"+12223334444">>, last_path_token(<<"/%2B12223334444">>))
     }
    ,{"Decode encoded spaces in path segment"
     ,?_assertEqual(<<"a b">>, last_path_token(<<"/a%20b">>))
     }
    ].

-spec is_account_admin_test_() -> [tuple()].
is_account_admin_test_() ->
    [{"an account API token is account-authoritative"
     ,?_assert(is_account_admin(auth_doc(<<"cb_api_auth">>)))
     }
    ,{"a request with no auth doc is not an account admin"
     ,?_assertNot(cb_context:is_account_admin(cb_context:new()))
     }
    ,{"an owner-less token from another auth method is not swept in"
     ,?_assertNot(is_account_admin(auth_doc(<<"cb_ip_auth">>)))
     }
    ].

-spec auth_doc(binary()) -> kz_json:object().
auth_doc(Method) ->
    kz_json:from_list([{<<"method">>, Method}
                      ,{<<"account_id">>, <<"account0000000000000000000000001">>}
                      ]).

-spec is_account_admin(kz_json:object()) -> boolean().
is_account_admin(AuthDoc) ->
    cb_context:is_account_admin(cb_context:set_auth_doc(cb_context:new(), AuthDoc)).

-spec path_tokens(binary()) -> [binary()].
path_tokens(Path) ->
    cb_context:path_tokens(cb_context:set_raw_path(cb_context:new(), Path)).

-spec last_path_token(binary()) -> binary().
last_path_token(Path) ->
    lists:last(path_tokens(Path)).
