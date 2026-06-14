-- OBS Filters Hotkey (Lua script — no build required)
-- Add via Tools → Scripts, then add the filter to any source.

local obs = obslua
local bit = require("bit")

local HOTKEY_NAME = "OpenFiltersHotkey"

local function hotkey_callback(pressed, filter)
  if not pressed then return end
  local parent = obs.obs_filter_get_parent(filter.context)
  if parent then
    obs.obs_frontend_open_source_filters(parent)
  end
end

local function register_hotkey(filter, parent)
  if filter.hotkey_id and filter.hotkey_id ~= obs.OBS_INVALID_HOTKEY_ID then
    return
  end

  local parent_name = obs.obs_source_get_name(parent) or "?"
  local description = "Open Filters (" .. parent_name .. ")"

  filter.hotkey_id = obs.obs_hotkey_register_source(
    filter.context,
    HOTKEY_NAME,
    description,
    function(pressed)
      hotkey_callback(pressed, filter)
    end
  )
end

local function make_filter_info(id, output_flags)
  local info = {}
  info.id = id
  info.type = obs.OBS_SOURCE_TYPE_FILTER
  info.output_flags = output_flags

  info.get_name = function()
    return "Open Filters Hotkey"
  end

  info.create = function(settings, source)
    local filter = {}
    filter.context = source
    filter.hotkey_id = obs.OBS_INVALID_HOTKEY_ID
    filter.loaded_settings = settings
    return filter
  end

  info.destroy = function(filter)
  end

  info.get_properties = function(unused)
    local props = obs.obs_properties_create()
    obs.obs_properties_add_text(
      props,
      "info",
      "Assign a hotkey in Settings → Hotkeys. Search for \"Open Filters\" and bind a key (e.g. Q).",
      obs.OBS_TEXT_INFO
    )
    return props
  end

  info.filter_add = function(filter, parent)
    register_hotkey(filter, parent)
  end

  if bit.band(output_flags, obs.OBS_SOURCE_AUDIO) ~= 0 then
    info.filter_audio = function(filter, audio)
      return audio
    end
  end

  if bit.band(output_flags, obs.OBS_SOURCE_VIDEO) ~= 0 then
    info.video_render = function(filter, effect)
      obs.obs_source_skip_video_filter(filter.context)
    end
  end

  return info
end

obs.obs_register_source(make_filter_info("open_filters_hotkey_audio_lua", obs.OBS_SOURCE_AUDIO))
obs.obs_register_source(make_filter_info("open_filters_hotkey_video_lua", obs.OBS_SOURCE_VIDEO))
