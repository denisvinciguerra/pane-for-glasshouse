# Security

## Reporting a vulnerability

Please report security issues privately, through GitHub's
[private vulnerability reporting](https://github.com/denisvinciguerra/pane-for-glasshouse/security/advisories/new),
not in a public issue. Include the version of Pane, the macOS version, and the steps to reproduce.

You should get an answer within a week. A fix goes out as a Sparkle update and a new release.

Only the latest release is supported.

## What Pane protects

- **Tokens.** A TV's Glasshouse token is stored in the macOS keychain and only sent to that TV's
  saved address. When a TV changes IP address, Pane looks for it without any token and sends the
  token only to the host whose MAC address matches, taken from the Mac's ARP table.
- **Network.** Pane only talks to your TVs on the local network, and to GitHub for update checks.
  To find TVs it sends an SSDP search and probes the Glasshouse port on the Mac's own subnet.
- **Updates.** Releases are signed with a Developer ID and notarized by Apple. Sparkle checks each
  update's EdDSA signature against the key built into the app before installing it.

## Out of scope

- **Glasshouse itself** (the server on the TV, its dashboard and its token): report those to
  [Glasshouse](https://github.com/rorygallagher2024/glasshouse).
- **The local network.** Glasshouse serves plain HTTP on the LAN; anyone on the same network can
  see its traffic. Don't expose the TV's port to the internet.
