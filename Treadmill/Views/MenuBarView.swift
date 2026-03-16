// ~/src/tmill/Treadmill/Views/MenuBarView.swift
import SwiftUI

struct MenuBarView: View {
    let treadmillState: TreadmillState
    let manager: TreadmillManager
    let programEngine: ProgramEngine?
    let onOpenHistory: () -> Void
    let onOpenPrograms: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    private var settings = SettingsManager.shared

    init(treadmillState: TreadmillState,
         manager: TreadmillManager,
         programEngine: ProgramEngine? = nil,
         onOpenHistory: @escaping () -> Void,
         onOpenPrograms: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.treadmillState = treadmillState
        self.manager = manager
        self.programEngine = programEngine
        self.onOpenHistory = onOpenHistory
        self.onOpenPrograms = onOpenPrograms
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerSection
            Divider()

            // Live stats
            if treadmillState.isConnected {
                statsSection
                Divider()

                // Controls
                controlsSection
                Divider()

                // Speed & Incline
                adjustmentSection
                Divider()

                // Program
                programSection
                Divider()
            } else {
                disconnectedSection
                Divider()
            }

            // Navigation
            navigationSection
        }
        .frame(width: 280)
        .onKeyPress(.upArrow) { adjustSpeed(up: true); return .handled }
        .onKeyPress(.downArrow) { adjustSpeed(up: false); return .handled }
        .onKeyPress(.leftArrow) { adjustIncline(up: false); return .handled }
        .onKeyPress(.rightArrow) { adjustIncline(up: true); return .handled }
        .onKeyPress(.space) { toggleStartPause(); return .handled }
        .onKeyPress(.escape) { Task { await manager.stop() }; return .handled }
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack {
            Text(treadmillState.deviceName.isEmpty ? "Treadmill" : treadmillState.deviceName)
                .font(.headline)
            Spacer()
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(treadmillState.connectionStatus.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statsSection: some View {
        VStack(spacing: 6) {
            HStack {
                StatLabel(label: "Speed", value: String(format: "%.1f km/h", treadmillState.speed))
                Spacer()
                StatLabel(label: "Incline", value: String(format: "%.0f%%", treadmillState.incline))
            }
            HStack {
                StatLabel(label: "Distance", value: formatDistance(treadmillState.distance))
                Spacer()
                StatLabel(label: "Time", value: formatTime(treadmillState.elapsed))
            }
            HStack {
                StatLabel(label: "Calories", value: "\(treadmillState.calories) kcal")
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var controlsSection: some View {
        HStack(spacing: 8) {
            Button(action: { Task { await manager.start() } }) {
                Label("Start", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(!treadmillState.isConnected || treadmillState.isRunning)

            Button(action: { Task { await manager.stop() } }) {
                Label("Stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!treadmillState.isRunning)

            Button(action: { Task { await manager.pause() } }) {
                Label("Pause", systemImage: "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!treadmillState.isRunning)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var adjustmentSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Speed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("\u{2212}") { adjustSpeed(up: false) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Text(String(format: "%.1f", treadmillState.targetSpeed))
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 40, alignment: .center)
                Button("+") { adjustSpeed(up: true) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            HStack {
                Text("Incline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("\u{2212}") { adjustIncline(up: false) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Text(String(format: "%.0f%%", treadmillState.targetIncline))
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 40, alignment: .center)
                Button("+") { adjustIncline(up: true) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var programSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Program")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let engine = programEngine, engine.isActive, let name = engine.programName {
                    Text(name)
                } else {
                    Text("None")
                        .foregroundStyle(.secondary)
                }
            }
            if let engine = programEngine, engine.isActive {
                HStack {
                    Text("Segment \(engine.currentSegmentIndex + 1)/\(engine.totalSegments)")
                        .font(.caption)
                    Spacer()
                    Text("\(Int(engine.segmentProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: engine.segmentProgress)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var disconnectedSection: some View {
        VStack(spacing: 8) {
            if treadmillState.connectionStatus == .unauthorized {
                Text("Bluetooth access is required.")
                    .font(.caption)
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if treadmillState.connectionStatus == .poweredOff {
                Text("Turn on Bluetooth to connect.")
                    .font(.caption)
            } else {
                Text("Looking for Merach T25...")
                    .font(.caption)
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
    }

    private var navigationSection: some View {
        VStack(spacing: 0) {
            MenuButton(title: "Open History...", shortcut: "\u{2318}H", action: onOpenHistory)
            MenuButton(title: "Edit Programs...", shortcut: "", action: onOpenPrograms)
            MenuButton(title: "Settings...", shortcut: "", action: onOpenSettings)
            Divider()
            MenuButton(title: "Quit Treadmill", shortcut: "\u{2318}Q", action: onQuit)
        }
    }

    // MARK: - Actions

    private func adjustSpeed(up: Bool) {
        let new = treadmillState.targetSpeed + (up ? settings.speedIncrement : -settings.speedIncrement)
        Task { await manager.setSpeed(new) }
    }

    private func adjustIncline(up: Bool) {
        let new = treadmillState.targetIncline + (up ? settings.inclineIncrement : -settings.inclineIncrement)
        Task { await manager.setIncline(new) }
    }

    private func toggleStartPause() {
        Task {
            if treadmillState.isRunning {
                await manager.pause()
            } else {
                await manager.start()
            }
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch treadmillState.connectionStatus {
        case .ready: return .green
        case .connected: return .yellow
        case .scanning, .connecting: return .orange
        case .unauthorized, .poweredOff: return .red
        case .disconnected: return .gray
        }
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

// MARK: - Subviews

private struct StatLabel: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}

private struct MenuButton: View {
    let title: String
    let shortcut: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if !shortcut.isEmpty {
                    Text(shortcut)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}
