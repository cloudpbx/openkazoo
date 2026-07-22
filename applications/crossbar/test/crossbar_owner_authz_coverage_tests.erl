%%%-----------------------------------------------------------------------------
%%% @doc Regression backstop for owner-authz coverage.
%%%
%%% Owner-authz is wired per-endpoint, so a new (or refactored) Crossbar module
%%% that serves per-user records can silently reopen the intra-account IDOR gap
%%% if it forgets the gate. These tests fail the build when that happens:
%%%
%%%   1. every module in gated/0 still references `crossbar_owner_authz'
%%%      (catches accidental removal of a gate);
%%%   2. every `cb_*' module that references `owner_id' is EITHER gated OR listed
%%%      in exempt/0 with a justification (forces a conscious decision for any new
%%%      owner-bearing endpoint).
%%%
%%% To add a new owner-bearing endpoint: wire `crossbar_owner_authz' into it (so
%%% it shows up as gated) OR, if it has no per-user record-ownership semantics,
%%% add it to exempt/0 with a one-line reason.
%%% @end
%%%-----------------------------------------------------------------------------
-module(crossbar_owner_authz_coverage_tests).
-include_lib("eunit/include/eunit.hrl").

%% Modules that MUST wire the shared owner-authz gate.
gated() ->
    ["cb_devices_v2", "cb_cdrs", "cb_users_v2", "cb_recordings", "cb_sms",
     "cb_mms", "cb_faxes", "cb_call_inspector", "cb_vmboxes", "cb_groups",
     "cb_storage"].

%% Modules that reference owner_id but are intentionally NOT owner-gated.
%% {Module, Reason}. A new owner_id-referencing module that is neither gated nor
%% listed here will FAIL no_ungated_owner_module_test_.
exempt() ->
    [{"cb_auth", "auth endpoint; owner_id is a token claim, not an owned record"},
     {"cb_user_auth", "auth endpoint; owner_id is a token claim"},
     {"cb_shared_auth", "auth endpoint; owner_id is a token claim"},
     {"cb_token_auth", "auth endpoint; owner_id is a token claim"},
     {"cb_token_restrictions", "token restriction config; owner_id is a token subject"},
     {"cb_apps_link", "SSO app-link token builder; owner_id is the token subject"},
     {"cb_onboard", "account creation flow; sets owner_id on new docs, reads none"},
     {"cb_migrations", "admin migration tooling; owner_id is audit metadata"},
     {"cb_rate_limits", "rate-limit config keyed to device/account, not user records"},
     {"cb_port_requests", "account-level porting; owner_id read for submitter attribution"},
     {"cb_quickcall", "originate nested under gated /devices|/users/{id}; parent gates access"},
     {"cb_channels", "live ephemeral channel state, not an owned doc; REVIEW: live-call visibility"},
     {"cb_alerts", "alerts self-scoped to caller owner_id from auth doc; REVIEW: migrate to shared gate"}].

gated_modules_reference_owner_authz_test_() ->
    [{M, ?_assert(refs(M, "crossbar_owner_authz"))} || M <- gated()].

no_ungated_owner_module_test_() ->
    Ungated = lists:usort(
                [basename(F)
                 || F <- source_files(),
                    refs_file(F, "owner_id"),
                    not lists:member(basename(F), gated()),
                    not lists:keymember(basename(F), 1, exempt()),
                    not refs_file(F, "crossbar_owner_authz")]),
    {"every owner_id-referencing crossbar module is gated or explicitly exempt",
     ?_assertEqual([], Ungated)}.

exempt_entries_have_reasons_test_() ->
    [{M, ?_assert(length(R) >= 10)} || {M, R} <- exempt()].

%%% helpers
source_dirs() ->
    Roots = roots(),
    Cands = lists:append([[filename:join([R, "src", "modules"]),
                           filename:join([R, "src", "modules_v2"])] || R <- Roots]),
    [D || D <- Cands, filelib:is_dir(D)].

roots() ->
    L = case code:lib_dir(crossbar) of
            {error, _} -> [];
            Dir -> [Dir]
        end,
    L ++ [filename:dirname(filename:dirname(?FILE))].

source_files() ->
    lists:append([filelib:wildcard(filename:join(D, "cb_*.erl")) || D <- source_dirs()]).

basename(F) -> filename:basename(F, ".erl").

refs(M, S) ->
    lists:any(fun(D) ->
                      F = filename:join(D, M ++ ".erl"),
                      filelib:is_file(F) andalso refs_file(F, S)
              end, source_dirs()).

refs_file(F, S) ->
    case file:read_file(F) of
        {ok, Bin} -> binary:match(Bin, list_to_binary(S)) =/= nomatch;
        _ -> false
    end.
