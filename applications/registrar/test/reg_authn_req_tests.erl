-module(reg_authn_req_tests).

-include_lib("eunit/include/eunit.hrl").

device(CustomSIPHeaders) ->
    kz_json:from_list_recursive([{<<"sip">>, [{<<"custom_sip_headers">>, CustomSIPHeaders}]}]).

all_external_ids_test() ->
    Device = device([{<<"in">>, [{<<"P-Ext-Org-ID">>, <<"org-1">>}
                                ,{<<"P-Ext-User-ID">>, <<"user-1">>}
                                ,{<<"P-Ext-Product-ID">>, <<"product-1">>}
                                ,{<<"P-Ext-Campaign-ID">>, <<"campaign-1">>}
                                ,{<<"X-Unrelated">>, <<"ignored">>}
                                ]}
                    ]),
    ?assertEqual([{<<"Ext-Org-ID">>, <<"org-1">>}
                 ,{<<"Ext-User-ID">>, <<"user-1">>}
                 ,{<<"Ext-Product-ID">>, <<"product-1">>}
                 ,{<<"Ext-Campaign-ID">>, <<"campaign-1">>}
                 ]
                ,reg_authn_req:external_id_ccvs(Device)
                ).

partial_external_ids_test() ->
    Device = device([{<<"in">>, [{<<"P-Ext-Org-ID">>, <<"org-1">>}]}]),
    ?assertEqual(kz_json:from_list([{<<"Ext-Org-ID">>, <<"org-1">>}])
                ,kz_json:from_list(reg_authn_req:external_id_ccvs(Device))
                ).

no_custom_sip_headers_adds_no_ccvs_test() ->
    ?assertEqual(kz_json:new()
                ,kz_json:from_list(reg_authn_req:external_id_ccvs(kz_json:new()))
                ).

out_headers_are_not_read_test() ->
    Device = device([{<<"out">>, [{<<"P-Ext-Org-ID">>, <<"org-out">>}]}]),
    ?assertEqual(kz_json:new()
                ,kz_json:from_list(reg_authn_req:external_id_ccvs(Device))
                ).
