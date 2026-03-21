require "utils"
require "systemMessages"
require "addStream"
require "readStream"

---@param ctx CommandContext
local cmd_yt_chat = function(ctx)
  local channel = ctx.channel

  if Trim5(channel:get_name()) == "" then
    Warn_Channel_Name(channel)
    return
  end

  if #ctx.words == 1 then
    Warn_No_URL_Provided(channel)
    return
  end

  local url = ctx.words[2]

  if Is_Valid_URL(url) == false then
    Warn_URL_Not_YouTube(channel, url)
    return
  end

  Log_Reading_URL(channel, url)

  if IO_LOCK then
    Warn_IO_Busy(channel)
    return
  end

  Initialize_URL(channel, url)
end

c2.register_command("/yt-chat", cmd_yt_chat)

c2.register_command("/yt-chat-stop", function(ctx)
  local channel = ctx.channel
  local split = channel:get_name()
  local found = false

  -- Iterate over all active streams and remove this split if present
  for videoId, splits in pairs(ACTIVE_STREAMS) do
    for i = #splits, 1, -1 do
      if splits[i] == split then
        Remove_Split_From_Active_Streams(videoId, split)
        found = true
      end
    end
  end

  if found then
    channel:add_system_message("[yt-chat] YouTube chat removed from this split.")
  else
    channel:add_system_message("[yt-chat] No YouTube chat was active in this split.")
  end
end)

c2.later(Read_Stream_Data, 1000)
