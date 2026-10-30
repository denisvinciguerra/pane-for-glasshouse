# Contributing to Pane for Glasshouse

Contributions are welcome. This guide covers how to propose a change, the conventions the code follows, and how to test it.

## Core principles

- **Local only.** Pane talks to your TVs and, for updates, to GitHub. No telemetry, no analytics, no account, no other server.
- **A token stays with its TV.** A TV's token is only ever sent to that TV's saved address, or to the host whose MAC address matches it when the TV moved. Any change near discovery, relocation or the API client keeps that rule.
- **The server describes, the app draws.** Picture, Audio, Game and HDMI rows come from what Glasshouse sends. Prefer reading a new field over hard-coding a list.
- **One dependency.** Sparkle, in the app target only. `PaneKit` has none.

## Working conventions

### Branches and pull requests

1. Create a branch from `main`.
2. Keep commits focused, one change each.
3. Open a pull request against `main`.

Follow-up adjustments go on the same branch, not in a new pull request. Merging is the maintainer's call.

### Commit messages and pull request descriptions

Say what changed and why, plainly. Keep pull request descriptions to what a reviewer needs.

If you use an AI coding assistant, point it at [AGENTS.md](AGENTS.md).

### Code reviews

Review comments follow [Conventional Comments](https://conventionalcomments.org/) (`praise:`, `suggestion:`, `issue:`, `nitpick:`, `question:`), so it is clear whether a comment blocks the merge.

## Code conventions

- **Swift 6, strict concurrency** (`SWIFT_STRICT_CONCURRENCY = complete`). No new warnings.
- **macOS 14** is the minimum. Gate anything newer with `if #available`.
- **Testable logic goes in `PaneKit`**: models, parsing, the API client, discovery, the session, keys and actions. The app (`App/`) is SwiftUI and AppKit, and stays thin.
- **Every visible string is localized**, in English (source) and French:
  - in the app, `String(localized:)`, catalogued in `App/Resources/Localizable.xcstrings`;
  - in `PaneKit`, `String(localized:bundle: .module)`, catalogued in `PaneKit/Sources/PaneKit/Resources/Localizable.xcstrings`.

  If you don't speak French, leave the French string empty and say so in the pull request: a maintainer fills it in.
- **The visual style** is square corners, 1 px hairlines, Manrope, small uppercase section labels. No rounded pills, gradients or emoji.

## Building and running tests

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project Pane.xcodeproj -scheme Pane -configuration Debug -scmProvider system -derivedDataPath build build
swift test --package-path PaneKit
```

`Pane.xcodeproj` is generated from `project.yml` and is not committed: edit `project.yml`, then run `xcodegen generate` again.

All tests must pass, without warnings. **Automated tests never use the network**: they read responses recorded from a real TV, in `PaneKit/Tests/PaneKitTests/Fixtures/`. `scripts/record-fixtures.sh <tv-ip>` records them again (GET requests only) and strips the TV's IP, MAC and network name.

### Previewing without a TV

Debug builds accept launch arguments for screenshots and UI work, listed at the top of `App/PaneApp.swift`. For example:

```sh
open "build/Build/Products/Debug/Pane for Glasshouse.app" --args -PaneFirstLaunch YES -PaneDemoSecondTV YES
```

`-PaneFirstLaunch YES` runs on throwaway settings and tokens. `-PaneTheme` writes the theme into your real preferences: set it back afterwards.

## Testing on a real TV

The tests cover the logic, not the TV. Before asking for a review, run the change against a TV running Glasshouse and use it the way someone would: the popover, the keys, the preferences.

- **Commands change the TV's state.** Note a setting before you change it for a test, and set it back after.
- **Power paths differ by state**: on, screen off, Active Standby, LG's Always Ready screen, deep standby (Wake-on-LAN). Say which ones you tried.

Add a short **Testing** section to the pull request:

- the TV's model, webOS version and Glasshouse version, for example "OLED65G45LW, webOS 10.3, Glasshouse 0.135";
- what you did and what you saw;
- what you didn't test.

```
## Testing

- OLED65G45LW, webOS 10.3, Glasshouse 0.135: switched HDMI 2 → HDMI 4 from a
  pinned action with its key; picture and sound followed within 2 s.
- Not tested with several TVs or with a token.
```

If you have no TV to test on, say so in the pull request.

## Releases

Releases are made by the maintainer with `scripts/release.sh` (Developer ID signing, notarization, Sparkle appcast, Homebrew cask). Contributors don't need it.
