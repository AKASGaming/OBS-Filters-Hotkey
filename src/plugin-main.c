/*
OBS Filters Hotkey
Copyright (C) 2026 Ashton

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
*/

#include <obs-module.h>
#include <plugin-support.h>
#include "open-filters-hotkey.h"

OBS_DECLARE_MODULE()
OBS_MODULE_USE_DEFAULT_LOCALE("obs-filters-hotkey", "en-US")

bool obs_module_load(void)
{
	obs_register_source(&open_filters_hotkey_audio);
	obs_register_source(&open_filters_hotkey_video);
	obs_log(LOG_INFO, "OBS Filters Hotkey loaded (version %s)", PLUGIN_VERSION);
	return true;
}

void obs_module_unload(void)
{
	obs_log(LOG_INFO, "OBS Filters Hotkey unloaded");
}
