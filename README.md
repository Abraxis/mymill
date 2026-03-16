# MyMill

macOS menu bar app for controlling a **Merach T25 treadmill** via Bluetooth (FTMS protocol).

[![Build and Test](https://github.com/Abraxis/mymill/actions/workflows/build.yml/badge.svg)](https://github.com/Abraxis/mymill/actions/workflows/build.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Menu bar controls** — start, stop, pause, adjust speed and incline from the status bar
- **Auto-connect** — scans and connects to your Merach T25 automatically on launch
- **Quick presets** — one-click speed/incline presets (Walk, Brisk, Hill, or custom)
- **Session tracking** — auto-records workouts with distance, time, calories, speed over time
- **Workout history** — browse past sessions with charts (speed/incline over time, weekly trends)
- **Interval programs** — create multi-segment workouts with speed, incline, and time/distance/calorie goals
- **Strava sync** — auto-uploads completed workouts to Strava as indoor walking activities with per-sample speed data
- **Apple Health** — ready to sync workouts when HealthKit becomes available on macOS
- **Settings** — configurable speed/incline steps, session duration threshold, quick presets, launch at login

## Requirements

- macOS 14 (Sonoma) or later
- Merach T25 treadmill (or compatible FTMS Bluetooth treadmill)
- Bluetooth enabled
- Strava account (optional, for workout sync)

## Install

### Download

Grab the latest `.dmg` or `.zip` from [Releases](https://github.com/Abraxis/mymill/releases).

### Build from source

```bash
# Install xcodegen (one time)
brew install xcodegen

# Clone and build
git clone https://github.com/Abraxis/mymill.git
cd tmill
xcodegen generate
xcodebuild build -project Treadmill.xcodeproj -scheme Treadmill \
  -configuration Release -destination 'platform=macOS' SYMROOT=build

# Run
open build/Release/Treadmill.app
```

Or open `Treadmill.xcodeproj` in Xcode and hit Cmd+R.

## Usage

1. **Turn on your Merach T25** using its remote control
2. **Launch Treadmill** — it appears as a walking icon in the menu bar
3. The app auto-connects via Bluetooth (status shown in the dropdown)
4. **Click the menu bar icon** to see live stats and controls
5. Use **Start/Stop/Pause** and **Speed +/-** to control the treadmill
6. **Quick presets** let you switch speed/incline with one click

### Menu bar

| State | Menu bar shows |
|-------|---------------|
| Disconnected | Walking icon only |
| Connected, idle | Walking icon only |
| Running | Walking icon + current speed (e.g. `3.5`) |

### Settings

Access from the menu dropdown > **Settings...**

**General tab:**
- Launch at login
- Apple Health sync status
- Strava connection and auto-sync toggle
- Minimum session duration (sessions shorter than this aren't saved)
- Speed/incline step sizes for the +/- buttons
- Treadmill speed and incline limits

**Quick Presets tab:**
- Create named presets with specific speed and incline values
- Presets appear in the menu dropdown for one-tap changes
- Default presets: Walk (3.0 km/h), Brisk (5.0 km/h, 2%), Hill (3.0 km/h, 12%)

### Strava Integration

1. Open **Settings > General > Strava**
2. Click **Connect to Strava** — browser opens for authorization
3. Approve access and return to the app
4. Enable **Auto-sync workouts**
5. Completed treadmill sessions are uploaded automatically as indoor walking activities

Uploaded data includes:
- Activity type: Walk (indoor/trainer)
- Per-sample speed data (TCX format, every 5 seconds)
- Total distance, duration, and calories
- Cumulative distance per trackpoint for pace analysis

### Workout Programs

Access from **Edit Programs...** in the menu.

Create interval programs with multiple segments. Each segment has:
- Target speed (km/h) — editable via text field or stepper
- Target incline (%) — editable via text field or stepper
- Goal: time (minutes), distance (meters), or calories

## Architecture

```
Treadmill/
├── Bluetooth/
│   ├── FTMSProtocol.swift          # BLE FTMS encode/decode (pure logic, fully tested)
│   └── TreadmillManager.swift      # CoreBluetooth scan/connect/command
├── Models/
│   ├── TreadmillState.swift        # Observable live state
│   ├── CoreDataModel.swift         # Programmatic Core Data model
│   └── *+CoreData.swift            # Managed object subclasses
├── Services/
│   ├── PersistenceController.swift # Core Data stack
│   ├── SessionTracker.swift        # Auto-record workouts
│   ├── ProgramEngine.swift         # Run interval programs
│   ├── SettingsManager.swift       # UserDefaults + quick presets
│   ├── HealthKitManager.swift      # Apple Health integration (ready when available)
│   ├── StravaManager.swift         # Strava OAuth2 + TCX upload
│   └── TCXGenerator.swift          # Generate TCX files from speed samples
└── Views/
    ├── TreadmillApp.swift          # App entry, MenuBarExtra, menu content
    ├── HistoryWindow.swift         # Session list + trends
    ├── SessionDetailView.swift     # Per-session charts
    ├── TrendsView.swift            # Weekly/monthly charts
    ├── ProgramEditorView.swift     # Create/edit programs
    └── SettingsView.swift          # General + Presets tabs
```

## FTMS Protocol

Uses the standard Bluetooth **Fitness Machine Service (FTMS)** protocol:

| Characteristic | UUID | Usage |
|---------------|------|-------|
| Treadmill Data | `0x2ACD` | Live speed, distance, incline, calories, time |
| Control Point | `0x2AD9` | Start, stop, set speed/incline |
| Machine Status | `0x2ADA` | Belt started/stopped events |
| Training Status | `0x2AD3` | Training mode changes |

**Treadmill limits:** Speed 1.0–6.5 km/h, Incline 0–12%

## Development

```bash
# Generate Xcode project
xcodegen generate

# Build (unsigned, for development)
xcodebuild build -project Treadmill.xcodeproj -scheme Treadmill \
  -destination 'platform=macOS' SYMROOT=build

# Run tests (33 tests: FTMS protocol, session tracker, program engine)
xcodebuild test -project Treadmill.xcodeproj -scheme Treadmill \
  -destination 'platform=macOS'

# Package DMG + ZIP
./scripts/build.sh && ./scripts/create-dmg.sh

# Create GitHub release
./scripts/release.sh 1.0.0
```

### Code signing

Strava OAuth and HealthKit require code signing. In `project.yml`, set your `DEVELOPMENT_TEAM` or configure signing in Xcode > Signing & Capabilities.

### Strava OAuth setup

The app includes built-in Strava API credentials for the MyMill app. If you want to use your own:

1. Create an app at [strava.com/settings/api](https://www.strava.com/settings/api)
2. Set **Authorization Callback Domain** to `localhost`
3. Replace `clientID` and `clientSecret` in `Treadmill/Services/StravaManager.swift`

The OAuth flow works by:
1. Opening the browser for Strava authorization
2. Spinning up a temporary HTTP server on `localhost:8089`
3. Catching the redirect with the authorization code
4. Exchanging the code for access + refresh tokens
5. Tokens are stored locally and auto-refreshed (they expire every 6 hours)

### CI/CD

GitHub Actions workflows:
- **Build and Test** — runs on every push/PR to `main` (build + 33 unit tests)
- **Release** — triggered by `v*` tags, builds Release .app, packages DMG + ZIP, creates GitHub Release with artifacts

## License

MIT
