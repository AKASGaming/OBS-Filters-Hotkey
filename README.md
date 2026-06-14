# OBS Filters Hotkey

Open a source's filter list with a keyboard shortcut. For example, press **Q** to jump straight to the delay and other effects on your microphone.

## Quick start (no build)

1. In OBS, go to **Tools → Scripts**.
2. Click **+** and add `scripts/open_filters_hotkey.lua`.
3. Right-click the source you want (e.g. your mic) → **Filters**.
4. Click **+** under Audio/Video Filters and add **Open Filters Hotkey**.
5. Open **File → Settings → Hotkeys** and search for **Open Filters**.
6. Bind a key (e.g. **Q**) to the entry for that source.
7. Press the hotkey anytime to open that source's filters window.

## Native plugin (recommended for production)

The compiled plugin provides the same behavior with better integration. Filter names appear as **Open Filters Hotkey** in the filter list.

### Download pre-built plugin

Every push to `master` triggers a GitHub Actions build. Download the latest native plugin from either:

- **[Nightly release](https://github.com/AKASGaming/OBS-Filters-Hotkey/releases/tag/nightly)** — Windows `.zip` (and Linux/macOS when those builds succeed)
- **Actions → latest workflow run → Artifacts** — platform-specific packages

Install on Windows:

1. Download `obs-filters-hotkey-*-windows-x64.zip` from the nightly release.
2. Extract and copy `obs-filters-hotkey.dll` to `%ProgramFiles%\obs-studio\obs-plugins\64bit\`
3. Copy the `obs-filters-hotkey` folder to `%ProgramFiles%\obs-studio\data\obs-plugins\obs-filters-hotkey\`
4. Restart OBS.

### Build from source (Windows)

Requires [CMake 3.28+](https://cmake.org/download/) and Visual Studio 2022.

```powershell
cmake --preset windows-x64
cmake --build build_x64 --config RelWithDebInfo
```

The built plugin is copied into the project's `build_x64/rundir/RelWithDebInfo/obs-plugins/` folder. Copy `obs-filters-hotkey.dll` and the `obs-filters-hotkey` data folder into your OBS install:

- `%ProgramFiles%\obs-studio\obs-plugins\64bit\`
- `%ProgramFiles%\obs-studio\data\obs-plugins\obs-filters-hotkey\`

### Build (macOS / Linux)

```bash
cmake --preset macos        # or ubuntu-x86_64
cmake --build build_macos --config RelWithDebInfo
```

See the [OBS plugin template wiki](https://github.com/obsproject/obs-plugintemplate/wiki) for full setup details.

## Usage

1. Add the **Open Filters Hotkey** filter to any audio or video source.
2. Assign a hotkey in **Settings → Hotkeys** (search for "Open Filters").
3. Press the hotkey to open that source's filter dialog.

The filter is a pass-through — it does not modify audio or video. You can add one instance per source; each gets its own hotkey binding.

### Open a VST plugin interface directly

OBS has no public API to open a specific filter's settings panel, but VST 2.x filters expose an **Open Plug-In Interface** button that can be triggered programmatically.

1. Add **Open Filters Hotkey** to your source (e.g. mic).
2. In the filter settings, set **Open target** to **VST plugin interface**.
3. If you have multiple VST filters on the same source, enter the filter's display name under **Filter name**.
4. Bind your hotkey in **Settings → Hotkeys**.

Pressing the hotkey opens the VST GUI directly — no need to navigate the filters window first. If no matching VST filter is found, it falls back to opening the filters window.

**Note:** The VST must already be loaded (a plugin selected in the VST filter dropdown). This works with OBS's built-in **VST 2.x Plug-in** filter only, not VST3 hosts like atkAudio.

## Example

| Source        | Hotkey | Action                          |
|---------------|--------|---------------------------------|
| Mic/Aux       | Q      | Opens mic filters (Delay, etc.) |
| Webcam        | F      | Opens webcam filters            |

## License

GPL v2 — same as OBS Studio.
