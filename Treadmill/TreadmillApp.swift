import SwiftUI

@main
struct TreadmillApp: App {
    @State private var treadmillState = TreadmillState()
    @State private var manager: TreadmillManager?
    @State private var sessionTracker: SessionTracker?
    @State private var programEngine: ProgramEngine?
    @State private var hasSetup = false

    private let persistence = PersistenceController.shared
    private let settings = SettingsManager.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                treadmillState: treadmillState,
                manager: manager,
                programEngine: programEngine,
                settings: settings,
                onOpenHistory: { openWindow(id: "history") },
                onOpenPrograms: { openWindow(id: "programs") },
                onOpenSettings: { openWindow(id: "settings") }
            )
            .task {
                if !hasSetup { setup() }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "figure.walk")
                if treadmillState.isConnected {
                    Text(String(format: "%.1f", treadmillState.speed))
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }

        Window("Workout History", id: "history") {
            HistoryWindow()
                .environment(\.managedObjectContext, persistence.viewContext)
        }

        Window("Edit Programs", id: "programs") {
            ProgramEditorView()
                .environment(\.managedObjectContext, persistence.viewContext)
        }

        Window("Settings", id: "settings") {
            SettingsView()
        }
    }

    @Environment(\.openWindow) private var openWindow

    private func setup() {
        hasSetup = true
        let mgr = TreadmillManager(state: treadmillState)
        manager = mgr
        sessionTracker = SessionTracker(
            state: treadmillState,
            persistence: persistence,
            minDuration: settings.minSessionDuration
        )
        programEngine = ProgramEngine(state: treadmillState)

        let workspace = NSWorkspace.shared
        workspace.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { _ in mgr.disconnect() }
        workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { _ in mgr.startScanning() }

        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                sessionTracker?.check()
                sessionTracker?.recordSample()
                programEngine?.updateFromState()
                if let speed = programEngine?.pendingSpeed {
                    await mgr.setSpeed(speed)
                    programEngine?.clearPendingCommands()
                }
                if let incline = programEngine?.pendingIncline {
                    await mgr.setIncline(incline)
                    programEngine?.clearPendingCommands()
                }
                if programEngine?.shouldStop == true {
                    await mgr.stop()
                    programEngine?.stop()
                }
            }
        }
    }
}

/// Menu bar content using standard menu items (no .window style — avoids layout crash)
struct MenuBarContentView: View {
    let treadmillState: TreadmillState
    let manager: TreadmillManager?
    let programEngine: ProgramEngine?
    let settings: SettingsManager
    let onOpenHistory: () -> Void
    let onOpenPrograms: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        // Connection status
        Text(statusLine)
            .font(.headline)

        Divider()

        if treadmillState.isConnected {
            // Live stats
            Text("Speed: \(String(format: "%.1f", treadmillState.speed)) km/h")
            Text("Incline: \(String(format: "%.0f", treadmillState.incline))%")
            Text("Distance: \(formatDistance(treadmillState.distance))")
            Text("Time: \(formatTime(treadmillState.elapsed))")
            Text("Calories: \(treadmillState.calories) kcal")

            Divider()

            // Controls
            Button("Start") { Task { await manager?.start() } }
                .disabled(treadmillState.isRunning)
                .keyboardShortcut("s", modifiers: [])
            Button("Stop") { Task { await manager?.stop() } }
                .disabled(!treadmillState.isRunning)
                .keyboardShortcut("x", modifiers: [])
            Button("Pause") { Task { await manager?.pause() } }
                .disabled(!treadmillState.isRunning)
                .keyboardShortcut("p", modifiers: [])

            Divider()

            // Speed adjustment
            Button("Speed + (\(String(format: "%.1f", settings.speedIncrement)))") {
                Task { await manager?.setSpeed(treadmillState.targetSpeed + settings.speedIncrement) }
            }
            .keyboardShortcut(.upArrow, modifiers: [])
            Button("Speed - (\(String(format: "%.1f", settings.speedIncrement)))") {
                Task { await manager?.setSpeed(treadmillState.targetSpeed - settings.speedIncrement) }
            }
            .keyboardShortcut(.downArrow, modifiers: [])

            // Incline adjustment
            Button("Incline + (\(String(format: "%.0f", settings.inclineIncrement))%)") {
                Task { await manager?.setIncline(treadmillState.targetIncline + settings.inclineIncrement) }
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            Button("Incline - (\(String(format: "%.0f", settings.inclineIncrement))%)") {
                Task { await manager?.setIncline(treadmillState.targetIncline - settings.inclineIncrement) }
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            if let engine = programEngine, engine.isActive {
                Divider()
                Text("Program: \(engine.programName ?? "Active")")
                Text("Segment \(engine.currentSegmentIndex + 1)/\(engine.totalSegments) — \(Int(engine.segmentProgress * 100))%")
            }
        } else {
            Text(treadmillState.connectionStatus.rawValue)
                .foregroundStyle(.secondary)
        }

        Divider()

        Button("Open History...") { onOpenHistory() }
            .keyboardShortcut("h")
        Button("Edit Programs...") { onOpenPrograms() }
        Button("Settings...") { onOpenSettings() }
            .keyboardShortcut(",")

        Divider()

        Button("Quit Treadmill") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        if treadmillState.isConnected {
            return "\(treadmillState.deviceName) — \(String(format: "%.1f", treadmillState.speed)) km/h"
        }
        return "Treadmill"
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
