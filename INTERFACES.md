# CAPTURR Interface Reference

CAPTURR is an end-user iOS application. It does not provide a public server API,
REST endpoint, command-line interface, library API, or SDK. Its supported external
interfaces are the app screens, the iOS share extension, URL routes, App Intents
and Shortcuts, widgets and system controls, and the Apple Watch app.

Unless a section says otherwise, capture-producing interfaces save their output
to CAPTURR's durable on-device outbox. A successful result means that the capture
was **queued locally**; it does not mean that Roam Research has received it yet.
CAPTURR sends queued work when network access and the required graph credentials
are available. Delivery state and errors are visible in the app's History screen.

## Configuration and destinations

Before using a capture interface, configure CAPTURR with a Roam Research graph
and API token. Additional graphs can be configured in the app. Where an interface
offers a Graph input, the available values are the primary graph and those
additional configured graphs.

A capture can use CAPTURR's configured defaults or override these destination
settings where the interface supports them:

- **Graph** selects the target Roam graph.
- **Page** sends the capture to a named page instead of the configured default.
- **Nest Under** places it beneath a matching block.
- **Tags** adds the supplied tags.
- **Add Timestamp** uses the app default or explicitly enables or disables the
  timestamp.

Roam credentials are stored in the iOS Keychain. Do not put an API token in
capture text, a Shortcut name, a URL, an issue report, or any other shared data.
See [SECURITY.md](SECURITY.md) and [PRIVACY.md](PRIVACY.md) for security and data-
handling guidance.

## iPhone application

The Capture tab exposes four interactive modes:

| Mode | Input | Output |
| --- | --- | --- |
| **Write** | Text entered as paragraphs or structured blocks, with supported formatting and indentation | A queued Roam note |
| **Todo** | Text for a task | A queued Roam TODO |
| **Voice** | A microphone recording or an imported audio file | An on-device transcript queued as a Roam note; imported files enter a background transcription stage first |
| **Scan** | One or more document pages captured with the camera | Recognised paragraphs, lists, indentation, and tables, queued as a Roam note after review |

Voice transcription and document recognition take place on-device. Voice may
require an Apple speech model to be downloaded the first time a language is used.

The TODO tab is a separate management interface. It reads TODOs from a configured
graph and can create TODOs or update their completion state. This feature requires
Roam's Backend API with read and edit access and is not available for encrypted
graphs.

## Share extension

Choose CAPTURR from the iOS share sheet in an application that supplies plain text
or a URL.

| Input or control | Behaviour |
| --- | --- |
| Shared plain text | Opens the CAPTURR editor with the text, which can be changed before sending |
| Shared URL | Opens the editor with the URL or a formatted title and URL, according to the app setting |
| **Send to Graph** | Queues the edited text as a note in the selected graph |
| **Send to Roam Reader** | For URL shares when Roam Reader is enabled, queues a Reader item for the selected graph |

When multiple graphs are enabled, the extension asks for a target graph. Empty
or whitespace-only text is not queued. Roam Reader may fetch the shared webpage
directly to obtain its title and metadata before sending it to the `Reading List:
Inbox` page in Roam.

## URL routes

CAPTURR registers the `capturr` URL scheme. Each supported route opens the app at
one interactive capture screen:

| URL | Result |
| --- | --- |
| `capturr://capture/note` | Opens Write capture |
| `capturr://capture/todo` | Opens Todo capture |
| `capturr://capture/voice` | Opens Voice capture |
| `capturr://capture/scan` | Opens Scan capture |

These routes accept no query parameters, capture content, credentials, or return
value. An unknown host, path, or capture mode is not a supported route.

Home Screen and Lock Screen widgets, app-icon quick actions, the Action Button,
Control Centre controls, and other system launchers use these same capture routes.

## App Intents and Shortcuts

CAPTURR publishes three actions to Siri and Apple's Shortcuts app.

### Capture

Queues a note or TODO without opening CAPTURR's capture screen.

| Parameter | Required | Accepted value or behaviour |
| --- | --- | --- |
| **Content** | Yes | Non-empty text after surrounding whitespace is removed |
| **Type** | No | `Note` (default) or `Todo` |
| **Graph** | No | The configured primary graph or an additional configured graph; otherwise CAPTURR uses its default |
| **Page** | No | A page-name override |
| **Nest Under** | No | A parent-block text override |
| **Tags** | No | A tag override |
| **Add Timestamp** | No | `App Default` (default), `Yes`, or `No` |

The action returns one temporary **Capture Result** to the running Shortcut:

| Field | Type | Meaning |
| --- | --- | --- |
| **ID** | Text | The UUID assigned to the local outbox item |
| **Content** | Text | The trimmed content that was queued |
| **Status** | Text | `queued` when the local save succeeds |

Capture Result values are not a searchable history API and cannot be retrieved by
ID in a later Shortcut run. Use **Get Sync Status** or CAPTURR's History screen to
check later delivery state. The action reports an error if CAPTURR has not been
configured, and requests a value if Content is empty.

### Open CAPTURR

Opens the application at an interactive capture screen. Its required **Mode**
parameter accepts `Note`, `Todo`, `Voice`, or `Scan`. The action has no output.

### Get Sync Status

Reads CAPTURR's local outbox without opening the app. It has no input parameters
and returns one temporary **Capture Status** value:

| Field | Type | Meaning |
| --- | --- | --- |
| **Pending Count** | Number | Captures waiting to sync or currently syncing |
| **Failed Count** | Number | Captures whose latest delivery attempt failed |
| **Last Sync Time** | Date, optional | Time of the most recent successful capture delivery, if any |

The spoken or displayed response is `All captures synced` when Pending Count is
zero, or reports the number of captures pending sync. A zero pending count does
not imply a zero failed count; Shortcuts can inspect both returned fields.

Capture Status values are created for the current action run and cannot be queried
by ID later.

## Apple Watch

The Watch app accepts microphone audio. Tapping the control starts a recording;
tapping again stops and saves it. The Watch keeps unsent recordings locally and
shows how many are `waiting for iPhone`.

The paired iPhone receives the recording, transcribes it on-device, and places the
result into CAPTURR's normal capture outbox for delivery to Roam. The Watch does
not accept a Roam token and does not send directly to Roam.

## Delivery and failure behaviour

All queued capture sources converge on the same local outbox. CAPTURR may show
these delivery states:

- **Pending** — saved locally and waiting for a delivery attempt.
- **In progress** — a delivery attempt is running.
- **Success** — Roam accepted the capture.
- **Failed** — the latest attempt failed; the History screen provides the
  user-visible status and retry context.

Deleting or changing graph configuration can prevent pending captures for that
graph from being delivered. Review History after changing credentials or graph
settings, and do not treat an App Intent's `queued` response as remote delivery
confirmation.
