# Security

## Reporting a vulnerability

Please report security issues privately, through GitHub's
[private vulnerability reporting](https://github.com/denisvinciguerra/pane-for-glasshouse/security/advisories/new),
not in a public issue. Include the version of Pane, the macOS or iOS version, and the steps to reproduce.

You should get an answer within a week. A fix goes out as a new version: a Sparkle update on the Mac,
an App Store update on iPhone and iPad.

Only the latest release is supported.

## What Pane protects

- **Tokens.** A TV's Glasshouse token is stored in the system keychain and only sent to that TV's
  saved address. When a TV changes IP address, the Mac app looks for it without any token and sends
  the token only to the host whose MAC address matches, taken from the Mac's ARP table. iOS cannot
  read that table, so the iOS app never sends a token to a new address on its own.
- **Network.** Pane only talks to your TVs on the local network; the Mac app also talks to GitHub
  for update checks. To find TVs it probes the Glasshouse port on the device's own subnet; the Mac
  app also sends an SSDP search.
- **Updates.** On the Mac, releases are signed with a Developer ID and notarized by Apple, and
  Sparkle checks each update's EdDSA signature against the key built into the app before installing
  it. On iPhone and iPad, updates come through the App Store.

## Out of scope

- **Glasshouse itself** (the server on the TV, its dashboard and its token): report those to
  [Glasshouse](https://github.com/rorygallagher2024/glasshouse).
- **The local network.** Glasshouse serves plain HTTP on the LAN; anyone on the same network can
  see its traffic. Don't expose the TV's port to the internet.
