-module(kz_nodes_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("kazoo_stdlib/include/kz_records.hrl").

%% Regression tests for openkazoo/kazoo#72: kz_nodes:is_up/1 used to raise
%% badarg when the registry ETS table did not exist yet, which is exactly the
%% state amqp_leader_listener polls during startup. It must answer false
%% instead of crashing, and still answer true once the node is registered.
is_up_test_() ->
    [{"registry table not started: is_up/1 answers false instead of raising"
     ,fun() ->
              ?assertNot(lists:member('kz_nodes', ets:all())),
              ?assertEqual('false', kz_nodes:is_up(node()))
      end
     }
    ,{"registry table started, node absent: is_up/1 answers false"
     ,{'setup', fun start_table/0, fun stop_table/1, fun(_) ->
                                                             ?_assertEqual('false', kz_nodes:is_up('some_other_node@nowhere'))
                                                     end}
     }
    ,{"registry table started, node present: is_up/1 answers true"
     ,{'setup', fun start_table/0, fun stop_table/1, fun(_) ->
                                                             ets:insert('kz_nodes', #kz_node{node = node()}),
                                                             ?_assertEqual('true', kz_nodes:is_up(node()))
                                                     end}
     }
    ].

start_table() ->
    ets:new('kz_nodes', ['set', 'protected', 'named_table', {'keypos', #kz_node.node}]).

stop_table(_) ->
    ets:delete('kz_nodes').
