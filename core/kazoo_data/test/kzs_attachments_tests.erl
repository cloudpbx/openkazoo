-module(kzs_attachments_tests).

-include_lib("eunit/include/eunit.hrl").

%% Regression tests for openkazoo/kazoo#24: publish_attachment_saved/1 is
%% fired whenever an attachment is saved, and has to fall back to the
%% attachment's own key when the doc carries no explicit "name", plus derive
%% the storage type from whichever handler key is present.
publish_attachment_saved_test_() ->
    {'setup'
    ,fun setup/0
    ,fun cleanup/1
    ,fun(_) ->
             [{"uses the explicit \"name\" field and handler key when present"
              ,fun() -> ?assertMatch(#{<<"Name">> := <<"recording.mp3">>, <<"Storage-Type">> := <<"s3">>}
                                     ,captured_props(doc_with_name_and_handler())
                                     )
               end
              }
             ,{"falls back to the first pvt_attachments key when \"name\" is absent"
              ,fun() -> ?assertMatch(#{<<"Name">> := <<"recording.mp3">>}, captured_props(doc_without_name()))
               end
              }
             ,{"falls back to \"native\" storage type when the attachment has no handler"
              ,fun() -> ?assertMatch(#{<<"Storage-Type">> := <<"native">>}, captured_props(doc_without_name()))
               end
              }
             ]
     end
    }.

doc_with_name_and_handler() ->
    kz_json:from_list(
      [{<<"_id">>, <<"doc0000000000000000000000000001">>}
      ,{<<"pvt_account_db">>, <<"account%2Fac%2Fco%2Facct0000000000000000000000001">>}
      ,{<<"name">>, <<"recording.mp3">>}
      ,{<<"pvt_attachments">>, kz_json:from_list(
                                  [{<<"recording.mp3">>, kz_json:from_list(
                                                            [{<<"handler">>, kz_json:from_list([{<<"s3">>, kz_json:new()}])}]
                                                           )}
                                  ])
       }
      ]).

doc_without_name() ->
    kz_json:from_list(
      [{<<"_id">>, <<"doc0000000000000000000000000002">>}
      ,{<<"pvt_account_db">>, <<"account%2Fac%2Fco%2Facct0000000000000000000000001">>}
      ,{<<"pvt_attachments">>, kz_json:from_list(
                                  [{<<"recording.mp3">>, kz_json:new()}]
                                 )
       }
      ]).

captured_props(Doc) ->
    Self = self(),
    meck:expect('kz_amqp_worker', 'cast', fun(Props, _PublishFun) -> Self ! {'published', Props}, 'ok' end),
    kzs_attachments:publish_attachment_saved(Doc),
    receive {'published', Props} -> maps:from_list(Props) after 100 -> ?assert('false') end.

setup() ->
    meck:new('kz_amqp_worker', ['non_strict']),
    'ok'.

cleanup(_) ->
    meck:unload('kz_amqp_worker').
