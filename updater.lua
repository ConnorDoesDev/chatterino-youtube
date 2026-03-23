--[[
  updater.lua

  Checks for a newer version of this plugin on startup by fetching a remote
  info.json, compares it against the local version using semver, downloads
  any changed source files if an update is available, then notifies the user
  to reload the plugin.

  Required info.json permissions:
    "FilesystemRead"
    "FilesystemWrite"
    "Network"

  Required info.json fields:
    "version"    : current semver string, e.g. "1.2.3"
    "update_url" : raw base URL of your repo's source files, no trailing slash
                   e.g. "https://raw.githubusercontent.com/you/repo/main"

  The remote manifest is expected at:  <update_url>/info.json
  Each source file is fetched from:    <update_url>/<filename>
]]

local json = require "libs/json"

-- Files that will be downloaded if the remote version is newer.
-- Paths are relative to the plugin root and must match the remote layout.
local MANAGED_FILES = {
  "info.json",
  "init.lua",
  "state.lua",
  "readStream.lua",
  "parseChat.lua",
  "buildMessage.lua",
  "addStream.lua",
  "streamsFile.lua",
  "utils.lua",
  "systemMessages.lua",
  "constants.lua",
  "mm2plHelper.lua",
}

-- Seconds after startup before the first update check fires.
-- Gives the rest of the plugin time to initialise.
local CHECK_DELAY_MS = 5000

-- Seconds between periodic re-checks (6 hours).
local RECHECK_INTERVAL_MS = 6 * 60 * 60 * 1000

-- ---------------------------------------------------------------------------
-- Semver comparison
-- Returns -1 / 0 / 1 (a < b / a == b / a > b).
-- Handles only the MAJOR.MINOR.PATCH numeric portion; pre-release tags are
-- ignored for simplicity, which is fine for a simple update notifier.
-- ---------------------------------------------------------------------------
local function parse_semver(v)
  local major, minor, patch = v:match("^(%d+)%.(%d+)%.(%d+)")
  if not major then
    return nil
  end
  return { tonumber(major), tonumber(minor), tonumber(patch) }
end

local function semver_cmp(a_str, b_str)
  local a = parse_semver(a_str)
  local b = parse_semver(b_str)

  if not a or not b then
    return 0
  end

  for i = 1, 3 do
    if a[i] < b[i] then return -1 end
    if a[i] > b[i] then return  1 end
  end
  return 0
end

-- ---------------------------------------------------------------------------
-- Read the local info.json so we know our own version and update_url.
-- ---------------------------------------------------------------------------
local function read_local_info()
  local f, err = io.open("info.json", "r")
  if not f then
    print("[updater] Could not open info.json: " .. tostring(err))
    return nil
  end

  local raw = f:read("a")
  f:close()

  local ok, info = pcall(json.decode, raw)
  if not ok or type(info) ~= "table" then
    print("[updater] Could not parse info.json")
    return nil
  end

  if not info.version then
    print("[updater] info.json is missing 'version' field")
    return nil
  end

  if not info.update_url then
    print("[updater] info.json is missing 'update_url' field — auto-update disabled")
    return nil
  end

  return info
end

-- ---------------------------------------------------------------------------
-- Write a file atomically: write to a temp file then rename.
-- Chatterino's Lua io wrapper does not expose os.rename, so we overwrite
-- directly — still safe because the write happens before we swap in the
-- new module references.
-- ---------------------------------------------------------------------------
local function write_file(path, data)
  local f, err = io.open(path, "w")
  if not f then
    return false, "open failed: " .. tostring(err)
  end

  local ok, werr = f:write(data)
  if not ok then
    f:close()
    return false, "write failed: " .. tostring(werr)
  end

  f:flush()
  f:close()
  return true, nil
end

-- ---------------------------------------------------------------------------
-- Download a single file and overwrite it on disk.
-- Calls `on_done(success, err_or_nil)` when finished.
-- ---------------------------------------------------------------------------
local function download_file(base_url, relative_path, on_done)
  local url = base_url .. "/" .. relative_path
  local req = c2.HTTPRequest.create(c2.HTTPMethod.Get, url)

  req:on_success(function(result)
    local status = result:status()
    if status ~= 200 then
      on_done(false, "HTTP " .. tostring(status) .. " for " .. relative_path)
      return
    end

    local ok, err = write_file(relative_path, result:data())
    if not ok then
      on_done(false, "write error for " .. relative_path .. ": " .. tostring(err))
      return
    end

    on_done(true, nil)
  end)

  req:on_error(function(result)
    on_done(false, "network error for " .. relative_path .. ": " .. result:error())
  end)

  req:execute()
end

-- ---------------------------------------------------------------------------
-- Download all managed files sequentially, then notify the user.
-- Sequential (rather than parallel) to avoid hammering the server and to
-- give a clear progress trail in the Chatterino log.
-- ---------------------------------------------------------------------------
local function download_all_files(base_url, remote_version, files, index, errors)
  index  = index  or 1
  errors = errors or {}

  if index > #files then
    -- All files attempted. Report outcome.
    if #errors == 0 then
      print("[updater] All files updated to " .. remote_version .. " successfully.")
      -- Notify every open channel so the user sees it regardless of which
      -- split they are looking at.
      local notice = "[youtube] Plugin updated to v" .. remote_version ..
                     ". Please reload the plugin (Settings → Plugins → toggle off/on) " ..
                     "or restart Chatterino to apply the update."
      -- We don't have a global "all channels" API, so log prominently.
      c2.log(c2.LogLevel.Warning, notice)
      -- Also post into any active stream splits so it's visible in chat.
      for videoId, splits in pairs(ACTIVE_STREAMS or {}) do
        for _, split in ipairs(splits) do
          local ch = c2.Channel.by_name(split)
          if ch then
            ch:add_system_message(notice)
          end
        end
      end
    else
      print("[updater] Update to " .. remote_version .. " completed with " ..
            #errors .. " error(s):")
      for _, e in ipairs(errors) do
        print("[updater]   " .. e)
      end
    end
    return
  end

  local file = files[index]
  print("[updater] Downloading " .. file .. " (" .. index .. "/" .. #files .. ")")

  download_file(base_url, file, function(ok, err)
    if not ok then
      table.insert(errors, err)
      print("[updater] Warning: " .. err)
    end
    -- Schedule the next download via c2.later to avoid deep recursion on
    -- large file lists. 0ms still yields back to the event loop.
    c2.later(function()
      download_all_files(base_url, remote_version, files, index + 1, errors)
    end, 0)
  end)
end

-- ---------------------------------------------------------------------------
-- Fetch the remote info.json and kick off a download if newer.
-- ---------------------------------------------------------------------------
local function check_for_update(local_info)
  local remote_url = local_info.update_url .. "/info.json"
  local req = c2.HTTPRequest.create(c2.HTTPMethod.Get, remote_url)

  req:on_success(function(result)
    local status = result:status()
    if status ~= 200 then
      print("[updater] Remote info.json returned HTTP " .. tostring(status))
      return
    end

    local ok, remote_info = pcall(json.decode, result:data())
    if not ok or type(remote_info) ~= "table" or not remote_info.version then
      print("[updater] Could not parse remote info.json")
      return
    end

    local cmp = semver_cmp(local_info.version, remote_info.version)

    if cmp < 0 then
      -- Remote is newer.
      print("[updater] Update available: " .. local_info.version ..
            " → " .. remote_info.version .. ". Downloading...")

      download_all_files(
        local_info.update_url,
        remote_info.version,
        MANAGED_FILES,
        1,
        {}
      )
    elseif cmp == 0 then
      print("[updater] Plugin is up to date (" .. local_info.version .. ")")
    else
      print("[updater] Local version (" .. local_info.version ..
            ") is ahead of remote (" .. remote_info.version .. ") — skipping")
    end
  end)

  req:on_error(function(result)
    print("[updater] Could not reach update server: " .. result:error())
  end)

  req:execute()
end

-- ---------------------------------------------------------------------------
-- Recurring check loop.
-- ---------------------------------------------------------------------------
local function schedule_checks(local_info)
  check_for_update(local_info)
  c2.later(function()
    schedule_checks(local_info)
  end, RECHECK_INTERVAL_MS)
end

-- ---------------------------------------------------------------------------
-- Public entry point — call once from init.lua.
-- ---------------------------------------------------------------------------
function Start_Auto_Updater()
  c2.later(function()
    local local_info = read_local_info()
    if local_info then
      schedule_checks(local_info)
    end
  end, CHECK_DELAY_MS)
end