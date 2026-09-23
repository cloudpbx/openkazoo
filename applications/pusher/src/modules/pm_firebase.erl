%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2026, 2600Hz
%%% @doc
%%% @author 2600Hz
%%% @author Circle Cloud
%%% @end
%%%-----------------------------------------------------------------------------
-module(pm_firebase).
-behaviour(gen_server).

-include("pusher.hrl").

-define(SERVER, ?MODULE).

-export([start_link/0]).

-export([init/1
        ,handle_call/3
        ,handle_cast/2
        ,handle_info/2
        ,terminate/2
        ,code_change/3
        ]).

-record(state, {tab :: ets:tid()}).
-type state() :: #state{}.

-define(FIREBASE_MAP, [{<<"Alert-Key">>, [<<"alert">>, <<"loc-key">>]}
                      ,{<<"Alert-Params">>, [<<"alert">>, <<"loc-args">>]}
                      ,{<<"Sound">>, [<<"sound">>]}
                      ,{<<"Call-ID">>, [<<"Call-ID">>]}
                      ,{<<"Payload">>, fun kz_json:merge/2}
                      ]).

-spec start_link() -> kz_types:startlink_ret().
start_link() ->
    gen_server:start_link({'local', ?SERVER}, ?MODULE, [],[]).

-spec init([]) -> {'ok', state()}.
init([]) ->
    kz_util:put_callid(?MODULE),
    process_flag('trap_exit', 'true'),
    lager:debug("starting server"),
    {'ok', #state{tab=ets:new(?MODULE, [])}}.

-spec handle_call(any(), kz_term:pid_ref(), state()) -> kz_types:handle_call_ret_state(state()).
handle_call(_Request, _From, State) ->
    {'reply', {'error', 'not_implemented'}, State}.

-spec handle_cast(any(), state()) -> kz_types:handle_cast_ret_state(state()).
handle_cast({'push', JObj}, #state{tab=ETS}=State) ->
    lager:debug("process a push"),
    TokenApp = kz_json:get_value(<<"Token-App">>, JObj),
    maybe_send_push_notification(get_fcm(TokenApp, ETS), JObj),
    {'noreply', State};
handle_cast('stop', State) ->
    {'stop', 'normal', State}.

-spec handle_info(any(), state()) -> kz_types:handle_info_ret_state(state()).
handle_info({'EXIT', Pid, Reason}, #state{tab = ETS} = State) ->
    case ets:take(ETS, Pid) of
        [{Pid, App}] ->
            lager:warning("fcm for ~s stopped: ~p", [App, Reason]),
            ets:delete(ETS, App);
        _ ->
            'ok'
    end,
    {'noreply', State};
handle_info(_Request, State) ->
    {'noreply', State}.

-spec terminate(any(), state()) -> 'ok'.
terminate(_Reason, #state{tab=ETS}) ->
    ets:delete(ETS),
    'ok'.

-spec code_change(any(), state(), any()) -> {'ok', state()}.
code_change(_OldVsn, State, _Extra) ->
    {'ok', State}.

-spec maybe_send_push_notification(push_app(), kz_json:object()) -> any().
maybe_send_push_notification('undefined', _JObj) -> lager:debug("no pid to send push");
maybe_send_push_notification({Pid, Envelope}, JObj) ->
    TokenID = kz_json:get_value(<<"Token-ID">>, JObj),
    Data = kz_json:map(fun(K, V) -> {K, to_data_value(V)} end, build_payload(JObj)),
    Message = #{<<"android">> => Envelope#{<<"ttl">> => <<"10s">>}
               ,<<"data">> => kz_json:to_map(Data)
               },

    lager:debug("pushing to ~p: ~s: ~p", [Pid, TokenID, Message]),
    fcm:push(Pid, [TokenID], Message, 3).

-spec build_payload(kz_json:object()) -> kz_json:object().
build_payload(JObj) ->
    kz_json:foldl(fun map_key/3, kz_json:new(), JObj).

-spec map_key(term(), term(), kz_json:object()) -> kz_json:object().
map_key(K, V, JObj) ->
    case lists:keyfind(K, 1, ?FIREBASE_MAP) of
        'false' -> JObj;
        {_, Fun} when is_function(Fun, 2) -> Fun(V, JObj);
        {_, K1} -> kz_json:set_value(K1, V, JObj)
    end.

-spec to_data_value(kz_json:json_term()) -> binary().
to_data_value(V) when is_binary(V) -> V;
to_data_value(V) -> kz_term:to_binary(kz_json:encode(V)).

-spec get_fcm(kz_term:api_binary(), ets:tid()) -> push_app().
get_fcm('undefined', _) -> 'undefined';
get_fcm(App, ETS) ->
    case ets:lookup(ETS, App) of
        [] ->
            lager:debug("fcm not found for ~p maybe loading it now...", [App]),
            maybe_load_fcm(App, ETS);
        [{App, Push}] -> Push
    end.

-spec maybe_load_fcm(kz_term:api_binary(), ets:tid()) -> push_app().
maybe_load_fcm(App, ETS) ->
    lager:debug("loading fcm secret for ~s", [App]),
    FCMServiceAcct = kapps_config:get_json(?CONFIG_CAT, [<<"firebase">>, <<"service_account">>], 'undefined', App),
    EnvelopeJObj = kapps_config:get_json(?CONFIG_CAT, [<<"firebase">>, <<"headers">>], kz_json:new(), App),
    Envelope = kz_json:to_map(EnvelopeJObj),
    maybe_load_fcm(App, ETS, FCMServiceAcct, Envelope).

-spec maybe_load_fcm(kz_term:api_binary(), ets:tid(), kz_term:api_binary(), map()) -> push_app().
maybe_load_fcm(App, _, 'undefined', _) ->
    lager:debug("firebase pusher service account for app ~s not found", [App]),
    'undefined';
maybe_load_fcm(App, ETS, FCMServiceAcct, Envelope) ->
    FcmName = kz_term:to_atom(<<"fcm_", App/binary>>, 'true'),
    lager:debug("starting new fcm with name ~p", [FcmName]),
    case fcm:start_pool_with_json_service_file_bin(FcmName, kz_term:to_binary(kz_json:encode(FCMServiceAcct))) of
        {'ok', Pid} ->
            lager:debug("started new fcm ~p", [Pid]),
            erlang:link(Pid),
            ets:insert(ETS, {App, {Pid, Envelope}}),
            ets:insert(ETS, {Pid, App}),
            {Pid, Envelope};
        {'error', {'already_started', Pid}} ->
            lager:debug("fcm already started ~p", [Pid]),
            ets:insert(ETS, {App, {Pid, Envelope}}),
            {Pid, Envelope};
        {'error', Reason} ->
            lager:error("error loading fcm ~p", [Reason]),
            'undefined'
    end.
