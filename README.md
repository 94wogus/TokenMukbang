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

```
claude-usage-widget/
├── Package.swift                 # SPM: ClaudeUsageKit (lib) + usage-cli (exec)
├── Sources/
│   ├── ClaudeUsageKit/           # PURE LOGIC — no AppKit/SwiftUI/WidgetKit
│   │   ├── Keychain/             # read "Claude Code-credentials" via `security`
│   │   ├── API/                  # OAuth client: /api/oauth/usage, /api/oauth/profile
│   │   ├── Models/               # Codable Usage, Profile, RateLimitWindow + ISO8601 JSON
│   │   ├── Sessions/             # active-session detection + context fraction
│   │   ├── Risk/                 # risk score (absolute + pacing) → color
│   │   ├── Focus/                # TTY → terminal-tab AppleScript focus
│   │   ├── SharedStore.swift     # App Group cached-snapshot bridge (app→widget)
│   │   └── UsageService.swift    # orchestrator → UsageSnapshot
│   └── usage-cli/                # headless `--print` full-pipeline runner
├── Tests/ClaudeUsageKitTests/    # 21 unit tests (run under the Xcode toolchain)
└── App/
    ├── project.yml               # XcodeGen spec → ClaudeUsageWidget.xcodeproj
    ├── ClaudeUsageWidgetApp/     # SwiftUI MenuBarExtra app
    ├── UsageWidgetExtension/     # WidgetKit widget
    └── Shared/                   # UI-only helpers (hex→Color) used by both targets
```

`ClaudeUsageKit` imports **only Foundation**, so the entire data/logic layer is unit-
testable with the Command Line Tools toolchain. The app and widget both depend on that
one package — no usage/session/risk logic is duplicated in the UI.

The widget never touches the Keychain or the network. The app runs the live pipeline and
writes a `UsageSnapshot` to the shared App Group container
(`group.com.claudeusagewidget`); the widget only reads it.

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

**In:** menu bar, dropdown panel, WidgetKit widget, active-session detection with context
fraction, click-to-focus. **Not yet:** history browser, 7-day sparklines, multiple
dashboard layouts, notifications, preferences, code-signed distribution.
