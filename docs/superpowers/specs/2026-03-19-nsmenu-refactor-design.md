# Menu Bar Refactoring: SwiftUI MenuBarExtra to NSMenu

## Problem

The current SwiftUI `MenuBarExtra` implementation causes menu items to flicker when state changes. `MenuBarExtra` rebuilds the underlying `NSMenu` on every SwiftUI body re-evaluation rather than updating items in-place. Observable state from BLE frames (every ~500ms) and the 2s timer trigger these rebuilds. The user also wants live-updating stats while the menu is open.

## Solution

Replace `MenuBarExtra` with a hand-managed `NSStatusItem` + `NSMenu`. Menu items are created once and updated in-place by mutating `.title` and `.isHidden` properties. This eliminates flicker and enables live updates.

## Architecture

### New file: `Treadmill/StatusBarController.swift`

A class that owns the menu bar presence:

```
StatusBarController : NSObject, NSMenuDelegate
  - statusItem: NSStatusItem
  - menu: NSMenu
  - references to all mutable NSMenuItems
  - appState: AppState (unowned)
  - actions: [MenuAction] (retained to prevent deallocation)
  - window-opening closures: onOpenHistory, onOpenPrograms, onOpenSettings (optional, set by App body)
```

### New property: `TreadmillState.elevationGain`

A live-accumulated `Double` computed from distance deltas and current incline on each `update(from:)` call. Displayed in the menu as "Elevation: X m".

**Accumulation**: In `update(from:)`, when `totalDistance` changes: `elevationGain += distanceDelta * (incline / 100.0)`. Only accumulate when `isRunning && incline > 0`.

**Reset**: When `isRunning` transitions to `false` (zeroSpeedCount threshold reached), reset both `elevationGain = 0` and `lastDistance = 0`. On the next `isRunning = true` transition, set `lastDistance` to the current distance to avoid a stale delta.

### Menu item layout

Items are created once at init and stored as properties for in-place updates:

```
statusItem              "DeviceName -- 3.5 km/h" | "MyMill"
---separator---
speedItem               "Speed: 3.5 km/h"          (hidden when disconnected)
inclineItem             "Incline: 2%"               (hidden when disconnected)
distanceItem            "Distance: 1.23 km"         (hidden when disconnected)
timeItem                "Time: 12:34"               (hidden when disconnected)
caloriesItem            "Calories: 150 kcal"        (hidden when disconnected)
elevationItem           "Elevation: 45 m"           (hidden when disconnected)
---separator---                                     (hidden when disconnected)
startItem               "Start"                     (hidden when running)
stopItem                "Stop"                      (hidden when not running)
pauseItem               "Pause"                     (hidden when not running)
---separator---                                     (hidden when disconnected)
speedUpItem             "Speed + (0.5)"             (hidden when disconnected)
speedDownItem           "Speed - (0.5)"             (hidden when disconnected)
inclineUpItem           "Incline + (1%)"            (hidden when disconnected)
inclineDownItem         "Incline - (1%)"            (hidden when disconnected)
---separator---                                     (hidden when no presets or disconnected)
preset items            "Walk -- 3.0 km/h, 0%"     (rebuilt in menuNeedsUpdate)
---separator---
programItem             "Program: Intervals 2/5"    (hidden when no active program)
---separator---
connectionStatusItem    "Scanning..." | etc         (hidden when connected)
hintItem                "Turn on treadmill..."      (hidden when not scanning/disconnected)
btSettingsItem          "Open System Settings"      (hidden unless unauthorized)
---separator---
errorItem               "! some error"              (hidden when no error)
---separator---
historyItem             "Open History..."           Cmd+H
programsItem            "Edit Programs..."
settingsItem            "Settings..."               Cmd+,
---separator---
quitItem                "Quit MyMill"               Cmd+Q
```

**Note on separators**: `NSMenuItem.separatorItem` instances may not reliably support `isHidden` on all macOS versions. Use regular `NSMenuItem` with empty title and disabled state as separators where hiding is needed, or accept that NSMenu auto-collapses consecutive separators.

### Action handling

A small `MenuAction` helper class (NSObject subclass) wraps closures:

```swift
final class MenuAction: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func perform() { handler() }
}
```

Each button item is wired with both `item.target = menuAction` and `item.action = #selector(MenuAction.perform)`. Both must be set — without `target`, NSMenu walks the responder chain and the action won't fire. All `MenuAction` instances are retained in an array on `StatusBarController`.

Actions that call `TreadmillManager` wrap in `Task { @MainActor in await ... }`.

### Update flow

1. **Timer-driven (2s)**: The existing timer in `AppState.init` calls `statusBarController.update()` which:
   - Updates status bar button title (speed or "MyMill") — intentionally throttled, not BLE-frame-driven, to avoid the original flicker issue
   - Updates all stat item titles from current `TreadmillState` values
   - Toggles start/stop/pause visibility based on `isRunning`
   - Toggles connected vs disconnected item sets
   - Shows/hides error item, then clears `lastError` to nil (mirrors current behavior in `MenuBarContentView`)
   - Updates program status item

2. **Menu-open refresh**: `NSMenuDelegate.menuNeedsUpdate(_:)` calls `update()` so menu is never stale on open. Also rebuilds preset items from `SettingsManager.quickPresets` (presets change rarely via Settings UI, so rebuilding on menu open is sufficient).

### Integration changes

**`TreadmillApp.swift`**:
- Remove `MenuBarExtra` from App body (keep Window scenes)
- Remove `MenuBarContentView` struct
- Remove `MenuSnapshot` struct
- Remove `menuBarLabel` property from `AppState`
- `AppState` creates and holds `StatusBarController`
- Timer calls `statusBarController.update()` alongside existing session/program logic
- App body sets window-opening closures on `StatusBarController` via `.onAppear` or similar. Closures are optional — if nil when action fires, the action is a no-op (not a crash).

**`TreadmillState.swift`**:
- Add `var elevationGain: Double = 0`
- Add `private var lastDistance: Double = 0`
- In `update(from:)`: accumulate elevation when running and incline > 0
- On `isRunning` transition to false: reset `elevationGain = 0`, `lastDistance = 0`
- On `isRunning` transition to true: set `lastDistance = distance` to anchor delta

### Window opening

`StatusBarController` stores optional closures: `onOpenHistory`, `onOpenPrograms`, `onOpenSettings`. The `TreadmillApp` body sets these using `@Environment(\.openWindow)`. These closures call `NSApplication.shared.activate(ignoringOtherApps: true)` then `openWindow(id:)`. NSMenu target-action fires on the main thread, so this is safe.

## Files changed

| File | Change |
|------|--------|
| `Treadmill/StatusBarController.swift` | New: ~200 lines |
| `Treadmill/TreadmillApp.swift` | Remove MenuBarExtra/MenuBarContentView/MenuSnapshot/menuBarLabel, wire StatusBarController |
| `Treadmill/Models/TreadmillState.swift` | Add elevationGain accumulation |
| `Treadmill/Views/MenuBarView.swift` | Delete (dead code, never referenced) |

## Features ported from MenuBarView.swift (dead code)

`MenuBarView.swift` is unreferenced dead code but contains features worth porting:
- **Program status display**: current segment index, total segments, progress — ported as `programItem` text item
- **Bluetooth sub-states**: unauthorized ("Open System Settings" button), powered off, scanning — ported as `connectionStatusItem`, `hintItem`, `btSettingsItem`
- **Keyboard shortcuts from MenuBarView are NOT ported**: `.onKeyPress` was SwiftUI-specific and only worked with the popover-style MenuBarExtra. NSMenu has its own keyboard equivalent system via `keyEquivalent` on items. Arrow-key speed/incline adjustment is not applicable to NSMenu (menus use arrows for navigation).

## Testing

- Existing `TreadmillTests` continue to pass (no test changes needed for menu — it's UI)
- Add unit test for `TreadmillState.elevationGain` accumulation and reset logic
- Manual verification: open menu while treadmill running, confirm no flicker, stats update every 2s
