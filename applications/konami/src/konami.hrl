-ifndef(KONAMI_HRL).
-include_lib("kazoo_stdlib/include/kz_types.hrl").
-include_lib("kazoo_stdlib/include/kz_log.hrl").
-include_lib("kazoo_stdlib/include/kz_databases.hrl").

-define(APP, 'konami').
-define(APP_NAME, <<"konami">>).
-define(APP_VERSION, kz_util:application_version(?APP)).

-define(CONFIG_CAT, ?APP_NAME).

-define(EVENT(CallId, EventName, Event)
       ,{'event', CallId, EventName, Event}
       ).

-define(WSD_ENABLED, kapps_config:get_is_true(?CONFIG_CAT, <<"webseq_enabled">>, 'false')).

%% The recordings running on the call's legs when a metaflow starts, whoever started them: {CallId, Path}.
-define(CALL_RECORDINGS_KEY, <<"konami_call_recordings">>).
-define(RECORDING_EVENTS, [<<"RECORD_START">>, <<"RECORD_STOP">>, <<"CHANNEL_DESTROY">>]).

-define(KONAMI_HRL, 'true').
-endif.
