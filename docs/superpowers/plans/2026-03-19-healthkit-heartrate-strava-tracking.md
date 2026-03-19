# HealthKit Heart Rate + Strava Activity Tracking — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add retrospective heart rate data from HealthKit to treadmill sessions and track Strava upload status with activity links.

**Architecture:** After each session, wait 15s for Apple Watch HR data to reach HealthKit, query it, store on the Core Data session, and include in the Strava TCX upload. Strava activity IDs are extracted from upload status polling and stored for web links. On-demand HR fetch and Strava re-upload available from the session detail view.

**Tech Stack:** Swift, HealthKit, Core Data (programmatic model), SwiftUI Charts, Strava API v3, TCX XML

**Spec:** `docs/superpowers/specs/2026-03-19-healthkit-heartrate-strava-tracking-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Treadmill/Models/CoreDataModel.swift` | Modify | Add 4 new attributes to WorkoutSession entity |
| `Treadmill/Models/WorkoutSession+CoreData.swift` | Modify | Add properties, HeartRateSample struct, computed helpers |
| `Treadmill/Services/HealthKitManager.swift` | Modify | Add HR read permission, fetchHeartRateSamples method |
| `Treadmill/Services/TCXGenerator.swift` | Modify | Add heartRateBPM to TrackPoint, emit in XML |
| `Treadmill/Services/StravaManager.swift` | Modify | Return activity ID, accept HR samples, polling loop |
| `Treadmill/Services/SessionTracker.swift` | Modify | Delayed HR fetch + Strava upload flow |
| `Treadmill/Views/SessionDetailView.swift` | Modify | HR stats, HR chart, Strava link, fetch HR button |
| `Treadmill/Views/HistoryWindow.swift` | Modify | Strava and HR icons in SessionRow |

---

### Task 1: Core Data Model — Add New Attributes

**Files:**
- Modify: `Treadmill/Models/CoreDataModel.swift:58-67`
- Modify: `Treadmill/Models/WorkoutSession+CoreData.swift`

- [ ] **Step 1: Add attributes to CoreDataModel.swift**

In `CoreDataModel.swift`, add 4 new attribute definitions before the `session.properties` array (after the `sessionElevationGain` block, around line 62):

```swift
let sessionAvgHeartRate = NSAttributeDescription()
sessionAvgHeartRate.name = "avgHeartRate"
sessionAvgHeartRate.attributeType = .doubleAttributeType
sessionAvgHeartRate.defaultValue = 0.0

let sessionMaxHeartRate = NSAttributeDescription()
sessionMaxHeartRate.name = "maxHeartRate"
sessionMaxHeartRate.attributeType = .doubleAttributeType
sessionMaxHeartRate.defaultValue = 0.0

let sessionHeartRateSamples = NSAttributeDescription()
sessionHeartRateSamples.name = "heartRateSamples"
sessionHeartRateSamples.attributeType = .binaryDataAttributeType
sessionHeartRateSamples.isOptional = true

let sessionStravaActivityId = NSAttributeDescription()
sessionStravaActivityId.name = "stravaActivityId"
sessionStravaActivityId.attributeType = .stringAttributeType
sessionStravaActivityId.isOptional = true
```

Update the `session.properties` array to include the new attributes:

```swift
session.properties = [
    sessionId, sessionDate, sessionDuration, sessionDistance,
    sessionCalories, sessionAvgSpeed, sessionMaxSpeed,
    sessionAvgIncline, sessionSpeedSamples, sessionElevationGain,
    sessionAvgHeartRate, sessionMaxHeartRate, sessionHeartRateSamples,
    sessionStravaActivityId
]
```

- [ ] **Step 2: Add @NSManaged properties to WorkoutSession+CoreData.swift**

Add to the `WorkoutSession` class (after `elevationGain`):

```swift
@NSManaged public var avgHeartRate: Double
@NSManaged public var maxHeartRate: Double
@NSManaged public var heartRateSamples: Data?
@NSManaged public var stravaActivityId: String?
```

- [ ] **Step 3: Add HeartRateSample struct and computed helpers**

Add to the `WorkoutSession` extension (after the existing `Sample` struct):

```swift
struct HeartRateSample: Codable {
    let time: Double  // seconds since session start
    let bpm: Int
}

var hrSamples: [HeartRateSample] {
    guard let data = heartRateSamples else { return [] }
    return (try? JSONDecoder().decode([HeartRateSample].self, from: data)) ?? []
}
```

- [ ] **Step 4: Build to verify model compiles**

Run: `xcodebuild build -scheme Treadmill -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Treadmill/Models/CoreDataModel.swift Treadmill/Models/WorkoutSession+CoreData.swift
git commit -m "feat: add heart rate and Strava activity ID to Core Data model"
```

---

### Task 2: HealthKit — Heart Rate Query

**Files:**
- Modify: `Treadmill/Services/HealthKitManager.swift:25-27`

- [ ] **Step 1: Add heartRate to readTypes**

In `HealthKitManager.swift`, update `readTypes` (line 25-27):

```swift
private let readTypes: Set<HKObjectType> = [
    HKObjectType.workoutType(),
    HKQuantityType(.heartRate),
]
```

- [ ] **Step 2: Add fetchHeartRateSamples method**

Add after the `saveWorkout` method (after line 142):

```swift
/// Fetch heart rate samples from HealthKit for a given time window
func fetchHeartRateSamples(from startDate: Date, to endDate: Date) async -> [(date: Date, bpm: Int)] {
    guard isAvailable else { return [] }

    if !isAuthorized {
        let ok = await requestAuthorization()
        guard ok else { return [] }
    }

    let heartRateType = HKQuantityType(.heartRate)
    let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
    let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

    return await withCheckedContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, error in
            guard let samples = samples as? [HKQuantitySample], error == nil else {
                continuation.resume(returning: [])
                return
            }
            let bpmUnit = HKUnit.count().unitDivided(by: .minute())
            let result = samples.map { sample in
                (date: sample.startDate, bpm: Int(sample.quantity.doubleValue(for: bpmUnit).rounded()))
            }
            continuation.resume(returning: result)
        }
        healthStore.execute(query)
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -scheme Treadmill -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Treadmill/Services/HealthKitManager.swift
git commit -m "feat: add HealthKit heart rate query method"
```

---

### Task 3: TCX Generator — Heart Rate Support

**Files:**
- Modify: `Treadmill/Services/TCXGenerator.swift:4-8,46-63`

- [ ] **Step 1: Add heartRateBPM to TrackPoint**

Update the `TrackPoint` struct (line 4-8):

```swift
struct TrackPoint {
    let timeOffset: TimeInterval   // seconds from start
    let distanceMeters: Double      // cumulative
    let speedMPS: Double?           // meters per second
    let altitudeMeters: Double?     // cumulative elevation
    let heartRateBPM: Int?          // beats per minute
}
```

- [ ] **Step 2: Emit HeartRateBpm in XML**

In the trackpoint loop (after the `AltitudeMeters` block, before the `Extensions` block, around line 56):

```swift
if let hr = point.heartRateBPM, hr > 0 {
    xml += "<HeartRateBpm><Value>\(hr)</Value></HeartRateBpm>\n"
}
```

- [ ] **Step 3: Fix all call sites that create TrackPoint**

There are 2 call sites in `StravaManager.swift` (lines 75 and 114) that create `TrackPoint`. Add `heartRateBPM: nil` to both for now — they'll be updated in Task 5.

In `uploadWorkout` (line 75-80):
```swift
TCXGenerator.TrackPoint(
    timeOffset: sample.timeOffset,
    distanceMeters: sample.distance,
    speedMPS: sample.speed / 3.6,
    altitudeMeters: sample.altitude > 0 ? sample.altitude : nil,
    heartRateBPM: nil
)
```

In `reuploadSession` (line 114-119):
```swift
TCXGenerator.TrackPoint(
    timeOffset: sample.timeOffset,
    distanceMeters: sample.distance,
    speedMPS: sample.speed / 3.6,
    altitudeMeters: sample.altitude > 0 ? sample.altitude : nil,
    heartRateBPM: nil
)
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild build -scheme Treadmill -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Treadmill/Services/TCXGenerator.swift Treadmill/Services/StravaManager.swift
git commit -m "feat: add heart rate support to TCX generator"
```

---

### Task 4: Strava Manager — Activity ID + HR Samples

**Files:**
- Modify: `Treadmill/Services/StravaManager.swift:54-133,282-288`

- [ ] **Step 1: Add UploadStatusResult struct and update checkUploadStatus**

Add the struct near `StravaError` (around line 302):

```swift
struct StravaUploadResult {
    let status: String
    let activityId: Int64?
}
```

Update `checkUploadStatus` (line 282-288) to return the struct:

```swift
private func checkUploadStatus(_ uploadId: String, token: String) async throws -> StravaUploadResult {
    var request = URLRequest(url: URL(string: "https://www.strava.com/api/v3/uploads/\(uploadId)")!)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (data, _) = try await URLSession.shared.data(for: request)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    let status = json["status"] as? String ?? "unknown"
    let activityId = json["activity_id"] as? Int64
    return StravaUploadResult(status: status, activityId: activityId)
}
```

- [ ] **Step 2: Add polling helper**

Add a private method that polls for activity ID:

```swift
private func pollForActivityId(_ uploadId: String, token: String) async -> Int64? {
    for attempt in 1...3 {
        try? await Task.sleep(for: .seconds(5))
        guard let result = try? await checkUploadStatus(uploadId, token: token) else { continue }
        logger.info("Strava poll attempt \(attempt): status=\(result.status), activityId=\(String(describing: result.activityId))")
        if let activityId = result.activityId {
            return activityId
        }
        if result.status.contains("error") {
            logger.error("Strava upload error: \(result.status)")
            return nil
        }
    }
    return nil
}
```

- [ ] **Step 3: Update uploadWorkout to accept HR samples and return activity ID**

Change signature and body (line 54-96):

```swift
@discardableResult
func uploadWorkout(
    startDate: Date,
    durationSeconds: Double,
    distanceMeters: Double,
    calories: Int,
    speedSamples: [(timeOffset: TimeInterval, speed: Double, distance: Double, altitude: Double)],
    heartRateSamples: [(timeOffset: TimeInterval, bpm: Int)] = []
) async -> Int64? {
    guard syncEnabled, isConnected else { return nil }

    guard let token = await getValidToken() else {
        logger.warning("No valid Strava token, skipping upload")
        return nil
    }

    // Generate TCX with HR interpolation
    let tcx = TCXGenerator.generate(
        startDate: startDate,
        totalTimeSeconds: durationSeconds,
        totalDistanceMeters: distanceMeters,
        calories: calories,
        trackPoints: speedSamples.map { sample in
            let nearestHR = heartRateSamples.min(by: {
                abs($0.timeOffset - sample.timeOffset) < abs($1.timeOffset - sample.timeOffset)
            })
            return TCXGenerator.TrackPoint(
                timeOffset: sample.timeOffset,
                distanceMeters: sample.distance,
                speedMPS: sample.speed / 3.6,
                altitudeMeters: sample.altitude > 0 ? sample.altitude : nil,
                heartRateBPM: nearestHR?.bpm
            )
        }
    )

    // Upload and poll for activity ID
    do {
        let uploadId = try await uploadTCX(tcx, token: token, name: "Treadmill Walk")
        logger.info("Strava upload submitted: \(uploadId)")
        return await pollForActivityId(uploadId, token: token)
    } catch {
        logger.error("Strava upload failed: \(error.localizedDescription)")
        return nil
    }
}
```

- [ ] **Step 4: Update reuploadSession to accept HR and return activity ID**

Change signature and body (line 99-133):

```swift
@discardableResult
func reuploadSession(_ session: WorkoutSession) async throws -> Int64? {
    guard isConnected else { throw StravaError.uploadFailed("Not connected to Strava") }

    guard let token = await getValidToken() else {
        throw StravaError.uploadFailed("No valid Strava token")
    }

    let samples = SessionTracker.buildStravaSamples(from: session.samples)
    let hrSamples = session.hrSamples.map { (timeOffset: $0.time, bpm: $0.bpm) }

    let tcx = TCXGenerator.generate(
        startDate: session.date,
        totalTimeSeconds: session.duration,
        totalDistanceMeters: session.distance,
        calories: Int(session.calories),
        trackPoints: samples.map { sample in
            let nearestHR = hrSamples.min(by: {
                abs($0.timeOffset - sample.timeOffset) < abs($1.timeOffset - sample.timeOffset)
            })
            return TCXGenerator.TrackPoint(
                timeOffset: sample.timeOffset,
                distanceMeters: sample.distance,
                speedMPS: sample.speed / 3.6,
                altitudeMeters: sample.altitude > 0 ? sample.altitude : nil,
                heartRateBPM: nearestHR?.bpm
            )
        }
    )

    let uploadId = try await uploadTCX(tcx, token: token, name: "Treadmill Walk")
    logger.info("Strava re-upload submitted: \(uploadId)")

    let activityId = await pollForActivityId(uploadId, token: token)

    if activityId == nil {
        // Check if it was an error vs just slow processing
        if let result = try? await checkUploadStatus(uploadId, token: token),
           result.status.contains("error") {
            throw StravaError.uploadFailed(result.status)
        }
    }

    return activityId
}
```

- [ ] **Step 5: Build to verify**

Run: `xcodebuild build -scheme Treadmill -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Treadmill/Services/StravaManager.swift
git commit -m "feat: return Strava activity ID from uploads, add HR sample support"
```

---

### Task 5: Session Tracker — Delayed HR Fetch + Strava Upload

**Files:**
- Modify: `Treadmill/Services/SessionTracker.swift:139-192`

- [ ] **Step 1: Restructure saveSession**

Replace the Strava upload block (lines 181-191) with a delayed task that fetches HR then uploads. The full `saveSession` method becomes:

```swift
private func saveSession(duration: TimeInterval) {
    let startDate = sessionStartDate ?? Date()
    let endDate = Date()
    let distance = state.distance - sessionStartDistance
    let calories = Int32(state.calories - sessionStartCalories)
    let avgSpeed = state.avgSpeed
    let avgIncline = inclineSampleCount > 0 ? inclineSum / Double(inclineSampleCount) : 0
    let elevationGain = WorkoutSession.calculateElevationGain(from: samples)

    // Save to Core Data
    let context = persistence.viewContext
    let session = WorkoutSession(entity: NSEntityDescription.entity(forEntityName: "WorkoutSession", in: context)!, insertInto: context)
    session.id = UUID()
    session.date = startDate
    session.duration = duration
    session.distance = distance
    session.calories = calories
    session.avgSpeed = avgSpeed
    session.maxSpeed = maxSpeed
    session.avgIncline = avgIncline
    session.elevationGain = elevationGain
    session.speedSamples = try? JSONEncoder().encode(samples)

    persistence.save()
    logger.info("Session saved: \(distance)m, \(duration)s")

    // Save to HealthKit
    let hkSamples = samples.map { sample in
        (date: startDate.addingTimeInterval(sample.time), speedKmh: sample.speed)
    }
    Task {
        await HealthKitManager.shared.saveWorkout(
            startDate: startDate,
            endDate: endDate,
            distanceMeters: distance,
            calories: Int(calories),
            avgSpeedKmh: avgSpeed,
            maxSpeedKmh: maxSpeed,
            speedSamples: hkSamples
        )
    }

    // Delayed: fetch HR from HealthKit, then upload to Strava
    let stravaSamples = buildStravaSamples()
    let sessionRef = session.objectID
    let persistenceRef = persistence
    Task {
        // Wait for Apple Watch to flush HR data to HealthKit
        try? await Task.sleep(for: .seconds(15))

        // Fetch HR samples
        let hrRaw = await HealthKitManager.shared.fetchHeartRateSamples(from: startDate, to: endDate)
        let hrSamples = hrRaw.map {
            WorkoutSession.HeartRateSample(time: $0.date.timeIntervalSince(startDate), bpm: $0.bpm)
        }

        // Update Core Data with HR data
        if !hrSamples.isEmpty {
            await MainActor.run {
                let ctx = persistenceRef.viewContext
                guard let session = try? ctx.existingObject(with: sessionRef) as? WorkoutSession else { return }
                let bpms = hrSamples.map(\.bpm)
                session.avgHeartRate = Double(bpms.reduce(0, +)) / Double(bpms.count)
                session.maxHeartRate = Double(bpms.max() ?? 0)
                session.heartRateSamples = try? JSONEncoder().encode(hrSamples)
                persistenceRef.save()
            }
        }

        // Upload to Strava (with HR if available)
        let hrForStrava = hrSamples.map { (timeOffset: $0.time, bpm: $0.bpm) }
        let activityId = await StravaManager.shared.uploadWorkout(
            startDate: startDate,
            durationSeconds: duration,
            distanceMeters: distance,
            calories: Int(calories),
            speedSamples: stravaSamples,
            heartRateSamples: hrForStrava
        )

        // Store Strava activity ID
        if let activityId {
            await MainActor.run {
                let ctx = persistenceRef.viewContext
                guard let session = try? ctx.existingObject(with: sessionRef) as? WorkoutSession else { return }
                session.stravaActivityId = String(activityId)
                persistenceRef.save()
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme Treadmill -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Treadmill/Services/SessionTracker.swift
git commit -m "feat: delayed HR fetch from HealthKit + Strava activity ID storage"
```

---

### Task 6: Session Detail View — HR Stats, Chart, Strava Link, Fetch Button

**Files:**
- Modify: `Treadmill/Views/SessionDetailView.swift`

- [ ] **Step 1: Add Core Data write access, observation, and state**

Change `let session` to `@ObservedObject var session` so SwiftUI re-renders when Core Data properties change (e.g., after fetching HR or storing a Strava activity ID). Add `@Environment` and new state vars:

```swift
@ObservedObject var session: WorkoutSession

@Environment(\.managedObjectContext) private var viewContext
@State private var isFetchingHR = false
```

- [ ] **Step 2: Add HR stat cards to summaryGrid**

After the existing "Elevation" `StatCard` (line 89), add conditionally:

```swift
if session.avgHeartRate > 0 {
    StatCard(label: "Avg HR", value: "\(Int(session.avgHeartRate)) bpm", icon: "heart.fill")
    StatCard(label: "Max HR", value: "\(Int(session.maxHeartRate)) bpm", icon: "bolt.heart.fill")
}
```

- [ ] **Step 3: Add heart rate chart**

Add a new computed property after `inclineChart`:

```swift
private var heartRateChart: some View {
    VStack(alignment: .leading) {
        Text("Heart Rate Over Time")
            .font(.headline)
        Chart(session.hrSamples, id: \.time) { sample in
            LineMark(
                x: .value("Time", sample.time / 60),
                y: .value("BPM", sample.bpm)
            )
            .foregroundStyle(.red)
        }
        .chartXAxisLabel("Minutes")
        .chartYAxisLabel("BPM")
        .frame(height: 150)
    }
}
```

Add it to the body VStack after `inclineChart`:

```swift
if !session.hrSamples.isEmpty {
    heartRateChart
}
```

- [ ] **Step 4: Add Fetch Heart Rate button**

Add a new computed property:

```swift
private var fetchHeartRateButton: some View {
    Button {
        isFetchingHR = true
        Task {
            let endDate = session.date.addingTimeInterval(session.duration)
            let hrRaw = await HealthKitManager.shared.fetchHeartRateSamples(from: session.date, to: endDate)
            let hrSamples = hrRaw.map {
                WorkoutSession.HeartRateSample(time: $0.date.timeIntervalSince(session.date), bpm: $0.bpm)
            }
            if !hrSamples.isEmpty {
                let bpms = hrSamples.map(\.bpm)
                session.avgHeartRate = Double(bpms.reduce(0, +)) / Double(bpms.count)
                session.maxHeartRate = Double(bpms.max() ?? 0)
                session.heartRateSamples = try? JSONEncoder().encode(hrSamples)
                try? viewContext.save()
            }
            isFetchingHR = false
        }
    } label: {
        HStack(spacing: 6) {
            if isFetchingHR {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "heart.text.clipboard")
            }
            Text("Fetch Heart Rate from HealthKit")
        }
    }
    .disabled(isFetchingHR)
}
```

Add it to the body VStack (after charts, before Strava section):

```swift
if session.heartRateSamples == nil {
    fetchHeartRateButton
}
```

- [ ] **Step 5: Replace Strava upload button with Strava section**

Replace the existing `stravaReuploadButton` condition in the body with:

```swift
stravaSection
```

Add a new computed property:

```swift
private var stravaSection: some View {
    HStack {
        if let activityId = session.stravaActivityId {
            Button {
                if let url = URL(string: "https://www.strava.com/activities/\(activityId)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                    Text("View on Strava")
                }
            }
        }

        if StravaManager.shared.isConnected && !session.samples.isEmpty {
            Button {
                isUploading = true
                uploadResult = nil
                Task {
                    do {
                        let activityId = try await StravaManager.shared.reuploadSession(session)
                        if let activityId {
                            session.stravaActivityId = String(activityId)
                            try? viewContext.save()
                        }
                        uploadResult = .success
                    } catch {
                        uploadResult = .failure(error.localizedDescription)
                    }
                    isUploading = false
                }
            } label: {
                HStack(spacing: 6) {
                    if isUploading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.to.line")
                    }
                    Text(session.stravaActivityId != nil ? "Re-upload to Strava" : "Upload to Strava")
                }
            }
            .disabled(isUploading)
        }

        if let result = uploadResult {
            switch result {
            case .success:
                Label("Uploaded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            case .failure(let msg):
                Label(msg, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
    }
}
```

Remove the old `stravaReuploadButton` computed property entirely.

- [ ] **Step 6: Build to verify**

Run: `xcodebuild build -scheme Treadmill -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add Treadmill/Views/SessionDetailView.swift
git commit -m "feat: add HR stats, HR chart, Strava link, and fetch HR button to session detail"
```

---

### Task 7: History Window — Status Icons in Session Row

**Files:**
- Modify: `Treadmill/Views/HistoryWindow.swift:63-80`

- [ ] **Step 1: Add Strava and HR icons to SessionRow**

Update the `SessionRow` body (line 66-79). Add icons after the existing HStack:

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 4) {
        HStack {
            Text(session.date, style: .date)
                .font(.headline)
            Spacer()
            if session.stravaActivityId != nil {
                Image(systemName: "arrow.up.to.line")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .help("Uploaded to Strava")
            }
            if session.heartRateSamples != nil {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .help("Heart rate data available")
            }
        }
        HStack(spacing: 12) {
            Label(session.durationFormatted, systemImage: "clock")
            Label(String(format: "%.2f km", session.distanceKm), systemImage: "figure.walk")
            Label("\(session.calories) cal", systemImage: "flame")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme Treadmill -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Treadmill/Views/HistoryWindow.swift
git commit -m "feat: add Strava and heart rate status icons to session list"
```

---

### Task 8: Final Build + Integration Test

- [ ] **Step 1: Full clean build**

Run: `xcodebuild clean build -scheme Treadmill -destination 'platform=macOS' 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Run existing tests**

Run: `xcodebuild build-for-testing -scheme Treadmill -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** TEST BUILD SUCCEEDED **`

- [ ] **Step 3: Verify no regressions in SessionTracker tests**

The existing `SessionTrackerTests` should still pass — the `saveSession` changes don't affect the Core Data save path for duration/distance/calories, only add a delayed Task for HR + Strava.

- [ ] **Step 4: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: address build issues from HR + Strava integration"
```
