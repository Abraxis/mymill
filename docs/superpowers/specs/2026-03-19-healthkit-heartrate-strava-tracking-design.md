# HealthKit Heart Rate + Strava Activity Tracking

## Summary

Add heart rate data to treadmill sessions by querying Apple HealthKit retrospectively after each session ends. Also track Strava upload status with activity IDs to show upload state and link to Strava web UI.

## Data Model Changes

### WorkoutSession (CoreDataModel.swift + WorkoutSession+CoreData.swift)

New attributes:
- `avgHeartRate: Double` (default 0.0)
- `maxHeartRate: Double` (default 0.0)
- `heartRateSamples: Data?` (optional, JSON-encoded)
- `stravaActivityId: String?` (optional)

Heart rate sample struct (in WorkoutSession extension):
```swift
struct HeartRateSample: Codable {
    let time: Double  // seconds since session start
    let bpm: Int
}
```

This is separate from the existing `Sample` struct because HR comes from a different source (HealthKit/Apple Watch) at different intervals (~3-5s) than treadmill speed/incline samples (~1s).

## HealthKit Integration

### Read Permissions

Add `HKQuantityType(.heartRate)` to `readTypes` in `HealthKitManager`. This requires the user to grant read access to heart rate data (authorization prompt will update automatically).

### New Method: fetchHeartRateSamples

```
func fetchHeartRateSamples(from startDate: Date, to endDate: Date) async -> [(date: Date, bpm: Double)]
```

- Queries `HKQuantityType(.heartRate)` with `HKQuery.predicateForSamples(withStart:end:)`
- Sorted ascending by start date
- Returns empty array if no data found (Apple Watch not worn, Garmin not synced, etc.)
- Used by both automatic post-session fetch and on-demand detail view fetch

### Source Compatibility

- **Apple Watch**: HR samples are written automatically during any active workout. User should start a workout on the watch (e.g., Indoor Walk) alongside the treadmill session.
- **Garmin Fenix 7**: HR data syncs to HealthKit via Garmin Connect app. Sync may be delayed, which is why on-demand re-fetch from the detail view is important.

## Session Tracker Changes

### Post-Session Flow (saveSession)

Current flow:
1. Save to Core Data
2. Save to HealthKit (fire-and-forget)
3. Upload to Strava (fire-and-forget)

New flow:
1. Save to Core Data (without HR — not yet available)
2. Save to HealthKit (fire-and-forget, unchanged)
3. Spawn delayed Task:
   a. Wait 15 seconds (let Apple Watch flush HR samples to HealthKit)
   b. Query HealthKit for HR samples in session time window
   c. Convert to relative timestamps (subtract session start date)
   d. Compute avg/max HR
   e. Update Core Data session with HR data
   f. Upload to Strava (with HR data if available)
   g. Store returned Strava activity ID on Core Data session

The 15s delay is a pragmatic choice — Apple Watch typically syncs HR within a few seconds, but we allow some margin. If no HR data is found, the Strava upload proceeds without it.

## Strava Changes

### Upload Return Value

`uploadWorkout` currently returns nothing. Change to return `Int64?` (the Strava activity ID).

`checkUploadStatus` response JSON contains `activity_id` when processing is complete. Extract and return it.

Both `uploadWorkout` and `reuploadSession` return the activity ID so it can be stored on the Core Data session.

### Heart Rate in TCX

Add optional `heartRateBPM: Int?` to `TCXGenerator.TrackPoint`.

When present, emit in the trackpoint XML:
```xml
<HeartRateBpm><Value>72</Value></HeartRateBpm>
```

HR samples from HealthKit won't align 1:1 with speed sample timestamps. Interpolation strategy: for each speed sample timestamp, find the nearest HR sample (nearest-neighbor). This is simple and accurate enough given the ~1s speed sampling vs ~3-5s HR sampling.

### Upload Signature Change

`uploadWorkout` and `reuploadSession` gain a new parameter:
```
heartRateSamples: [(timeOffset: TimeInterval, bpm: Int)]
```

These are merged into the TCX trackpoints during generation.

## UI Changes

### SessionDetailView

**New stat cards** (in summaryGrid, when avgHeartRate > 0):
- Avg HR with `heart.fill` icon
- Max HR with `heart.fill` icon (or `bolt.heart.fill`)

**New chart** (when heartRateSamples is populated):
- "Heart Rate Over Time" — red `LineMark`, same style as speed/incline charts
- X-axis: minutes, Y-axis: BPM

**Strava section** (replaces current upload button):
- If `stravaActivityId` is set: show Strava badge/link that opens `https://www.strava.com/activities/{id}` in browser
- If not set: show existing "Upload to Strava" button (which now saves the activity ID on success)

**Fetch Heart Rate button**:
- Appears when `heartRateSamples` is nil and session has a valid date range
- Queries HealthKit, updates Core Data, refreshes the view

### HistoryWindow (SessionRow)

Add icons to the row's HStack:
- Small Strava icon (e.g., `arrow.up.to.line` or custom) when `stravaActivityId != nil`
- Small heart icon (`heart.fill`) when `heartRateSamples != nil`

These give at-a-glance visibility into which sessions have HR data and Strava uploads.

## Files to Modify

1. `Treadmill/Models/CoreDataModel.swift` — add 4 new attributes
2. `Treadmill/Models/WorkoutSession+CoreData.swift` — add properties, HeartRateSample struct, computed helpers
3. `Treadmill/Services/HealthKitManager.swift` — add heartRate to readTypes, add fetchHeartRateSamples method
4. `Treadmill/Services/SessionTracker.swift` — restructure saveSession for delayed HR fetch + Strava upload
5. `Treadmill/Services/StravaManager.swift` — return activity ID from uploads, accept HR samples
6. `Treadmill/Services/TCXGenerator.swift` — add heartRateBPM to TrackPoint, emit in XML
7. `Treadmill/Views/SessionDetailView.swift` — HR stats, HR chart, Strava link, fetch HR button
8. `Treadmill/Views/HistoryWindow.swift` — Strava and HR icons in SessionRow

## Edge Cases

- **No HR data available**: Strava upload proceeds without HR. UI shows "Fetch Heart Rate" button for later retry.
- **Garmin sync delay**: User can re-fetch HR from detail view after Garmin Connect syncs to HealthKit.
- **Strava upload fails**: Activity ID remains nil. User can re-upload from detail view (existing functionality).
- **Multiple HR sources**: HealthKit merges samples from all sources. If both Apple Watch and Garmin are writing HR, HealthKit handles deduplication.
- **Old sessions**: `heartRateSamples` and `stravaActivityId` are optional with nil defaults, so existing sessions are unaffected. User can fetch HR retroactively for past sessions if HealthKit still has the data.
