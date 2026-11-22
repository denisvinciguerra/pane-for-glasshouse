# Changelog

All notable changes to Pane for Glasshouse. Versions follow [Semantic Versioning](https://semver.org).

## 1.3.0

- Demo: "Try without a TV" has the pointer's touchpad and keyboard, and a full Apps grid.
- Apps: a new tab, second after Remote, lists every app on the TV, system apps included: click one to launch it, or open the list with "Pin…" and pin any app in one click. iOS: Game moves to More.
- Remote: the classic keys (Back, Home, Settings, D-pad and Pointer, the arrows, playback, volume, Mute, Power) show a fine-line icon instead of a word, drawn after Glasshouse's own remote; the word shows on hover and for VoiceOver. The key that swaps the d-pad and the pointer's pad has a stronger edge, to stand out from its row.
- Pointer: when the TV's Glasshouse offers it (0.146 or later, Pointer input turned on in Server › Experimental features), the Remote's Pointer key swaps the d-pad for a trackpad. On the Mac, click and drag, or hold ⌥ and move the mouse, as picked above the pad (the Mac cursor stays on the pad meanwhile), click to select, right-click to go back, scroll with the wheel or two fingers; on iPhone and iPad, slide to move, tap to click, two fingers to scroll. Contributed by Kirill Klenovich ([@clima365](https://github.com/clima365)).
- Pointer: type on the TV from the pointer's pad. On the Mac, type directly; on iPhone and iPad, tap the keyboard icon. Letters light up as they arrive and fade out ten seconds later; Return submits, Esc clears. While the pad shows on the Mac, keys type instead of pressing their buttons; Space with nothing typed still plays or pauses.
- Mac: the Picture tab's mode menu takes its own width, so a long mode name (HDR Game) is no longer cut short.
- Mac: the search for TVs no longer reports local network access as blocked only because the SSDP search was refused while the subnet probes went through.
- iOS: turn the TV on from deep standby with Wake-on-LAN, and find it on the network right away instead of scanning the subnet (Apple granted the multicast entitlement).
- Look: the d-pad is a ring, as on Glasshouse's own remote, and the key back to it shows the ring's chevrons; keys, menus and fields have rounded corners and softer edges; names and numbers are set in Outfit; settings get round-thumb sliders, switches, and group titles over a rule. The app's own on/off settings are switches too.
- iOS: the ↗ of the links to the dashboard and the web, and the ↩ of the Return key in shortcuts, no longer show as blue emoji.
- iPhone: on a tall screen, the Remote's spare room goes above and below the d-pad (or the pointer's pad) instead of piling up under the volume.

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
