# Claude Usage Widget

> **TL;DR:** A native macOS menu-bar app + WidgetKit widget (inspired by
> [TokenEater](https://github.com/AThevon/TokenEater)) that reads Claude Code's
> OAuth token from the Keychain, shows live per-window usage % + reset countdowns
> with a risk-colored gauge, lists your **active Claude Code sessions** with their
> context-window fill, and lets you **click a session to focus its terminal**.
> The brain is a UI-free Swift package (`ClaudeUsageKit`) so it's fully unit-tested;
> the app/widget are generated with XcodeGen. v1 is built and verified end-to-end.

## What it does

- **Menu bar** — a live headline like `5h 33%`, tinted by risk (green → amber → red).
- **Dropdown panel** — every usage window (`5h`, `7d`, `Opus 7d`, `Sonnet 7d`) with a
  progress bar, percentage, reset countdown, and risk level; plus the active-session list.
- **WidgetKit widget** — `systemSmall` (big headline gauge) and `systemMedium`
  (windows + sessions), reading a cached snapshot the app writes (offline-safe).
- **Active sessions** — detects running `claude` processes, maps each to its project
  directory and newest transcript, and computes the **context-window fraction** from the
  last assistant `usage` block (≥200k tokens ⇒ 1M-context model).
- **Click → focus terminal** — best-effort: matches the session's controlling TTY to a
  Terminal.app / iTerm2 tab via AppleScript and focuses it; other terminals just get
  activated; failures are silent.

## Architecture

A UI-free Swift package (`ClaudeUsageKit`, `import Foundation` only) holds all logic, so
the data/logic layer is fully unit-testable; the SwiftUI app and WidgetKit widget both
depend on that one package (no duplicated logic), and the widget only ever reads a cached
`UsageSnapshot` the app writes to a shared App Group container.

- **큰 그림·다이어그램** → [`ARCHITECTURE.md`](ARCHITECTURE.md)
- **왜 그렇게 했나 (결정 기록)** → [`docs/adr/`](docs/adr/README.md)
- **개발 규칙·명령어** → [`CLAUDE.md`](CLAUDE.md)

## Requirements

- macOS 14+
- Xcode (full) for building the app/widget — the menu-bar/widget targets need
  `xcodebuild`. The `ClaudeUsageKit` core + `usage-cli` build with Command Line Tools.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) to generate
  the Xcode project.
- A signed-in Claude Code (Pro/Max/Team) — the OAuth token is read from the macOS Keychain
  service `Claude Code-credentials`.

## Build & run

```bash
# 1. Core + CLI (Command Line Tools is enough)
swift build
swift run usage-cli --print          # headless: full pipeline → stdout
swift run usage-cli --json           # machine-readable snapshot

# 2. Tests (need the Xcode toolchain for XCTest)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# 3. The menu-bar app + widget
cd App && xcodegen generate && cd ..
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project App/ClaudeUsageWidget.xcodeproj \
  -scheme ClaudeUsageWidgetApp -destination 'platform=macOS' build
```

> `DEVELOPER_DIR=...` activates a full Xcode install for that command without changing
> the system-wide `xcode-select` (no `sudo` needed).

## `usage-cli --print` example

```
Claude Usage · Max plan
────────────────────────────────
5h ▓░░░░ 14%  resets in 4h 19m  [Calm]
7d ▓▓░░░ 33%  resets in 4d 5h  [Calm]
Sonnet 7d ░░░░░ 5%  resets in 4d 5h  [Calm]
────────────────────────────────
Active sessions:
  ● njtransit             ctx 100%  (ttys016, pid 21399)
  ● claude-usage-widget   ctx  90%  (ttys002, pid 32002)
  ● arkraft               ctx  45%  (ttys017, pid 62434)
```

The access token is **never** printed or logged.

## Privacy

The app talks only to Apple's Keychain and Anthropic's OAuth API (the same read-only
`GET /api/oauth/usage` and `/api/oauth/profile` calls Claude Code itself makes). Nothing
is sent anywhere else.

## Scope (v1)

**In:** 먹방 mascot personality (menu-bar kaomoji + chew, 완식 copy, model cast), menu bar,
dropdown panel (현황|기록 top toggle + a separate ⌘, Settings window, ADR-0017), WidgetKit widget
with sparkline, active-session detection with context fraction, click-to-focus, smart
(pacing-aware) coloring + pace warning, and a 7-day history browser with usage graphs.
**Not yet:** notifications, preferences, auto-launch, code-signed/notarized distribution.
