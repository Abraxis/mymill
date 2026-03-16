// ~/src/tmill/Treadmill/Services/ProgramEngine.swift
// Stub — will be replaced with full implementation in a later commit
import Foundation

@Observable
final class ProgramEngine {
    private(set) var isActive = false
    private(set) var isComplete = false
    private(set) var shouldStop = false
    private(set) var currentSegmentIndex = 0
    private(set) var segmentProgress: Double = 0
    private(set) var pendingSpeed: Double?
    private(set) var pendingIncline: Double?

    var totalSegments: Int { 0 }
    var programName: String? { nil }

    private let state: TreadmillState

    init(state: TreadmillState) {
        self.state = state
    }

    func clearPendingCommands() {
        pendingSpeed = nil
        pendingIncline = nil
    }

    func stop() {
        isActive = false
        isComplete = false
        pendingSpeed = nil
        pendingIncline = nil
    }
}
