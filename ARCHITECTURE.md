# Architecture

> **TL;DR:** All logic lives in one Foundation-only Swift package, `ClaudeUsageKit`, so it's
> fully unit-testable; the menu-bar app and the WidgetKit widget are thin UI shells over it.
> One orchestrator — `UsageService.snapshot()` — runs Keychain → OAuth API → session scan
> and returns a single `UsageSnapshot` that *never throws* (failures become
> `snapshot.error`). The **app** runs that live pipeline and writes the snapshot to a shared
> App Group file; the **widget** only ever reads it (it never touches Keychain or network).
> Every system/network boundary is behind an injectable protocol for testing.

## 1. Layers

> Decision: [ADR-0001 — Foundation-only core package](docs/adr/0001-foundation-only-core-package.md)

```
claude-usage-widget/
├── Package.swift                 # SPM: ClaudeUsageKit (lib) + usage-cli (exec) + tests
├── Sources/
│   ├── ClaudeUsageKit/           # PURE LOGIC — imports only Foundation
│   └── usage-cli/                # headless --print / --json pipeline runner
├── Tests/ClaudeUsageKitTests/    # 21 XCTest cases + Fixtures/
└── App/                          # XcodeGen-generated app + widget (UI only)
    ├── project.yml               # source of truth → ClaudeUsageWidget.xcodeproj
    ├── ClaudeUsageWidgetApp/      # SwiftUI MenuBarExtra app
    ├── UsageWidgetExtension/      # WidgetKit widget (systemSmall + systemMedium)
    └── Shared/                    # UI-only helpers used by both targets
```

The defining rule: **`ClaudeUsageKit` has no UI-framework dependency.** Three consumers
sit on top of it — `usage-cli`, the app, and the widget — and none of them re-implement
any logic. The widget gets its data indirectly (via a file the app writes), not by
running the pipeline itself.

```mermaid
flowchart TB
    subgraph kit["ClaudeUsageKit (Foundation only)"]
        US["UsageService.snapshot()"]
    end
    CLI["usage-cli<br/>(--print / --json)"] --> US
    APP["Menu-bar app<br/>AppModel (60s loop)"] --> US
    APP -- "writes UsageSnapshot" --> STORE[("SharedStore<br/>App Group file")]
    WIDGET["WidgetKit widget<br/>(sandboxed)"] -- "reads only" --> STORE
    APP -- "reloadAllTimelines()" --> WIDGET
```

## 2. The pipeline — `UsageService.snapshot()`

> Decision: [ADR-0004 — snapshot() never throws](docs/adr/0004-usageservice-never-throws.md)

The orchestrator is dependency-injected (`CredentialProviding`, `UsageFetching`,
`SessionDetector`, and a `now` clock) so it runs in tests/previews without real
credentials. It **never throws** — each failure becomes `UsageSnapshot.error`, and the
UI shows partial data where it can.

```mermaid
flowchart TD
    A["snapshot()"] --> B{"load Keychain<br/>credentials"}
    B -- "fail" --> Z1["UsageSnapshot.failure(error)"]
    B -- "ok" --> C{"token expired?"}
    C -- "yes" --> Z2["snapshot: no windows,<br/>still scans sessions,<br/>error = 'refresh token'"]
    C -- "no" --> D["async let usage = GET /api/oauth/usage<br/>async let profile = GET /api/oauth/profile"]
    D -- "throws" --> Z3["snapshot: no windows,<br/>still scans sessions,<br/>error = transport/decode"]
    D -- "ok" --> E["windows = map(usage) with RiskScorer<br/>sessions = SessionDetector scan"]
    E --> F["UsageSnapshot(windows, sessions, planLabel, error: nil)"]
```

Usage and profile are fetched concurrently (`async let`). Sessions are scanned even when
the token is expired or the network fails, because they're derived locally and remain
useful.

## 3. Boundaries & injection seams

> Decisions: [ADR-0006 — inject system boundaries](docs/adr/0006-inject-system-boundaries-behind-protocols.md) · [ADR-0002 — Keychain via `security` CLI](docs/adr/0002-keychain-via-security-cli.md)

Everything that touches the OS or the network is behind a `Sendable` protocol so tests
substitute a fake:

| Concern | Protocol | Live impl | What it shells to / calls |
|---|---|---|---|
| Subprocess | `ProcessRunning` | `SystemProcessRunner` | `Process` |
| Keychain creds | `CredentialProviding` | `SecurityCLICredentialStore` | `security find-generic-password` (read-only) |
| HTTP | `HTTPTransport` | `URLSessionTransport` | `URLSession` |
| OAuth API | `UsageFetching` | `ClaudeUsageClient` | `GET /api/oauth/{usage,profile}` |
| Sessions | (concrete, injects `ProcessRunning`) | `SessionDetector` | `ps` + `lsof` |
| Terminal focus | (concrete, injects `ProcessRunning`) | `TerminalFocus` | `osascript` |

`ClaudeUsageKit` module map:

- **`Keychain/Credentials.swift`** — reads the `Claude Code-credentials` Keychain item
  (top-level `claudeAiOauth`); models `OAuthCredentials` with `isExpired(asOf:)`.
- **`API/UsageClient.swift`** — OAuth client; sends `Authorization: Bearer` +
  `anthropic-beta: oauth-2025-04-20`. Maps HTTP/transport/decode failures to `UsageAPIError`.
- **`Models/`** — `Usage` + `RateLimitWindow` + `UsageWindowKind` (the four display
  windows), `Profile` (plan label), and `ClaudeJSON` (fractional-second ISO-8601 decoder).
- **`Sessions/`** — `SessionDetector` (running `claude` procs → cwd → newest transcript)
  and `ContextFraction` (last assistant `usage` block → 0…1 window fill).
- **`Risk/RiskScore.swift`** — pacing-aware 0…1 score → 4-level `RiskLevel` + hex color.
- **`Focus/TerminalFocus.swift`** — TTY → terminal tab, best-effort across Terminal.app/iTerm2
  (AppleScript) + WezTerm (`wezterm cli` pane match) + kitty + tmux; `SupportedTerminal` enum;
  every failure swallowed.

> The app layer (`App/ClaudeUsageWidgetApp/Overlay/`) adds a floating `NSPanel` **Agent Watchers**
> overlay (`OverlayController`, Frost/Neon styles, 2-second session scan, dock-like hover) that
> calls `TerminalFocus.focus(_:)` to jump to a session's terminal.
- **`SharedStore.swift`** — App↔widget snapshot bridge (App Group container, Application
  Support fallback).
- **`UsageSnapshot.swift`** — the Codable DTO the UI renders; `headlineWindow` (max
  utilization) drives the menu-bar/widget headline.
- **`UsageService.swift`** — the orchestrator above.
- **`Mukbang/`** — `MukbangZone`/`MukbangFace` (pacing zones, faces, chew frames),
  `MukbangCopy` (완식 POV copy + event lines), `ModelCast` (대식가/평균인/소식좌). See ADR-0009.
- **`Risk/`** — `RiskScorer` (absolute + pacing → color), `PaceForecast` ("N시간 뒤 완식"),
  `PacingCalculator` (equilibrium line = elapsed%, delta = actual − equilibrium, isAheadOfPace),
  `Temperament` (Confident/Balanced/Suspicious — projection weight + early-window damping).
- **`History/`** — `HistoryStore` (`HistorySample` append/prune/load, 7-day rolling JSON,
  injectable dir; ADR-0011) + `HistoryAnalytics` (`Sparkline.series` bucketing, `HistoryFilter`
  by ModelCast + timeframe; `Timeframe` 24h/7d/30d/90d + `HistoryFilter.tokenEvents`)
  + `JSONLParser`/`TokenHistory` (절대 토큰 소비량을
  `~/.claude/projects/*.jsonl`에서 파싱·집계 — by day/model/project, heaviest day, top project;
  ADR-0012).
- **`Settings/`** — `AppSettings` (Codable: `Theme` 4 presets + custom `ThemePalette`,
  `RiskThresholds`, `NotificationSettings`) + `SettingsStore` (JSON persistence, injectable dir).
- **`Notifications/`** — `NotificationDecider` (edge-triggered: compares previous vs current
  snapshot → escalation/recovery/pacing/reset/expiry alerts, gated by per-surface + per-event
  settings; pure & tested). The app delivers them via `UNUserNotificationCenter`.
- **`Update/`** — `UpdateChecker` (parse GitHub `/releases/latest` tag + semver compare;
  delivery is ADR-0010). The `Casks/token-mukbang.rb` Homebrew cask ships the release.
- **`Support/`** — `ProcessRunner`, `Formatting` (bars/percents/countdowns), `FileWatcher`
  (`FileWatching` seam + `DispatchSource` reactive refresh when the credential file changes; ADR-0014).

> Decision: [ADR-0011 — local history persistence](docs/adr/0011-local-history-persistence.md)
> The app calls `history.record(snap)` each poll, then attaches the headline window's
> 7-day sparkline to `UsageSnapshot.headlineSparkline` before caching so the widget can
> draw it without history access.

## 4. App ↔ widget data flow

> Decision: [ADR-0003 — app writes, widget reads](docs/adr/0003-app-writes-widget-reads-snapshot.md)

The widget extension is **sandboxed** and cannot read the Keychain or reach the network.
The contract that makes the widget work:

1. `AppModel` runs a 60s loop calling `UsageService.snapshot()`.
2. It publishes the snapshot to the SwiftUI menu UI **and** `SharedStore.write(_:)`s it
   as JSON into the App Group container.
3. It calls `WidgetCenter.shared.reloadAllTimelines()`.
4. The widget's timeline provider calls `SharedStore.read()` — pure file read, offline-safe.

So the **App Group ID must match exactly** across `App/project.yml` (both targets) and
`SharedStore.appGroupID`. If it drifts, `SharedStore` falls back to Application Support and
the widget reads a different (stale/empty) file. The app is intentionally **not
sandboxed** (it shells out to `security`/`ps`/`lsof`/`osascript`); only the widget is.

## 5. Build topology

> Decision: [ADR-0005 — XcodeGen as project source of truth](docs/adr/0005-xcodegen-as-project-source-of-truth.md)

- **`ClaudeUsageKit` + `usage-cli` + tests** are plain SPM (`Package.swift`), buildable
  with Command Line Tools — except `swift test`, which needs the Xcode toolchain for XCTest.
- **The app + widget** are not in SPM. `App/project.yml` is the XcodeGen source of truth;
  `xcodegen generate` produces `App/ClaudeUsageWidget.xcodeproj`, which references the
  root SPM package for `ClaudeUsageKit`. The widget extension is embedded in the app.

```mermaid
flowchart LR
    PY["App/project.yml"] -- "xcodegen generate" --> XP["ClaudeUsageWidget.xcodeproj"]
    PKG["Package.swift<br/>(ClaudeUsageKit)"] -. "package dependency" .-> XP
    XP --> APPTGT["ClaudeUsageWidgetApp"]
    XP --> WTGT["UsageWidgetExtension"]
    APPTGT -- embeds --> WTGT
```

See [ADR-0010 — sign + notarize + Homebrew Cask distribution](docs/adr/0010-sign-notarize-homebrew-cask-distribution.md)
for the release plan (and the pending `ClaudeUsageWidget` → `TokenMukbang` rename). The
product concept is [ADR-0009](docs/adr/0009-mukbang-product-concept.md).
