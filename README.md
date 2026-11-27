<p align="center"><img src="App/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="Pane for Glasshouse icon"></p>

# Pane for Glasshouse

A remote for an LG webOS TV running [Glasshouse](https://github.com/rorygallagher2024/glasshouse), on the Mac (in the menu bar), iPhone and iPad: remote control, sources, Picture, Audio and Game settings, HDMI ports and metrics, without opening the web dashboard. The rest of the dashboard opens from a link, on the right tab.

<p align="center"><a href="https://apps.apple.com/app/id6830095172"><strong>iPhone and iPad: App Store</strong></a> · <a href="#install"><strong>Mac: Homebrew or DMG</strong></a></p>

<p align="center"><img src="docs/screenshots/hero.png" width="830" alt="Pane's popover under its menu-bar icon: remote, inputs, and pinned Apple TV, Netflix and Spotify tiles"></p>

- Settings are drawn from what the server sends, so a setting added on the server appears without updating the app.
- Apps: Recent apps keeps the TV’s recent order (with the app on screen added at the top when omitted by the TV), marks apps on screen or in memory and shows RAM use for running apps. Other running apps appear below under In background. Select an app to open it; closing a recent card stops its app and removes the card, while background apps are stopped without changing the recent list. Closing the on-screen app asks for confirmation. Close all stops the apps in both lists and removes recent cards after confirmation; any failures remain visible. The list refreshes on screen-app changes, after closing apps and every ten seconds while visible.
- Apps: a tab with every app on the TV: click to launch, pin any of them in one click.
- Pinned items: a setting or a sequence of actions on the Remote tab. A pin that launches an app can show the app's icon. Triggered while the TV is off, it turns the TV on first.
- Power from any state: on, Active Standby and LG's Always Ready screen. Wake-on-LAN too, for a TV in deep standby.
- Pointer: control the TV's cursor like a mouse, from a pad in place of the d-pad on the Remote tab: on the Mac, click and drag, or hold ⌥ and move the mouse (a switch above the pad picks the gesture), and right-click to go back; slide a finger on iPhone and iPad; click and scroll too, and type text into the TV's search fields. It needs Glasshouse 0.146 or later with Pointer input turned on (Server › Experimental features).
- iPhone Motion pointer: choose Motion above the touchpad, hold the pad and turn the phone to move the cursor, release to reposition, tap to click and use two fingers to scroll. Pointer settings beside the keyboard offer separate sensitivity and vibration switches for Touchpad and Motion. The border highlights movement and flashes on clicks. Motion requests 60 Hz to balance responsiveness and energy use; the rate can be raised if needed. Each sensor sample is processed once, using its own timestamp. Motion runs only while held; sensors and frame callbacks stop on release, when covered or when the app becomes inactive. Unsent moves are discarded on release. Motion requires an iPhone with a gyroscope.
- Several TVs, dark and light themes, English and French.

On the Mac:

- Keyboard remote while the popover is open: Arrows and Gaming profiles (by key position, whatever the keyboard layout), and every key can be changed in a Custom profile kept apart.
- Global shortcuts: a key combination for a button, an input, an action or a pinned item that works in any app, with a small card under the menu-bar icon.

## Screenshots

On iPhone, shown here with the app's demo TV:

<table>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/iphone-remote.png" width="253" alt="Pane on an iPhone: the whole remote on one screen, with sources and pinned apps"><br><sub>The whole remote on one screen</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/iphone-apps.png" width="253" alt="Pane on an iPhone: the Apps tab, every app on the TV in a grid"><br><sub>Every app on the TV, one tap away</sub></td>
  </tr>
</table>

On the Mac:

<table>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/keys-dark.png" width="328" alt="Remote tab with the keyboard keys and global shortcuts shown"><br><sub>Keys and global shortcuts, set from the bottom bar</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/pointer-light.png" width="328" alt="Remote tab in light theme, with the pointer's trackpad in place of the d-pad"><br><sub>Pointer trackpad, light theme</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/picture-dark.png" width="328" alt="Picture tab"><br><sub>Picture settings, as the TV sends them</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/hdmi-dark.png" width="328" alt="HDMI tab"><br><sub>HDMI ports, receiver and settings</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/game-dark.png" width="328" alt="Game tab"><br><sub>Game settings</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/stats-dark.png" width="328" alt="Stats tab"><br><sub>Live statistics</sub></td>
  </tr>
</table>

## Install

**iPhone and iPad:** [Pane for Glasshouse on the App Store](https://apps.apple.com/app/id6830095172), free.

**Mac:**

```sh
brew install --cask denisvinciguerra/tap/pane-for-glasshouse
```

Or download the DMG from the [releases](https://github.com/denisvinciguerra/pane-for-glasshouse/releases) and drag Pane to Applications.

## Requirements

- macOS 14 (Sonoma) or later, or iOS 17 or later (iPhone and iPad).
- An LG webOS TV running Glasshouse (port 8080 by default).

## Adding a TV

On first launch Pane shows a welcome screen and looks for TVs on the network. On the Mac, the popover opens by itself and searches by SSDP, then on the Mac's subnet on port 8080; on iPhone and iPad, the welcome screen searches the same way. Otherwise, type the TV's address (for example `192.168.1.20`; port 8080 by default) or paste a dashboard link: its `k=` parameter carries the token.

<p align="center"><img src="docs/screenshots/welcome-dark.png" width="328" alt="Welcome screen: searching the network for a TV, or typing its address"></p>

macOS asks for local network access the first time Pane searches (iOS too, on iPhone and iPad). On the Mac, if it was denied, Pane says so and points to System Settings › Privacy & Security › Local Network.

With several TVs on the Mac, the ⌄ menu in the header switches TV, and Preferences › TV manages them.

## iPhone and iPad

The same remote, for the couch: sources, pinned apps and actions, the pad and volume on one screen, every app on the TV under Apps (tap to launch, long-press to pin), Picture, Audio, Game, HDMI and Stats under tabs, and the other TVs as chips showing what they are doing (reading only). Pane for Glasshouse is [on the App Store](https://apps.apple.com/app/id6830095172), free; updates come from the App Store.

- iPhone: the remote fits one screen. iPad in landscape: two columns, the remote on the right by default (Settings › Remote column › Left swaps them). Portrait, Split View and Slide Over use the iPhone layout.
- Settings are touch-friendly, with an ⓘ that explains each one. The pins editor reorders by dragging a tile.
- With a hardware keyboard on an iPad, the Arrows, Gaming and Custom profiles work while Pane is in front.
- No global shortcuts, no menu-bar icon and no hardware volume buttons: iOS offers no equivalent for an app like this. Pane does nothing in the background.
- "Try without a TV" (on the welcome screen and in Settings) runs the whole app against a demo TV.
- iOS asks for local network access the first time Pane searches for a TV.
- Tokens are stored in the iOS keychain. There is no iCloud sync: each device is set up on its own.

What differs from the Mac:

- **A TV with a token that changed address must be found again by hand.** iOS does not let an app read the ARP table, so nothing proves which host carries the TV's MAC address, and the token is never sent to an unproven host. Pane says the TV is not found and offers to search again or to type the new address. A TV saved without a token is still found again by its MAC address.

## Updates

On iPhone and iPad, updates come from the App Store.

On the Mac, Pane uses [Sparkle](https://sparkle-project.org). It checks once a day by default; change this in Preferences › General › Updates (Check automatically, Check Now). When an update is found while Pane is not in front, you get a system notification, a dot on the menu-bar icon and a bar in the popover. Installing opens Sparkle's window with the release notes.

## Privacy

- A TV's token is only ever sent to that TV's saved address. If the TV changed IP address, the Mac app looks for it without any token and sends the token only to the host whose MAC address matches: the one in the Mac's ARP table or, when the table has none for that host, the one in the server's stats. It only looks for a TV saved by an IP address on the Mac's current network, and waits longer between searches while it stays lost (5, 15, then 60 minutes). iOS cannot read the ARP table, so on iPhone and iPad a TV with a token is found again by hand.
- Tokens are stored in the macOS keychain (the iOS keychain on iPhone and iPad). The iOS app collects no data: no telemetry, no account, no iCloud.
- To find TVs (on the add screen, or when a saved TV stops answering on the same network), Pane probes the Glasshouse port (8080 by default) on the device's local subnet, and sends an SSDP search. Turning on a TV in deep standby sends a Wake-on-LAN packet on the local network. Apart from that and, on the Mac, Sparkle's update checks to GitHub (the appcast and, when you install an update, the DMG), it only talks to your TVs. No telemetry.

## Building

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project Pane.xcodeproj -scheme Pane -configuration Release -scmProvider system build
swift test --package-path PaneKit
```

The testable logic is in the `PaneKit` package. The Mac app is in `App/`, the iPhone and iPad app in `iOSApp/`, and what they share (the model, theme and views) in `Shared/`; all SwiftUI. The iOS app builds with `xcodebuild -project Pane.xcodeproj -scheme "Pane iOS" -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` (a device build needs your own signing team; a Release device build or an archive also needs Apple's multicast entitlement, so without it remove `CODE_SIGN_ENTITLEMENTS` from `project.yml`; a build without the entitlement, such as a Debug build, finds TVs by sweeping the subnet and cannot wake a TV from deep standby). Local builds are ad hoc signed. `-scmProvider system` avoids a keychain prompt when Xcode resolves Sparkle. Releases are signed with a Developer ID and notarized by the maintainer. A source build and the released app are signed differently, so after switching from one to the other macOS asks once per saved token for access to the keychain.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security issues: [SECURITY.md](SECURITY.md). Changes between versions: [CHANGELOG.md](CHANGELOG.md).

## Credits

- [Glasshouse](https://github.com/rorygallagher2024/glasshouse) by Rory Gallagher (MIT). The test fixture `PaneKit/Tests/PaneKitTests/Fixtures/ui.html` is a recorded copy of its dashboard page, under the same licence.
- [Manrope](https://github.com/googlefonts/manrope), SIL Open Font License (`Shared/Resources/Fonts/OFL.txt`).
- [Outfit](https://github.com/Outfitio/Outfit-Fonts), SIL Open Font License (`Shared/Resources/Fonts/Outfit-OFL.txt`).
- [Sparkle](https://sparkle-project.org) (MIT).

## Disclaimer

An independent project, not affiliated with or endorsed by LG Electronics or the Glasshouse project. webOS is a trademark of LG Electronics. Pane sends commands to your TV, including power; use it at your own risk.

## License

MIT, see [LICENSE](LICENSE).
