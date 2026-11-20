-module(kvm_util_tests).

-include_lib("eunit/include/eunit.hrl").

%% Regression test for openkazoo/kazoo#19: publish_voicemail_saved/1 takes a
%% saved voicemail doc directly (as used by change_folder/5 and
%% maybe_update_meta/5) and must extract the right AMQP payload from its
%% metadata, including the Voicemail-Folder field this PR adds.
publish_voicemail_saved_from_doc_test_() ->
    {'setup'
    ,fun setup/0
    ,fun cleanup/1
    ,fun(_) ->
             JObj = kz_json:from_list(
                      [{<<"source_id">>, <<"box0000000000000000000000000001">>}
                      ,{<<"pvt_account_db">>, <<"account%2Fac%2Fco%2Facct0000000000000000000000001">>}
                      ,{<<"pvt_account_id">>, <<"acct0000000000000000000000001">>}
                      ,{<<"metadata">>, kz_json:from_list(
                                          [{<<"from_user">>, <<"1000">>}
                                          ,{<<"from_realm">>, <<"example.com">>}
                                          ,{<<"to_user">>, <<"2000">>}
                                          ,{<<"to_realm">>, <<"example.com">>}
                                          ,{<<"caller_id_number">>, <<"5551234567">>}
                                          ,{<<"caller_id_name">>, <<"Jane Caller">>}
                                          ,{<<"call_id">>, <<"call-abc123">>}
                                          ,{<<"length">>, 12345}
                                          ,{<<"folder">>, <<"saved">>}
                                          ,{<<"media_id">>, <<"media0000000000000000000000001">>}
                                          ])
                       }
                      ]),
             [{"publishes with the folder and voicemail id taken from the doc's metadata"
              ,fun() ->
                       Self = self(),
                       meck:expect('kz_amqp_worker', 'cast', fun(Prop, _PublishFun) -> Self ! {'published', Prop}, 'ok' end),
                       kvm_util:publish_voicemail_saved(JObj),
                       PublishedProp = receive {'published', P} -> P after 100 -> ?assert('false') end,
                       ?assertEqual(<<"saved">>, props:get_value(<<"Voicemail-Folder">>, PublishedProp)),
                       ?assertEqual(<<"media0000000000000000000000001">>, props:get_value(<<"Voicemail-ID">>, PublishedProp)),
                       ?assertEqual(<<"box0000000000000000000000000001">>, props:get_value(<<"Voicemail-Box">>, PublishedProp)),
                       ?assertEqual(12345, props:get_value(<<"Voicemail-Length">>, PublishedProp)),
                       ?assertEqual(<<"5551234567">>, props:get_value(<<"Caller-ID-Number">>, PublishedProp))
               end
              }
             ]
     end
    }.

setup() ->
    meck:new('kz_amqp_worker', ['non_strict']),
    'ok'.

cleanup(_) ->
    meck:unload('kz_amqp_worker').
