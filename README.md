# Work Monitor

A **macOS 13+** **menu bar–only** utility: listening ports, Docker, memory, and top processes in one popover from the status item—no Dock window.

Repository: [github.com/BrezhnevEugen/WorkMonitor](https://github.com/BrezhnevEugen/WorkMonitor)

## Features

- **Memory** — RAM usage, swap, pressure, breakdown (apps / wired / compressed); **Processes** opens a side panel with RSS-based top processes and the ability to terminate **user** processes.
- **Ports** — listening TCP sockets (`lsof`), grouped by process; optional web UI hint via `http://localhost:PORT`.
- **Docker** — `docker ps -a` (status, image, port mappings) when the Docker CLI is available.
- **About** — overview and optional support on [Boosty](https://boosty.to/genius_me/donate).

## Project layout

SwiftPM sources and the app bundle script live here:

```text
work monitor/WorkMonitor/
  Package.swift
  WorkMonitor/              # executable target (SwiftUI + AppKit)
  WorkMonitorCore/          # models + CLI output parsers
  Tests/WorkMonitorCoreTests/
```

## Build

From the package directory:

```bash
cd "work monitor/WorkMonitor"
swift build -c release
```

Build a **`.app`** (copies the binary and `Info.plist`):

```bash
./build.sh
open WorkMonitor.app
```

## DMG, code signing, and notarization

From the same package directory, [`build-dmg.sh`](work%20monitor/WorkMonitor/build-dmg.sh) runs `build.sh`, packs **`WorkMonitor-<version>.dmg`** (compressed UDZO with the `.app` and an **Applications** shortcut), optionally **signs the app** with the **hardened runtime**, then **notarizes** and **staples** the DMG when you provide credentials.

Entitlements used for release signing: [`WorkMonitor.entitlements`](work%20monitor/WorkMonitor/WorkMonitor/WorkMonitor.entitlements) (outbound network for localhost HTTP checks; app sandbox stays off so `lsof` / `docker` / `ps` via `Process` keep working).

### Unsigned DMG (local / CI artifact)

```bash
cd "work monitor/WorkMonitor"
./build-dmg.sh
```

The `.dmg` is listed in `.gitignore` and is not committed.

### Signed + notarized (release)

1. **Apple Developer**: “Developer ID Application” certificate installed in Keychain.  
2. **Export** your signing identity (example):

   ```bash
   export CODESIGN_IDENTITY='Developer ID Application: Your Name (XXXXXXXXXX)'
   ```

3. **Notarytool** — choose one authentication method:

   - **Keychain profile** (good for laptops):

     ```bash
     xcrun notarytool store-credentials "workmonitor-notary" \
       --apple-id "you@example.com" \
       --team-id "YOUR10CHARTEAMID" \
       --password "abcd-abcd-abcd-abcd"
     export NOTARY_KEYCHAIN_PROFILE=workmonitor-notary
     ```

     Use an [app-specific password](https://support.apple.com/en-us/102654) for `--password`, not your Apple ID login password.

   - **Environment variables** (CI-friendly, app-specific password):

     ```bash
     export APPLE_ID=you@example.com
     export APPLE_TEAM_ID=YOUR10CHARTEAMID
     export APPLE_APP_PASSWORD=abcd-abcd-abcd-abcd
     ```

   - **App Store Connect API key** (recommended for automation):

     ```bash
     export NOTARY_KEY_PATH=/path/to/AuthKey_XXXXXXXXXX.p8
     export NOTARY_KEY_ID=XXXXXXXXXX
     export NOTARY_ISSUER=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
     ```

4. **Run** (with `CODESIGN_IDENTITY` plus one of the notary options above):

   ```bash
   cd "work monitor/WorkMonitor"
   ./build-dmg.sh
   ```

The script waits on `notarytool submit --wait`, then runs **`stapler staple`** and **`stapler validate`** on the DMG. A local **`spctl --assess`** is printed for a quick check (it can still warn depending on context; Gatekeeper on a clean Mac is the real check).

## Tests

Unit tests cover parsers (`lsof`, Docker `ps` format, memory stats, `ps` RSS lines, HTML `<title>` extraction):

```bash
cd "work monitor/WorkMonitor"
swift test
```

CI: [`.github/workflows/swift-tests.yml`](.github/workflows/swift-tests.yml) runs `swift test -c release` on `macos-14` for pushes and pull requests to `main`.

## Git hooks

After `git clone`, run once:

```bash
./scripts/install-git-hooks.sh
```

This sets `core.hooksPath` to `.githooks`. The `commit-msg` hook strips the `Made-with: Cursor` trailer from commit messages.

## Requirements

- macOS **13** or later  
- Xcode / Swift **5.9** (or a toolchain that can build this package)

## License

See [LICENSE](LICENSE) in the repository root.
