// ~/src/tmill/Treadmill/Services/SettingsManager.swift
// Stub — will be replaced with full implementation in a later commit
import Foundation

@Observable
final class SettingsManager {
    static let shared = SettingsManager()

    var speedIncrement: Double = 0.5
    var inclineIncrement: Double = 1.0

    private init() {}
}
