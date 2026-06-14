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

#define HOTKEY_ID "OpenFiltersHotkey"

struct open_filters_data {
	obs_source_t *context;
	obs_hotkey_id hotkey_id;
};

static const char *open_filters_get_name(void *unused)
{
	UNUSED_PARAMETER(unused);
	return obs_module_text("OpenFiltersHotkey");
}

static void open_filters_hotkey_pressed(void *data, obs_hotkey_id id, obs_hotkey_t *hotkey, bool pressed)
{
	UNUSED_PARAMETER(id);
	UNUSED_PARAMETER(hotkey);

	if (!pressed)
		return;

	struct open_filters_data *filter = data;
	obs_source_t *parent = obs_filter_get_parent(filter->context);
	if (!parent)
		return;

	obs_frontend_open_source_filters(parent);
}

static void register_open_filters_hotkey(struct open_filters_data *filter, obs_source_t *parent)
{
	if (!filter || filter->hotkey_id != OBS_INVALID_HOTKEY_ID)
		return;

	const char *parent_name = obs_source_get_name(parent);
	char description[256];
	snprintf(description, sizeof(description), "%s (%s)", obs_module_text("OpenFiltersHotkeyAction"),
		   parent_name ? parent_name : "?");

	filter->hotkey_id = obs_hotkey_register_source(filter->context, HOTKEY_ID, description,
						       open_filters_hotkey_pressed, filter);
}

static void *open_filters_create(obs_data_t *settings, obs_source_t *source)
{
	UNUSED_PARAMETER(settings);

	struct open_filters_data *filter = bzalloc(sizeof(*filter));
	filter->context = source;
	filter->hotkey_id = OBS_INVALID_HOTKEY_ID;
	return filter;
}

static void open_filters_destroy(void *data)
{
	struct open_filters_data *filter = data;
	bfree(filter);
}

static void open_filters_filter_add(void *data, obs_source_t *parent)
{
	register_open_filters_hotkey(data, parent);
}

static obs_properties_t *open_filters_properties(void *unused)
{
	UNUSED_PARAMETER(unused);

	obs_properties_t *props = obs_properties_create();
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
	obs_source_skip_video_filter(filter->context);
}

struct obs_source_info open_filters_hotkey_audio = {
	.id = "open_filters_hotkey_audio",
	.type = OBS_SOURCE_TYPE_FILTER,
	.output_flags = OBS_SOURCE_AUDIO,
	.get_name = open_filters_get_name,
	.create = open_filters_create,
	.destroy = open_filters_destroy,
	.filter_add = open_filters_filter_add,
	.filter_audio = open_filters_filter_audio,
	.get_properties = open_filters_properties,
};

struct obs_source_info open_filters_hotkey_video = {
	.id = "open_filters_hotkey_video",
	.type = OBS_SOURCE_TYPE_FILTER,
	.output_flags = OBS_SOURCE_VIDEO,
	.get_name = open_filters_get_name,
	.create = open_filters_create,
	.destroy = open_filters_destroy,
	.filter_add = open_filters_filter_add,
	.video_render = open_filters_video_render,
	.get_properties = open_filters_properties,
};
