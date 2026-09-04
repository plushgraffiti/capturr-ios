# CAPTURR

[![GitHub Release](https://img.shields.io/github/v/release/plushgraffiti/capturr-ios)](https://github.com/plushgraffiti/capturr-ios/releases/latest) 
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/plushgraffiti/capturr-ios/badge)](https://scorecard.dev/viewer/?uri=github.com/plushgraffiti/capturr-ios) 
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/14446/badge)](https://www.bestpractices.dev/projects/14446)
[![CodeQL](https://github.com/plushgraffiti/capturr-ios/actions/workflows/codeql.yml/badge.svg?branch=main)](https://github.com/plushgraffiti/capturr-ios/actions/workflows/codeql.yml) 

CAPTURR is a native iOS quick-capture app for [Roam Research](https://roamresearch.com). It is designed for fast capture, reliable offline queuing, and deep integration with Apple devices.

[Download the official CAPTURR app from the Apple App Store](https://apps.apple.com/us/app/capturr-for-roam-research/id6751626906).

CAPTURR is free, has no analytics or tracking, and does not operate a developer backend. Information stays on your device unless it is sent to Roam Research as part of a feature you choose to use.

CAPTURR is an independent application and is not affiliated with, endorsed by, or sponsored by Roam Research or Apple.

## Features

### Quick capture

- Capture notes, TODOs, voice transcripts, and scanned documents.
- Preserve document structure including paragraphs, lists, indentation, and tables.
- Queue captures offline and deliver them through background sync.
- Send to Daily Notes, another page, or a nested block.
- Add optional tags and timestamps.
- Configure and quickly switch between multiple graphs.
- Capture to encrypted Roam graphs where supported by the relevant Roam API.

### Native Apple integration

- Share text and URLs from other apps using the share extension.
- Send links directly to Roam Reader with optional webpage metadata.
- Start captures from Home Screen and Lock Screen widgets.
- Use the Action Button, Control Centre, App Shortcuts, and the Shortcuts app.
- In CAPTURR 2.0, capture voice notes from Apple Watch and transcribe them on iPhone.

### TODO management

- Retrieve and manage TODOs from your Roam graph.
- Filter TODOs using include and exclude tags.
- Create custom sections with their own filters and time periods.
- Add TODOs and update their completion state from CAPTURR.
- Display the outstanding total as an app-icon badge.

TODO management uses Roam's Backend API and is not available for encrypted graphs.

## Privacy

CAPTURR does not contain analytics, behavioural tracking, advertising, remote telemetry, or third-party analytics SDKs. Roam API credentials are stored in the iOS Keychain, while captures, settings, and history are stored locally on-device.

When you use a feature that communicates with your graph, CAPTURR sends the information required for that request directly to Roam Research. Roam Reader enrichment can also request a shared webpage directly to obtain its title and metadata.

See [PRIVACY.md](PRIVACY.md) for the complete data-handling policy and [SECURITY.md](SECURITY.md) for private vulnerability reporting.

## Requirements

### Official application

- An iPhone running iOS 26 or later.
- A Roam Research account and API token.
- An Apple Watch running watchOS 26 or later for the optional Watch app.

### Building from source

- A Mac running Xcode 26 or later.
- An Apple Developer account and development team for device builds and capabilities.
- Your own bundle identifiers and App Group identifier.

CAPTURR has no external package dependencies. It is built with Swift, SwiftUI, SwiftData, App Intents, WidgetKit, Vision, Speech, and other Apple frameworks.

## Source availability

CAPTURR 2.0 is the first open-source release. Its source is available in this repository.

The source code is licensed under the [GNU General Public License v3.0](LICENSE). The CAPTURR name, icon, and branding are covered separately by the [CAPTURR Trademark Policy](TRADEMARKS.md).

Only the version published by Paul Griffiths through the Apple App Store is the official CAPTURR application. Independently built or modified versions are unofficial and must follow the source licence and trademark policy.

## Building CAPTURR

To build CAPTURR:

1. Clone the repository and open `Capturr.xcodeproj` in Xcode 26 or later.
2. Assign your own development team to the app and extension targets.
3. Replace the existing bundle identifiers with identifiers registered to your development team.
4. Create an App Group owned by your team and replace `group.com.pg.capturr.app` in:
   - `Capturr/Capturr.entitlements`
   - `Sharing/Sharing.entitlements`
   - `Capturr/Services/Support/Constants.swift`
5. Enable the same App Group for both the `Capturr` and `Sharing` targets.
6. Select the shared `Capturr` scheme and run it on an iOS 26 simulator or device.

The repository contains the following application and extension targets:

- `Capturr` — main iPhone application.
- `Sharing` — system share extension.
- `CapturrWidgetsExtension` — Home Screen and Lock Screen widgets.
- `CapturrWatch` — Apple Watch capture application.
- `CapturrWatchWidgetsExtension` — Apple Watch complications.
- `CapturrTests` — unit tests.

To perform a command-line simulator build without code signing:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
    -project Capturr.xcodeproj \
    -scheme Capturr \
    -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO \
    build
```

Run the unit tests from Xcode with **Product → Test** using the `Capturr` scheme and an installed iOS 26 simulator.

## Project structure

- `Capturr/` contains the main SwiftUI application, models, views, App Intents, and services.
- `Capturr/Services/Sync/` owns the durable outbox, background delivery, TODO synchronisation, and Watch handoff.
- `Capturr/Services/Roam/` contains the Roam Append and Backend API clients and response parsing.
- `Capturr/Services/Profile/` manages local settings and Keychain-backed credentials.
- `Capturr/Services/Audio/` and `Capturr/Services/Scan/` provide on-device transcription and document recognition.
- `Sharing/`, `CapturrWidgets/`, `CapturrWatch/`, and `CapturrWatchWidgets/` contain the app extensions and Watch experience.
- `CapturrTests/` contains the unit test suite.

Captures from the app, shortcuts, widgets, share extension, and Watch are normalised into a shared SwiftData outbox. The sync worker delivers queued work to Roam when connectivity and the required credentials are available.

## Issues and contributions

Bug reports and feature requests are welcome through [GitHub Issues](https://github.com/plushgraffiti/capturr-ios/issues). Do not include Roam API tokens, graph content, or other private data in an issue.

External code contributions and pull requests are not currently accepted. See [CONTRIBUTING.md](CONTRIBUTING.md) for the complete policy.

## Version history

### v2.0

- Added voice capture from Apple Watch with private on-device transcription on iPhone
- Added audio-file import with private on-device transcription
- Added more flexible capture timestamps
- Improved the reliability of background delivery
- Published the CAPTURR source under GPLv3

### v1.8.2

- Fixed a further edge case with background syncing from Shortcuts

### v1.8.1

- Background sync fix to allow sending to graph without opening the app
- Wrapping long line lengths for TODO items

### v1.8

- Write Capture now has blocks, indentation and basic formatting options
- Separated the Write and TODO Shortcut intents for easier action mapping
- Long-press actions added to the CAPTURR icon for write, TODO, scan, and voice capture

### v1.7

- You can now add Sections to your TODOs
- Capture methods and sync status now available for Apple Shortcuts

### v1.6

- Added multiple graph support for quick capture
- Added ability to share URLs directly to Roam Reader
- Added clear history options for all history or entries older than 30, 60, or 90 days

### v1.5

- Added TODO management functionality, available through Settings and not supported for encrypted graphs
- Various bug fixes and performance improvements

### v1.4.1

- Fixed a bug with voice capture sending concatenated in-progress transcription
- Fixed a rare occurrence of duplicate syncs when the app is backgrounded on cellular

### v1.4

- Added structured document scanning with iOS 26 to parse paragraphs, lists, and tables into your graph
- Added Home Screen and Lock Screen widgets with one-tap access to text, TODO, voice, and scan capture
- Various bug fixes and performance improvements

### v1.3

- Enhanced voice capture for all Apple-supported on-device languages
- Various bug fixes and performance improvements

### v1.2

- Added the share extension for sending text and links from other apps to your graph
- Added an optional setting to send shared URLs as formatted links
- Updated the interface for Liquid Glass
- Various bug fixes and performance improvements

### v1.1

- Added a new onboarding flow
- Various bug fixes and performance improvements
