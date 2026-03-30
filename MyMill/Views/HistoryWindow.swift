// Views/HistoryWindow.swift
import SwiftUI
import CoreData

struct HistoryWindow: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SessionTracker.self) private var sessionTracker: SessionTracker?
    @Environment(MyMillState.self) private var mymill: MyMillState?
    @State private var selectedSession: WorkoutSession?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \WorkoutSession.date, ascending: false)],
        animation: .default
    )
    private var sessions: FetchedResults<WorkoutSession>

    var body: some View {
        VStack(spacing: 0) {
            // Overall stats — always visible
            overallStats
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.bar)

            Divider()

            // Session list + detail
            HSplitView {
                sessionList
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
                if let session = selectedSession {
                    let hasHR = session.avgHeartRate > 0
                    SessionDetailView(session: session)
                        .frame(minWidth: hasHR ? 600 : 450)
                } else {
                    Text("Select a session")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 700)
    }

    // MARK: - Overall Stats

    private var overallStats: some View {
        HStack(spacing: 8) {
            OverallStatCard(label: "Sessions", value: "\(sessions.count)", icon: "figure.walk", color: .blue)
            OverallStatCard(label: "Distance", value: String(format: "%.1f km", totalDistance), icon: "map", color: .green)
            OverallStatCard(label: "Time", value: formatTotalTime, icon: "clock", color: .orange)
            OverallStatCard(label: "Calories", value: "\(totalCalories)", icon: "flame", color: .red)
            OverallStatCard(label: "Elevation", value: String(format: "%.0f m", totalElevation), icon: "mountain.2", color: .purple)
        }
    }

    private var totalDistance: Double {
        sessions.reduce(0) { $0 + $1.distance } / 1000
    }

    private var totalCalories: Int {
        sessions.reduce(0) { $0 + Int($1.calories) }
    }

    private var totalElevation: Double {
        sessions.reduce(0) { $0 + $1.computedElevationGain }
    }

    private var formatTotalTime: String {
        let total = sessions.reduce(0.0) { $0 + $1.duration }
        let hours = Int(total) / 3600
        let mins = (Int(total) % 3600) / 60
        return "\(hours)h \(mins)m"
    }

    // MARK: - Session List

    private var sessionList: some View {
        List(selection: $selectedSession) {
            if let tracker = sessionTracker, let state = mymill,
               tracker.isRecording || state.isPaused {
                LiveSessionRow(tracker: tracker, state: state)
            }
            ForEach(sessions, id: \.objectID) { session in
                SessionRow(session: session)
                    .tag(session)
                    .onTapGesture { selectedSession = session }
            }
            .onDelete(perform: deleteSessions)
        }
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            viewContext.delete(sessions[index])
        }
        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
        }
    }
}

private struct OverallStatCard: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.callout.bold())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct LiveSessionRow: View {
    let tracker: SessionTracker
    let state: MyMillState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(state.isPaused ? "Paused" : "In Progress")
                    .font(.subheadline.bold())
                Spacer()
                Image(systemName: state.isPaused ? "pause.circle.fill" : "record.circle")
                    .foregroundStyle(state.isPaused ? .orange : .red)
                    .font(.caption)
            }
            HStack(spacing: 8) {
                let mins = Int(tracker.liveDuration) / 60
                let secs = Int(tracker.liveDuration) % 60
                Text(String(format: "%d:%02d", mins, secs))
                let dist = tracker.liveDistance
                Text(dist >= 1000 ? String(format: "%.2f km", dist / 1000) : "\(Int(dist)) m")
                Text("\(tracker.liveCalories) cal")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct SessionRow: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.date, style: .date)
                    .font(.subheadline.bold())
                Spacer()
                if session.stravaActivityId != nil {
                    Image(systemName: "arrow.up.to.line")
                        .foregroundStyle(.orange)
                        .font(.caption2)
                }
                if session.heartRateSamples != nil {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                        .font(.caption2)
                }
            }
            HStack(spacing: 8) {
                Text(session.durationFormatted)
                Text(String(format: "%.2f km", session.distanceKm))
                Text("\(session.calories) cal")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
