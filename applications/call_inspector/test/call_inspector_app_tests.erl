-module(call_inspector_app_tests).

-include_lib("eunit/include/eunit.hrl").

%% Regression test for openkazoo/kazoo#69: cb_call_inspector is the one
%% endpoint owned by call_inspector rather than Crossbar itself (it does a
%% synchronous AMQP call, so it cannot be a Crossbar default without
%% publishing a route that times out when the app is not running). Asserts
%% the app still registers its own Crossbar module at startup.
-spec registers_its_own_crossbar_module_test() -> any().
registers_its_own_crossbar_module_test() ->
    Integrations = call_inspector_app:integration_modules(),
    ?assert(lists:member({'cb_call_inspector', 'crossbar_maintenance', 'start_module'}, Integrations)).
