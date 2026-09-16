# MenuBarCompact

A small, native menu-bar manager for macOS 27. Keep selected apps visible, tuck others away, and reveal them when needed.

MenuBarCompact is an experimental AppKit application with per-app visibility rules, launch-at-login support, and an automatic compatibility workaround for iStat Menus 7. It runs independently of Thaw.

## Features

- **Always show**, **Hide**, and **Always hide** rules for application bundles.
- Click the menu-bar button to reveal or hide apps; Option-click to show everything.
- Optional automatic re-hiding after 15 seconds.
- Searchable settings, with an option to show all running apps.
- Launch at login through Apple's `SMAppService`.
- Automatic iStat compatibility checks at startup and once a minute.
- Import existing Thaw visibility groups on first use, when available.
- Release hiding restrictions on quit, error, or activation timeout; pause while Thaw runs.

The first prototype was called MenuShelter. Existing prototype visibility rules and re-hide preferences migrate automatically.

## Requirements

- macOS 27; tested on 27.0 build 26A428.
- Xcode with a macOS 27 SDK to build.
- Developer-tools Python at `/usr/bin/python3` for the bundled iStat compatibility utility.
- Write access to `/Applications` when applying the iStat workaround.

This version uses an **undocumented macOS menu-bar API**. Future OS updates may change its behavior or remove it. It is a local, ad-hoc-signed build, not a notarized distribution.

## Build and run

Open `MenuBarCompact.xcodeproj` in Xcode and run the **MenuBarCompact** scheme, or:

```sh
./build.sh
```

The output is `build/MenuBarCompact.app`. Quit any running copy before replacing it, then copy the built app to `/Applications` and open it. Running from Applications helps the menu-bar host resolve the app's identity correctly.

Enable **Launch at login** in Settings to start automatically. When replacing another menu-bar manager, disable that app's login setting and quit it. Close Settings to leave MenuBarCompact running; quit MenuBarCompact to release its restrictions.

## Using visibility rules

| Rule | Normal state | Click to reveal | Show everything |
| --- | --- | --- | --- |
| Always show | Visible | Visible | Visible |
| Hide | Hidden | Visible | Visible |
| Always hide | Hidden | Hidden | Visible |

Right-click the menu-bar button for Settings and quick controls. Reopening the app also opens Settings.

Settings initially shows configured apps and iStat. Turn on **Show all running apps** to configure another app. Some apps use a separate menu-bar helper: Box's menu item, for example, belongs to **Box UI**. The expanded list can include processes without menu items; changing those has no visible effect.

macOS system items and iStat are protected from hiding in this version.

## iStat Menus compatibility

On the tested macOS 27 build, iStat Menus 7.30's Combined item disappeared under menu-bar restrictions even when its bundle ID was allowed. Launching its unchanged, signed helper from Applications kept Combined present while other apps were hidden.

When iStat Menus 7 is installed, MenuBarCompact's compatibility utility:

1. Verifies the original helper's signature.
2. Copies it from `~/Library/Application Support/iStat Menus 7/iStat Menus Menubar.app` to `/Applications/iStat Menus Menubar Compatibility.app`.
3. Changes only `Program` in the existing `com.bjango.istatmenus.status` user LaunchAgent, preserving its Mach service and other fields.
4. Registers the copy with Launch Services and restarts the helper.

The original helper is retained. The utility checks for executable, plist, and sealed-resource changes and refreshes the copy when needed. An unchanged installation is not restarted. If compatibility fails, hiding is paused and Settings shows an error.

Backups and management state are stored in `~/Library/Application Support/MenuBarCompact/`. Existing diagnostic-prototype backup files are migrated without overwriting current state. No iStat executable is included in this repository.

To inspect or restore the original launch path, first quit MenuBarCompact, then run from this repository:

```sh
/usr/bin/python3 istat_workaround.py status
/usr/bin/python3 istat_workaround.py restore
```

Inactive copies and backups are retained. Restoring the original helper location may bring back the original compatibility issue under menu-bar restrictions.

## Development and validation

- `main.m`: native UI, persisted rules, menu-bar control, lifecycle handling, and login registration.
- `istat_workaround.py`: compatibility detection, installation, status, rollback, and legacy-state migration.
- `tests/test_workaround.py`: isolated tests that do not modify real applications or launch services.

```sh
/usr/bin/python3 -m unittest discover -s tests -v
```

Local validation covered hiding/revealing with iStat retained, automatic re-hiding, rule persistence, quitting/relaunching, and conflict handling with Thaw. Menu-bar presence was checked through macOS accessibility; that does not verify every rendered meter or interaction. An actual logout/login, sleep/wake cycle, and multiple-display behavior have not been comprehensively tested.

The compatibility tests cover unchanged copies, executable updates, resource-only updates, absent installations, unexpected helper paths, rollback preservation, and legacy migration.

Logs stay local at `~/Library/Application Support/MenuBarCompact/events.log`. Preferences use `io.github.iamwrm.MenuBarCompact`. Local logs, screenshots, build products, and user settings are excluded from the repository. There is no telemetry or network service.

## Current limitations

Visibility is per app bundle, not per individual icon. Drag-to-reorder layouts, hover/scroll reveal, global hotkeys, and an overflow panel are not implemented. Revealed icons can still overflow a crowded or notched menu bar.

The menu-bar API is loaded dynamically and checked at runtime. The implementation does not require a private entitlement or changes to OS security settings. There is no dependency on Thaw's binary or source code.

## References

- [Apple: SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Thaw](https://github.com/thaw-app/Thaw), whose compatibility issue motivated the original investigation.
- [Pelmet's troubleshooting FAQ](https://github.com/fif7y/pelmet/blob/main/docs/FAQ.md), which suggested investigating application location and Launch Services registration.
