import SwiftUI

@main
struct TreadmillApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra(appState.menuBarLabel, systemImage: "figure.walk") {
            MenuBarContentView(appState: appState)
        }

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

    /// Throttled label — updated every 2s, not on every BLE frame
    var menuBarLabel: String = "MyMill"

    init() {
        manager = TreadmillManager(state: treadmill)
        programEngine = ProgramEngine(state: treadmill)
        sessionTracker = SessionTracker(
            state: treadmill,
            persistence: persistence,
            minDuration: settings.minSessionDuration
        )

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

        // Update label + session tracking on a calm 2s timer
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // Update menu bar label (throttled)
                if self.treadmill.isConnected && self.treadmill.speed > 0 {
                    self.menuBarLabel = String(format: "%.1f", self.treadmill.speed)
                } else {
                    self.menuBarLabel = "MyMill"
                }

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

/// Snapshot of treadmill state — captured once when menu opens
struct MenuSnapshot {
    let isConnected: Bool
    let isRunning: Bool
    let connectionStatus: String
    let deviceName: String
    let speed: Double
    let incline: Double
    let distance: Double
    let elapsed: TimeInterval
    let calories: Int
    let targetSpeed: Double
    let targetIncline: Double
    let lastError: String?

    init(from t: TreadmillState) {
        isConnected = t.isConnected
        isRunning = t.isRunning
        connectionStatus = t.connectionStatus.rawValue
        deviceName = t.deviceName
        speed = t.speed
        incline = t.incline
        distance = t.distance
        elapsed = t.elapsed
        calories = t.calories
        targetSpeed = t.targetSpeed
        targetIncline = t.targetIncline
        lastError = t.lastError
    }

    var statusLine: String {
        if isConnected {
            return "\(deviceName) — \(isRunning ? String(format: "%.1f km/h", speed) : "Idle")"
        }
        return "MyMill"
    }

    var distanceFormatted: String {
        distance >= 1000 ? String(format: "%.2f km", distance / 1000) : "\(Int(distance)) m"
    }

    var timeFormatted: String {
        let mins = Int(elapsed) / 60
        let secs = Int(elapsed) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

/// Menu content — reads only from snapshot (no Observable)
struct MenuBarContentView: View {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let snap = MenuSnapshot(from: appState.treadmill)
        let mgr = appState.manager
        let s = appState.settings
        let _ = { appState.treadmill.lastError = nil }()

        Text(snap.statusLine)
            .font(.headline)

        Divider()

        if snap.isConnected {
            Text("Speed: \(String(format: "%.1f", snap.speed)) km/h")
            Text("Incline: \(String(format: "%.0f", snap.incline))%")
            Text("Distance: \(snap.distanceFormatted)")
            Text("Time: \(snap.timeFormatted)")
            Text("Calories: \(snap.calories) kcal")

            Divider()

            if snap.isRunning {
                Button("⏹ Stop") { fire { await mgr.stop() } }
                Button("⏸ Pause") { fire { await mgr.pause() } }
            } else {
                Button("▶ Start") { fire { await mgr.start() } }
            }

            Divider()

            Button("Speed + (\(String(format: "%.1f", s.speedIncrement)))") {
                fire { await mgr.setSpeed(snap.targetSpeed + s.speedIncrement) }
            }
            Button("Speed − (\(String(format: "%.1f", s.speedIncrement)))") {
                fire { await mgr.setSpeed(snap.targetSpeed - s.speedIncrement) }
            }
            Button("Incline + (\(String(format: "%.0f", s.inclineIncrement))%)") {
                fire { await mgr.setIncline(snap.targetIncline + s.inclineIncrement) }
            }
            Button("Incline − (\(String(format: "%.0f", s.inclineIncrement))%)") {
                fire { await mgr.setIncline(snap.targetIncline - s.inclineIncrement) }
            }

            if !s.quickPresets.isEmpty {
                Divider()
                ForEach(s.quickPresets) { preset in
                    Button("⚡ \(preset.name) — \(String(format: "%.1f", preset.speed)) km/h, \(String(format: "%.0f", preset.incline))%") {
                        fire {
                            await mgr.setSpeed(preset.speed)
                            await mgr.setIncline(preset.incline)
                        }
                    }
                }
            }
        } else {
            Text(snap.connectionStatus)
                .foregroundStyle(.secondary)

            if snap.connectionStatus == "Not Connected" || snap.connectionStatus == "Scanning..." {
                Divider()
                Text("Turn on treadmill to connect")
                    .foregroundStyle(.tertiary)
            }
        }

        if let error = snap.lastError {
            Divider()
            Text("⚠ \(error)")
                .foregroundStyle(.orange)
        }

        Divider()

        Button("Open History...") { activateAndOpen("history") }
            .keyboardShortcut("h")
        Button("Edit Programs...") { activateAndOpen("programs") }
        Button("Settings...") { activateAndOpen("settings") }
            .keyboardShortcut(",")

        Divider()

        Button("Quit MyMill") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func fire(_ action: @escaping @Sendable () async -> Void) {
        Task.detached { await action() }
    }

    private func activateAndOpen(_ id: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }
}
