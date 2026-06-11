# Changelog

All notable changes to this project are documented here.

## [0.1.0] — 2026-06-11

First working version — a native macOS menu-bar app + WidgetKit widget that monitors
Claude usage, inspired by [TokenEater](https://github.com/AThevon/TokenEater).

### Added
- **`ClaudeUsageKit`** — UI-framework-free Swift package holding all logic:
  - Keychain credential reader (`Claude Code-credentials`, read-only, via `security`).
  - OAuth client for `GET /api/oauth/usage` and `/api/oauth/profile`, with ISO-8601
    (fractional-second) date decoding.
  - `Usage` / `Profile` / `RateLimitWindow` Codable models (`5h`, `7d`, `Opus 7d`,
    `Sonnet 7d` windows).
  - Risk scorer blending absolute utilization with pacing → 4-level color mapping.
  - Active Claude Code session detection (`ps` + `lsof` + transcript dirs) with
    context-window fraction from the last assistant `usage` block (≥200k ⇒ 1M window).
  - Best-effort terminal focus: TTY → Terminal.app / iTerm2 tab via AppleScript.
  - `SharedStore` App Group cached-snapshot bridge (app writes, widget reads).
  - `UsageService` orchestrator producing a single `UsageSnapshot`; never throws —
    missing/expired/offline states are surfaced as `snapshot.error`.
- **`usage-cli`** — headless `--print` / `--json` full-pipeline runner (exit 0 even on
  graceful failure; the access token is never printed).
- **Menu-bar app** (`ClaudeUsageWidgetApp`) — SwiftUI `MenuBarExtra` with a risk-tinted
  headline, a dropdown panel (usage windows + clickable active-session rows), and a
  60-second refresh loop that re-caches the snapshot and reloads widget timelines.
- **WidgetKit widget** (`UsageWidgetExtension`) — `systemSmall` + `systemMedium` reading
  the cached snapshot (no Keychain/network from the widget sandbox).
- **XcodeGen** project spec (`App/project.yml`) generating the app + widget extension
  targets with correct Info.plist / entitlements (App Group, widget sandbox, `LSUIElement`).
- 21 unit tests covering decoding, risk, context fraction, session parsing, TTY matching,
  formatting, and the orchestrator's graceful-failure paths.

### Verified
- `swift build`, `swift test` (21 pass), `swift run usage-cli --print` (live, no token
  leak), `xcodegen generate`, and `xcodebuild ... BUILD SUCCEEDED` (app + widget) all green.

### Not yet (planned)
- History browser, 7-day sparklines, multiple dashboard layouts, notifications,
  preferences UI, code-signed/notarized distribution.
