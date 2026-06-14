-- OBS Filters Hotkey (Lua script — no build required)
-- Add via Tools → Scripts, then add the filter to any source.

local obs = obslua
local bit = require("bit")

local HOTKEY_PREFIX = "open_filters;"
local VST_FILTER_ID = "vst_filter"
local VST_OPEN_BUTTON = "open_vst_settings"

local TARGET_FILTERS_WINDOW = "filters_window"
local TARGET_VST_INTERFACE = "vst_interface"

local function filter_name_matches(desired, actual)
  if desired == nil or desired == "" then
    return true
  end
  return actual == desired
end

local function open_vst_interface(parent, filter_name)
  local filters = obs.obs_source_enum_filters(parent)
  if filters == nil then
    return false
  end

  for _, f in ipairs(filters) do
    local id = obs.obs_source_get_id(f)
    local name = obs.obs_source_get_name(f)
    if id == VST_FILTER_ID and filter_name_matches(filter_name, name) then
      local props = obs.obs_source_properties(f)
      if props then
        local btn = obs.obs_properties_get(props, VST_OPEN_BUTTON)
        if btn and obs.obs_property_button_clicked(btn, f) then
          obs.obs_properties_destroy(props)
          obs.source_list_release(filters)
          return true
        end
        obs.obs_properties_destroy(props)
      end
    end
  end

  obs.source_list_release(filters)
  return false
end

local function open_target(parent, settings)
  if parent == nil then
    return
  end

  local target = obs.obs_data_get_string(settings, "target")
  if target == nil or target == "" then
    target = TARGET_FILTERS_WINDOW
  end

  if target == TARGET_VST_INTERFACE then
    local filter_name = obs.obs_data_get_string(settings, "filter_name")
    if open_vst_interface(parent, filter_name) then
      return
    end
  end

  obs.obs_frontend_open_source_filters(parent)
end

local function register_hotkey(filter, settings)
  if filter.created_hotkeys then
    return
  end

  local parent = obs.obs_filter_get_parent(filter.context)
  if not parent then
    return
  end

  local source_name = obs.obs_source_get_name(parent)
  local source_uuid = obs.obs_source_get_uuid(parent)
  if not source_name or not source_uuid then
    return
  end

  filter.target = parent
  filter.hotkey_name = HOTKEY_PREFIX .. source_uuid

  filter.hotkey_id = obs.obs_hotkey_register_frontend(
    filter.hotkey_name,
    "Open Filters (" .. source_name .. ")",
    function(pressed)
      if pressed and filter.target and filter.loaded_settings then
        open_target(filter.target, filter.loaded_settings)
      end
    end
  )

  local saved = obs.obs_data_get_array(settings, filter.hotkey_name)
  obs.obs_hotkey_load(filter.hotkey_id, saved)
  obs.obs_data_array_release(saved)

  filter.created_hotkeys = true
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
    filter.hotkey_name = nil
    filter.created_hotkeys = false
    filter.loaded_settings = settings
    filter.target = nil
    return filter
  end

  info.update = function(filter, settings)
    filter.loaded_settings = settings
  end

  info.destroy = function(filter)
  end

  info.get_properties = function(unused)
    local props = obs.obs_properties_create()

    local target = obs.obs_properties_add_list(
      props,
      "target",
      "Open target",
      obs.OBS_COMBO_TYPE_LIST,
      obs.OBS_COMBO_FORMAT_STRING
    )
    obs.obs_property_list_add_string(target, "Filters window", TARGET_FILTERS_WINDOW)
    obs.obs_property_list_add_string(target, "VST plugin interface", TARGET_VST_INTERFACE)

    obs.obs_properties_add_text(
      props,
      "filter_name",
      "Filter name (optional — use when multiple VST filters exist)",
      obs.OBS_TEXT_DEFAULT
    )

    obs.obs_properties_add_text(
      props,
      "info",
      "Assign a hotkey in Settings → Hotkeys. Search for \"Open Filters\" and bind a key (e.g. Q).",
      obs.OBS_TEXT_INFO
    )
    return props
  end

  info.save = function(filter, settings)
    if filter.created_hotkeys and filter.hotkey_id and filter.hotkey_name then
      local saved = obs.obs_hotkey_save(filter.hotkey_id)
      obs.obs_data_set_array(settings, filter.hotkey_name, saved)
      obs.obs_data_array_release(saved)
    end
  end

  info.video_tick = function(filter, seconds)
    register_hotkey(filter, filter.loaded_settings)
  end

  if bit.band(output_flags, obs.OBS_SOURCE_AUDIO) ~= 0 then
    info.filter_audio = function(filter, audio)
      return audio
    end
  end

  if bit.band(output_flags, obs.OBS_SOURCE_VIDEO) ~= 0 then
    info.video_render = function(filter, effect)
      register_hotkey(filter, filter.loaded_settings)
      obs.obs_source_skip_video_filter(filter.context)
    end
  end

  return info
end

function script_description()
  return [[Add the "Open Filters Hotkey" filter to any source, then bind a key under Settings → Hotkeys. Set the target to "VST plugin interface" to open a VST 2.x filter's GUI directly.]]
end

obs.obs_register_source(make_filter_info("open_filters_hotkey_audio_lua", obs.OBS_SOURCE_AUDIO))
obs.obs_register_source(make_filter_info("open_filters_hotkey_video_lua", obs.OBS_SOURCE_VIDEO))
