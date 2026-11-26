%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2022, 2600Hz
%%% @doc Record something
%%% "data":{
%%%   "action":["start","stop"] // one of these
%%%   ,"time_limit":600 // in seconds, how long to record the call
%%%   ,"format":["mp3","wav"] // what format to store the recording in
%%%   ,"url":"http://server.com/path/to/dump/file" // what URL to PUT the file to
%%%   ,"on_demand":true // only announce and mark the press; Kazoo's recording is left alone
%%%   ,"mark":true // start or stop as usual, and also mark the press
%%% }
%%%
%%% @author James Aimonetti
%%% @end
%%%-----------------------------------------------------------------------------
-module(konami_record_call).

-export([handle/2
        ,number_builder/1
        ]).

-include("konami.hrl").

%% FreeSWITCH stops every recording on the leg when the stop names this instead of a file.
-define(STOP_ALL, <<"all">>).
-define(STOP_WAIT_MS, 2 * ?MILLISECONDS_IN_SECOND).
%% Each on-demand press is a channel variable of its own (Record-On-Demand-<ms> = start | stop), so
%% the leg's CDR lists every press and none has to be read back to append another.
-define(ON_DEMAND_PREFIX, <<"Record-On-Demand-">>).

-spec handle(kz_json:object(), kapps_call:call()) ->
          {'continue', kapps_call:call()}.
handle(Data, Call) ->
    Call1 = handle(Data, Call, get_action(kz_json:get_ne_binary_value(<<"action">>, Data))),
    {'continue', Call1}.

-spec handle(kz_json:object(), kapps_call:call(), kz_term:ne_binary()) ->
          kapps_call:call().
handle(_Data, Call, <<"mask">>) ->
    lager:debug("masking recording, see you on the other side"),
    kapps_call:mask_recording(Call);
handle(_Data, Call, <<"unmask">>) ->
    lager:debug("unmasking recording, see you on the other side"),
    kapps_call:unmask_recording(Call);
handle(Data, Call, Action) when Action =:= <<"start">>; Action =:= <<"stop">> ->
    case kz_json:is_true(<<"on_demand">>, Data) of
        'true' -> on_demand(Data, Call, Action);
        'false' ->
            _ = kz_json:is_true(<<"mark">>, Data)
                andalso mark_press(press_leg(Data, Call), Action, Call),
            handle_recording(Data, Call, Action)
    end.

%% For a person who doesn't record by default, at a firm that records every call: Kazoo is already
%% recording, so nothing is started or stopped (a colleague's recording on the other leg keeps
%% running). The press is announced and marked on the person's own leg; processing keeps only what
%% lies between their starts and stops.
-spec on_demand(kz_json:object(), kapps_call:call(), kz_term:ne_binary()) -> kapps_call:call().
on_demand(Data, Call, Action) ->
    Leg = press_leg(Data, Call),
    lager:debug("on-demand ~s on ~s", [Action, Leg]),
    mark_press(Leg, Action, Call),
    announce(<<"recording-", Action/binary>>, Call),
    Call.

-spec press_leg(kz_json:object(), kapps_call:call()) -> kz_term:ne_binary().
press_leg(Data, Call) ->
    kz_json:get_ne_binary_value(<<"dtmf_leg">>, Data, kapps_call:call_id_direct(Call)).

-spec mark_press(kz_term:ne_binary(), kz_term:ne_binary(), kapps_call:call()) -> 'ok'.
mark_press(Leg, Action, Call) ->
    Key = <<?ON_DEMAND_PREFIX/binary, (kz_term:to_binary(erlang:system_time('millisecond')))/binary>>,
    kapps_call_command:set(kz_json:from_list([{Key, Action}]), 'undefined', kapps_call:set_call_id(Leg, Call)).

-spec handle_recording(kz_json:object(), kapps_call:call(), kz_term:ne_binary()) -> kapps_call:call().
handle_recording(Data, Call, <<"start">>) ->
    case running(Call) =:= [] andalso live_recorders(Call) =:= [] of
        'false' ->
            lager:debug("already recording, ignoring start"),
            Call;
        'true' ->
            lager:debug("starting recording, see you on the other side"),
            announce(<<"recording-start">>, Call),
            kapps_call:start_recording(Data, track(Call, []))
    end;
handle_recording(_Data, Call, <<"stop">>) ->
    Legs = legs(Call),
    Known = running(Call) =/= [] orelse live_recorders(Call) =/= [],
    _ = Known orelse listen_for_stops(Legs),
    stop_all(Legs, Call),
    Call1 = track(Call, []),
    case Known orelse stopped_any(Legs) of
        'true' ->
            lager:debug("sent command to stop recording call"),
            announce(<<"recording-stop">>, Call1);
        'false' ->
            lager:debug("nothing was recording, stopping without an announcement")
    end,
    Call1.

-spec legs(kapps_call:call()) -> kz_term:ne_binaries().
legs(Call) ->
    lists:usort([CallId || CallId <- [kapps_call:call_id_direct(Call), kapps_call:other_leg_call_id(Call)]
                               ,is_binary(CallId)
                ]).

%% konami may not have seen a recording (one that started before it bound to the leg), so whether
%% the stop ended anything is read from the legs' RECORD_STOP events.
-spec listen_for_stops(kz_term:ne_binaries()) -> 'ok'.
listen_for_stops(Legs) ->
    lists:foreach(fun(CallId) -> konami_event_listener:add_call_binding(CallId, [<<"RECORD_STOP">>]) end, Legs).

-spec stopped_any(kz_term:ne_binaries()) -> boolean().
stopped_any(Legs) ->
    Stopped = wait_for_stop(Legs, ?STOP_WAIT_MS),
    lists:foreach(fun(CallId) -> konami_event_listener:rm_call_binding(CallId, [<<"RECORD_STOP">>]) end, Legs),
    Stopped.

-spec wait_for_stop(kz_term:ne_binaries(), timeout()) -> boolean().
wait_for_stop(Legs, Timeout) ->
    Start = os:timestamp(),
    case kapps_call_command:receive_event(Timeout) of
        {'ok', JObj} ->
            case kz_call_event:event_name(JObj) =:= <<"RECORD_STOP">>
                andalso lists:member(kz_call_event:call_id(JObj), Legs)
            of
                'true' -> 'true';
                'false' -> wait_for_stop(Legs, kz_time:decr_timeout(Timeout, Start))
            end;
        {'error', 'timeout'} -> 'false'
    end.

%% Every recording running on the call's legs, whoever started it (the account's or the endpoint's
%% auto-recording, or konami): a firm's settings record each leg, so one stop has to end them all.
-spec running(kapps_call:call()) -> [{kz_term:ne_binary(), kz_term:ne_binary()}].
running(Call) ->
    kapps_call:kvs_fetch(?CALL_RECORDINGS_KEY, [], Call).

%% By leg, not by name: an auto-recording can start before konami binds to that leg (on an inbound
%% call it starts on answer, as the leg is bridged), so konami may never have seen it. Each recording
%% stopped this way is still stored.
-spec stop_all(kz_term:ne_binaries(), kapps_call:call()) -> 'ok'.
stop_all(CallIds, Call) ->
    lists:foreach(fun(CallId) ->
                          lager:debug("stopping every recording on ~s", [CallId]),
                          kapps_call_command:stop_record_call([{<<"Media-Name">>, ?STOP_ALL}]
                                                             ,kapps_call:set_call_id(CallId, Call)
                                                             )
                  end
                 ,CallIds
                 ).

%% A recorder exits once its recording is stored, whoever stopped it: konami, its time
%% limit, or another party. Stop drops the one it stops, so only the rest are checked here.
-spec live_recorders(kapps_call:call()) -> [{kz_term:ne_binary(), pid()}].
live_recorders(Call) ->
    [Ref || {_MediaName, Pid}=Ref <- queue:to_list(kapps_call:get_recordings(Call)), is_live(Pid)].

-spec is_live(pid()) -> boolean().
is_live(Pid) when node(Pid) =:= node() -> is_process_alive(Pid);
is_live(Pid) ->
    case rpc:call(node(Pid), 'erlang', 'is_process_alive', [Pid], ?MILLISECONDS_IN_SECOND) of
        IsAlive when is_boolean(IsAlive) -> IsAlive;
        {'badrpc', 'nodedown'} -> 'false';
        %% Unknown: a duplicate recording is worse than a skipped start.
        {'badrpc', _Reason} -> 'true'
    end.

-spec track(kapps_call:call(), [{kz_term:ne_binary(), pid()}]) -> kapps_call:call().
track(Call, Recorders) ->
    kapps_call:set_recordings(queue:from_list(Recorders), Call).

%% `Leg: "Both"' reaches both parties in one command when ecallmgr's
%% `is_bridged/1' is true at the moment the command runs (the common
%% case). It falls back to self-leg-only when `is_bridged/1' is false
%% (CORV-1986, not yet root-caused). Sending a second explicit command for
%% the other leg was tried as a workaround for that case, but it either
%% double-plays (when "Both" is used on both) or drops audio entirely
%% (when "self" is used on both, confirmed live: nothing played). Until
%% CORV-1986 has a real fix, a single "Both" command is the safer choice:
%% reliable when bridged, and silent only on the far leg in the rarer
%% unbridged case, rather than risking a broken announcement either way.
-spec announce(kz_term:ne_binary(), kapps_call:call()) -> 'ok'.
announce(PromptId, Call) ->
    Media = kz_media_util:get_prompt(PromptId, kapps_call:language(Call), kapps_call:account_id(Call)),
    PlayCommand = kapps_call_command:play_command(Media, ?ANY_DIGIT, <<"Both">>, Call),
    kapps_call_command:send_command(kz_json:set_value(<<"Insert-At">>, <<"now">>, PlayCommand), Call).

-spec get_action(kz_term:api_ne_binary()) -> kz_term:ne_binary().
get_action('undefined') -> <<"start">>;
get_action(<<"mask">>) -> <<"mask">>;
get_action(<<"unmask">>) -> <<"unmask">>;
get_action(<<"stop">>) -> <<"stop">>;
get_action(_) -> <<"start">>.

-spec number_builder(kz_json:object()) -> kz_json:object().
number_builder(DefaultJObj) ->
    io:format("Let's configure a 'record_call' metaflow~n", []),

    {'ok', [Number]} = io:fread("What number should invoke 'record_call'? ", "~d"),

    K = [<<"numbers">>, kz_term:to_binary(Number)],

    case number_builder_check(kz_json:get_value(K, DefaultJObj)) of
        'undefined' -> kz_json:delete_key(K, DefaultJObj);
        NumberJObj -> kz_json:set_value(K, NumberJObj, DefaultJObj)
    end.

-spec number_builder_check(kz_term:api_object()) -> kz_term:api_object().
number_builder_check('undefined') ->
    number_builder_action(kz_json:new());
number_builder_check(NumberJObj) ->
    io:format("  Existing config for this number: ~s~n", [kz_json:encode(NumberJObj)]),
    io:format("  e. Edit Number~n", []),
    io:format("  d. Delete Number~n", []),
    {'ok', [Option]} = io:fread("What would you like to do: ", "~s"),
    number_builder_check_option(NumberJObj, Option).

-spec number_builder_check_option(kz_json:object(), string()) -> kz_term:api_object().
number_builder_check_option(NumberJObj, "e") ->
    number_builder_action(NumberJObj);
number_builder_check_option(_NumberJObj, "d") ->
    'undefined';
number_builder_check_option(NumberJObj, _Option) ->
    io:format("invalid selection~n", []),
    number_builder_check(NumberJObj).

-spec number_builder_action(kz_json:object()) -> kz_json:object().
number_builder_action(NumberJObj) ->
    {'ok', [Action]} = io:fread("What action: 'start' or 'stop': ", "~s"),
    number_builder_time_limit(NumberJObj, kz_term:to_binary(Action)).

-spec number_builder_time_limit(kz_json:object(), kz_term:ne_binary()) -> kz_json:object().
number_builder_time_limit(NumberJObj, Action) ->
    {'ok', [TimeLimit]} = io:fread("How many seconds to limit the recording to: ", "~d"),
    number_builder_format(NumberJObj, Action, TimeLimit).

-spec number_builder_format(kz_json:object(), kz_term:ne_binary(), pos_integer()) -> kz_json:object().
number_builder_format(NumberJObj, Action, TimeLimit) ->
    {'ok', [Format]} = io:fread("What format would you like the recording? ('wav' or 'mp3'): ", "~3s"),
    number_builder_url(NumberJObj, Action, TimeLimit, kz_term:to_binary(Format)).

-spec number_builder_url(kz_json:object(), kz_term:ne_binary(), pos_integer(), kz_term:ne_binary()) -> kz_json:object().
number_builder_url(NumberJObj, Action, TimeLimit, Format) ->
    {'ok', [URL]} = io:fread("What URL to send the recording to at the end: ", "~s"),
    metaflow_jobj(NumberJObj, Action, TimeLimit, Format, kz_term:to_binary(URL)).

-spec metaflow_jobj(kz_json:object(), kz_term:ne_binary(), pos_integer(), kz_term:ne_binary(), kz_term:ne_binary()) -> kz_json:object().
metaflow_jobj(NumberJObj, Action, TimeLimit, Format, URL) ->
    kz_json:set_values([{<<"module">>, <<"record_call">>}
                       ,{<<"data">>, data(Action, TimeLimit, Format, URL)}
                       ], NumberJObj).

-spec data(kz_term:ne_binary(), pos_integer(), kz_term:ne_binary(), kz_term:ne_binary()) -> kz_json:object().
data(Action, TimeLimit, Format, URL) ->
    kz_json:from_list([{<<"action">>, Action}
                      ,{<<"time_limit">>, TimeLimit}
                      ,{<<"format">>, Format}
                      ,{<<"url">>, URL}
                      ]).
