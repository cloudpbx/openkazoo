%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2010-2026, 2600Hz
%%% @doc
%%% @end
%%%-----------------------------------------------------------------------------
-module(pm_webhook).
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

-record(state, {}).
-type state() :: #state{}.

-define(CONNECT_TIMEOUT, 5 * ?MILLISECONDS_IN_SECOND).
-define(REQUEST_TIMEOUT, 10 * ?MILLISECONDS_IN_SECOND).

-spec start_link() -> kz_types:startlink_ret().
start_link() ->
    gen_server:start_link({'local', ?SERVER}, ?MODULE, [],[]).

-spec init([]) -> {'ok', state()}.
init([]) ->
    kz_util:put_callid(?MODULE),
    lager:debug("starting server"),
    {'ok', #state{}}.

-spec handle_call(any(), kz_term:pid_ref(), state()) -> kz_types:handle_call_ret_state(state()).
handle_call(_Request, _From, State) ->
    {'reply', {'error', 'not_implemented'}, State}.

-spec handle_cast(any(), state()) -> kz_types:handle_cast_ret_state(state()).
handle_cast({'push', JObj}, State) ->
    kz_util:put_callid(JObj),
    TokenApp = kz_json:get_value(<<"Token-App">>, JObj),
    maybe_send_push_notification(webhook_url(TokenApp), TokenApp, JObj),
    {'noreply', State};
handle_cast('stop', State) ->
    {'stop', 'normal', State};
handle_cast(_Msg, State) ->
    lager:debug("unhandled cast: ~p", [_Msg]),
    {'noreply', State}.

-spec handle_info(any(), state()) -> kz_types:handle_info_ret_state(state()).
handle_info(_Request, State) ->
    {'noreply', State}.

-spec terminate(any(), state()) -> 'ok'.
terminate(_Reason, _State) ->
    'ok'.

-spec code_change(any(), state(), any()) -> {'ok', state()}.
code_change(_OldVsn, State, _Extra) ->
    {'ok', State}.

-spec webhook_url(kz_term:api_binary()) -> kz_term:api_ne_binary().
webhook_url('undefined') -> 'undefined';
webhook_url(App) ->
    kapps_config:get_ne_binary(?CONFIG_CAT, [?WEBHOOK, <<"url">>], 'undefined', App).

-spec request_headers(kz_term:api_binary()) -> kz_http:headers().
request_headers(App) ->
    JObj = kapps_config:get_json(?CONFIG_CAT, [?WEBHOOK, <<"headers">>], kz_json:new(), App),
    props:insert_value(<<"content-type">>, <<"application/json">>, kz_json:to_proplist(JObj)).

-spec maybe_send_push_notification(kz_term:api_ne_binary(), kz_term:api_binary(), kz_json:object()) -> 'ok'.
maybe_send_push_notification('undefined', App, _JObj) ->
    lager:debug("webhook pusher url for app ~s not found", [App]);
maybe_send_push_notification(Url, App, JObj) ->
    TokenID = kz_json:get_value(<<"Token-ID">>, JObj),
    Message = kz_json:from_list([{<<"token">>, TokenID}
                                ,{<<"data">>, kz_json:from_list([{<<"payload">>, kz_json:encode(build_payload(JObj))}])}
                                ]),
    Body = kz_json:encode(Message),
    Headers = request_headers(App),

    lager:debug("pushing to ~s: ~s: ~s", [Url, TokenID, Body]),

    _ = kz_util:spawn(fun send/3, [Url, Headers, Body]),
    'ok'.

-spec build_payload(kz_json:object()) -> kz_json:object().
build_payload(JObj) ->
    Alert = #{<<"loc-key">> => kz_json:get_value(<<"Alert-Key">>, JObj)
             ,<<"loc-args">> => kz_json:get_value(<<"Alert-Params">>, JObj)
             },
    kz_json:set_values([{<<"voip">>, 'true'}
                       ,{<<"alert">>, kz_json:from_map(Alert)}
                       ,{<<"remote_contact">>, kz_json:get_value([<<"Payload">>, <<"caller-id-number">>], JObj)}
                       ,{<<"sound">>, kz_json:get_value(<<"Sound">>, JObj)}
                       ], kz_json:get_value(<<"Payload">>, JObj)).

-spec send(kz_term:ne_binary(), kz_http:headers(), iodata()) -> 'ok'.
send(Url, Headers, Body) ->
    Options = [{'connect_timeout', ?CONNECT_TIMEOUT}
              ,{'timeout', ?REQUEST_TIMEOUT}
              ],
    case kz_http:post(kz_term:to_list(Url), Headers, Body, Options) of
        {'ok', Status, _RespHeaders, _RespBody}
          when Status >= 200,
               Status < 300 ->
            lager:debug("webhook push to ~s returned ~b", [Url, Status]);
        {'ok', Status, _RespHeaders, RespBody} ->
            lager:warning("webhook push to ~s returned ~b: ~s", [Url, Status, RespBody]);
        Resp ->
            lager:warning("webhook push to ~s failed: ~p", [Url, Resp])
    end.
