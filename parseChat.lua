local json = require "libs/json"

require "buildMessage"
require "mm2plHelper"

---@param action table
local add_chat = function(data, action)
  local videoId = data.videoId

  local splits = Get_Active_Stream_Splits(videoId)

  local item = OptionalChain(action, "addChatItemAction", "item")

  local showChannel = #splits > 0

  if item == nil then
    print("Missing addChatItemAction.item")
    print(json.encode(action))
    return
  end

  local message = Build_Message(data, item, showChannel)

  if message == nil then
    return
  end

  for _, split in ipairs(splits) do
    local channel = c2.Channel.by_name(split)
    if channel then
      -- channel:add_system_message(text)
      channel:add_message(message)
    end
  end
end

---@param youtubeData table
local add_chats = function(data, youtubeData)
  local actions = OptionalChain(youtubeData, "continuationContents", "liveChatContinuation", "actions")

  if actions == nil then
    return
  end

  for _, action in ipairs(actions) do
    add_chat(data, action)
  end
end

---@param youtubeData table
local get_next_continuation = function(youtubeData)
  local nextContinuation = nil

  local CS = OptionalChain(youtubeData, "continuationContents", "liveChatContinuation", "continuations")

  if CS then
    nextContinuation = CS[1]
  end

  local continuation = nil

  if nextContinuation then
    local ICDC = OptionalChain(nextContinuation, "invalidationContinuationData", "continuation")
    local TCDC = OptionalChain(nextContinuation, "timedContinuationData", "continuation")

    continuation = ICDC or TCDC
  end

  if continuation == nil then
    continuation = OptionalChain(youtubeData, "invalidationContinuationData", "continuation")
  end

  return continuation
end

---@param data { channelName:string, channelId:string, videoId:string, apiKey:string, clientVersion:string, continuation:string }
---@param result c2.HTTPResponse

-- Retry config
local MAX_RETRIES = 5
local BASE_BACKOFF = 1000 -- ms

-- Helper to send system message to all splits for a videoId
local function notify_splits(videoId, msg)
  local splits = Get_Active_Stream_Splits(videoId) or {}
  for _, split in ipairs(splits) do
    local channel = c2.Channel.by_name(split)
    if channel then
      channel:add_system_message("[youtube] " .. msg)
    end
  end
end

local function parse_live_chat_response(data, result)
  local videoId = data.videoId
  local status = result:status()
  local retryCount = data.retryCount or 0

  if status >= 500 or status == 429 then
    -- Retry on server errors or rate limit
    if retryCount < MAX_RETRIES then
      local backoff = BASE_BACKOFF * (2 ^ retryCount)
      notify_splits(videoId, "Temporary error (status " .. status .. "). Retrying in " .. math.floor(backoff/1000) .. "s...")
      c2.later(function()
        Read_YouTube_Chat({
          continuation = data.continuation,
          videoId = data.videoId,
          apiKey = data.apiKey,
          clientVersion = data.clientVersion,
          channelId = data.channelId,
          channelName = data.channelName,
          retryCount = retryCount + 1
        })
      end, backoff)
      return
    else
      notify_splits(videoId, "Polling stopped after repeated errors (status " .. status .. ").")
      Remove_From_Active_Streams(videoId)
      return
    end
  elseif status >= 300 then
    notify_splits(videoId, "Polling stopped due to HTTP error (status " .. status .. ").")
    Remove_From_Active_Streams(videoId)
    return
  end

  local stringJson = result:data()
  local youtubeData = json.decode(stringJson)

  if type(youtubeData) ~= "table" then
    if retryCount < MAX_RETRIES then
      local backoff = BASE_BACKOFF * (2 ^ retryCount)
      notify_splits(videoId, "Invalid data from YouTube. Retrying in " .. math.floor(backoff/1000) .. "s...")
      c2.later(function()
        Read_YouTube_Chat({
          continuation = data.continuation,
          videoId = data.videoId,
          apiKey = data.apiKey,
          clientVersion = data.clientVersion,
          channelId = data.channelId,
          channelName = data.channelName,
          retryCount = retryCount + 1
        })
      end, backoff)
      return
    else
      notify_splits(videoId, "Polling stopped: YouTube returned invalid data repeatedly.")
      Remove_From_Active_Streams(videoId)
      return
    end
  end

  add_chats(data, youtubeData)

  local splits = Get_Active_Stream_Splits(videoId)
  for _, split in ipairs(splits) do
    local channel = c2.Channel.by_name(split)
    if channel == nil then
      Remove_Split_From_Active_Streams(videoId, split)
    end
  end

  splits = Get_Active_Stream_Splits(videoId)
  if #splits == 0 then
    notify_splits(videoId, "Polling stopped: No splits left using this chat.")
    Remove_From_Active_Streams(videoId)
    return
  end

  local newContinuation = get_next_continuation(youtubeData)
  if newContinuation == nil then
    if retryCount < MAX_RETRIES then
      local backoff = BASE_BACKOFF * (2 ^ retryCount)
      notify_splits(videoId, "No continuation token. Retrying in " .. math.floor(backoff/1000) .. "s...")
      c2.later(function()
        Read_YouTube_Chat({
          continuation = data.continuation,
          videoId = data.videoId,
          apiKey = data.apiKey,
          clientVersion = data.clientVersion,
          channelId = data.channelId,
          channelName = data.channelName,
          retryCount = retryCount + 1
        })
      end, backoff)
      return
    else
      notify_splits(videoId, "Polling stopped: No continuation token after multiple attempts.")
      Remove_From_Active_Streams(videoId)
      return
    end
  end

  -- Success: reset retryCount
  c2.later(function()
    Read_YouTube_Chat({
      continuation = newContinuation,
      videoId = data.videoId,
      apiKey = data.apiKey,
      clientVersion = data.clientVersion,
      channelId = data.channelId,
      channelName = data.channelName,
      retryCount = 0
    })
  end, 600)
end

---@param data { channelName:string, channelId:string, videoId:string, apiKey:string, clientVersion:string, continuation:string }

function Read_YouTube_Chat(data)
  local videoId = data.videoId
  local apiKey = data.apiKey
  local clientVersion = data.clientVersion
  local continuation = data.continuation
  local retryCount = data.retryCount or 0

  local request = c2.HTTPRequest.create(c2.HTTPMethod.Post,
    "https://www.youtube.com/youtubei/v1/live_chat/get_live_chat?key=" .. apiKey)

  Mutate_Request_Default_Headers(request)
  request:set_header("Content-Type", "application/json")

  request:set_payload([[ 
    {
      "context": {
        "client": {
          "clientVersion": "]]' .. clientVersion .. [[",
          "clientName": "WEB"
        }
      },
      "continuation": "]]' .. continuation .. [["
    }
  ]])

  request:on_success(function(result)
    parse_live_chat_response(data, result)
  end)

  request:on_error(function(result)
    if retryCount < MAX_RETRIES then
      local backoff = BASE_BACKOFF * (2 ^ retryCount)
      notify_splits(videoId, "Network error: " .. result:error() .. ". Retrying in " .. math.floor(backoff/1000) .. "s...")
      c2.later(function()
        Read_YouTube_Chat({
          continuation = continuation,
          videoId = videoId,
          apiKey = apiKey,
          clientVersion = clientVersion,
          channelId = data.channelId,
          channelName = data.channelName,
          retryCount = retryCount + 1
        })
      end, backoff)
    else
      notify_splits(videoId, "Polling stopped: Network error after multiple attempts (" .. result:error() .. ").")
      Remove_From_Active_Streams(videoId)
    end
  end)

  request:execute()
end
