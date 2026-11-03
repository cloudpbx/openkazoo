-module(stepswitch_outbound_tests).

-include_lib("eunit/include/eunit.hrl").

%% Regression tests for openkazoo/kazoo#15: shortdial correction for
%% originate-type requests (e.g. fax) is gated behind
%% system_config/{application}.shortdial_correction. An OffnetReq with no
%% Server-ID makes publish_no_resources/1 a safe no-op, so these exercise the
%% real gate without needing to mock AMQP.
maybe_correct_shortdial_originate_test_() ->
    {'setup'
    ,fun setup/0
    ,fun cleanup/1
    ,fun(_) ->
             [{"flag off: shortdial correction is never attempted"
              ,fun() ->
                       meck:expect('kapps_config', 'get_boolean', fun(<<"fax">>, <<"shortdial_correction">>) -> 'false' end),
                       OffnetReq = offnet_req(<<"fax">>),
                       ?assertEqual('ok', stepswitch_outbound:maybe_correct_shortdial_originate(<<"1234">>, OffnetReq)),
                       ?assertNot(meck:called('stepswitch_util', 'correct_shortdial', '_'))
               end
              }
             ,{"flag on: shortdial correction is attempted"
              ,fun() ->
                       meck:expect('kapps_config', 'get_boolean', fun(<<"fax">>, <<"shortdial_correction">>) -> 'true' end),
                       meck:expect('stepswitch_util', 'correct_shortdial', fun(_Number, _Req) -> 'undefined' end),
                       OffnetReq = offnet_req(<<"fax">>),
                       ?assertEqual('ok', stepswitch_outbound:maybe_correct_shortdial_originate(<<"1234">>, OffnetReq)),
                       ?assert(meck:called('stepswitch_util', 'correct_shortdial', [<<"1234">>, OffnetReq]))
               end
              }
             ]
     end
    }.

-spec offnet_req(kz_term:ne_binary()) -> kz_json:object().
offnet_req(AppName) ->
    kz_json:from_list([{<<"Application-Name">>, AppName}
                      ,{<<"Resource-Type">>, <<"originate">>}
                      ]).

setup() ->
    meck:new('kapps_config', ['non_strict']),
    meck:new('stepswitch_util', ['non_strict']),
    'ok'.

cleanup(_) ->
    meck:unload('kapps_config'),
    meck:unload('stepswitch_util').
