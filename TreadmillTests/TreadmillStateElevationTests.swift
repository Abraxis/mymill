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

        // Second frame: moved 100m at 10% incline -> 10m elevation
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
        state.update(from: FTMSProtocol.TreadmillDataFrame(
            speed: 5.0, avgSpeed: nil, totalDistance: 100,
            incline: 10, totalEnergy: nil, elapsedTime: nil
        ))
        state.update(from: FTMSProtocol.TreadmillDataFrame(
            speed: 5.0, avgSpeed: nil, totalDistance: 200,
            incline: 10, totalEnergy: nil, elapsedTime: nil
        ))
        XCTAssertTrue(state.elevationGain > 0)

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
        state.update(from: FTMSProtocol.TreadmillDataFrame(
            speed: 5.0, avgSpeed: nil, totalDistance: 500,
            incline: 10, totalEnergy: nil, elapsedTime: nil
        ))
        for _ in 0..<3 {
            state.update(from: FTMSProtocol.TreadmillDataFrame(
                speed: 0, avgSpeed: nil, totalDistance: 500,
                incline: 0, totalEnergy: nil, elapsedTime: nil
            ))
        }
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
