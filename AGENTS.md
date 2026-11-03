# Working conventions

- Branch, push the branch, open a pull request. Never push to `main`.
- Build and test before saying a change works:
  `xcodegen generate`, then
  `xcodebuild -project Pane.xcodeproj -scheme Pane -configuration Debug -scmProvider system -derivedDataPath build build`,
  and `swift test --package-path PaneKit`. No new warnings.
  A change to `Shared/`, `iOSApp/` or `PaneKit/` also builds the iOS app:
  `xcodebuild -project Pane.xcodeproj -scheme "Pane iOS" -configuration Debug -scmProvider system -derivedDataPath build -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`.
- Automated tests never use the network or run processes such as `arp`: they read the fixtures in
  `PaneKit/Tests/PaneKitTests/Fixtures/`.
- Never send a command to a real TV (power, input, volume, settings) without the user's go-ahead
  each time. GET requests are fine.
- Every visible string is localized, English and French, through `String(localized:)` (app) or
  `String(localized:bundle: .module)` (PaneKit).
- A TV's token is only sent to that TV's saved address, or to the host whose MAC address matches
  it during relocation.
- Never commit a real IP address, MAC address or network name. Tests use `192.0.2.x` and
  `00:11:22:33:44:55`.
- Match the surrounding code: its comment density, naming and idioms.

# Code map

- `project.yml` - the XcodeGen project; `Pane.xcodeproj` is generated, not committed.
- `PaneKit/` - everything testable without UI:
  `API/` (HTTP client, commands), `Models/` (server payloads), `Session/` (`TVSession`: polling,
  commands, power and Wake-on-LAN; `TVConfig`: saved TVs), `Discovery/` (SSDP, subnet sweep,
  ARP table, relocation), `Keys/` (keyboard profiles), `Actions/` (pinned and custom actions),
  `Logic/` (power state, Wake-on-LAN packet, small helpers).
- `Shared/` - the model and the screens both apps show, built into each: `AppModel` (wiring),
  `Views/` (tabs, pins, action editor), `TVs/` (welcome and add screens), `Keys/` (key modes and
  their tiles), `Theme/`, `Platform.swift` (the few calls that differ on macOS and iOS), and the
  strings and fonts (`Resources/`).
- `App/` - the Mac app only: `StatusBarController` (menu-bar item and popover), `Views/` (popover
  frame and footer), `Preferences/`, `Keys/` (key bar, global shortcuts), `Updates/` (Sparkle).
- `iOSApp/` - the iPhone and iPad app.
