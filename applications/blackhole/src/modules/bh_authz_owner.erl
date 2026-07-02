%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2026, 2600Hz
%%% @doc Owner-based subscribe authorization. In `reject' mode, denies event
%%% subscriptions from owner-restricted (non-admin) sessions, since Blackhole
%%% event bindings are not inherently user-scoped. In `filter' mode it is a
%%% no-op (delivery filtering happens in bh_events). Runs after
%%% bh_authz_subscribe (the account-hierarchy gate).
%%% @end
%%%-----------------------------------------------------------------------------
-module(bh_authz_owner).

-export([init/0
        ,authorize_owner/2
        ]).

-include("blackhole.hrl").

-spec init() -> 'ok'.
init() ->
    _ = blackhole_bindings:bind(<<"blackhole.events.authorize.*">>, ?MODULE, 'authorize_owner'),
    'ok'.

-spec authorize_owner(bh_context:context(), map()) -> bh_context:context().
authorize_owner(Context, _Map) ->
    case bh_owner_authz:is_enforced(Context)
        andalso bh_owner_authz:mode(Context) =:= <<"reject">>
    of
        'true' ->
            lager:debug("owner-restricted session denied event subscription (reject mode)"),
            bh_context:add_error(Context, <<"unauthorized: owner-restricted subscription">>);
        'false' ->
            Context
    end.
