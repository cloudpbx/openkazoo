%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2026, 2600Hz
%%% @doc Opt-in, owner-based (per-user) access control shared by crossbar modules.
%%% Generalizes the cb_vmboxes owner-restriction pattern. Admins bypass.
%%% @end
%%%-----------------------------------------------------------------------------
-module(crossbar_owner_authz).

-export([
    is_enforced/1,
    general_endpoint_mode/1,
    authorize_collection/1,
    authorize_doc/2,
    scope_owner_id/1,
    maybe_scope_nouns/2,
    filter_owned/2,
    doc_owner_id/1
]).

-include("crossbar.hrl").

-define(OWNER_AUTHZ_CAT, <<(?CONFIG_CAT)/binary, ".owner_authz">>).

%%------------------------------------------------------------------------------
%% @doc Config readers (per-account with system fallback).
%%------------------------------------------------------------------------------
-spec restrict_to_owner(kz_term:api_ne_binary()) -> boolean().
restrict_to_owner(AccountId) ->
    kz_term:is_true(
        kapps_account_config:get_global(
            AccountId,
            ?OWNER_AUTHZ_CAT,
            <<"should_restrict_access_to_owner">>,
            'false'
        )
    ).

-spec restrict_unowned(kz_term:api_ne_binary()) -> boolean().
restrict_unowned(AccountId) ->
    kz_term:is_true(
        kapps_account_config:get_global(
            AccountId,
            ?OWNER_AUTHZ_CAT,
            <<"should_restrict_access_to_unowned">>,
            'false'
        )
    ).

-spec general_endpoint_mode(kz_term:api_ne_binary()) -> <<_:48>>.
%% Return is precisely one of the literal binaries `<<"reject">>' or `<<"filter">>'
%% (each exactly 48 bits / 6 bytes), so authorize_collection/2's case is exhaustive.
%% NOTE: Erlang typespecs cannot express literal binary *values* (`<<"reject">>'),
%% only bit-size binaries; `<<_:48>>' is the tightest valid type covering both.
general_endpoint_mode(AccountId) ->
    case
        kapps_account_config:get_global(
            AccountId,
            ?OWNER_AUTHZ_CAT,
            <<"general_endpoint_mode">>,
            <<"filter">>
        )
    of
        <<"reject">> -> <<"reject">>;
        _ -> <<"filter">>
    end.

%%------------------------------------------------------------------------------
%% @doc Owner restriction applies iff the flag is on, the requester is a
%% non-admin, and an auth user id is present. Admins short-circuit (bypass).
%%------------------------------------------------------------------------------
-spec is_enforced(cb_context:context()) -> boolean().
is_enforced(Context) ->
    AccountId = cb_context:auth_account_id(Context),
    restrict_to_owner(AccountId) andalso
        (not is_admin(Context)) andalso
        cb_context:auth_user_id(Context) =/= 'undefined'.

-spec is_admin(cb_context:context()) -> boolean().
is_admin(Context) ->
    cb_context:is_superduper_admin(Context) orelse
        cb_context:is_account_admin(Context).

%%------------------------------------------------------------------------------
%% @doc Authorize a COLLECTION request. Tri-state, framework-native:
%%   'false'        -> defer (unchanged behavior / filter-mode scoping happens later)
%%   'true'         -> allow (self-scoped /users/{auth_user_id}/...)
%%   {'stop', Ctx}  -> hard deny (403)
%% Callers must only invoke this for collection endpoints (not specific records).
%%------------------------------------------------------------------------------
-spec authorize_collection(cb_context:context()) ->
    boolean() | {'stop', cb_context:context()}.
authorize_collection(Context) ->
    case is_enforced(Context) of
        'false' -> 'false';
        'true' -> authorize_collection(Context, requested_owner_id(cb_context:req_nouns(Context)))
    end.

authorize_collection(Context, 'undefined') ->
    %% account-wide collection
    case general_endpoint_mode(cb_context:auth_account_id(Context)) of
        <<"reject">> ->
            lager:debug(
                "rejecting account-wide collection for restricted user ~s (reject mode)",
                [cb_context:auth_user_id(Context)]
            ),
            {'stop', cb_context:add_system_error('forbidden', Context)};
        <<"filter">> ->
            'false'
    end;
authorize_collection(Context, UserId) ->
    case cb_context:auth_user_id(Context) of
        UserId ->
            'true';
        _Other ->
            lager:debug(
                "rejecting cross-user collection: auth user ~s requested ~s",
                [cb_context:auth_user_id(Context), UserId]
            ),
            {'stop', cb_context:add_system_error('forbidden', Context)}
    end.

-spec requested_owner_id(req_nouns()) -> kz_term:api_ne_binary().
requested_owner_id(Nouns) ->
    case props:get_value(<<"users">>, Nouns) of
        [UserId | _] -> UserId;
        %% An empty users-noun arg list ({<<"users">>, []}) is intentionally
        %% treated as account-wide (no specific owner), returning 'undefined'.
        _ -> 'undefined'
    end.

%%------------------------------------------------------------------------------
%% @doc Record-level ownership, called from validate AFTER the doc is loaded.
%% Mirrors cb_vmboxes:check_if_user_is_owner/2. Returns Context unchanged when
%% allowed, or with a 'forbidden' system error when denied.
%%------------------------------------------------------------------------------
-spec authorize_doc(cb_context:context(), kz_term:api_ne_binary()) -> cb_context:context().
authorize_doc(Context, OwnerId) ->
    case is_enforced(Context) of
        'false' -> Context;
        'true' -> authorize_owner(Context, OwnerId, cb_context:auth_user_id(Context))
    end.

%% Invariant: AuthUserId (3rd arg) is a non-'undefined' ne_binary(), guaranteed by
%% is_enforced/1 (which requires cb_context:auth_user_id/1 =/= 'undefined'). Thus the
%% (Context, OwnerId, OwnerId) equality clause cannot collide on 'undefined'/'undefined';
%% an 'undefined' OwnerId falls through to the dedicated unowned clause below.
-spec authorize_owner(cb_context:context(), kz_term:api_ne_binary(), kz_term:ne_binary()) ->
    cb_context:context().
authorize_owner(Context, OwnerId, OwnerId) ->
    Context;
authorize_owner(Context, 'undefined', _AuthUserId) ->
    case restrict_unowned(cb_context:auth_account_id(Context)) of
        'true' -> cb_context:add_system_error('forbidden', Context);
        'false' -> Context
    end;
authorize_owner(Context, _OwnerId, _AuthUserId) ->
    cb_context:add_system_error('forbidden', Context).

%%------------------------------------------------------------------------------
%% @doc In filter mode, returns the auth_user_id to scope an account-wide
%% collection by; otherwise 'undefined'.
%%------------------------------------------------------------------------------
-spec scope_owner_id(cb_context:context()) -> kz_term:api_ne_binary().
scope_owner_id(Context) ->
    case
        is_enforced(Context) andalso
            general_endpoint_mode(cb_context:auth_account_id(Context)) =:= <<"filter">>
    of
        'true' -> cb_context:auth_user_id(Context);
        'false' -> 'undefined'
    end.

%%------------------------------------------------------------------------------
%% @doc Rewrite an account-wide request's nouns into the /users/{auth_user_id}/...
%% form so existing owner-scoped view clauses are reused. No-op if already
%% users-scoped or not in filter mode.
%%------------------------------------------------------------------------------
-spec maybe_scope_nouns(cb_context:context(), req_nouns()) -> req_nouns().
maybe_scope_nouns(Context, Nouns) ->
    case scope_owner_id(Context) of
        'undefined' -> Nouns;
        UserId -> inject_user_noun(Nouns, UserId)
    end.

-spec inject_user_noun(req_nouns(), kz_term:ne_binary()) -> req_nouns().
inject_user_noun([{_Mod, _Args} = ModNoun, {?KZ_ACCOUNTS_DB, _} = Acct | Rest], UserId) ->
    [ModNoun, {<<"users">>, [UserId]}, Acct | Rest];
inject_user_noun(Nouns, _UserId) ->
    %% already users-scoped (users noun precedes accounts) or unexpected shape
    lager:debug(
        "filter scoping expected but noun shape was unexpected; proceeding account-wide: ~p",
        [Nouns]
    ),
    Nouns.

%%------------------------------------------------------------------------------
%% @doc Drop documents whose owner_id is not the auth user (used for CDR
%% interaction legs so bridged legs owned by others are not returned).
%% Honors should_restrict_access_to_unowned.
%%------------------------------------------------------------------------------
-spec filter_owned(cb_context:context(), kz_json:objects()) -> kz_json:objects().
filter_owned(Context, JObjs) ->
    case is_enforced(Context) of
        'false' ->
            JObjs;
        'true' ->
            AuthUserId = cb_context:auth_user_id(Context),
            RestrictUnowned = restrict_unowned(cb_context:auth_account_id(Context)),
            [JObj || JObj <- JObjs, is_owned(JObj, AuthUserId, RestrictUnowned)]
    end.

-spec is_owned(kz_json:object(), kz_term:ne_binary(), boolean()) -> boolean().
is_owned(JObj, AuthUserId, RestrictUnowned) ->
    case doc_owner_id(JObj) of
        AuthUserId -> 'true';
        'undefined' -> not RestrictUnowned;
        _Other -> 'false'
    end.

%%------------------------------------------------------------------------------
%% @doc Resolve a record's owner id. CDR docs carry the owner under
%% `custom_channel_vars.owner_id'; most other docs (e.g. devices) use a
%% top-level `owner_id'. Check the nested location first, then fall back.
%%------------------------------------------------------------------------------
-spec doc_owner_id(kz_json:object()) -> kz_term:api_ne_binary().
doc_owner_id(JObj) ->
    kz_json:get_first_defined(
        [[<<"custom_channel_vars">>, <<"owner_id">>], <<"owner_id">>], JObj
    ).
