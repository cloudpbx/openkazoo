-module(crossbar_autoload_endpoints_tests).

-include_lib("eunit/include/eunit.hrl").
-include("../src/crossbar.hrl").

%% Regression test for openkazoo/kazoo#69: these nine endpoints shipped with
%% Crossbar but needed an operator to run `sup crossbar_maintenance
%% start_module` by hand before their routes existed. Asserts they stay in
%% the default-loaded module set.
-spec autoloaded_feature_endpoints_test_() -> any().
autoloaded_feature_endpoints_test_() ->
    Expected = ['cb_storage'
               ,'cb_acls'
               ,'cb_allotments'
               ,'cb_att_handlers_errors'
               ,'cb_dialplans'
               ,'cb_mms'
               ,'cb_rate_limits'
               ,'cb_recordings'
               ,'cb_resource_selectors'
               ],
    [{kz_term:to_list(Mod) ++ " is a default-loaded Crossbar module"
     ,?_assert(lists:member(Mod, ?DEFAULT_MODULES))
     }
     || Mod <- Expected
    ].
