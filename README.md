# ClipVault

A private, encrypted clipboard history that lives in the macOS menu bar.

ClipVault records the text and images you copy, lets you find and paste them again
from a keyboard-driven panel, and keeps everything on your Mac — encrypted at rest,
sandboxed, and with no network access at all.

## Features

- **Text and images** — screenshots, "Copy Image" from browsers, Preview, code, anything.
- **Fast panel** — open it with a global shortcut (default **⇧⌘V**) or the menu bar icon.
  Search as you type, filter by Text / Images / Pinned, and see a full preview.
- **Paste straight into the app you were using** — the panel never steals focus, so
  choosing an item pastes it where your cursor was (requires Accessibility permission;
  without it, the item is copied and you press ⌘V).
- **Configurable shortcuts** — record your own global shortcuts for opening the history
  and pausing capture. Conflicts with other apps are detected.
- **Pin** items to keep them forever; everything else expires on your schedule.
- **Launch at login**, automatically, once installed in `/Applications`.

### Keyboard

| Key | Action |
| --- | --- |
| ↑ ↓ | Move selection |
| ↩ | Paste selected item |
| ⇧↩ | Copy only, don't paste |
| ⌘1 … ⌘9 | Paste item 1–9 |
| ⌘P | Pin / unpin |
| ⌘⌫ | Delete item |
| ⇥ / ⇧⇥ | Switch filter |
| esc | Clear search, then close |
| ⌘, | Settings |

## Security model

| Protection | How |
| --- | --- |
| Encrypted at rest | History index and every image are sealed with **AES-256-GCM** (CryptoKit). Each file's name is authenticated, so files can't be swapped or renamed. |
| Key never on disk | The 256-bit key is generated on first launch and stored in your login **Keychain** (`WhenUnlockedThisDeviceOnly`, never synced). |
| Locked-down files | Data lives in the app's sandbox container; the directory is `0700` and files are `0600`. |
| Passwords are skipped | Copies marked with the [nspasteboard.org](http://nspasteboard.org) concealed / transient / auto-generated types (1Password, Bitwarden, Keychain Access, KeePassXC…) are never recorded. |
| Per-app exclusions | Password managers are excluded by default; add any running app in Settings › Privacy. |
| App Sandbox, no network | The only entitlement is `com.apple.security.app-sandbox`. There is no networking code and no network entitlement. Hardened runtime is enabled. |
| Bounded retention | Unpinned items expire (default 30 days) and history is capped (default 200 items). |
| Fail safe | If the Keychain is unavailable, history is kept in memory only — nothing unencrypted is ever written. If stored data fails authentication, it is discarded rather than trusted. |
| Lock screen | The panel closes as soon as the screen locks. |
| No content in logs | Logs record errors only, never clipboard content. |

## Install

Requires macOS 14 or later and the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/gabriel-pelinsari/clipvault.git
cd clipvault
./scripts/create-signing-identity.sh   # optional, recommended — see below
./scripts/install.sh
```

`install.sh` builds a release app, signs it, copies it to `/Applications`, and launches it.
Run it again to update.

### Why a local signing identity?

ClipVault isn't notarized, so it's signed locally. An ad hoc signature changes on every
build, which makes macOS ask for Keychain access again and forget the Accessibility
permission after each update. `create-signing-identity.sh` creates a self-signed
"ClipVault Local Signing" certificate in your login keychain (usable only by
`codesign`, not added to any trust settings) so every build keeps the same identity.

### Enable auto-paste

The first time you pick an item, macOS asks to let ClipVault control your computer.
Enable it under **System Settings › Privacy & Security › Accessibility**. ClipVault only
uses it to press ⌘V right after you choose an item.

## Development

```bash
swift build                  # debug build
./scripts/test.sh            # Swift Testing suite (works with Command Line Tools only)
./scripts/build-app.sh       # release .app in ./build
```

Project layout:

```
Sources/ClipVault/
  App/        entry point, composition root, main menu
  Model/      ClipItem, KeyCombo, AppSettings
  Services/   pasteboard monitor, encrypted store, Keychain key, history, hot keys, paster
  UI/         panel, history view, settings, shortcut recorder, status item
Tests/        Swift Testing suites
scripts/      build, install, test, icon and signing helpers
```

## License

MIT — see [LICENSE](LICENSE).
