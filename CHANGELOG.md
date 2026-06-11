# Changelog

All notable changes to this project are documented here.

## [Unreleased]

### Added — full TokenEater parity (in progress)
- **Token-consumption data (ADR-0012)**: `JSONLParser` reads real token counts from
  `~/.claude/projects/*.jsonl` (TokenEvent); `TokenHistory` aggregates by day/model/project +
  heaviest-day + top-project — the data behind TokenEater's token History browser.
- **Monitoring space (Area B)**: `PacingCalculator` (equilibrium = elapsed%, delta,
  isAheadOfPace) in Kit `Risk/`; `MonitoringView` with flippable `FlipTile` (front %완식 /
  back sparkline), `PacingEquilibriumView` (sparkline + dashed equilibrium line + delta),
  peak-day + top-project callouts. Classic layout = Monitoring space.
- **Token History browser (Area C)**: `Timeframe` (24h/7d/30d/90d) + `HistoryFilter.tokenEvents`
  (by timeframe + model) in Kit; `HistoryBrowserView` now shows a `TokenBarChart` of daily token
  consumption with hover detail + timeframe/model pickers + heaviest-day/top-project.

### Added — TokenEater feature parity + 먹방 personality
- **먹방 personality (ADR-0009)**: `MukbangZone`/`MukbangFace` (pacing zones, faces, chew
  frames), `MukbangCopy` (완식 POV copy + event lines), `ModelCast` (대식가/평균인/소식좌);
  menu-bar SF Mono mascot that chews on each refresh; popover mascot + status line;
  widget "NN% 완식" framing; `usage-cli --print` 먹방 voice.
- **Smart coloring**: pacing-aware risk (windowStart = resetsAt − window duration) +
  `PaceForecast` "이 속도면 N시간 뒤 완식" warning.
- **Dashboard**: 4 layouts (Classic / Compact / Focus / History) with a segmented picker.
- **History (ADR-0011)**: `HistoryStore` (7-day rolling JSON), `Sparkline.series` bucketing,
  `HistoryFilter` (by ModelCast + timeframe), `HistoryBrowserView`, dashboard usage graphs,
  and a widget sparkline via `UsageSnapshot.headlineSparkline`.
- 19 new unit tests (40 total). All `swift build` / `swift test` / `xcodebuild` green.

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

### Not yet (planned at 0.1.0 — history/sparklines/layouts since landed, see [Unreleased])
- Notifications, preferences UI, auto-launch, code-signed/notarized distribution.
