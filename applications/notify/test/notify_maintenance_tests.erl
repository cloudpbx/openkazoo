-module(notify_maintenance_tests).

-include_lib("eunit/include/eunit.hrl").

-define(NOTIFY_CONFIG_CAT, <<"notify">>).
-define(SMTP_CLIENT_DOC, <<"smtp_client">>).

%% Regression tests for openkazoo/kazoo#8: new notify_maintenance functions
%% to configure SMTP SSL/TLS mode and a system-wide default from-address.
notify_maintenance_test_() ->
    {'setup'
    ,fun setup/0
    ,fun cleanup/1
    ,fun(_) ->
             [{"configure_smtp_ssl/1 coerces its argument to a boolean"
              ,fun() ->
                       meck:expect('kapps_config', 'set', fun(?SMTP_CLIENT_DOC, <<"use_ssl">>, 'true') -> {'ok', 'ignored'} end),
                       ?assertEqual('ok', notify_maintenance:configure_smtp_ssl(<<"true">>))
               end
              }
             ,{"configure_smtp_tls/1 accepts always, if_available, and never"
              ,fun() ->
                       [begin
                            meck:expect('kapps_config', 'set', fun(?SMTP_CLIENT_DOC, <<"tls">>, V) when V =:= Value -> {'ok', 'ignored'} end),
                            ?assertEqual('ok', notify_maintenance:configure_smtp_tls(Value))
                        end
                        || Value <- [<<"always">>, <<"if_available">>, <<"never">>]
                       ]
               end
              }
             ,{"system_default_from_email/1 sets the system-wide config"
              ,fun() ->
                       Email = <<"ops@example.com">>,
                       meck:expect('kapps_config', 'set', fun(?NOTIFY_CONFIG_CAT, <<"system_default_from_email">>, E) when E =:= Email -> {'ok', 'ignored'} end),
                       ?assertEqual('ok', notify_maintenance:system_default_from_email(Email))
               end
              }
             ]
     end
    }.

setup() ->
    meck:new('kapps_config', ['non_strict']),
    'ok'.

cleanup(_) ->
    meck:unload('kapps_config').
