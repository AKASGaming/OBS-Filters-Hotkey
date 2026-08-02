# OBS Filters Hotkey

Open a source's filters window — or jump straight into a specific filter — with a keyboard shortcut. For example, press **Q** for your mic's filter list, or **W** to open Noise Suppression directly.

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
   - Add **one instance per hotkey** you want (e.g. one for Noise Suppression, one for VST).
2. In each instance, set **Open target**:
   - **Filters window** — opens the full filters dialog
   - **A VST filter (VST GUI)** — opens that VST plug-in interface directly
   - **Any other filter** — opens the Filters dialog focused on that filter's page
3. Assign each instance a hotkey in **Settings → Hotkeys** (search for "Open Filters").
4. Press the hotkey to jump straight there.

The dropdown lists every filter currently on the source (except this hotkey filter itself). Re-open the filter settings after adding/removing filters to refresh the list. After adding new hotkey instances, re-check **Settings → Hotkeys** — each instance gets its own binding.

The filter is a pass-through — it does not modify audio or video.

## Example

| Source  | Open Filters Hotkey instance | Open target       | Hotkey | Action                                        |
|---------|------------------------------|-------------------|--------|-----------------------------------------------|
| Mic/Aux | Instance A                   | Filters window    | Q      | Opens mic filters dialog                      |
| Mic/Aux | Instance B                   | Noise Suppression | W      | Opens mic filters on Noise Suppression        |
| Mic/Aux | Instance C                   | My EQ (VST GUI)   | E      | Opens that VST plug-in GUI                    |

## License

GPL v2 — same as OBS Studio.
