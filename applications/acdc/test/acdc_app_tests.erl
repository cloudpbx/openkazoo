-module(acdc_app_tests).

-include_lib("eunit/include/eunit.hrl").

%% Regression test for openkazoo/kazoo#63: acdc's own Crossbar and Blackhole
%% modules shipped in the build but were never registered, so their REST
%% endpoints and websocket bindings were silently dead. Asserts the six
%% expected integrations stay declared.
-spec integration_modules_test_() -> any().
integration_modules_test_() ->
    Integrations = acdc_app:integration_modules(),
    ExpectedCrossbar = ['cb_agents', 'cb_queues', 'cb_acdc_call_stats'],
    ExpectedBlackhole = [<<"bh_acdc_agent">>, <<"bh_acdc_member">>, <<"bh_acdc_queue">>],
    [{"crossbar module " ++ kz_term:to_list(Mod) ++ " is registered via crossbar_maintenance:start_module"
     ,?_assert(lists:member({Mod, 'crossbar_maintenance', 'start_module'}, Integrations))
     }
     || Mod <- ExpectedCrossbar
    ] ++
        [{"blackhole module " ++ kz_term:to_list(Mod) ++ " is registered via blackhole_maintenance:start_module"
         ,?_assert(lists:member({Mod, 'blackhole_maintenance', 'start_module'}, Integrations))
         }
         || Mod <- ExpectedBlackhole
        ].
