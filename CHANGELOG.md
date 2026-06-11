# Changelog

All notable changes to this project are documented here.

## [Unreleased]

### Changed — UI redesign ("Liquid Vitals, Instrument-Grade" design system)
- **Design system** (`docs/design/DESIGN_RESEARCH.md` + `docs/design/DESIGN_SYSTEM.md`):
  scheme-branched risk palette resolved app-side (`RiskTone` in `App/Shared/DesignSystem.swift`);
  Kit stays color-free, emitting only `Window.riskLevel` (rawValue) + `isOver`. 6-rung type scale,
  8pt spacing grid, demoted 6pt `GaugeBar`, single eyebrow + single hairline seam, reusable
  `DSSegmented` control (replaces `Picker(.segmented)`, which mis-renders and reads non-native).
- **Menu bar — typography carries the signal**: one `Text(AttributedString)` with per-run styling —
  `5h`/`7d` unit labels 10pt @ 50% opacity (context), value+% 13pt **bold, risk-tinted** by state.
  Removed the ▲/✕ glyph (color is the cue). Shows **5h + 7d** both, `.monospacedDigit` (no jitter).
  Mascot no longer in the menu bar (popover header chip + widget only).
- **Popover redesign**: hero 28pt % top-right + demoted bar; compact `WindowRow`s on a shared
  right value-column; sessions show a risk-colored dot (the meaning channel) with **neutral** ctx%
  + aligned tty columns; custom footer tab bar; pacing graph hides until ≥2 trend points.
- Dark-mode `watch` toned from neon `#FFD60A` → `#D9B225` (it out-shouted critical red).
- Poll interval 60s → **300s** (was hitting OAuth 429s).

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
- **Settings space (Area D)**: Kit `Settings/AppSettings` — `Theme` (4 presets + custom palette),
  `RiskThresholds` (+ `RiskScorer.level(percent:thresholds:)`), `NotificationSettings`
  (per-surface + per-event), `SettingsStore` (JSON persistence, injectable dir). App `SettingsView`
  (theme picker + custom hex colors + threshold sliders + notification toggles) as a 5th layout;
  theme accent applied to the popover.
- **Notifications (Area E)**: Kit `NotificationDecider` (edge-triggered alerts — escalation /
  recovery / pacing / reset / token-expiry — gated by per-surface + per-event settings, 먹방 copy);
  App `NotificationService` delivers via `UNUserNotificationCenter`, driven from each poll.
- **Agent Watchers floating overlay (Area F)**: Kit `TerminalFocus` extended with
  `SupportedTerminal` (Terminal/iTerm2/tmux/kitty/WezTerm) + WezTerm pane matching by tty; App
  `OverlayController`/`AgentWatcherOverlay` — floating `NSPanel` with dock-like hover, Frost/Neon
  styles, 2-second session scan, click-to-focus-terminal. Toggle from the popover footer.
- **Smart-color temperament (Area G)**: `Temperament` (Confident/Balanced/Suspicious) +
  `RiskScorer.score(…, temperament:)` with early-window confidence damping; Settings picker.
- **Reactive refresh (Area H)**: `FileWatcher` (`DispatchSource`) refreshes immediately when
  Claude Code rewrites its credential file, complementing the 60s poll.
- **Update check + cask (Area I)**: `UpdateChecker` (GitHub `/releases/latest` parse + semver
  compare); `Casks/token-mukbang.rb` Homebrew cask (signed/notarized DMG release is ADR-0010).

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
