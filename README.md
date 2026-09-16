# MenuBarCompact

A small, native menu-bar manager for macOS 27. Keep selected apps visible, tuck others away, and reveal them when needed.

MenuBarCompact is an experimental AppKit application with per-app visibility rules, launch-at-login support, and an automatic compatibility workaround for iStat Menus 7. It runs independently of Thaw.

## Features

- Three **Always Show**, **Hide**, and **Always Hide** sections: drag icons between sections to save visibility rules immediately. Icons wrap onto additional rows instead of scrolling horizontally.
- Automatic discovery of macOS system categories and installed menu extras, including **Time Machine**, with persistent visibility rules.
- System items are discovered at startup, refreshed when loaded menu extras change, and rescanned through **Rescan system items**.
- Click the menu-bar button to open a shallow second row of icons beneath it; Option-click includes Always hide.
- Optional automatic panel closing after 15 seconds.
- Resizable, searchable settings with remembered window size/position and an option to show all running apps.
- Launch at login through Apple's `SMAppService`.
- Automatic iStat compatibility checks at startup, when helper files or processes change, and hourly.
- Import existing Thaw visibility groups on first use, when available.
- Release hiding restrictions on quit, error, or activation timeout; pause while Thaw runs.

The first prototype was called MenuShelter. Existing prototype visibility rules and re-hide preferences migrate automatically.

## Requirements

- macOS 27; tested on 27.0 build 26A428.
- Xcode with a macOS 27 SDK to build.
- Developer-tools Python at `/usr/bin/python3` for the bundled iStat compatibility utility.
- Write access to `/Applications` when applying the iStat workaround.

This version uses an **undocumented macOS menu-bar API**. Future OS updates may change its behavior or remove it. Download builds are not notarized.

## Download

Get the ZIP from [GitHub Releases](https://github.com/iamwrm/MenuBarCompact/releases/latest). Release downloads target **Apple Silicon running macOS 27**. Unzip the asset and copy `MenuBarCompact.app` to `/Applications`.

Release builds use no Apple signing certificate or notarization. macOS may require manual approval on first launch, and Accessibility permission may need to be renewed after replacing a differently signed build. The arm64 linker can include an ad-hoc code seal required to execute the binary; it is not a developer signature. A `.sha256` checksum accompanies each ZIP.

### Publishing a release

The **Download release** GitHub Actions workflow runs tests on the `xcode-27` runner, builds the tagged source in Release configuration with certificate signing disabled, and publishes the ZIP and checksum. No signing secrets are needed. It also retains a workflow artifact for 30 days.

Update the Xcode project's `MARKETING_VERSION` and build number, commit and push, then push a matching version tag such as `v0.7.0`. The tag version must match the app version or packaging fails. The workflow can also be started manually with an existing tag. Published releases are not overwritten; retries can finish an incomplete draft.

To build the same package locally:

```sh
./scripts/package-release.sh 0.7.0
```

Output: `dist/MenuBarCompact-0.7.0-macOS-arm64.zip` and its checksum. This packaging path is separate from the certificate-signed local development build below.

## Build and run

Open `MenuBarCompact.xcodeproj` in Xcode and run the **MenuBarCompact** scheme, or:

```sh
./build.sh
```

The script builds optimized Release code by default; use `CONFIGURATION=Debug ./build.sh` for debugging. The output is `build/MenuBarCompact.app`. Quit any running copy before replacing it, then copy the built app to `/Applications` and open it. Running from Applications helps the menu-bar host resolve the app's identity correctly.

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

Select an icon to request its original menu. The app searches both the host’s system extras and its status windows, briefly retries delayed discovery, and uses a position-checked menu-bar click only when a control explicitly rejects Accessibility activation. A timed-out press is never repeated. iStat rejects the AX activation request on this macOS build, so its uniquely identified host control uses one position-checked click directly. If access is missing, clicking an icon opens the permission page; enable MenuBarCompact in macOS **Device Control and Data Access** (Accessibility). Only the selected item is temporarily allowed back into the menu bar while its menu opens. The previous visibility restriction stays active until its replacement is acknowledged, avoiding an unrestricted gap. Activation then checks for a stable, on-screen target immediately, with short bounded retries while the host lays it out; there is no fixed 700 ms delay. The panel closes as soon as an icon is selected. A moving, ambiguous, or unavailable target is never clicked. Other hidden items stay hidden. The selected item hides again after a click, Escape, or a 30-second fallback timeout. No Screen Recording permission is needed.

If an app exposes multiple status controls or no identifiable control, the panel reports that direct selection is unavailable rather than pressing an arbitrary control. Certificate-backed builds preserve the app’s signing identity across updates. Switching signing identities still requires a fresh permission grant.

Right-click the menu-bar button for Settings and quick controls. Reopening the app also opens Settings.

Settings has three icon sections with compact 56-point spacing. At the default width, each row fits 13 icons; overflow wraps onto a second row, then further rows if needed. There is no horizontal scrolling in Settings. Resize the window to change the number of columns. Its size and position are remembered; the minimum content size is 800 × 600 points. The initial window grows to fit ordinary lists, while larger lists scroll vertically as one page. Once you resize it, your chosen size is preserved. Search does not resize the window on each keystroke.

Long labels truncate; hover to read the full name. Drag an icon into **Always Show**, **Hide**, or **Always Hide** to change its rule, or search to filter all three sections. Clicking a settings icon does not open a menu or change its rule. Items are alphabetized left to right and then downward within each section; dragging changes their visibility group, not their order in the macOS menu bar. Locked icons remain in Always Show.

Settings initially shows configured apps, iStat, and discovered system items. Turn on **Show all running apps** to configure another app. Some apps use a separate menu-bar helper: Box's menu item, for example, belongs to **Box UI**. The expanded list can include processes without menu items; changing those has no visible effect.

System discovery reads the OS’s `MBSystemItemIdentifier.allCases` and string names, then scans `/System/Library/CoreServices/Menu Extras/*.menu` metadata. Category numbers and the list of plug-ins are not hard-coded. The tested macOS build exposes nine categories and eight additional menu extras; Spotlight’s existing compatibility adapter supplies one more entry. A few display-name, icon, protected-item, and compatibility mappings remain intentional.

Discovered items stay listed while hidden, and new items default to Always show. Clock and Control Center remain protected. iStat defaults to Always Show and can be dragged into Hide or Always Hide like other apps; its compatibility helper remains active for all three choices. Always show permits an item that macOS has enabled; it does not enable an inactive item in System Settings. Installed legacy extras can therefore be listed even when their controls are inactive.

The allowlist includes all discovered plug-in bundle IDs by default, preventing discovery omissions from suppressing them. Existing Battery, Input Method, and Spotlight rule keys remain unchanged. Unknown retired synthetic keys never enter the app allowlist. If runtime enumeration fails, the app releases its visibility restriction rather than applying guessed category IDs.

Discovery covers the published category API and installed `.menu` bundles, not every possible Control Center gallery module. Adding other module families can still require a separate discovery/control adapter. Discovering an item is not proof that its native menu supports external activation. A uniquely loaded legacy extra can use SystemUIServer’s menu control. Its visibility rule also targets that host: macOS can attribute the visible icon to SystemUIServer rather than the plug-in bundle. This fixes Time Machine remaining visible despite a Hide rule when it is the sole loaded legacy extra. When several legacy extras share the host, it remains allowed to avoid hiding unrelated controls; independent hiding may be unavailable. Ambiguous menu activation fails without pressing an arbitrary menu.

System-item rules are temporary visibility restrictions: they do not change the selected input source, disable Spotlight search, or edit macOS's menu-bar preferences. Battery uses its system category; Input Method uses the keyboard category and input-menu agent; Spotlight handles both known host app identities. The panel can list these controls while they remain hidden in the main bar.

## Efficiency

Workspace notifications handle app launches and exits. A single 60-second maintenance timer, with 10 seconds of scheduling tolerance, catches missed helper events and checks file metadata. Maintenance pauses during sleep and inactive user sessions. There is no three-second process polling.

Full iStat signature and resource audits run at startup, after relevant metadata or helper-process changes, on manual request, and hourly. Unchanged minute checks do not launch Python or codesign. Failed checks back off for at least a minute.

System metadata, artwork, and status images are cached. Closed Settings windows skip UI updates; visible sections rebuild only when their contents or column count change. Resizing within the same column count reuses existing icon controls. Accessibility discovery reuses overlapping traversal results within each request. Panel/window transition animations and cancelled-drag animations are disabled; drag destination feedback remains. Release builds enable compiler optimization. These changes reduce avoidable work; they are not a measured battery-life claim.

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

See [Swift migration validation and measurements](docs/SWIFT_MIGRATION.md) for the 0.7.0 comparison with the previous Objective-C build.

The application uses Swift and AppKit. A small Objective-C bridge catches exceptions from the undocumented menu-bar API; the iStat utility remains Python. Swift Release builds use whole-module optimization. The migration does not introduce SwiftUI, additional polling, or new visual effects.

- `AppController.swift` and `main.swift`: lifecycle, persisted rules, workspace events, and application entry point.
- `Settings.swift` and `VisibilityEditor.swift`: resizable settings, wrapping layout, and native drag-and-drop.
- `Overflow.swift` and `MenuActivation.swift`: second-row panel, bounded Accessibility traversal, cancellation, and native menu activation.
- `VisibilityPolicy.swift` and `VisibilityController.swift`: allowlists and asynchronous assertion handoff.
- `RestrictionBridge.h/.m`: runtime selector checks and Objective-C exception containment.
- `SystemDiscovery.swift` and `SystemCatalog.swift`: runtime categories, installed extras, stable preference keys, and cached metadata.
- `Compatibility.swift` and `MaintenancePolicy.swift`: login registration, helper process, fingerprints, and audit backoff.
- `istat_workaround.py`: compatibility detection, installation, status, rollback, and legacy-state migration.
- `tests/RegressionTests.swift`: production Swift policy, lifecycle, geometry, discovery, and maintenance tests.
- `tests/test_workaround.py`: isolated compatibility tests without changes to real applications or launch services.

The parity fixture pins Objective-C commit `66eabab47f917d16c966edfde720ac5656ff4ecd` (v0.6.8). It compares 1,536 deterministic cases covering allowlists, both panels, and temporary activation, including invalid rules and retired system IDs. Regenerate the independent oracle with `python3 tests/generate_parity_fixture.py` in a clone containing that commit. Normal tests use the checked-in digest and need no Git history or network.

```sh
./tests/run.sh
```

Local validation covered hiding/revealing with iStat retained, rule persistence, quitting/relaunching, conflict handling with Thaw, and opening the overflow panel while keeping the main bar compact. Live checks confirmed original Box, Lungo, Battery, Input Method, and discovered Time Machine menus after replacing a stale Accessibility entry. Permission remained valid across subsequent certificate-signed updates. Spotlight discovery and fallback event delivery were checked, but its search interface did not appear; a direct click on its original icon had the same result on this macOS build. Spotlight launch therefore remains unverified. Menu-bar presence was checked through macOS accessibility; that does not verify every rendered meter or interaction. An actual logout/login, sleep/wake cycle, and multiple-display behavior have not been comprehensively tested.

iStat visibility tests cover all three choices, default visibility, second-row filtering, and isolated temporary activation. Live checks confirmed hiding the Combined item and opening its native popup from the second row while retaining the signed compatibility helper.

The three-row editor was checked with native drag gestures across all three groups, a drop outside the rows, protected Clock rejection, search filtering, and rule persistence across a signed-app restart. Test visibility changes were restored afterward.

Version 0.6.3 was checked live for Settings search, dragging iStat into Hide, and opening native Battery and iStat menus from the second row. Test rule changes were restored.

Version 0.6.4 replaces the fixed activation delay with host acknowledgement and two matching geometry samples. Live checks opened Battery and iStat menus; click-to-target-ready timings on the development Mac were 184 ms and 125 ms respectively (individual samples, not guaranteed timings). Lungo and Input Method targets were ready in 92 ms and 141 ms; their AX requests timed out, so popup display timing was not established for those apps. The previous code waited 700 ms before beginning target discovery. Local diagnostics report readiness and action-return timings separately.

Version 0.6.5 was checked with Time Machine as the sole loaded SystemUIServer menu extra: its host item disappeared under Hide, reappeared for second-row activation, and the menu action returned success. The native computer-use provider could not read the popup contents. Visibility tests cover exclusive-host hiding, temporary reveal, Always Show, Always Hide, preserving modern system hosts, and leaving shared/unknown hosts allowed.

Version 0.6.7 was checked live at normal and expanded window sizes, with 17 configured Always Show items wrapping onto two rows and the 34-item running-app list wrapping onto three rows. The larger list scrolled vertically; no horizontal scroller was present. Layout tests cover wrapping boundaries, narrow/wide windows, empty drop targets, and non-overlapping in-bounds icon frames through 100 items.

Visibility-transition tests use fake assertions to cover replacement handoff, waiting for acknowledgement, superseded updates, failure, timeout, stale replies, and exact-once release without changing the real menu bar.

Accessibility traversal tests cover overlapping roots, one query per shared control, leaf selection, open-menu isolation, and exhausted request budgets.

Maintenance tests cover unchanged idle sweeps, same-size helper replacement, installation/removal, PID changes, hourly audits, manual checks, and failure backoff.

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
