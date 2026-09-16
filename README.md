# MenuBarCompact

A small, native menu-bar manager for macOS 27. Keep selected apps visible, tuck others away, and reveal them when needed.

MenuBarCompact is an experimental AppKit application with per-app visibility rules, launch-at-login support, and an automatic compatibility workaround for iStat Menus 7. It runs independently of Thaw.

## Features

- Three horizontal **Always Show**, **Hide**, and **Always Hide** rows: drag icons between rows to save visibility rules immediately.
- Automatic discovery of macOS system categories and installed menu extras, including **Time Machine**, with persistent visibility rules.
- System items rescan at startup, once a minute, and through **Rescan system items**.
- Click the menu-bar button to open a shallow second row of icons beneath it; Option-click includes Always hide.
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

This version uses an **undocumented macOS menu-bar API**. Future OS updates may change its behavior or remove it. It is a local development build, not a notarized distribution.

## Build and run

Open `MenuBarCompact.xcodeproj` in Xcode and run the **MenuBarCompact** scheme, or:

```sh
./build.sh
```

The output is `build/MenuBarCompact.app`. Quit any running copy before replacing it, then copy the built app to `/Applications` and open it. Running from Applications helps the menu-bar host resolve the app's identity correctly.

The project uses **Apple Development** signing. The build script selects an installed Apple Development identity when available; set `SIGNING_IDENTITY` to select another certificate. Without one, the script falls back to ad-hoc signing. Ad-hoc signatures are specific to one build, so macOS privacy grants can become stale after rebuilding.

If macOS shows the permission enabled but the app still reports no access after a signing change, remove the old MenuBarCompact entry from **Device Control and Data Access**, add `/Applications/MenuBarCompact.app` again, enable it, and reopen the app. Use the same signing identity for subsequent builds.

Enable **Launch at login** in Settings to start automatically. When replacing another menu-bar manager, disable that app's login setting and quit it. Close Settings to leave MenuBarCompact running; quit MenuBarCompact to release its restrictions.

## Using visibility rules

| Rule | Main menu bar | Hidden panel | Include always hidden |
| --- | --- | --- | --- |
| Always show | Visible | Not listed | Not listed |
| Hide | Hidden | Listed | Listed |
| Always hide | Hidden | Not listed | Listed |

Opening either panel leaves the main menu bar compact. Closed apps are omitted. The second row has no tiles, labels, or header. Hover an icon for its name. It scrolls horizontally when necessary. Artwork comes from installed apps’ bundled menu glyphs where available, with application-icon and system-symbol fallbacks. These are representative icons, not live screenshots or status updates.

Select an icon to request its original menu. The app searches both the host’s system extras and its status windows, briefly retries delayed discovery, and uses a position-checked menu-bar click only when a control explicitly rejects Accessibility activation. A timed-out press is never repeated. iStat rejects the AX activation request on this macOS build, so its uniquely identified host control uses one position-checked click directly. If access is missing, clicking an icon opens the permission page; enable MenuBarCompact in macOS **Device Control and Data Access** (Accessibility). Only the selected item is temporarily allowed back into the menu bar while its menu opens. Other hidden items stay hidden. The selected item hides again after a click, Escape, or a 30-second fallback timeout. No Screen Recording permission is needed.

If an app exposes multiple status controls or no identifiable control, the panel reports that direct selection is unavailable rather than pressing an arbitrary control. Certificate-backed builds preserve the app’s signing identity across updates. Switching signing identities still requires a fresh permission grant.

Right-click the menu-bar button for Settings and quick controls. Reopening the app also opens Settings.

Settings has three horizontal icon rows. Drag an icon into **Always Show**, **Hide**, or **Always Hide** to change its rule. Scroll sideways to reach more icons, or search to filter all three rows. Clicking a settings icon does not open a menu or change its rule. Items are alphabetized within each row; dragging changes their visibility group, not their order in the macOS menu bar. Locked icons remain in Always Show.

Settings initially shows configured apps, iStat, and discovered system items. Turn on **Show all running apps** to configure another app. Some apps use a separate menu-bar helper: Box's menu item, for example, belongs to **Box UI**. The expanded list can include processes without menu items; changing those has no visible effect.

System discovery reads the OS’s `MBSystemItemIdentifier.allCases` and string names, then scans `/System/Library/CoreServices/Menu Extras/*.menu` metadata. Category numbers and the list of plug-ins are not hard-coded. The tested macOS build exposes nine categories and eight additional menu extras; Spotlight’s existing compatibility adapter supplies one more entry. A few display-name, icon, protected-item, and compatibility mappings remain intentional.

Discovered items stay listed while hidden, and new items default to Always show. Clock and Control Center remain protected. iStat defaults to Always Show and can be dragged into Hide or Always Hide like other apps; its compatibility helper remains active for all three choices. Always show permits an item that macOS has enabled; it does not enable an inactive item in System Settings. Installed legacy extras can therefore be listed even when their controls are inactive.

The allowlist includes all discovered plug-in bundle IDs by default, preventing discovery omissions from suppressing them. Existing Battery, Input Method, and Spotlight rule keys remain unchanged. Unknown retired synthetic keys never enter the app allowlist. If runtime enumeration fails, the app releases its visibility restriction rather than applying guessed category IDs.

Discovery covers the published category API and installed `.menu` bundles, not every possible Control Center gallery module. Adding other module families can still require a separate discovery/control adapter. Discovering an item is not proof that its native menu supports external activation. A uniquely loaded legacy extra can use SystemUIServer’s menu control; ambiguous hosts fail without pressing an arbitrary menu.

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
- `VisibilityEditor.h`: native icon drag sources, validated row drop targets, and drag feedback.
- `SystemDiscovery.swift`: runtime enumeration of system category IDs and names.
- `SystemDiscovery.h`: installed menu-extra and legacy-host discovery.
- `SystemCatalog.h`: stable preference keys, category/plugin metadata, names, and symbols.
- `MenuActivation.h`: bounded Accessibility discovery and menu activation.
- `istat_workaround.py`: compatibility detection, installation, status, rollback, and legacy-state migration.
- `tests/test_workaround.py`: isolated tests that do not modify real applications or launch services.

```sh
./tests/run.sh
```

Local validation covered hiding/revealing with iStat retained, rule persistence, quitting/relaunching, conflict handling with Thaw, and opening the overflow panel while keeping the main bar compact. Live checks confirmed original Box, Lungo, Battery, Input Method, and discovered Time Machine menus after replacing a stale Accessibility entry. Permission remained valid across subsequent certificate-signed updates. Spotlight discovery and fallback event delivery were checked, but its search interface did not appear; a direct click on its original icon had the same result on this macOS build. Spotlight launch therefore remains unverified. Menu-bar presence was checked through macOS accessibility; that does not verify every rendered meter or interaction. An actual logout/login, sleep/wake cycle, and multiple-display behavior have not been comprehensively tested.

iStat visibility tests cover all three choices, default visibility, second-row filtering, and isolated temporary activation. Live checks confirmed hiding the Combined item and opening its native popup from the second row while retaining the signed compatibility helper.

The three-row editor was checked with native drag gestures across all three groups, a drop outside the rows, protected Clock rejection, search filtering, and rule persistence across a signed-app restart. Test visibility changes were restored afterward.

The compatibility tests cover unchanged copies, executable updates, resource-only updates, absent installations, unexpected helper paths, rollback preservation, and legacy migration.

Discovery tests cover runtime enumeration, an unknown future category with a nonsequential numeric ID, new plug-ins, default visibility, old preference keys, protected items, and obsolete synthetic IDs. Native visibility-policy tests also cover system-only activation, independent Battery changes, Input Method and Spotlight identities, protected items, both legacy reveal modes, panel filtering, and temporary visibility limited to the selected item. Battery and Spotlight hide/reveal behavior was checked live on macOS 27; the input-menu control is unlabeled in the host's accessibility tree, limiting automated identification.

Logs stay local at `~/Library/Application Support/MenuBarCompact/events.log`. Preferences use `io.github.iamwrm.MenuBarCompact`. Local logs, screenshots, build products, and user settings are excluded from the repository. There is no telemetry or network service.

## Current limitations

Third-party visibility is per app bundle, not per individual icon. Discovered system categories and menu extras have separate rules. Per-item hiding of every legacy plug-in has not been visually verified. Reordering icons within a row or the actual menu bar, hover/scroll reveal, and global hotkeys are not implemented. Panel icons represent apps, not live meter contents. Menu activation depends on each app’s Accessibility support; native menus retain their original location and are not embedded in the panel. The one temporarily revealed item may still overflow a crowded or notched menu bar.

The menu-bar API is loaded dynamically and checked at runtime. The implementation does not require a private entitlement or changes to OS security settings. There is no dependency on Thaw's binary or source code.

## References

- [Apple: SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Thaw](https://github.com/thaw-app/Thaw), whose compatibility issue motivated the original investigation.
- [Pelmet's troubleshooting FAQ](https://github.com/fif7y/pelmet/blob/main/docs/FAQ.md), which suggested investigating application location and Launch Services registration.
