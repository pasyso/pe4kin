%%% @author Sergey Prokhorov <me@seriyps.ru>
%%% @copyright (C) 2016, Sergey Prokhorov
%%% @doc
%%% Main API module.
%%% @end
%%% Created : 18 May 2016 by Sergey Prokhorov <me@seriyps.ru>

-module(pe4kin).
-export([api_call/2, api_call/3, download_file/2, send_big_text/2]).
-export([launch_bot/3]).
-export([get_me/1, send_message/2, forward_message/2, send_photo/2, send_audio/2,
         send_document/2, send_sticker/2, send_video/2, send_voice/2, send_location/2,
         send_venue/2, send_contact/2, send_chat_action/2, get_user_profile_photos/2,
         get_file/2, kick_chat_member/2, unban_chat_member/2, answer_callback_query/2,
         get_updates_sync/2]).
-export([get_env/1, get_env/2]).

-export_type([bot_name/0, chat_id/0, update/0]).
-export_type([json_object/0, json_value/0]).

-type bot_name() :: binary().                   % bot name without leading "@"
-type chat_id() :: integer().                   % =< 52 bit
-type update() :: json_object().
-type input_file() :: {file, Name :: binary(), ContentType :: binary(), Payload :: iodata()}
                    | {file_path, file:name()}
                    | integer().


-type json_literal() :: null
                      | true
                      | false
                      | json_string()
                      | json_number().
-type json_value() :: json_literal()
                    | json_object()
                    | json_array().

-type json_array()  :: [json_value()].
-type json_string() :: atom() | binary().
-type json_number() :: integer() | float().

-type json_object() :: #{json_string() => json_value()}.

-type api_body() :: undefined
                    | {json, json_object()}
                    | {query, #{json_string() => json_literal()}}
                    | {multipart, #{json_string() => json_literal() | input_file()}}.

get_token(Bot) ->
    {ok, Token} = get_env({Bot, token}),
    Token.

launch_bot(Bot, Token, Opts) ->
    set_env({Bot, token}, Token),
    case Opts of
        #{receiver := true} ->
            %% pe4kin_receiver_sup:start_receiver(
            pe4kin_receiver:start_link(
              Bot,
              Token,
              maps:remove(receiver, Opts));
       _ -> ok
    end.

%% Api methods

get_me(Bot) ->
    api_call(Bot, <<"getMe">>).

send_message(Bot, #{chat_id := _, text := _} = Message) ->
    api_call(Bot, <<"sendMessage">>, {json, Message}).

forward_message(Bot, #{chat_id := _, from_chat_id := _, message_id := _} = Req) ->
    api_call(Bot, <<"forwardMessage">>, {json, Req}).

send_photo(Bot, #{chat_id := _, photo := _} = Req) ->
    api_call(Bot, <<"sendPhoto">>, body_with_file([photo], Req)).

send_audio(Bot, #{chat_id := _, audio := _} = Req) ->
    api_call(Bot, <<"sendAudio">>, body_with_file([audio], Req)).

send_document(Bot, #{chat_id := _, document := _} = Req) ->
    api_call(Bot, <<"sendDocument">>, body_with_file([document], Req)).

send_sticker(Bot, #{chat_id := _, sticker := _} = Req) ->
    api_call(Bot, <<"sendSticker">>, body_with_file([sticker], Req)).

send_video(Bot, #{chat_id := _, video := _} = Req) ->
    api_call(Bot, <<"sendVideo">>, body_with_file([video], Req)).

send_voice(Bot, #{chat_id := _, voice := _} = Req) ->
    api_call(Bot, <<"sendVoice">>, body_with_file([voice], Req)).

send_location(Bot, #{chat_id := _, latitude := _, longitude := _} = Req) ->
    api_call(Bot, <<"sendLocation">>, {json, Req}).

send_venue(Bot, #{chat_id := _, latitude := _, longitude := _, title := _, address := _} = Req) ->
    api_call(Bot, <<"sendVenue">>, {json, Req}).

send_contact(Bot, #{chat_id := _, phone_number := _, first_name := _} = Req) ->
    api_call(Bot, <<"sendContact">>, {json, Req}).

send_chat_action(Bot, #{chat_id := _, action := _} = Req) ->
    api_call(Bot, <<"sendChatAction">>, {json, Req}).

get_user_profile_photos(Bot, #{user_id := _} = Req) ->
    api_call(Bot, <<"getUserProfilePhotos">>, {json, Req}).

get_file(Bot, #{file_id := _} = Req) ->
    api_call(Bot, <<"getFile">>, {json, Req}).

kick_chat_member(Bot, #{chat_id := _, user_id := _} = Req) ->
    api_call(Bot, <<"kickChatMember">>, {json, Req}).

unban_chat_member(Bot, #{chat_id := _, user_id := _} = Req) ->
    api_call(Bot, <<"unbanChatMember">>, {json, Req}).

answer_callback_query(Bot, #{callback_query_id := _} = Req) ->
    api_call(Bot, <<"answerCallbackQuery">>, {json, Req}).


%% @doc Sends text message and if it's too big for a single message, splits it to many.
%% It's not a good idea to add extra fields like online keyboards, because they will be
%% attached to every message
send_big_text(Bot, #{chat_id := _, text := Text} = Message) ->
    case pe4kin_util:strlen(Text) of
        L when L > 4095 ->
            {split, send_text_by_parts(Bot, Text, Message)};
        _ ->
            send_message(Bot, Message)
    end.

send_text_by_parts(Bot, Utf8Str, Extra) ->
    try pe4kin_util:slice_pos(Utf8Str, 4095) of
        SliceBSize ->
            <<Slice:SliceBSize/binary, Rest/binary>> = Utf8Str,
            Res = send_message(Bot, Extra#{text => Slice}),
            [Res | send_text_by_parts(Bot, Rest, Extra)]
    catch error:_ ->
            %% too short
            [send_message(Bot, Extra#{text => Utf8Str})]
    end.


%% @doc
%% This API is for testing purposes
get_updates_sync(Bot, Opts) ->
    Opts1 = Opts#{timeout => 0},
    QS = cow_qs:qs([{atom_to_binary(Key, utf8), integer_to_binary(Val)}
                    || {Key, Val} <- maps:to_list(Opts1)]),
    api_call(Bot, <<"getUpdates?", QS/binary>>).

%% Generic API methods

-spec download_file(bot_name(), json_object()) -> {ok, Headers :: [{binary(), binary()}], Body :: binary()}.
download_file(Bot, #{<<"file_id">> := _,
                     <<"file_path">> := FilePath}) ->
    Endpoint = get_env(api_server_endpoint, <<"https://api.telegram.org">>),
    Token = get_token(Bot),
    Url = <<Endpoint/binary, "/file/bot", Token/binary, "/", FilePath/binary>>,
    {ok, 200, Headers, Body} = do_api_call(Url, undefined),
    {ok, Headers, Body}.


-spec api_call(bot_name(), binary()) -> {ok, json_value()} | {error, Type :: atom(), term()}.
api_call(Bot, Method) ->
    api_call(Bot, Method, undefined).

-spec api_call(bot_name(), binary(), api_body()) -> {ok, json_value()} | {error, Type :: atom(), term()}.
api_call(Bot, Method, Payload) ->
    Endpoint = get_env(api_server_endpoint, <<"https://api.telegram.org">>),
    Token = get_token(Bot),
    api_call({Endpoint, Token}, Bot, Method, Payload).

api_call({_ApiServerEndpoint, Token}, _Bot, Method, Payload) ->
    Url = <<"/bot", Token/binary, "/", Method/binary>>,
    case do_api_call(Url, Payload) of
        {Code, Hdrs, Body} when Code >= 200, Code < 300 ->
            ContentType = cow_http_hd:parse_content_type(
                            proplists:get_value(<<"content-type">>, Hdrs)),
            case {Body, ContentType, Code} of
                {<<>>, _, 200} -> ok;
                {Body, {<<"application">>, <<"json">>, _}, _}  ->
                    case jiffy:decode(Body, [return_maps]) of
                        #{<<"ok">> := true, <<"result">> := Result} when Code == 200 ->
                            {ok, Result};
                        #{<<"ok">> := false, <<"description">> := ErrDescription,
                          <<"error_code">> := ErrCode} when Code =/= 200 ->
                            {error, telegram, {ErrCode, Code, ErrDescription}}
                    end
            end;
        {Code, _Hdrs, _Body} -> {error, http, #{status_code => Code}};
        {error, ErrReason} -> {error, http, ErrReason}
    end.


do_api_call(Url, undefined) ->
    pe4kin_http:get(Url);
do_api_call(Url, {json, _} = Json) ->
    Headers = [{<<"content-type">>, <<"application/json">>},
               {<<"accept">>, <<"application/json">>}],
    pe4kin_http:post(Url, Headers, Json);
do_api_call(Url, {query, Payload}) ->
    Headers = [{<<"content-type">>, <<"application/x-www-form-urlencoded; encoding=utf-8">>},
               {<<"accept">>, <<"application/json">>}],
    pe4kin_http:post(Url, Headers, {form, maps:to_list(Payload)});
do_api_call(Url, {multipart, Payload}) ->
    Headers = [{<<"content-type">>, <<"multipart/form-data">>},
               {<<"accept">>, <<"application/json">>}],
    pe4kin_http:post(Url, Headers, {multipart, Payload}).

body_with_file(FileFields, Payload) ->
    body_with_file_(FileFields, json, Payload).

body_with_file_([Key | Keys] = AllKeys, json, Map) ->
    case maps:get(Key, Map) of
        Bin when is_binary(Bin) -> body_with_file_(Keys, json, Map);
        File when (element(1, File) == file) orelse (element(1, File) == file_path) ->
            body_with_file_(AllKeys, multipart, maps:to_list(Map))
    end;
body_with_file_([Key | Keys], multipart, List) ->
    case lists:keyfind(Key, 1, List) of
        {Key, Bin} when is_binary(Bin) ->
            %% file ID
            body_with_file_(Keys, multipart, List);
        {Key, File} when is_tuple(File) ->
            %% `file' or `file_name' tuple
            body_with_file_(Keys, multipart, lists:keyreplace(Key, 1, List, file2multipart(Key, File)))
    end;
body_with_file_([], multipart, Load) ->
    ToBin = fun(V) when is_integer(V) -> integer_to_binary(V);
               (V) when is_atom(V) -> atom_to_binary(V, utf8);
               (V) -> V
            end,
    BinLoad = lists:map(fun({K, V}) ->
                                {ToBin(K), ToBin(V)};
                           (File) -> File
                        end, Load),
    {multipart, BinLoad};
body_with_file_([], Enctype, Load) ->
    %% json
    {Enctype, Load}.

file2multipart(Key, {file, FileName, ContentType, Payload}) ->
    {atom_to_binary(Key, utf8),
     Payload,
     {<<"form-data">>, [{<<"name">>, atom_to_binary(Key, utf8)},
                        {<<"filename">>, FileName}]},
     [{<<"Content-Type">>, ContentType}]};
file2multipart(Key, {file_path, Path}) ->
    {file,
     Path,
     {<<"form-data">>, [{<<"name">>, atom_to_binary(Key, utf8)},
                        {<<"filename">>, filename:basename(Path)}]},
      []}.

-dialyzer({nowarn_function, get_env/2}).
-spec get_env(any(), any()) -> any().
get_env(Key, Default) ->
    application:get_env(?MODULE, Key, Default).

-dialyzer({nowarn_function, get_env/1}).
-spec get_env(any()) -> {ok, any()}.
get_env(Key) ->
    application:get_env(?MODULE, Key).

-dialyzer({nowarn_function, set_env/2}).
-spec set_env(any(), any()) -> ok.
set_env(Key, Value) ->
    application:set_env(?MODULE, Key, Value).
