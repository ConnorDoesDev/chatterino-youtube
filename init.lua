require "utils"
require "systemMessages"
require "addStream"
require "readStream"
require "updater"
Start_Auto_Updater()

---@param ctx CommandContext
local cmd_youtube = function(ctx)
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

c2.register_command("/youtube", cmd_youtube)

c2.register_command("/youtube-stop", function(ctx)
  local channel = ctx.channel
  local split = channel:get_name()
  local found = false


  -- Remove split from ACTIVE_STREAMS and persistent STREAMS_DATA
  for videoId, splits in pairs(ACTIVE_STREAMS) do
    for i = #splits, 1, -1 do
      if splits[i] == split then
        Remove_Split_From_Active_Streams(videoId, split)
        found = true
      end
    end
  end

  -- Remove split from all channels in STREAMS_DATA
  local changed = false
  for channelId, channelData in pairs(STREAMS_DATA[STREAMS_CHANNELS_PROPERTY_NAME]) do
    local splitList = channelData[STREAMS_SPLITS_PROPERTY_NAME]
    if splitList then
      for i = #splitList, 1, -1 do
        if splitList[i] == split then
          table.remove(splitList, i)
          changed = true
        end
      end
      -- If no splits left, remove the channel entry
      if #splitList == 0 then
        STREAMS_DATA[STREAMS_CHANNELS_PROPERTY_NAME][channelId] = nil
        changed = true
      end
    end
  end
  if changed then
    StreamFile_Update(STREAMS_DATA)
  end

  if found or changed then
    channel:add_system_message("[youtube] YouTube chat removed from this split.")
  else
    channel:add_system_message("[youtube] No YouTube chat was active in this split.")
  end
end)

-- Hook for split deletion (call this when a split is closed)
function Remove_Youtube_Split_Persistently(split)
  local changed = false
  for channelId, channelData in pairs(STREAMS_DATA[STREAMS_CHANNELS_PROPERTY_NAME]) do
    local splitList = channelData[STREAMS_SPLITS_PROPERTY_NAME]
    if splitList then
      for i = #splitList, 1, -1 do
        if splitList[i] == split then
          table.remove(splitList, i)
          changed = true
        end
      end
      if #splitList == 0 then
        STREAMS_DATA[STREAMS_CHANNELS_PROPERTY_NAME][channelId] = nil
        changed = true
      end
    end
  end
  if changed then
    StreamFile_Update(STREAMS_DATA)
  end
end

c2.later(Read_Stream_Data, 1000)
