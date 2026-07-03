%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2026, 2600Hz
%%% @doc Opt-in owner-based access policy for Blackhole, shared by the
%%% subscribe gate (bh_authz_owner) and the delivery filter (bh_events).
%%% Mirrors the Crossbar owner policy and reuses the crossbar.owner_authz
%%% config so REST and WebSocket enforcement stay consistent.
%%% @end
%%%-----------------------------------------------------------------------------
-module(bh_owner_authz).

-export([is_enforced/1
        ,mode/1
        ,should_deliver/2
        ,event_owner_id/1
        ]).

-include("blackhole.hrl").

-define(OWNER_AUTHZ_CAT, <<"crossbar.owner_authz">>).

%%------------------------------------------------------------------------------
%% @doc Owner restriction applies iff the flag is on, the session is a
%% non-admin, and an auth user id is present. Admins short-circuit (bypass).
%% @end
%%------------------------------------------------------------------------------
-spec is_enforced(bh_context:context()) -> boolean().
is_enforced(Context) ->
    AccountId = bh_context:auth_account_id(Context),
    restrict_to_owner(AccountId)
        andalso (not is_admin(Context))
        andalso bh_context:auth_user_id(Context) =/= 'undefined'.

-spec is_admin(bh_context:context()) -> boolean().
is_admin(Context) ->
    bh_context:is_superduper_admin(Context)
        orelse bh_context:is_account_admin(Context).

-spec restrict_to_owner(kz_term:api_ne_binary()) -> boolean().
restrict_to_owner(AccountId) ->
    kz_term:is_true(
      kapps_account_config:get_global(AccountId, ?OWNER_AUTHZ_CAT
                                     ,<<"should_restrict_access_to_owner">>, 'false'
                                     )
     ).

-spec mode(bh_context:context()) -> kz_term:ne_binary().
mode(Context) ->
    AccountId = bh_context:auth_account_id(Context),
    case kapps_account_config:get_global(AccountId, ?OWNER_AUTHZ_CAT
                                        ,<<"general_endpoint_mode">>, <<"filter">>
                                        )
    of
        <<"reject">> -> <<"reject">>;
        _ -> <<"filter">>
    end.

%%------------------------------------------------------------------------------
%% @doc Delivery-time decision: deliver iff not enforced, OR the event's
%% resolved owner equals the session's auth user. Events with no resolvable
%% owner are dropped (fail-closed) when enforced.
%% @end
%%------------------------------------------------------------------------------
-spec should_deliver(bh_context:context(), kz_json:object()) -> boolean().
should_deliver(Context, EventJObj) ->
    case is_enforced(Context) of
        'false' -> 'true';
        'true' -> event_owner_id(EventJObj) =:= bh_context:auth_user_id(Context)
    end.

%%------------------------------------------------------------------------------
%% @doc Best-effort owner extraction from a normalized event payload. Unknown
%% shapes return 'undefined', which the caller treats as "drop" when enforced.
%% @end
%%------------------------------------------------------------------------------
-spec event_owner_id(kz_json:object()) -> kz_term:api_ne_binary().
event_owner_id(JObj) ->
    kz_json:get_first_defined([<<"owner_id">>
                              ,[<<"custom_channel_vars">>, <<"owner_id">>]
                              ,[<<"doc">>, <<"owner_id">>]
                              ]
                             ,JObj
                             ).
