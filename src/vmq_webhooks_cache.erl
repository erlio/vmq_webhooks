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

%% @doc A cache for `vmq_webhooks` used to cache the hooks
%% `auth_on_register`, `auth_on_publish` and `auth_on_subscribe` as
%% authentication data is often static.
-module(vmq_webhooks_cache).

-export([
         new/0
        ,reset_stats/0
        ,lookup/3
        ,insert/5
        ,stats/0
        ,purge_all/0
        ]).

-define(CACHE, vmq_webhooks_cache).
-define(STATS, vmq_webhooks_cache_stats).

%% API
new() ->
    ets:new(?CACHE, [public, bag, named_table, {read_concurrency, true}]),
    ets:new(?STATS, [public, ordered_set, named_table, {write_concurrency, true}]),
    ets:insert(?STATS, {hits, 0}),
    ets:insert(?STATS, {misses, 0}),
    ok.

reset_stats() ->
    ets:insert(?STATS, {hits, 0}),
    ets:insert(?STATS, {misses, 0}).

purge_all() ->
    ets:delete_all_objects(?CACHE),
    reset_stats().    

lookup(Endpoint, Hook, Args) ->
    case lookup_(Endpoint, Hook, Args) of
        not_found ->
            miss(),
            not_found;
        Val ->
            hit(),
            Val
    end.

insert(Endpoint, Hook, Args, ExpiryInSecs, Modifiers) ->
    SubscriberId =
        {proplists:get_value(mountpoint, Args),
         proplists:get_value(client_id, Args)},
    ExpirationTs = ts_from_now(ExpiryInSecs),
    %% Remove the payload from cache, as it doesn't make sense to
    %% cache that.
    Key = {Endpoint, Hook, lists:keydelete(payload, 1, Args)},
    %% do not store the payload modifier
    Row = {Key, SubscriberId, ExpirationTs, lists:keydelete(payload, 1, Modifiers)},
    true = ets:insert(?CACHE, Row),
    ok.

%% internal functions.
lookup_(Endpoint, Hook, Args) ->
    %% The payload is not part of the key, so we remove it.
    Key = {Endpoint, Hook, lists:keydelete(payload, 1, Args)},
    case ets:lookup(?CACHE, Key) of
        [] ->
            not_found;
        [{{_EP,_H,_Args},_Sid,ExpirationTs, Modifiers}] ->
            case expired(ExpirationTs) of
                true ->
                    ets:delete(?CACHE, Key),
                    not_found;
                false ->
                    Modifiers
            end
    end.

miss() ->
    ets:update_counter(?STATS, misses, 1, {misses, 0}).

hit() ->
    ets:update_counter(?STATS, hits, 1, {hits, 0}).

expired(ExpirationTs) ->
    ExpirationTs < erlang:system_time(second).

ts_from_now(MaxAge) ->
    erlang:system_time(second) + MaxAge.

stats() ->
    [{_,Hits}] = ets:lookup(?STATS, hits),
    [{_,Misses}] = ets:lookup(?STATS, misses),
    #{hits => Hits,
      misses => Misses,
      entries => ets:info(?CACHE, size)}.
