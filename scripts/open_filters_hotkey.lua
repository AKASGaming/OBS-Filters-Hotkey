-- OBS Filters Hotkey (Lua script — no build required)
-- Add via Tools → Scripts, then add the filter to any source.
--
-- Open target:
--   • Filters window — opens the source Filters dialog
--   • A specific filter — opens that dialog focused on the filter's page

local obs = obslua
local bit = require("bit")

local HOTKEY_PREFIX = "open_filters;"
local VST_FILTER_ID = "vst_filter"
local VST_OPEN_BUTTON = "open_vst_settings"
local TARGET_FILTERS_WINDOW = "filters_window"

local SELF_IDS = {
  open_filters_hotkey_audio_lua = true,
  open_filters_hotkey_video_lua = true,
  open_filters_hotkey_audio = true,
  open_filters_hotkey_video = true,
}

local pending_restores = {}

local function is_self_filter(source)
  local id = obs.obs_source_get_id(source)
  return SELF_IDS[id] == true
end

local function open_vst_interface(filter_source)
  local props = obs.obs_source_properties(filter_source)
  if not props then
    return false
  end

  local btn = obs.obs_properties_get(props, VST_OPEN_BUTTON)
  local opened = false
  if btn then
    opened = obs.obs_property_button_clicked(btn, filter_source)
  end
  obs.obs_properties_destroy(props)
  return opened
end

local function cancel_pending_restore(key)
  local pending = pending_restores[key]
  if not pending then
    return
  end

  if pending.timer then
    obs.timer_remove(pending.timer)
  end
  if pending.filter then
    obs.obs_source_release(pending.filter)
  end
  if pending.parent then
    obs.obs_source_release(pending.parent)
  end
  pending_restores[key] = nil
end

-- OBS queues the Filters dialog onto the UI thread, and always selects the
-- first async/effect filter on open. Move the target to index 0, open, then
-- restore order after a short delay so selection sticks to that filter.
local function open_filters_to_filter(parent, filter_source)
  local idx = obs.obs_source_filter_get_index(parent, filter_source)
  if idx == nil or idx < 0 then
    obs.obs_frontend_open_source_filters(parent)
    return
  end

  local key = tostring(parent) .. ":" .. tostring(filter_source)
  cancel_pending_restore(key)

  if idx ~= 0 then
    obs.obs_source_filter_set_index(parent, filter_source, 0)
  end

  obs.obs_frontend_open_source_filters(parent)

  if idx == 0 then
    return
  end

  local parent_ref = obs.obs_source_get_ref(parent)
  local filter_ref = obs.obs_source_get_ref(filter_source)
  if not parent_ref or not filter_ref then
    if parent_ref then
      obs.obs_source_release(parent_ref)
    end
    if filter_ref then
      obs.obs_source_release(filter_ref)
    end
    obs.obs_source_filter_set_index(parent, filter_source, idx)
    return
  end

  local restore
  restore = function()
    local pending = pending_restores[key]
    if not pending then
      return
    end

    obs.timer_remove(restore)
    obs.obs_source_filter_set_index(pending.parent, pending.filter, pending.idx)
    obs.obs_source_release(pending.filter)
    obs.obs_source_release(pending.parent)
    pending_restores[key] = nil
  end

  pending_restores[key] = {
    parent = parent_ref,
    filter = filter_ref,
    idx = idx,
    timer = restore,
  }

  -- Delay long enough for the queued Filters dialog to open and select item 0.
  obs.timer_add(restore, 150)
end

local function find_filter(parent, target)
  if parent == nil or target == nil or target == "" then
    return nil
  end

  local filters = obs.obs_source_enum_filters(parent)
  if filters == nil then
    return nil
  end

  local found = nil
  for _, f in ipairs(filters) do
    local uuid = obs.obs_source_get_uuid(f)
    local name = obs.obs_source_get_name(f)
    if uuid == target or name == target then
      found = obs.obs_source_get_ref(f)
      break
    end
  end

  obs.source_list_release(filters)
  return found
end

local function open_target(parent, settings)
  if parent == nil then
    return
  end

  local target = obs.obs_data_get_string(settings, "target")
  if target == nil or target == "" or target == TARGET_FILTERS_WINDOW then
    obs.obs_frontend_open_source_filters(parent)
    return
  end

  -- Legacy: old "vst_interface" setting opens the first VST filter GUI.
  if target == "vst_interface" then
    local filters = obs.obs_source_enum_filters(parent)
    if filters then
      local legacy_name = obs.obs_data_get_string(settings, "filter_name")
      for _, f in ipairs(filters) do
        if obs.obs_source_get_id(f) == VST_FILTER_ID then
          local name = obs.obs_source_get_name(f)
          if legacy_name == nil or legacy_name == "" or name == legacy_name then
            if open_vst_interface(f) then
              obs.source_list_release(filters)
              return
            end
          end
        end
      end
      obs.source_list_release(filters)
    end
    obs.obs_frontend_open_source_filters(parent)
    return
  end

  local filter_source = find_filter(parent, target)
  if filter_source == nil then
    obs.obs_frontend_open_source_filters(parent)
    return
  end

  open_filters_to_filter(parent, filter_source)
  obs.obs_source_release(filter_source)
end

local function populate_target_list(list, parent)
  obs.obs_property_list_clear(list)
  obs.obs_property_list_add_string(list, "Filters window", TARGET_FILTERS_WINDOW)

  if parent == nil then
    return
  end

  local filters = obs.obs_source_enum_filters(parent)
  if filters == nil then
    return
  end

  for _, f in ipairs(filters) do
    if not is_self_filter(f) then
      local name = obs.obs_source_get_name(f)
      local uuid = obs.obs_source_get_uuid(f)
      obs.obs_property_list_add_string(list, name, uuid)
    end
  end

  obs.source_list_release(filters)
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

  info.get_properties = function(filter)
    local props = obs.obs_properties_create()

    local target = obs.obs_properties_add_list(
      props,
      "target",
      "Open target",
      obs.OBS_COMBO_TYPE_LIST,
      obs.OBS_COMBO_FORMAT_STRING
    )

    local parent = nil
    if filter and filter.context then
      parent = obs.obs_filter_get_parent(filter.context)
    end
    populate_target_list(target, parent)

    obs.obs_properties_add_text(
      props,
      "info",
      "Pick the filters window, or a specific filter on this source. The hotkey opens that source's Filters dialog on the chosen filter's page. Assign a hotkey in Settings → Hotkeys.",
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
  return [[Add the "Open Filters Hotkey" filter to any source, then bind a key under Settings → Hotkeys. Use Open target to jump to the filters window or open directly to a specific filter's page (e.g. Noise Suppression).]]
end

function script_unload()
  for key, _ in pairs(pending_restores) do
    cancel_pending_restore(key)
  end
end

obs.obs_register_source(make_filter_info("open_filters_hotkey_audio_lua", obs.OBS_SOURCE_AUDIO))
obs.obs_register_source(make_filter_info("open_filters_hotkey_video_lua", obs.OBS_SOURCE_VIDEO))
