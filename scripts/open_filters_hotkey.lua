-- OBS Filters Hotkey (Lua script — no build required)
-- Add via Tools → Scripts, then add the filter to any source.
--
-- Add one "Open Filters Hotkey" filter per hotkey you want.
-- Each instance gets its own hotkey under Settings → Hotkeys.
--
-- Open target:
--   • Filters window — opens the source Filters dialog
--   • A VST filter — opens the VST plug-in GUI directly
--   • Any other filter — opens the Filters dialog focused on that filter

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
  return SELF_IDS[obs.obs_source_get_id(source)] == true
end

local function is_vst_filter(source)
  return obs.obs_source_get_id(source) == VST_FILTER_ID
end

local function source_ref(source)
  if source == nil then
    return nil
  end
  if obs.obs_source_get_ref ~= nil then
    return obs.obs_source_get_ref(source)
  end
  return source
end

local function source_release(source)
  if source == nil or obs.obs_source_release == nil then
    return
  end
  -- Only release when get_ref exists (we took an extra reference).
  if obs.obs_source_get_ref ~= nil then
    obs.obs_source_release(source)
  end
end

local function open_vst_interface(filter_source)
  local props = obs.obs_source_properties(filter_source)
  if not props then
    return false
  end

  local btn = obs.obs_properties_get(props, VST_OPEN_BUTTON)
  local opened = false
  if btn then
    opened = obs.obs_property_button_clicked(btn, filter_source) == true
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
  source_release(pending.filter)
  source_release(pending.parent)
  pending_restores[key] = nil
end

local function open_filters_window(parent)
  obs.obs_frontend_open_source_filters(parent)
end

-- Focus a non-VST filter page inside the Filters dialog.
-- OBS queues dialog creation and selects the first filter on open, so we
-- briefly move the target to index 0, open, then restore order after a delay.
local function open_filters_to_filter(parent, filter_source)
  local has_index_api = obs.obs_source_filter_get_index ~= nil and obs.obs_source_filter_set_index ~= nil
  if not has_index_api then
    open_filters_window(parent)
    return
  end

  local ok, idx = pcall(obs.obs_source_filter_get_index, parent, filter_source)
  if not ok or idx == nil or idx < 0 then
    open_filters_window(parent)
    return
  end

  local key = tostring(obs.obs_source_get_uuid(parent)) .. ":" .. tostring(obs.obs_source_get_uuid(filter_source))
  cancel_pending_restore(key)

  if idx ~= 0 then
    pcall(obs.obs_source_filter_set_index, parent, filter_source, 0)
  end

  open_filters_window(parent)

  if idx == 0 then
    return
  end

  local parent_ref = source_ref(parent)
  local filter_ref = source_ref(filter_source)
  if not parent_ref or not filter_ref then
    source_release(parent_ref)
    source_release(filter_ref)
    pcall(obs.obs_source_filter_set_index, parent, filter_source, idx)
    return
  end

  local restore
  restore = function()
    local pending = pending_restores[key]
    if not pending then
      return
    end

    obs.timer_remove(restore)
    pcall(obs.obs_source_filter_set_index, pending.parent, pending.filter, pending.idx)
    source_release(pending.filter)
    source_release(pending.parent)
    pending_restores[key] = nil
  end

  pending_restores[key] = {
    parent = parent_ref,
    filter = filter_ref,
    idx = idx,
    timer = restore,
  }
  obs.timer_add(restore, 200)
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
    if not is_self_filter(f) then
      local uuid = obs.obs_source_get_uuid(f)
      local name = obs.obs_source_get_name(f)
      if uuid == target or name == target then
        found = source_ref(f)
        break
      end
    end
  end

  obs.source_list_release(filters)
  return found
end

local function target_label(parent, target)
  if target == nil or target == "" or target == TARGET_FILTERS_WINDOW then
    return "Filters window"
  end
  if target == "vst_interface" then
    return "VST plugin interface"
  end

  local filter_source = find_filter(parent, target)
  if filter_source then
    local name = obs.obs_source_get_name(filter_source)
    source_release(filter_source)
    if name and name ~= "" then
      return name
    end
  end
  return "Filters"
end

local function open_target(parent, settings)
  if parent == nil then
    return
  end

  local target = obs.obs_data_get_string(settings, "target")
  if target == nil or target == "" or target == TARGET_FILTERS_WINDOW then
    open_filters_window(parent)
    return
  end

  -- Legacy target value from older script versions.
  if target == "vst_interface" then
    local filters = obs.obs_source_enum_filters(parent)
    if filters then
      local legacy_name = obs.obs_data_get_string(settings, "filter_name")
      for _, f in ipairs(filters) do
        if is_vst_filter(f) then
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
    open_filters_window(parent)
    return
  end

  local filter_source = find_filter(parent, target)
  if filter_source == nil then
    open_filters_window(parent)
    return
  end

  if is_vst_filter(filter_source) then
    if not open_vst_interface(filter_source) then
      open_filters_window(parent)
    end
  else
    open_filters_to_filter(parent, filter_source)
  end

  source_release(filter_source)
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
      local label = name
      if is_vst_filter(f) then
        label = name .. " (VST GUI)"
      end
      obs.obs_property_list_add_string(list, label, uuid)
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
  local self_uuid = obs.obs_source_get_uuid(filter.context)
  if not source_name or not source_uuid or not self_uuid then
    return
  end

  filter.target = parent
  -- Unique per hotkey-filter instance so multiple bindings on one source work.
  filter.hotkey_name = HOTKEY_PREFIX .. source_uuid .. ";" .. self_uuid

  local target = obs.obs_data_get_string(settings, "target")
  local label = target_label(parent, target)
  local description = "Open Filters (" .. source_name .. ") — " .. label

  filter.hotkey_id = obs.obs_hotkey_register_frontend(
    filter.hotkey_name,
    description,
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
      "Each Open Filters Hotkey instance has its own hotkey. VST targets open the plugin GUI; other filters open the Filters dialog on that filter's page. Rebind keys in Settings → Hotkeys after adding instances.",
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
  return [[Add an "Open Filters Hotkey" filter per shortcut you want. Set Open target to Filters window, a VST (opens the plugin GUI), or another filter (opens the Filters dialog on that page). Bind each instance under Settings → Hotkeys.]]
end

function script_unload()
  for key, _ in pairs(pending_restores) do
    cancel_pending_restore(key)
  end
end

obs.obs_register_source(make_filter_info("open_filters_hotkey_audio_lua", obs.OBS_SOURCE_AUDIO))
obs.obs_register_source(make_filter_info("open_filters_hotkey_video_lua", obs.OBS_SOURCE_VIDEO))
