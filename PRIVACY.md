# CAPTURR Privacy Policy

Last updated: August 3rd, 2026

CAPTURR is a privacy-focused iOS application for capturing content to Roam Research. CAPTURR does not operate a backend service and does not collect app data for its developer, Paul Griffiths.

In normal use, your information stays on your device or is sent directly to Roam Research at your request so that CAPTURR can perform its core function.

## What CAPTURR does not collect

CAPTURR does not include:

- Analytics or behavioural tracking.
- Advertising or advertising identifiers.
- Third-party analytics, tracking, or advertising SDKs.
- A developer-operated account system, database, or server.
- Remote logging or telemetry sent to the developer.
- Location, contacts, or browsing-history collection.

The Application uses Apple's system logging for local diagnostic messages. CAPTURR does not transmit those logs to the developer. If you choose to share diagnostics with Apple, Apple handles that information under its own terms and privacy settings.

## Information stored on your device

CAPTURR stores the information required to provide its features locally on your device. Depending on the features you use, this can include:

- Roam Research graph names and API credentials.
- Notes, TODOs, scans, voice transcripts, shared text, and URLs that you capture.
- Pending, successful, and failed capture history.
- Locally cached TODO content retrieved from your Roam Research graph.
- App settings, capture destinations, tags, and display preferences.
- Audio awaiting transcription or retained after an unsuccessful transcription.
- Link titles, descriptions, and image URLs obtained for Roam Reader captures.

Roam Research API credentials are stored in the iOS Keychain. Other app data is stored in CAPTURR's local app-group container so it can be used by the main app, widgets, shortcuts, and share extension. CAPTURR does not use CloudKit or its own cloud-storage service for this information.

## Information sent to Roam Research

CAPTURR sends information directly to Roam Research when you use a feature that requires access to your graph. This is the core purpose of the Application.

Depending on the feature, the information sent can include:

- Your graph name and the relevant Roam Research API credential.
- Content you have chosen to capture, including text, TODOs, transcripts, scanned text, URLs, and link metadata.
- Capture destinations, tags, timestamps, or block identifiers needed to perform the requested action.
- Queries required to retrieve and manage TODO content from your graph.

These requests are sent over HTTPS to Roam Research's APIs. Information received or stored by Roam Research is governed by your relationship with Roam Research and its own terms and privacy practices. CAPTURR and Paul Griffiths are not affiliated with Roam Research and do not receive a copy of this information.

You control whether CAPTURR connects to Roam Research by choosing whether to provide API credentials and use features that communicate with your graph.

## Webpage metadata

If you enable Roam Reader support and share a web link, CAPTURR may request that webpage directly to obtain its title, description, and image metadata. The website receives an ordinary web request and may see information normally associated with such a request, including your IP address, user agent, and the requested URL.

The website does not receive your Roam Research API credential, graph information, CAPTURR history, or other captures. Any metadata obtained is processed locally and may then be sent to your Roam Research graph as part of the capture you requested. The website's own privacy policy applies to its handling of the request.

## Camera, microphone, speech, and Watch features

CAPTURR requests access to protected device features only when they are required for a feature you choose to use.

- Document scanning and text recognition are performed on-device.
- Voice recordings and speech transcription are processed on-device. CAPTURR may download language models supplied by Apple, but captured voice audio is not sent to Apple for transcription.
- Audio captured on a paired Apple Watch may be transferred to your iPhone using Apple's WatchConnectivity system for on-device transcription and delivery to Roam Research.

You can manage camera, microphone, and speech-recognition permissions through iOS Settings.

## Retention and deletion

CAPTURR retains local information only as needed to provide the features you use:

- Capture history remains on-device until you delete individual entries or use CAPTURR's history-clearing options.
- Locally cached TODO content is removed when TODO management is disabled and is otherwise refreshed as you use the feature.
- Audio is normally deleted after successful transcription. Audio associated with a failed or interrupted transcription may remain so that you can retry or delete the history entry.
- Credentials remain in the iOS Keychain until they are replaced or removed. Deleting an additional graph from CAPTURR also removes its stored credential.

You can revoke any CAPTURR API credential through Roam Research at any time. Revoking a credential prevents it from being used even if a copy remains on the device.

Deleting CAPTURR removes its local app container in accordance with iOS behaviour. Because Keychain retention is controlled by iOS, revoke your Roam Research credentials separately to ensure they cannot be used after uninstalling CAPTURR or disposing of your device.

CAPTURR cannot delete content that has already been sent to your Roam Research graph; manage that content and your Roam account directly through Roam Research.

Because CAPTURR does not operate a user account or backend database, there is no server-side CAPTURR account or capture history for the developer to delete.

## Children

CAPTURR is not directed at children and the developer does not knowingly collect personal information from children through the Application.

## Security

CAPTURR uses platform security features including the iOS Keychain and encrypted HTTPS connections. No method of storage or transmission is completely secure, so you are responsible for protecting your device, Roam Research account, and API credentials.

If you believe an API credential has been exposed, revoke or rotate it promptly through Roam Research.

## Changes to this policy

This policy may be updated when CAPTURR's features or data practices change. The current version will be published in this repository with its effective date shown above.

## Contact

For privacy questions or requests concerning information you have sent directly to the developer, contact Paul Griffiths at tenth_tickles.9x@icloud.com.
