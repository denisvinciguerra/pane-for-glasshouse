# Changelog

All notable changes to Pane for Glasshouse. Versions follow [Semantic Versioning](https://semver.org).

## Unreleased

- Mac: the search for TVs no longer reports local network access as blocked only because the SSDP search was refused while the subnet probes went through.

## 1.2.0

- iOS: first version, for iPhone and iPad (iOS 17 or later): the whole remote on one screen, Picture, Audio, Game, HDMI and Stats under tabs, pinned apps and actions with an editor you reorder by dragging, and the other TVs shown as chips with their live state.
- iOS: on iPad in landscape, the remote and a tab side by side (the remote on the right, or on the left with Settings › Remote column); with a hardware keyboard, the Arrows, Gaming and Custom profiles.
- iOS: "Try without a TV" runs the app on a demo TV, offline.
- iOS: the demo TV's apps and inputs have invented names and icons (PearTV, NetMovies, Musicify; Pear, PS7, YBox).
- iOS: long picture mode names (HDR Cinema, HDR Filmmaker) are no longer cut in the Picture tab's title.
- iOS: a TV with a token that changed address is not found again automatically (iOS cannot read the ARP table): search again or type the new address.
- iOS: Wake-on-LAN and SSDP search wait for Apple's multicast entitlement; until then Pane sweeps the subnet and asks to keep the TV in Active Standby.

## 1.1.0

- Global shortcuts: give a button, an input or an action a key combination that works in any app, with a small card under the menu-bar icon. Set them in Settings › Keys or from the popover's keyboard icon.
- Click the keyboard icon, then a button, to set its popover key and its global shortcut from the bottom bar; the keys' edit mode (⌥-click) is gone.
- A pinned action triggered while the TV is off, from its tile, its key or its global shortcut, now turns it on first, then runs.
- Edit the pins on Remote: the pencil next to Pinned adds a pin, deletes one with its keys, or moves it by dragging. Unpin is gone from the keys' bar.
- A pinned app tile is greyed evenly while the TV is off: its icon no longer shows brighter than the colour around it.

## 1.0.0

The first public release.

- A remote for an LG webOS TV running Glasshouse, in the macOS menu bar: remote control buttons, sources, volume.
- Picture, Audio and Game settings, and HDMI ports, drawn from what the server sends.
- Live statistics from the TV.
- Power from any state: on, Active Standby, LG's Always Ready screen, and Wake-on-LAN for a TV in deep standby.
- Several TVs, found by searching the network, by address, or from a dashboard link. A TV that changed IP address is found again by its MAC address.
- Keyboard keys while the popover is open: Arrows, Gaming and Custom profiles, shared by all TVs.
- Pinned settings and custom actions, with their keys, kept for each TV. A pin that launches an app can show the app's icon instead of its title.
- Dark and light themes, English and French.
- Updates through Sparkle, with a notification when one is available.
