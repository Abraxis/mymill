# NSMenu Menu Bar Refactoring — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace SwiftUI MenuBarExtra with NSStatusItem + NSMenu to eliminate menu flicker and enable live stat updates.

**Architecture:** A `StatusBarController` class owns the `NSStatusItem` and `NSMenu`, creates all menu items once at init, and updates their titles/visibility in-place via a 2s timer and `NSMenuDelegate`. `TreadmillState` gains live elevation gain tracking.

**Tech Stack:** Swift, AppKit (NSStatusItem/NSMenu/NSMenuItem), SwiftUI (Window scenes only)

**Spec:** `docs/superpowers/specs/2026-03-19-nsmenu-refactor-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `Treadmill/Models/TreadmillState.swift` | Modify | Add `elevationGain` accumulation + reset logic |
| `TreadmillTests/TreadmillStateElevationTests.swift` | Create | Unit tests for elevation gain |
| `Treadmill/StatusBarController.swift` | Create | NSStatusItem + NSMenu owner, item creation, update logic |
| `Treadmill/TreadmillApp.swift` | Modify | Remove MenuBarExtra/MenuBarContentView/MenuSnapshot, wire StatusBarController |
| `Treadmill/Views/MenuBarView.swift` | Delete | Dead code (never referenced) |

---

### Task 1: Add elevation gain tracking to TreadmillState

**Files:**
- Modify: `Treadmill/Models/TreadmillState.swift`
- Create: `TreadmillTests/TreadmillStateElevationTests.swift`

- [ ] **Step 1: Write failing tests for elevation gain**

Create `TreadmillTests/TreadmillStateElevationTests.swift`:

```swift
import XCTest
@testable import Treadmill

final class TreadmillStateElevationTests: XCTestCase {

    func testElevationAccumulatesFromDistanceAndIncline() {
        let state = TreadmillState()
        // Start running: first frame sets anchor
        state.update(from: FTMSProtocol.TreadmillDataFrame(
            speed: 5.0, avgSpeed: nil, totalDistance: 100,
            incline: 10, totalEnergy: nil, elapsedTime: nil
        ))
        XCTAssertEqual(state.elevationGain, 0, "First frame sets anchor, no gain yet")

        // Second frame: moved 100m at 10% incline → 10m elevation
        state.update(from: FTMSProtocol.TreadmillDataFrame(
            speed: 5.0, avgSpeed: nil, totalDistance: 200,
            incline: 10, totalEnergy: nil, elapsedTime: nil
        ))
        XCTAssertEqual(state.elevationGain, 10.0, accuracy: 0.01)
    }

    func testElevationDoesNotAccumulateAtZeroIncline() {
        let state = TreadmillState()
        state.update(from: FTMSProtocol.TreadmillDataFrame(
            speed: 5.0, avgSpeed: nil, totalDistance: 100,
            incline: 0, totalEnergy: nil, elapsedTime: nil
        ))
        state.update(from: FTMSProtocol.TreadmillDataFrame(
            speed: 5.0, avgSpeed: nil, totalDistance: 200,
            incline: 0, totalEnergy: nil, elapsedTime: nil
        ))
        XCTAssertEqual(state.elevationGain, 0)
    }

    func testElevationResetsWhenTreadmillStops() {
        let state = TreadmillState()
        // Build up some elevation
        state.update(from: FTMSProtocol.TreadmillDataFrame(
            speed: 5.0, avgSpeed: nil, totalDistance: 100,
            incline: 10, totalEnergy: nil, elapsedTime: nil
        ))
        state.update(from: FTMSProtocol.TreadmillDataFrame(
            speed: 5.0, avgSpeed: nil, totalDistance: 200,
            incline: 10, totalEnergy: nil, elapsedTime: nil
        ))
        XCTAssertTrue(state.elevationGain > 0)

        // Send enough zero-speed frames to trigger stop (threshold = 3)
        for _ in 0..<3 {
            state.update(from: FTMSProtocol.TreadmillDataFrame(
                speed: 0, avgSpeed: nil, totalDistance: 200,
                incline: 0, totalEnergy: nil, elapsedTime: nil
            ))
        }
        XCTAssertFalse(state.isRunning)
        XCTAssertEqual(state.elevationGain, 0)
    }

    func testElevationAnchorsOnRestart() {
        let state = TreadmillState()
        // First session
        state.update(from: FTMSProtocol.TreadmillDataFrame(
            speed: 5.0, avgSpeed: nil, totalDistance: 500,
            incline: 10, totalEnergy: nil, elapsedTime: nil
        ))
        // Stop
        for _ in 0..<3 {
            state.update(from: FTMSProtocol.TreadmillDataFrame(
                speed: 0, avgSpeed: nil, totalDistance: 500,
                incline: 0, totalEnergy: nil, elapsedTime: nil
            ))
        }
        // Restart at totalDistance=500 — should not get a huge delta
        state.update(from: FTMSProtocol.TreadmillDataFrame(
            speed: 5.0, avgSpeed: nil, totalDistance: 500,
            incline: 10, totalEnergy: nil, elapsedTime: nil
        ))
        XCTAssertEqual(state.elevationGain, 0, "Re-anchor on restart, no gain yet")

        state.update(from: FTMSProtocol.TreadmillDataFrame(
            speed: 5.0, avgSpeed: nil, totalDistance: 600,
            incline: 10, totalEnergy: nil, elapsedTime: nil
        ))
        XCTAssertEqual(state.elevationGain, 10.0, accuracy: 0.01)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Treadmill.xcodeproj -scheme Treadmill -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO SYMROOT=build 2>&1 | grep -E '(Test Case|FAIL|error:)'`

Expected: Compile error — `elevationGain` property doesn't exist on TreadmillState.

Check: `FTMSProtocol.TreadmillDataFrame` init — tests assume a memberwise init. Read `Treadmill/Bluetooth/FTMSProtocol.swift` to verify the struct fields and adjust test code if the init signature differs.

- [ ] **Step 3: Implement elevation gain in TreadmillState**

Modify `Treadmill/Models/TreadmillState.swift`. Add these properties after existing properties:

```swift
var elevationGain: Double = 0
private var lastDistance: Double = 0
private var wasRunning: Bool = false
```

In `update(from:)`, add elevation tracking after the existing distance update (`if let d = frame.totalDistance { distance = Double(d) }`):

```swift
// Elevation gain tracking
if isRunning {
    if !wasRunning {
        // Just started — anchor lastDistance
        lastDistance = distance
    } else if incline > 0 {
        let delta = distance - lastDistance
        if delta > 0 {
            elevationGain += delta * (incline / 100.0)
        }
    }
    lastDistance = distance
}
if !isRunning && wasRunning {
    // Just stopped — reset
    elevationGain = 0
    lastDistance = 0
}
wasRunning = isRunning
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project Treadmill.xcodeproj -scheme Treadmill -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO SYMROOT=build 2>&1 | tail -20`

Expected: All tests pass including new elevation tests.

- [ ] **Step 5: Commit**

```bash
git add Treadmill/Models/TreadmillState.swift TreadmillTests/TreadmillStateElevationTests.swift
git commit -m "feat: add live elevation gain tracking to TreadmillState"
```

---

### Task 2: Create StatusBarController

**Files:**
- Create: `Treadmill/StatusBarController.swift`

- [ ] **Step 1: Create StatusBarController with menu items**

Create `Treadmill/StatusBarController.swift`:

```swift
import AppKit

/// Wraps a closure as an NSMenu target-action pair
final class MenuAction: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func perform() { handler() }
}

/// Owns the NSStatusItem and NSMenu, updates items in-place
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private unowned let appState: AppState
    private var actions: [MenuAction] = []

    // Window-opening closures — set by TreadmillApp body
    var onOpenHistory: (() -> Void)?
    var onOpenPrograms: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    // MARK: - Menu items (held for in-place updates)

    private let statusLine = NSMenuItem()
    private let statsSeparator = NSMenuItem.separator()

    private let speedItem = NSMenuItem()
    private let inclineItem = NSMenuItem()
    private let distanceItem = NSMenuItem()
    private let timeItem = NSMenuItem()
    private let caloriesItem = NSMenuItem()
    private let elevationItem = NSMenuItem()

    private let controlsSeparator = NSMenuItem.separator()
    private let startItem = NSMenuItem()
    private let stopItem = NSMenuItem()
    private let pauseItem = NSMenuItem()

    private let adjustSeparator = NSMenuItem.separator()
    private let speedUpItem = NSMenuItem()
    private let speedDownItem = NSMenuItem()
    private let inclineUpItem = NSMenuItem()
    private let inclineDownItem = NSMenuItem()

    private let presetSeparator = NSMenuItem.separator()
    // Preset items are rebuilt in menuNeedsUpdate

    private let programSeparator = NSMenuItem.separator()
    private let programItem = NSMenuItem()

    private let connectionSeparator = NSMenuItem.separator()
    private let connectionStatusItem = NSMenuItem()
    private let hintItem = NSMenuItem()
    private let btSettingsItem = NSMenuItem()

    private let errorSeparator = NSMenuItem.separator()
    private let errorItem = NSMenuItem()

    // Tracks where preset items are inserted
    private var presetInsertIndex: Int = 0
    private var presetCount: Int = 0

    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "figure.walk", accessibilityDescription: "MyMill")
            button.imagePosition = .imageLeading
            button.title = "MyMill"
        }

        menu.delegate = self
        buildMenu()
        statusItem.menu = menu
    }

    // MARK: - Build menu (once)

    private func buildMenu() {
        let mgr = appState.manager
        let settings = appState.settings

        // Status line
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(statsSeparator)

        // Stats (disabled = non-interactive text)
        for item in [speedItem, inclineItem, distanceItem, timeItem, caloriesItem, elevationItem] {
            item.isEnabled = false
            menu.addItem(item)
        }

        // Controls
        menu.addItem(controlsSeparator)
        startItem.title = "▶ Start"
        wireAction(startItem) { Task { await mgr.start() } }
        menu.addItem(startItem)

        stopItem.title = "⏹ Stop"
        wireAction(stopItem) { Task { await mgr.stop() } }
        menu.addItem(stopItem)

        pauseItem.title = "⏸ Pause"
        wireAction(pauseItem) { Task { await mgr.pause() } }
        menu.addItem(pauseItem)

        // Adjustments
        menu.addItem(adjustSeparator)

        speedUpItem.title = "Speed + (\(String(format: "%.1f", settings.speedIncrement)))"
        wireAction(speedUpItem) { [weak self] in
            guard let s = self?.appState else { return }
            Task { await s.manager.setSpeed(s.treadmill.targetSpeed + s.settings.speedIncrement) }
        }
        menu.addItem(speedUpItem)

        speedDownItem.title = "Speed − (\(String(format: "%.1f", settings.speedIncrement)))"
        wireAction(speedDownItem) { [weak self] in
            guard let s = self?.appState else { return }
            Task { await s.manager.setSpeed(s.treadmill.targetSpeed - s.settings.speedIncrement) }
        }
        menu.addItem(speedDownItem)

        inclineUpItem.title = "Incline + (\(String(format: "%.0f", settings.inclineIncrement))%)"
        wireAction(inclineUpItem) { [weak self] in
            guard let s = self?.appState else { return }
            Task { await s.manager.setIncline(s.treadmill.targetIncline + s.settings.inclineIncrement) }
        }
        menu.addItem(inclineUpItem)

        inclineDownItem.title = "Incline − (\(String(format: "%.0f", settings.inclineIncrement))%)"
        wireAction(inclineDownItem) { [weak self] in
            guard let s = self?.appState else { return }
            Task { await s.manager.setIncline(s.treadmill.targetIncline - s.settings.inclineIncrement) }
        }
        menu.addItem(inclineDownItem)

        // Presets placeholder
        menu.addItem(presetSeparator)
        presetInsertIndex = menu.items.count

        // Program
        menu.addItem(programSeparator)
        programItem.isEnabled = false
        menu.addItem(programItem)

        // Connection status (shown when disconnected)
        menu.addItem(connectionSeparator)
        connectionStatusItem.isEnabled = false
        menu.addItem(connectionStatusItem)

        hintItem.isEnabled = false
        menu.addItem(hintItem)

        btSettingsItem.title = "Open System Settings"
        wireAction(btSettingsItem) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
                NSWorkspace.shared.open(url)
            }
        }
        menu.addItem(btSettingsItem)

        // Error
        menu.addItem(errorSeparator)
        errorItem.isEnabled = false
        menu.addItem(errorItem)

        // Navigation
        menu.addItem(NSMenuItem.separator())

        let historyItem = NSMenuItem()
        historyItem.title = "Open History..."
        historyItem.keyEquivalent = "h"
        historyItem.keyEquivalentModifierMask = .command
        wireAction(historyItem) { [weak self] in self?.onOpenHistory?() }
        menu.addItem(historyItem)

        let programsItem = NSMenuItem()
        programsItem.title = "Edit Programs..."
        wireAction(programsItem) { [weak self] in self?.onOpenPrograms?() }
        menu.addItem(programsItem)

        let settingsItem = NSMenuItem()
        settingsItem.title = "Settings..."
        settingsItem.keyEquivalent = ","
        settingsItem.keyEquivalentModifierMask = .command
        wireAction(settingsItem) { [weak self] in self?.onOpenSettings?() }
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem()
        quitItem.title = "Quit MyMill"
        quitItem.keyEquivalent = "q"
        quitItem.keyEquivalentModifierMask = .command
        wireAction(quitItem) { NSApplication.shared.terminate(nil) }
        menu.addItem(quitItem)
    }

    // MARK: - Update (called by 2s timer + menuNeedsUpdate)

    func update() {
        let t = appState.treadmill
        let engine = appState.programEngine!
        let connected = t.isConnected
        let running = t.isRunning

        // Status bar button
        if let button = statusItem.button {
            button.title = connected && t.speed > 0
                ? String(format: " %.1f", t.speed)
                : " MyMill"
        }

        // Status line
        if connected {
            let name = t.deviceName.isEmpty ? "Treadmill" : t.deviceName
            statusLine.title = running
                ? "\(name) — \(String(format: "%.1f km/h", t.speed))"
                : "\(name) — Idle"
        } else {
            statusLine.title = "MyMill"
        }

        // Stats
        speedItem.title = "Speed: \(String(format: "%.1f", t.speed)) km/h"
        inclineItem.title = "Incline: \(String(format: "%.0f", t.incline))%"
        distanceItem.title = "Distance: \(formatDistance(t.distance))"
        timeItem.title = "Time: \(formatTime(t.elapsed))"
        caloriesItem.title = "Calories: \(t.calories) kcal"
        elevationItem.title = "Elevation: \(Int(t.elevationGain)) m"

        // Stats visibility
        for item in [speedItem, inclineItem, distanceItem, timeItem, caloriesItem, elevationItem,
                     statsSeparator, controlsSeparator, adjustSeparator] {
            item.isHidden = !connected
        }

        // Controls
        startItem.isHidden = !connected || running
        stopItem.isHidden = !connected || !running
        pauseItem.isHidden = !connected || !running

        // Adjustments
        for item in [speedUpItem, speedDownItem, inclineUpItem, inclineDownItem] {
            item.isHidden = !connected
        }

        // Program
        if engine.isActive, let name = engine.programName {
            programItem.title = "Program: \(name) — \(engine.currentSegmentIndex + 1)/\(engine.totalSegments) (\(Int(engine.segmentProgress * 100))%)"
            programItem.isHidden = false
            programSeparator.isHidden = false
        } else {
            programItem.isHidden = true
            programSeparator.isHidden = true
        }

        // Connection (shown when disconnected)
        connectionStatusItem.title = t.connectionStatus.rawValue
        connectionStatusItem.isHidden = connected
        connectionSeparator.isHidden = connected

        let showHint = !connected && (t.connectionStatus == .disconnected || t.connectionStatus == .scanning)
        hintItem.title = "Turn on treadmill to connect"
        hintItem.isHidden = !showHint

        btSettingsItem.isHidden = t.connectionStatus != .unauthorized

        // Error
        if let error = t.lastError {
            errorItem.title = "⚠ \(error)"
            errorItem.isHidden = false
            errorSeparator.isHidden = false
            t.lastError = nil
        } else {
            errorItem.isHidden = true
            errorSeparator.isHidden = true
        }

        // Presets
        presetSeparator.isHidden = !connected || appState.settings.quickPresets.isEmpty
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildPresets()
        update()
    }

    // MARK: - Presets

    private func rebuildPresets() {
        // Remove old preset items
        for _ in 0..<presetCount {
            menu.removeItem(at: presetInsertIndex)
        }
        presetCount = 0

        let presets = appState.settings.quickPresets
        let mgr = appState.manager
        for preset in presets {
            let item = NSMenuItem()
            item.title = "⚡ \(preset.name) — \(String(format: "%.1f", preset.speed)) km/h, \(String(format: "%.0f", preset.incline))%"
            wireAction(item) {
                Task {
                    await mgr.setSpeed(preset.speed)
                    await mgr.setIncline(preset.incline)
                }
            }
            menu.insertItem(item, at: presetInsertIndex + presetCount)
            presetCount += 1
        }
    }

    // MARK: - Helpers

    private func wireAction(_ item: NSMenuItem, _ handler: @escaping () -> Void) {
        let action = MenuAction(handler)
        actions.append(action)
        item.target = action
        item.action = #selector(MenuAction.perform)
    }

    private func formatDistance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.2f km", meters / 1000) : "\(Int(meters)) m"
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodegen generate && xcodebuild build -project Treadmill.xcodeproj -scheme Treadmill -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO SYMROOT=build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED (StatusBarController compiles but isn't used yet)

- [ ] **Step 3: Commit**

```bash
git add Treadmill/StatusBarController.swift
git commit -m "feat: add StatusBarController with NSMenu-based menu bar"
```

---

### Task 3: Wire StatusBarController into TreadmillApp and remove SwiftUI menu

**Files:**
- Modify: `Treadmill/TreadmillApp.swift`
- Delete: `Treadmill/Views/MenuBarView.swift`

- [ ] **Step 1: Modify TreadmillApp.swift**

Replace the entire file. Key changes:
- Remove `MenuBarExtra` from App body
- Remove `MenuBarContentView` struct (lines 146-242)
- Remove `MenuSnapshot` struct (lines 98-143)
- Remove `menuBarLabel` property from `AppState`
- Add `statusBarController: StatusBarController` to `AppState`
- Timer calls `statusBarController.update()` instead of updating `menuBarLabel`

**Window opening approach:** `@Environment(\.openWindow)` is only available inside SwiftUI views. Since we're removing `MenuBarExtra` (the only always-present view), we use `NSApp.windows` matching by title as a fallback. `StatusBarController` has an `activateAndOpen` helper that activates the app and finds/shows the window by title. SwiftUI's `Window` scenes keep the windows alive once opened, so title matching works reliably after first open. For robustness, `StatusBarController` also stores optional closures (`onOpenHistory`, etc.) that can be set from any SwiftUI view context if needed later.

New `TreadmillApp.swift`:

```swift
import SwiftUI

@main
struct TreadmillApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        Window("Workout History", id: "history") {
            HistoryWindow()
                .environment(\.managedObjectContext, appState.persistence.viewContext)
        }

        Window("Edit Programs", id: "programs") {
            ProgramEditorView()
                .environment(\.managedObjectContext, appState.persistence.viewContext)
        }

        Window("Settings", id: "settings") {
            SettingsView()
                .fixedSize()
        }
        .windowResizability(.contentSize)
    }
}

/// Holds all app-level state, initialized eagerly at launch
@Observable
final class AppState {
    let treadmill = TreadmillState()
    let persistence = PersistenceController.shared
    let settings = SettingsManager.shared
    let manager: TreadmillManager
    var sessionTracker: SessionTracker!
    var programEngine: ProgramEngine!
    var statusBarController: StatusBarController!

    init() {
        manager = TreadmillManager(state: treadmill)
        programEngine = ProgramEngine(state: treadmill)
        sessionTracker = SessionTracker(
            state: treadmill,
            persistence: persistence,
            minDuration: settings.minSessionDuration
        )
        statusBarController = StatusBarController(appState: self)

        let mgr = manager
        let workspace = NSWorkspace.shared
        workspace.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { _ in mgr.disconnect() }
        workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { _ in mgr.startScanning() }

        // Update menu + session tracking on a calm 2s timer
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // Update menu bar
                self.statusBarController.update()

                // Session tracking
                self.sessionTracker.check()
                self.sessionTracker.recordSample()

                // Program engine
                self.programEngine.updateFromState()
                if let speed = self.programEngine.pendingSpeed {
                    await self.manager.setSpeed(speed)
                    self.programEngine.clearPendingCommands()
                }
                if let incline = self.programEngine.pendingIncline {
                    await self.manager.setIncline(incline)
                    self.programEngine.clearPendingCommands()
                }
                if self.programEngine.shouldStop {
                    await self.manager.stop()
                    self.programEngine.stop()
                }
            }
        }
    }
}
```

In `StatusBarController`, update `buildMenu()` to use `activateAndOpen` for window items instead of closures:

```swift
// In buildMenu:
wireAction(historyItem) { [weak self] in self?.activateAndOpen("Workout History") }
wireAction(programsItem) { [weak self] in self?.activateAndOpen("Edit Programs") }
wireAction(settingsItem) { [weak self] in self?.activateAndOpen("Settings") }

// Add helper method to StatusBarController:
private func activateAndOpen(_ windowTitle: String) {
    NSApplication.shared.activate(ignoringOtherApps: true)
    if let w = NSApp.windows.first(where: { $0.title == windowTitle }) {
        w.makeKeyAndOrderFront(nil)
    }
}
```

This will work. The worst case (no window ever opened yet) just activates the app, which is reasonable.

- [ ] **Step 2: Delete MenuBarView.swift**

```bash
rm Treadmill/Views/MenuBarView.swift
```

- [ ] **Step 3: Regenerate Xcode project and build**

Run: `xcodegen generate && xcodebuild build -project Treadmill.xcodeproj -scheme Treadmill -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO SYMROOT=build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Run all tests**

Run: `xcodebuild test -project Treadmill.xcodeproj -scheme Treadmill -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO SYMROOT=build 2>&1 | tail -10`

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: replace MenuBarExtra with NSMenu-based StatusBarController

Eliminates menu flicker by updating NSMenuItem properties in-place
instead of rebuilding the menu on every SwiftUI body re-evaluation.
Live stats update every 2s while the menu is open.
Adds elevation gain display. Deletes dead MenuBarView.swift."
```

---

### Task 4: Manual verification and cleanup

- [ ] **Step 1: Launch the app and verify**

Run: `open build/Debug/MyMill.app`

Verify:
- Menu bar shows "figure.walk" icon with "MyMill" text
- Clicking the icon opens the menu with correct items
- When treadmill connects: stats appear, connection items hide
- When running: stats update every 2s without flicker
- Start/Stop/Pause buttons work
- Speed/Incline +/- buttons work
- Quick presets appear and work
- "Open History...", "Edit Programs...", "Settings..." open their windows
- "Quit MyMill" quits the app
- Error display works (if applicable)

- [ ] **Step 2: Run full test suite one final time**

Run: `xcodegen generate && xcodebuild test -project Treadmill.xcodeproj -scheme Treadmill -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO SYMROOT=build 2>&1 | tail -10`

Expected: All tests pass.
