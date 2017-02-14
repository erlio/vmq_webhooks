%% Copyright 2017 Erlio GmbH Basel Switzerland (http://erl.io)
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(vmq_webhooks_cli).
-export([register_cli/0]).
-behaviour(clique_handler).

register_cli() ->
    register_cli_usage(),
    status_cmd(),
    register_cmd(),
    cache_stats_cmd(),
    deregister_cmd().

cache_stats_cmd() ->
    Cmd = ["vmq-admin", "webhooks", "cache", "stats"],
    FlagSpecs = [{reset, [{longname, "reset"}]}],
    Callback =
        fun(_, [], []) ->
                Table =
                    maps:fold(
                      fun({Type, Endpoint, Hook}, Ctr, Acc) ->
                              [[{stat, Type},
                                {endpoint, Endpoint},
                                {hook, Hook},
                                {value, Ctr}] | Acc]
                      end,
                      [],
                      vmq_webhooks_cache:stats()),
                [clique_status:table(Table)];
           (_, [], [{reset, _ResetFlag}]) ->
                vmq_webhooks_cache:reset_stats(),
                [clique_status:text("Done")];
           (_, _, _) ->
                Text = clique_status:text(cache_usage()),
                [clique_status:alert([Text])]
        end,
    clique:register_command(Cmd, [], FlagSpecs, Callback).

status_cmd() ->
    Cmd = ["vmq-admin", "webhooks", "status"],
    Callback =
        fun(_, [], []) ->
                Table = 
                    [[{hook, Hook}, {endpoint, binary_to_list(Endpoint)},
                      {base64payload, b64opt(Opts)}] ||
                        {Hook, Endpoints} <- vmq_webhooks_plugin:all_hooks(),
                        {Endpoint, Opts} <- Endpoints],
                [clique_status:table(Table)];
           (_, _, _) ->
                Text = clique_status:text(webhooks_usage()),
                [clique_status:alert([Text])]
        end,
    clique:register_command(Cmd, [], [], Callback).

b64opt(#{base64_payload := Val}) ->
    Val;
b64opt(_) -> false.

register_cmd() ->
    Cmd = ["vmq-admin", "webhooks", "register"],
    KeySpecs = [hook_keyspec(), endpoint_keyspec()],
    FlagSpecs = [{base64_payload, [{longname, "base64payload"},
                                   {typecast,
                                    fun("true") -> true;
                                       ("false") -> false;
                                       (Val) -> {{error, {invalid_flag_value, {base64payload, Val}}}}
                                    end}]}],
    Callback =
        fun(_, [{hook, Hook}, {endpoint, Endpoint}], Flags) ->
                Opts = get_opts(Flags),
                case vmq_webhooks_plugin:register_endpoint(Endpoint, Hook, Opts) of
                    ok ->
                        [clique_status:text("Done")];
                    {error, Reason} ->
                        lager:warning("Can't register endpoint ~p ~p due to ~p",
                                      [Hook, Endpoint, Reason]),
                        Text = io_lib:format("can't register endpoint due to '~p'", [Reason]),
                        [clique_status:alert([clique_status:text(Text)])]
                end;
           (_, _, _) ->
                Text = clique_status:text(register_usage()),
                [clique_status:alert([Text])]
        end,
    clique:register_command(Cmd, KeySpecs, FlagSpecs, Callback).

get_opts(Flags) ->
    Defaults = #{
      base64_payload => true
     },
    Keys = [base64_payload],
    maps:merge(Defaults, maps:with(Keys, maps:from_list(Flags))).

deregister_cmd() -> 
    Cmd = ["vmq-admin", "webhooks", "deregister"],
    KeySpecs = [hook_keyspec(), endpoint_keyspec()],
    FlagSpecs = [],
    Callback =
        fun(_, [{hook, Hook}, {endpoint, Endpoint}], []) ->
                case vmq_webhooks_plugin:deregister_endpoint(Endpoint, Hook) of
                    ok ->
                        [clique_status:text("Done")];
                    {error, Reason} ->
                        lager:warning("Can't deregister endpoint ~p ~p due to ~p",
                                      [Hook, Endpoint, Reason]),
                        Text = io_lib:format("can't deregister endpoint due to '~p'", [Reason]),
                        [clique_status:alert([clique_status:text(Text)])]
                end;
           (_, _, _) ->
                Text = clique_status:text(deregister_usage()),
                [clique_status:alert([Text])]
        end,
    clique:register_command(Cmd, KeySpecs, FlagSpecs, Callback).

hook_keyspec() ->
    {hook, [{typecast,
             fun(Hook) when is_list(Hook) ->
                     case lists:member(Hook,
                                       ["auth_on_register",
                                        "auth_on_publish",
                                        "auth_on_subscribe",
                                        "on_register",
                                        "on_publish",
                                        "on_subscribe",
                                        "on_unsubscribe",
                                        "on_deliver",
                                        "on_offline_message",
                                        "on_client_wakeup",
                                        "on_client_offline",
                                        "on_client_gone"]) of
                         true ->
                             binary_to_atom(list_to_binary(Hook), utf8);
                         _ -> {error, {invalid_value, Hook}}
                     end;
                (Hook) -> {error, {invalid_value, Hook}}
             end}]}.

endpoint_keyspec() ->
    {endpoint, [{typecast,
                 fun(E) when is_list(E) ->
                         try hackney_url:parse_url(E) of
                             _ ->
                                 list_to_binary(E)
                         catch
                             _:_ ->
                                 {error, {invalid_value, E}}
                         end;
                    (E) -> {error, {invalid_value, E}}
                 end}]}.

register_cli_usage() ->
    clique:register_usage(["vmq-admin", "webhooks"], webhooks_usage()),
    clique:register_usage(["vmq-admin", "webhooks", "register"], register_usage()),
    clique:register_usage(["vmq-admin", "webhooks", "deregister"], deregister_usage()),
    clique:register_usage(["vmq-admin", "webhooks", "status"], status_usage()),
    clique:register_usage(["vmq-admin", "webhooks", "cache"], cache_usage()).

webhooks_usage() ->
    ["vmq-admin webhooks <sub-command>\n\n",
     "  Manage VerneMQ Webhooks.\n\n",
     "  Sub-commands:\n",
     "    status      Show the status of registered webhooks\n",
     "    register    Register a webhook\n",
     "    deregister  Deregister a webhook\n",
     "    cache       Manage the webhooks cache\n\n",
     "  Use --help after a sub-command for more details.\n"
    ].

register_usage() ->
    ["vmq-admin webhooks register hook=<Hook> endpoint=<Url>\n\n",
     "  Registers a webhook endpoint with a hook.",
     "\n\n"
     "  --base64payload=<true|false>\n",
     "     base64 encode the MQTT payload. Defaults to true.",
     "\n\n"
    ].

deregister_usage() ->
    ["vmq-admin webhooks deregister hook=<Hook> endpoint=<Url>\n\n",
     "  Deregisters a webhook endpoint.",
     "\n\n"
    ].

status_usage() ->
    ["vmq-admin webhooks status\n\n",
     "  Shows the information of the registered webhooks.",
     "\n\n"
    ].

cache_usage() ->
    ["vmq-admin webhooks cache\n\n",
     "  Manage the webhooks cache."
     "\n\n",
     "  Sub-commands:\n",
     "    stats       Show statistics about the cache\n"
    ].
