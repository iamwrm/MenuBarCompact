# MenuBarCompact

A small, native menu-bar manager for macOS 27. Keep selected apps visible, tuck others away, and reveal them when needed.

MenuBarCompact is an experimental AppKit application with per-app visibility rules, launch-at-login support, and an automatic compatibility workaround for iStat Menus 7. It runs independently of Thaw.

## Features

- **Always show**, **Hide**, and **Always hide** rules for application bundles.
- The same visibility choices for **Battery**, **Input Method**, and **Spotlight**.
- Click the menu-bar button to open a hidden-icon panel beneath it; Option-click includes Always hide.
- Optional automatic panel closing after 15 seconds.
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

| Rule | Main menu bar | Hidden panel | Include always hidden |
| --- | --- | --- | --- |
| Always show | Visible | Not listed | Not listed |
| Hide | Hidden | Listed | Listed |
| Always hide | Hidden | Not listed | Listed |

Opening either panel leaves the main menu bar compact. Closed apps are omitted. The panel uses application icons and system symbols, rather than live screenshots of menu-bar items.

Select an icon to request its original menu. On first use, choose **Allow menu access…** and enable MenuBarCompact in macOS **Device Control and Data Access** (Accessibility). Only the selected item is temporarily allowed back into the menu bar while its menu opens. Other hidden items stay hidden. The selected item hides again after a click, Escape, or a 30-second fallback timeout. No Screen Recording permission is needed.

If an app exposes multiple status controls or no identifiable control, the panel reports that direct selection is unavailable rather than pressing an arbitrary control. Local ad-hoc builds may need permission granted again after replacing the executable.

Right-click the menu-bar button for Settings and quick controls. Reopening the app also opens Settings.

Settings initially shows configured apps and iStat. Turn on **Show all running apps** to configure another app. Some apps use a separate menu-bar helper: Box's menu item, for example, belongs to **Box UI**. The expanded list can include processes without menu items; changing those has no visible effect.

Battery, Input Method, and Spotlight always appear in Settings, including when hidden. They default to Always show until configured. iStat and the remaining macOS system items are protected from hiding.

System-item rules are temporary visibility restrictions: they do not change the selected input source, disable Spotlight search, or edit macOS's menu-bar preferences. Battery uses its system category; Input Method uses the keyboard category and input-menu agent; Spotlight handles both known host app identities. The panel can list these controls while they remain hidden in the main bar.

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
- `VisibilityPolicy.h`: app/system allowlists, panel filtering, and isolated temporary menu visibility.
- `MenuActivation.h`: bounded Accessibility discovery and menu activation.
- `istat_workaround.py`: compatibility detection, installation, status, rollback, and legacy-state migration.
- `tests/test_workaround.py`: isolated tests that do not modify real applications or launch services.

```sh
./tests/run.sh
```

Local validation covered hiding/revealing with iStat retained, rule persistence, quitting/relaunching, conflict handling with Thaw, and opening the overflow panel while keeping the main bar compact. Opening original menus still needs live verification after granting MenuBarCompact Accessibility permission. Menu-bar presence was checked through macOS accessibility; that does not verify every rendered meter or interaction. An actual logout/login, sleep/wake cycle, and multiple-display behavior have not been comprehensively tested.

The compatibility tests cover unchanged copies, executable updates, resource-only updates, absent installations, unexpected helper paths, rollback preservation, and legacy migration.

Native visibility-policy tests also cover system-only activation, independent Battery changes, Input Method and Spotlight identities, protected items, both legacy reveal modes, panel filtering, and temporary visibility limited to the selected item. Battery and Spotlight hide/reveal behavior was checked live on macOS 27; the input-menu control is unlabeled in the host's accessibility tree, limiting automated identification.

Logs stay local at `~/Library/Application Support/MenuBarCompact/events.log`. Preferences use `io.github.iamwrm.MenuBarCompact`. Local logs, screenshots, build products, and user settings are excluded from the repository. There is no telemetry or network service.

## Current limitations

Third-party visibility is per app bundle, not per individual icon. The three supported system controls have separate rules. Drag-to-reorder layouts, hover/scroll reveal, and global hotkeys are not implemented. Panel icons represent apps, not live meter contents. Menu activation depends on each app’s Accessibility support; native menus retain their original location and are not embedded in the panel. The one temporarily revealed item may still overflow a crowded or notched menu bar.

The menu-bar API is loaded dynamically and checked at runtime. The implementation does not require a private entitlement or changes to OS security settings. There is no dependency on Thaw's binary or source code.

## References

- [Apple: SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Thaw](https://github.com/thaw-app/Thaw), whose compatibility issue motivated the original investigation.
- [Pelmet's troubleshooting FAQ](https://github.com/fif7y/pelmet/blob/main/docs/FAQ.md), which suggested investigating application location and Launch Services registration.
