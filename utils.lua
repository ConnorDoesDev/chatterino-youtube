
-- Request Helpers
function Mutate_Request_Default_Headers(request)
  request:set_header("User-Agent", "facebookexternalhit/")
  request:set_header("Accept-Language", "en")
end


-- String Helpers
function Is_Valid_URL(url)
  if type(url) ~= "string" then
    return false
  end
  if url:find("^https://www%.youtube%.com/") == nil then
    return false
  end
  return true
end


-- File Helpers
function FileExists(filename)
  local isPresent = nil
  local f = io.open(filename, "r")
  if f then
    isPresent = true
    f:close()
  end
  return isPresent
end


-- Table Helpers
function Table_Has_Value(table, value)
  if rawget(table, value) then
    return true
  end
  return false
end


function Get_Keys(t)
  local keys = {}
  for key, _ in pairs(t) do
    table.insert(keys, key)
  end
  return keys
end


function Parse_HTML(result)
  local html = result:data()
  local videoId = html:match(LIVE_ID_REGEX) or html:match(VIDEO_ID_REGEX)
  if videoId == nil then return nil, "videoId" end
  local apiKey = html:match(API_KEY_REGEX)
  if apiKey == nil then return nil, "apiKey" end
  local continuation = html:match(CONTINUATION_REGEX)
  if continuation == nil then return nil, "continuation" end
  local clientVersion = html:match(CLIENT_VERSION_REGEX)
  if clientVersion == nil then return nil, "clientVersion" end
  local channelId = html:match(CHANNEL_ID_REGEX)
  if channelId == nil then return nil, "channelId" end
  local channelName = html:match(CHANNEL_NAME_REGEX)
  return {
    videoId = videoId,
    apiKey = apiKey,
    clientVersion = clientVersion,
    continuation = continuation,
    channelId = channelId,
    channelName = channelName or videoId
  }
end

-- Color Helpers
local colors = { "blue", "coral", "dodgerBlue", "springGreen", "yellowGreen", "green", "orangeRed", "red", "goldenRod",
  "hotPink", "cadetBlue", "seaGreen", "chocolate", "blueViolet", "firebrick" }
-- Weird attempt to port https://stackoverflow.com/questions/64513938/map-strings-to-a-color-selected-from-a-predefined-array-javascript?

function Get_Color(str)
  local total = 0
  for i = 1, #str do
    total = total + string.byte(str, i)
  end
  local index = (total % #colors) + 1
  return colors[index]
end


function Trim5(s)
  return s:match '^%s*(.*%S)' or ''
end


function Only_Available_Splits(splits)
  local t = {}
  for _, value in ipairs(splits) do
    local c = c2.Channel.by_name(value)
    if c then
      table.insert(t, value)
    end
  end
  return t
end


function LumeFind(t, value)
  for k, v in ipairs(t) do
    if v == value then return k end
  end
  return nil
end


function Ternary(condition, whenTrue, whenFalse)
  if condition then
    return whenTrue
  end
  return whenFalse
end

-- General Helpers
function OptionalChain(obj, ...)
  for _, value in ipairs({ ... }) do
    obj = obj[value]
    if not obj then return nil end
  end
  return obj
end
