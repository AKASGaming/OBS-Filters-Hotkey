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

#include <QApplication>
#include <QDialog>
#include <QLabel>
#include <QListWidget>
#include <QTimer>

#include "open-filters-hotkey.h"

#define HOTKEY_PREFIX "open_filters;"
#define VST_FILTER_ID "vst_filter"
#define VST_OPEN_BUTTON "open_vst_settings"

#define SETTING_TARGET "target"

#define TARGET_FILTERS_WINDOW "filters_window"
#define TARGET_VST_INTERFACE_LEGACY "vst_interface"

struct open_filters_data {
	obs_source_t *context;
	obs_source_t *target;
	obs_hotkey_id hotkey_id;
	char *hotkey_name;
	char *target_mode;
	char *legacy_filter_name;
	bool hotkey_registered;
};

struct find_filter_data {
	const char *uuid;
	const char *legacy_name;
	bool find_first_vst;
	obs_source_t *found;
};

static const char *open_filters_get_name(void *unused)
{
	UNUSED_PARAMETER(unused);
	return obs_module_text("OpenFiltersHotkey");
}

static bool is_self_filter(obs_source_t *source)
{
	const char *id = obs_source_get_id(source);
	return strcmp(id, "open_filters_hotkey_audio") == 0 || strcmp(id, "open_filters_hotkey_video") == 0 ||
	       strcmp(id, "open_filters_hotkey_audio_lua") == 0 || strcmp(id, "open_filters_hotkey_video_lua") == 0;
}

static bool open_vst_interface(obs_source_t *filter_source)
{
	obs_properties_t *props = obs_source_properties(filter_source);
	if (!props)
		return false;

	bool opened = false;
	obs_property_t *button = obs_properties_get(props, VST_OPEN_BUTTON);
	if (button)
		opened = obs_property_button_clicked(button, filter_source);

	obs_properties_destroy(props);
	return opened;
}

static void enum_find_filter(obs_source_t *parent, obs_source_t *source, void *param)
{
	struct find_filter_data *data = static_cast<struct find_filter_data *>(param);

	UNUSED_PARAMETER(parent);

	if (data->found)
		return;

	if (data->find_first_vst) {
		if (strcmp(obs_source_get_id(source), VST_FILTER_ID) != 0)
			return;
		if (data->legacy_name && *data->legacy_name &&
		    strcmp(obs_source_get_name(source), data->legacy_name) != 0)
			return;
		data->found = source;
		return;
	}

	if (data->uuid && strcmp(obs_source_get_uuid(source), data->uuid) == 0)
		data->found = source;
}

static obs_source_t *find_filter_by_uuid(obs_source_t *parent, const char *uuid)
{
	struct find_filter_data data;
	data.uuid = uuid;
	data.legacy_name = NULL;
	data.find_first_vst = false;
	data.found = NULL;
	obs_source_enum_filters(parent, enum_find_filter, &data);
	return data.found;
}

static obs_source_t *find_legacy_vst(obs_source_t *parent, const char *filter_name)
{
	struct find_filter_data data;
	data.uuid = NULL;
	data.legacy_name = filter_name;
	data.find_first_vst = true;
	data.found = NULL;
	obs_source_enum_filters(parent, enum_find_filter, &data);
	return data.found;
}

static bool list_item_matches_name(QListWidgetItem *item, QListWidget *list, const QString &filter_name)
{
	if (!item)
		return false;

	if (item->text() == filter_name)
		return true;

	QWidget *widget = list->itemWidget(item);
	if (!widget)
		return false;

	const auto labels = widget->findChildren<QLabel *>();
	for (QLabel *label : labels) {
		if (label->text() == filter_name)
			return true;
	}

	return false;
}

static bool select_filter_in_dialog(QWidget *dialog, const QString &filter_name)
{
	const auto lists = dialog->findChildren<QListWidget *>();
	for (QListWidget *list : lists) {
		for (int i = 0; i < list->count(); i++) {
			QListWidgetItem *item = list->item(i);
			if (!list_item_matches_name(item, list, filter_name))
				continue;

			list->setCurrentItem(item);
			list->scrollToItem(item);
			list->setFocus(Qt::OtherFocusReason);
			return true;
		}
	}

	return false;
}

static void select_filter_in_open_filters_window(const char *source_name, const char *filter_name)
{
	if (!source_name || !filter_name || !*filter_name)
		return;

	const QString expected_title = QStringLiteral("Filters for '%1'").arg(QString::fromUtf8(source_name));
	const QString wanted = QString::fromUtf8(filter_name);

	auto try_select = [expected_title, wanted]() {
		const auto widgets = QApplication::topLevelWidgets();
		for (QWidget *widget : widgets) {
			if (widget->windowTitle() == expected_title && select_filter_in_dialog(widget, wanted))
				return;

			const auto dialogs = widget->findChildren<QDialog *>();
			for (QDialog *dialog : dialogs) {
				if (dialog->windowTitle() == expected_title && select_filter_in_dialog(dialog, wanted))
					return;
			}
		}
	};

	/* Always queue onto the UI thread — hotkeys may not run there. */
	QTimer::singleShot(0, qApp, try_select);
	QTimer::singleShot(50, qApp, try_select);
	QTimer::singleShot(150, qApp, try_select);
}

static void open_filters_to_filter(obs_source_t *parent, obs_source_t *filter_source)
{
	const char *source_name = obs_source_get_name(parent);
	const char *filter_name = obs_source_get_name(filter_source);

	obs_frontend_open_source_filters(parent);
	select_filter_in_open_filters_window(source_name, filter_name);
}

static void open_target(struct open_filters_data *filter)
{
	if (!filter->target)
		return;

	const char *target = filter->target_mode && *filter->target_mode ? filter->target_mode : TARGET_FILTERS_WINDOW;

	if (strcmp(target, TARGET_FILTERS_WINDOW) == 0) {
		obs_frontend_open_source_filters(filter->target);
		return;
	}

	/* Legacy setting: open the VST plug-in GUI directly. */
	if (strcmp(target, TARGET_VST_INTERFACE_LEGACY) == 0) {
		obs_source_t *vst = find_legacy_vst(filter->target, filter->legacy_filter_name);
		if (vst && open_vst_interface(vst))
			return;
		obs_frontend_open_source_filters(filter->target);
		return;
	}

	obs_source_t *filter_source = find_filter_by_uuid(filter->target, target);
	if (!filter_source) {
		obs_frontend_open_source_filters(filter->target);
		return;
	}

	open_filters_to_filter(filter->target, filter_source);
}

static void open_filters_hotkey_pressed(void *data, obs_hotkey_id id, obs_hotkey_t *hotkey, bool pressed)
{
	UNUSED_PARAMETER(id);
	UNUSED_PARAMETER(hotkey);

	if (!pressed)
		return;

	open_target(static_cast<struct open_filters_data *>(data));
}

static void update_target_settings(struct open_filters_data *filter, obs_data_t *settings)
{
	const char *target = obs_data_get_string(settings, SETTING_TARGET);
	const char *legacy_name = obs_data_get_string(settings, "filter_name");

	bfree(filter->target_mode);
	bfree(filter->legacy_filter_name);

	filter->target_mode = bstrdup(target && *target ? target : TARGET_FILTERS_WINDOW);
	filter->legacy_filter_name = bstrdup(legacy_name ? legacy_name : "");
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

	filter->hotkey_id =
		obs_hotkey_register_frontend(hotkey_name.array, description.array, open_filters_hotkey_pressed, filter);

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
	struct open_filters_data *filter =
		static_cast<struct open_filters_data *>(bzalloc(sizeof(struct open_filters_data)));
	filter->context = source;
	filter->hotkey_id = OBS_INVALID_HOTKEY_ID;
	filter->hotkey_registered = false;
	register_open_filters_hotkey(filter, settings);
	return filter;
}

static void open_filters_update(void *data, obs_data_t *settings)
{
	struct open_filters_data *filter = static_cast<struct open_filters_data *>(data);
	update_target_settings(filter, settings);
}

static void open_filters_destroy(void *data)
{
	struct open_filters_data *filter = static_cast<struct open_filters_data *>(data);
	bfree(filter->hotkey_name);
	bfree(filter->target_mode);
	bfree(filter->legacy_filter_name);
	bfree(filter);
}

static void open_filters_save(void *data, obs_data_t *settings)
{
	struct open_filters_data *filter = static_cast<struct open_filters_data *>(data);

	if (!filter->hotkey_registered || filter->hotkey_id == OBS_INVALID_HOTKEY_ID || !filter->hotkey_name)
		return;

	obs_data_array_t *saved = obs_hotkey_save(filter->hotkey_id);
	obs_data_set_array(settings, filter->hotkey_name, saved);
	obs_data_array_release(saved);
}

static void open_filters_video_tick(void *data, float seconds)
{
	UNUSED_PARAMETER(seconds);

	struct open_filters_data *filter = static_cast<struct open_filters_data *>(data);
	if (!filter->hotkey_registered)
		register_open_filters_hotkey(filter, obs_source_get_settings(filter->context));
}

static void enum_add_filter_option(obs_source_t *parent, obs_source_t *source, void *param)
{
	obs_property_t *list = static_cast<obs_property_t *>(param);

	UNUSED_PARAMETER(parent);

	if (is_self_filter(source))
		return;

	const char *name = obs_source_get_name(source);
	const char *uuid = obs_source_get_uuid(source);
	if (!name || !uuid)
		return;

	obs_property_list_add_string(list, name, uuid);
}

static obs_properties_t *open_filters_properties(void *data)
{
	struct open_filters_data *filter = static_cast<struct open_filters_data *>(data);
	obs_properties_t *props = obs_properties_create();

	obs_property_t *target = obs_properties_add_list(props, SETTING_TARGET, obs_module_text("OpenFiltersTarget"),
							 OBS_COMBO_TYPE_LIST, OBS_COMBO_FORMAT_STRING);
	obs_property_list_add_string(target, obs_module_text("OpenFiltersTargetWindow"), TARGET_FILTERS_WINDOW);

	if (filter && filter->context) {
		obs_source_t *parent = obs_filter_get_parent(filter->context);
		if (parent)
			obs_source_enum_filters(parent, enum_add_filter_option, target);
	}

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

	struct open_filters_data *filter = static_cast<struct open_filters_data *>(data);
	if (!filter->hotkey_registered)
		register_open_filters_hotkey(filter, obs_source_get_settings(filter->context));
	obs_source_skip_video_filter(filter->context);
}

static struct obs_source_info make_audio_info()
{
	struct obs_source_info info = {};
	info.id = "open_filters_hotkey_audio";
	info.type = OBS_SOURCE_TYPE_FILTER;
	info.output_flags = OBS_SOURCE_AUDIO;
	info.get_name = open_filters_get_name;
	info.create = open_filters_create;
	info.update = open_filters_update;
	info.destroy = open_filters_destroy;
	info.save = open_filters_save;
	info.video_tick = open_filters_video_tick;
	info.filter_audio = open_filters_filter_audio;
	info.get_properties = open_filters_properties;
	return info;
}

static struct obs_source_info make_video_info()
{
	struct obs_source_info info = {};
	info.id = "open_filters_hotkey_video";
	info.type = OBS_SOURCE_TYPE_FILTER;
	info.output_flags = OBS_SOURCE_VIDEO;
	info.get_name = open_filters_get_name;
	info.create = open_filters_create;
	info.update = open_filters_update;
	info.destroy = open_filters_destroy;
	info.save = open_filters_save;
	info.video_render = open_filters_video_render;
	info.get_properties = open_filters_properties;
	return info;
}

extern "C" {
struct obs_source_info open_filters_hotkey_audio = make_audio_info();
struct obs_source_info open_filters_hotkey_video = make_video_info();
}
