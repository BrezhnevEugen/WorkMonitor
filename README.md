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

From `work monitor/WorkMonitor/`:

```bash
swift build -c release          # binary only
./build.sh                        # WorkMonitor.app (optional: export CODESIGN_IDENTITY to sign)
./build-dmg.sh                    # DMG for distribution — Apple/notary env vars: see script comments at top
```

The `.dmg` is gitignored.

## Tests

Unit tests cover parsers (`lsof`, Docker `ps` format, memory stats, `ps` RSS lines, HTML `<title>` extraction):

```bash
cd "work monitor/WorkMonitor"
swift test
```

CI: [`.github/workflows/swift-tests.yml`](.github/workflows/swift-tests.yml) runs `swift test -c release` on `macos-15` for pushes and pull requests to `main`.

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
