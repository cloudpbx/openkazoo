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

%% kapps_call kvs a newer statem on the same leg inherits from the one it replaces, and the only kvs a
%% metaflow may change on its statem's call: the recorders record_call started.
-define(INHERITED_KVS, [<<"recordings">>]).

-define(KONAMI_HRL, 'true').
-endif.
