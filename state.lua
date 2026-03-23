require "utils"
require "streamsFile"

IO_LOCK = false

ACTIVE_STREAMS = {}

---@param videoId string
---@param splits table
function Add_To_Active_Streams(videoId, splits)
  -- BUG 5 FIX: Merge into the existing table rather than replacing it.
  -- Replacing the table reference orphans any code that captured the old
  -- reference, and causes ACTIVE_STREAMS to desync when a second split is
  -- added to an already-polling stream.
  if ACTIVE_STREAMS[videoId] then
    for _, split in ipairs(splits) do
      if not LumeFind(ACTIVE_STREAMS[videoId], split) then
        table.insert(ACTIVE_STREAMS[videoId], split)
      end
    end
  else
    ACTIVE_STREAMS[videoId] = splits
  end
end

---@param videoId string
---@return boolean
function Is_Active_Stream_VideoId_Active(videoId)
  -- BUG 1 FIX: ACTIVE_STREAMS is keyed by videoId, so a key-presence check
  -- is correct. The previous Table_Has_Value call iterated the *values*
  -- (arrays of split names) and compared them to a string, which always
  -- returned false — causing Initialize_Live_Polling to fire every second
  -- and spawn duplicate polling chains that all rendered the same messages.
  return ACTIVE_STREAMS[videoId] ~= nil
end

---@param videoId string
---@return table|nil
function Get_Active_Stream_Splits(videoId)
  return ACTIVE_STREAMS[videoId]
end

---@param videoId string
function Remove_From_Active_Streams(videoId)
  ACTIVE_STREAMS[videoId] = nil
end

---@param videoId string
---@param split string
function Remove_Split_From_Active_Streams(videoId, split)
  if not Is_Active_Stream_VideoId_Active(videoId) then
    return
  end

  local index = LumeFind(ACTIVE_STREAMS[videoId], split)
  if type(index) == "number" then
    table.remove(ACTIVE_STREAMS[videoId], index)
  end

  if #ACTIVE_STREAMS[videoId] == 0 then
    Remove_From_Active_Streams(videoId)
  end
end

STREAMS_DATA = StreamFile_Read()

---@param channel string
---@param split string
function Stream_Create_Channel(channel, split)
  STREAMS_DATA[STREAMS_CHANNELS_PROPERTY_NAME][channel] = {
    [STREAMS_SPLITS_PROPERTY_NAME] = { split }
  }

  return { split }
end

function Stream_Read_Channels()
  return STREAMS_DATA[STREAMS_CHANNELS_PROPERTY_NAME]
end

---@param channel string
function Stream_Read_Channel(channel)
  local channels = Stream_Read_Channels()

  return OptionalChain(channels, channel)
end

---@param channel string
---@param split string
function Stream_Add_Split_To_Channel(channel, split)
  local splits = OptionalChain(STREAMS_DATA, STREAMS_CHANNELS_PROPERTY_NAME, channel, STREAMS_SPLITS_PROPERTY_NAME)

  if splits ~= nil then
    table.insert(STREAMS_DATA[STREAMS_CHANNELS_PROPERTY_NAME][channel][STREAMS_SPLITS_PROPERTY_NAME], split)
  else
    STREAMS_DATA[STREAMS_CHANNELS_PROPERTY_NAME][channel][STREAMS_SPLITS_PROPERTY_NAME] = { split }
  end

  return STREAMS_DATA[STREAMS_CHANNELS_PROPERTY_NAME][channel][STREAMS_SPLITS_PROPERTY_NAME]
end

---@param channelData string
---@param split string
function StreamData_Has_Split(channelData, split)
  local index = LumeFind(channelData[STREAMS_SPLITS_PROPERTY_NAME], split)
  return type(index) == "number"
end