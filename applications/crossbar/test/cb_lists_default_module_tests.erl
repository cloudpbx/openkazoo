-module(cb_lists_default_module_tests).

-include_lib("eunit/include/eunit.hrl").
-include("../src/crossbar.hrl").

%% Regression test for openkazoo/kazoo#64: GET /v2/accounts/{id}/lists 404ed
%% because 'cb_lists' was never in ?DEFAULT_MODULES, so nothing ever started
%% the module. Asserts the base atom stays registered so this cannot silently
%% drop out again.
-spec cb_lists_is_a_default_module_test() -> any().
cb_lists_is_a_default_module_test() ->
    ?assert(lists:member('cb_lists', ?DEFAULT_MODULES)).
