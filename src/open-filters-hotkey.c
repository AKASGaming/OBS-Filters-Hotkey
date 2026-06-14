/*
OBS Filters Hotkey
Copyright (C) 2026 Ashton

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
*/

#include <obs-module.h>
#include <obs-frontend-api.h>
#include <util/platform.h>
#include <util/dstr.h>

#define HOTKEY_PREFIX "open_filters;"
#define VST_FILTER_ID "vst_filter"
#define VST_OPEN_BUTTON "open_vst_settings"

#define SETTING_TARGET "target"
#define SETTING_FILTER_NAME "filter_name"

#define TARGET_FILTERS_WINDOW "filters_window"
#define TARGET_VST_INTERFACE "vst_interface"

struct open_filters_data {
	obs_source_t *context;
	obs_source_t *target;
	obs_hotkey_id hotkey_id;
	char *hotkey_name;
	char *target_mode;
	char *filter_name;
	bool hotkey_registered;
};

struct vst_enum_data {
	const char *filter_name;
	bool opened;
};

static const char *open_filters_get_name(void *unused)
{
	UNUSED_PARAMETER(unused);
	return obs_module_text("OpenFiltersHotkey");
}

static bool filter_name_matches(const char *desired, const char *actual)
{
	if (!desired || !*desired)
		return true;
	return actual && strcmp(desired, actual) == 0;
}

static void enum_vst_filter(obs_source_t *parent, obs_source_t *source, void *param)
{
	struct vst_enum_data *data = param;

	UNUSED_PARAMETER(parent);

	if (data->opened)
		return;

	if (strcmp(obs_source_get_id(source), VST_FILTER_ID) != 0)
		return;

	if (!filter_name_matches(data->filter_name, obs_source_get_name(source)))
		return;

	obs_properties_t *props = obs_source_properties(source);
	if (!props)
		return;

	obs_property_t *button = obs_properties_get(props, VST_OPEN_BUTTON);
	if (button)
		data->opened = obs_property_button_clicked(button, source);

	obs_properties_destroy(props);
}

static bool open_vst_interface(obs_source_t *parent, const char *filter_name)
{
	struct vst_enum_data data = {.filter_name = filter_name, .opened = false};
	obs_source_enum_filters(parent, enum_vst_filter, &data);
	return data.opened;
}

static void open_target(struct open_filters_data *filter)
{
	if (!filter->target)
		return;

	const char *target = filter->target_mode && *filter->target_mode ? filter->target_mode
									  : TARGET_FILTERS_WINDOW;

	if (strcmp(target, TARGET_VST_INTERFACE) == 0) {
		if (open_vst_interface(filter->target, filter->filter_name))
			return;
	}

	obs_frontend_open_source_filters(filter->target);
}

static void open_filters_hotkey_pressed(void *data, obs_hotkey_id id, obs_hotkey_t *hotkey, bool pressed)
{
	UNUSED_PARAMETER(id);
	UNUSED_PARAMETER(hotkey);

	if (!pressed)
		return;

	open_target(data);
}

static void update_target_settings(struct open_filters_data *filter, obs_data_t *settings)
{
	const char *target = obs_data_get_string(settings, SETTING_TARGET);
	const char *filter_name = obs_data_get_string(settings, SETTING_FILTER_NAME);

	bfree(filter->target_mode);
	bfree(filter->filter_name);

	filter->target_mode = bstrdup(target && *target ? target : TARGET_FILTERS_WINDOW);
	filter->filter_name = bstrdup(filter_name ? filter_name : "");
}

static void register_open_filters_hotkey(struct open_filters_data *filter, obs_data_t *settings)
{
	if (!filter || filter->hotkey_registered)
		return;

	obs_source_t *parent = obs_filter_get_parent(filter->context);
	if (!parent)
		return;

	const char *parent_name = obs_source_get_name(parent);
	const char *parent_uuid = obs_source_get_uuid(parent);
	if (!parent_name || !parent_uuid)
		return;

	filter->target = parent;
	update_target_settings(filter, settings);

	struct dstr hotkey_name = {0};
	struct dstr description = {0};
	dstr_printf(&hotkey_name, "%s%s", HOTKEY_PREFIX, parent_uuid);
	dstr_printf(&description, "%s (%s)", obs_module_text("OpenFiltersHotkeyAction"), parent_name);

	filter->hotkey_id = obs_hotkey_register_frontend(hotkey_name.array, description.array,
							 open_filters_hotkey_pressed, filter);

	obs_data_array_t *saved = obs_data_get_array(settings, hotkey_name.array);
	obs_hotkey_load(filter->hotkey_id, saved);
	obs_data_array_release(saved);

	filter->hotkey_name = bstrdup(hotkey_name.array);
	filter->hotkey_registered = true;

	dstr_free(&hotkey_name);
	dstr_free(&description);
}

static void *open_filters_create(obs_data_t *settings, obs_source_t *source)
{
	struct open_filters_data *filter = bzalloc(sizeof(*filter));
	filter->context = source;
	filter->hotkey_id = OBS_INVALID_HOTKEY_ID;
	filter->hotkey_registered = false;
	register_open_filters_hotkey(filter, settings);
	return filter;
}

static void open_filters_update(void *data, obs_data_t *settings)
{
	struct open_filters_data *filter = data;
	update_target_settings(filter, settings);
}

static void open_filters_destroy(void *data)
{
	struct open_filters_data *filter = data;
	bfree(filter->hotkey_name);
	bfree(filter->target_mode);
	bfree(filter->filter_name);
	bfree(filter);
}

static void open_filters_save(void *data, obs_data_t *settings)
{
	struct open_filters_data *filter = data;
	if (!filter->hotkey_registered || filter->hotkey_id == OBS_INVALID_HOTKEY_ID || !filter->hotkey_name)
		return;

	obs_data_array_t *saved = obs_hotkey_save(filter->hotkey_id);
	obs_data_set_array(settings, filter->hotkey_name, saved);
	obs_data_array_release(saved);
}

static void open_filters_video_tick(void *data, float seconds)
{
	UNUSED_PARAMETER(seconds);

	struct open_filters_data *filter = data;
	if (!filter->hotkey_registered)
		register_open_filters_hotkey(filter, obs_source_get_settings(filter->context));
}

static obs_properties_t *open_filters_properties(void *unused)
{
	UNUSED_PARAMETER(unused);

	obs_properties_t *props = obs_properties_create();

	obs_property_t *target = obs_properties_add_list(props, SETTING_TARGET, obs_module_text("OpenFiltersTarget"),
							 OBS_COMBO_TYPE_LIST, OBS_COMBO_FORMAT_STRING);
	obs_property_list_add_string(target, obs_module_text("OpenFiltersTargetWindow"), TARGET_FILTERS_WINDOW);
	obs_property_list_add_string(target, obs_module_text("OpenFiltersTargetVst"), TARGET_VST_INTERFACE);

	obs_properties_add_text(props, SETTING_FILTER_NAME, obs_module_text("OpenFiltersFilterName"),
				  OBS_TEXT_DEFAULT);
	obs_properties_add_text(props, "info", obs_module_text("OpenFiltersHotkeyInfo"), OBS_TEXT_INFO);
	return props;
}

static struct obs_audio_data *open_filters_filter_audio(void *data, struct obs_audio_data *audio)
{
	UNUSED_PARAMETER(data);
	return audio;
}

static void open_filters_video_render(void *data, gs_effect_t *effect)
{
	UNUSED_PARAMETER(effect);

	struct open_filters_data *filter = data;
	if (!filter->hotkey_registered)
		register_open_filters_hotkey(filter, obs_source_get_settings(filter->context));
	obs_source_skip_video_filter(filter->context);
}

struct obs_source_info open_filters_hotkey_audio = {
	.id = "open_filters_hotkey_audio",
	.type = OBS_SOURCE_TYPE_FILTER,
	.output_flags = OBS_SOURCE_AUDIO,
	.get_name = open_filters_get_name,
	.create = open_filters_create,
	.update = open_filters_update,
	.destroy = open_filters_destroy,
	.save = open_filters_save,
	.video_tick = open_filters_video_tick,
	.filter_audio = open_filters_filter_audio,
	.get_properties = open_filters_properties,
};

struct obs_source_info open_filters_hotkey_video = {
	.id = "open_filters_hotkey_video",
	.type = OBS_SOURCE_TYPE_FILTER,
	.output_flags = OBS_SOURCE_VIDEO,
	.get_name = open_filters_get_name,
	.create = open_filters_create,
	.update = open_filters_update,
	.destroy = open_filters_destroy,
	.save = open_filters_save,
	.video_render = open_filters_video_render,
	.get_properties = open_filters_properties,
};
