# Changelog

All notable changes to this project are documented here.

## [Unreleased]

### Changed — 메뉴바 팝오버 IA 재구성 + 라이브 피드백 (2026-06-12, ADR-0017)
실제 앱 실행 + 네이티브 컨벤션 리서치(Control Center·iStat Menus·Stats·Itsycal 등) 반영:
- **하단 탭바 폐기 → 상단 `현황 | 기록` 세그먼트 토글**(위치 고정 → 탭 점프 제거). `DashboardLayout` 3→2 케이스.
- **Settings → 별도 macOS 설정 창(⌘,)**. 헤더 기어가 연다(accessory 앱이라 활성화 정책을 잠깐 `.regular`로
  올렸다 창 닫히면 `.accessory` 복귀). 팝오버는 content-sized + `maxHeight` 캡.
- **게이지 히트램프 그라데이션 복원**(`RiskTone.gaugeRamp`) — 단색 폐기, calm→…→현재 티어로 *데워지는*
  amber→red 램프(개념 목업 04-steam의 의미 복원).
- **자체 베이스 워시**(`Steam.baseWash`) — 팝오버가 데스크톱 벽지에 의존하지 않고 자기 색/깊이를 가짐(밋밋함 해결).
  라이트모드 국물 글로우 alpha ~절반(밝은 배경 peach stain 방지). 검증 도구에 *평범한 데스크톱*(neutralDark/Light)
  백드롭 추가 — 컬러풀 벽지로 과대포장하던 렌더를 정직하게.

### Changed — 디자인 크리틱 반영 (자체 비평 루프, 2026-06-12)
병렬 디자인-크리틱 에이전트(IA·계층·색·네이티브)를 *충실 렌더*(TMK_SNAPSHOT, 실제 material/blur)
위에 돌려 두 라운드 반영:
- **탭 5→3 통합**: 중복 뷰모드였던 Compact/Focus 제거 → 진짜 목적지 셋(**Dashboard / History / Settings**).
  `DashboardLayout` 재정의(+SF Symbol). MODEL HISTORY는 History 탭에만(대시보드 중복 제거).
- **중복 제거**: 페이스 경고/에러 배너를 전 탭 → 대시보드 한정. 헤더 `Max`를 고스트(아웃라인) 칩으로 강등.
- **색 통일·탈채도**: `RiskTone.color`를 desaturate + L\*-밴딩으로 — calm 틸그린 / watch 앰버골드 /
  warning 오커 / **critical 쿨 크림슨 `#C23B4E`**(토마토수프 오렌지레드 폐기). 모델 식별 팔레트도 탈채도.
- **김/국물 절제**: 김 plume alpha **≤0.22 캡**, 국물 0.62→0.40 + *바닥 그라디언트*로 가둠(검은 배경 범람 수정).
  게이지 fill에 density ramp(시작 옅게→선단 엠버) 추가.
- **네이티브 폴리시**: 하단 크롬 축소(탭바=SF Symbol+라벨 세그먼트, 액션=아이콘 전용 한 줄). 종료 빨강 중립화
  (빨강은 위험 채널 전용). GlassTile 보더/스페큘러 scheme-적응 + 그림자 부드럽게. 코너 28/22→18/14.
  Settings 섹션을 GlassTile 카드로 묶음.
- 빌드 green(app+widget) · `swift test` 77/77.

### Changed — 김 서림(Steam) 비주얼 방향 (ADR-0016, supersedes "Liquid Vitals")
- **디자인 방향 전환**: 멀티에이전트 리서치(v1 12종·v2 유리국밥 변주 6종, `docs/design/concepts/`) 끝
  **김 서림(Steam)** 채택 — 위험을 hue가 아니라 *김의 밀도·높이·빛깔*로. 정본 `docs/design/STEAM_DESIGN.md`,
  계획 `STEAM_IMPLEMENTATION_PLAN.md`, 결정 ADR-0016. `DESIGN_SYSTEM.md`("Liquid Vitals") supersede.
- **토큰(S1)**: `RiskTone.steamTint`(김 plume 색·alpha) + `brothGlow`(z0 언더글로우) + `enum Steam`
  표면 토큰(frostPanel/frostTile/scrimNumber/ink/edgeLens/hairline/condensation). `RiskTone`(ADR-0015) 상속.
- **컴포넌트(S2)**: `App/Shared/SteamComponents.swift` — `BrothGlow`·`SteamPlume`(상단 fade 마스크)·
  `Condensation`·`GlassTile` + `.steamBackground(level:isOver:scheme:)`.
- **팝오버(S4)**: 히어로/모니터링/세션을 솟은 `GlassTile` 3겹으로 + z3 김 + z0 broth. 위험↑일수록 김 짙어짐,
  숫자/게이지는 레이어 위 가독 불변.
- **위젯(S5)**: `containerBackground`를 정적 김(broth+프로스트+김 한 프레임, ADR-0003)으로.
- **메뉴바(S3)**: 기존 "5h/7d 둘 다 + 색 %" 라벨 유지 + warning↑일 때만 텍스트 *뒤* 은은한 김 haze(윤곽 아님).
- 빌드 green(app+widget) · `swift test` 77/77.

### Fixed / Added — per-model History breakdown
- **Fable mapping (bug)**: `claude-fable-5` wasn't matched by `ModelCast.forModel` (only
  opus/sonnet/haiku) → ~24% of recent tokens were uncategorized and invisible to the model
  filter. Added `ModelCast.fable` (미식가); unmapped models now fall into an explicit "기타" bucket.
- **Per-model breakdown (Kit)**: `TokenHistory.byCast` (consumed tokens per cast, 기타 incl.) +
  `byDayCast` (per-day model segments) + `summary` (active/cached + cache-hit + Δ vs previous period).
- **History UI redesign**: the daily bar chart is now **stacked by model** (`StackedTokenBarChart`) so
  each day's bar shows its model composition, over a summary header (신선/재가열 tokens + 캐시 적중률 +
  trend badge) and a per-model legend (color · model · total). Model-identity colors via `DS.modelColor`.
  Purely token-based — the API utilization % is a different, **account-wide** metric (covers claude.ai
  web etc., not just CLI), so it's not mixed into the per-CLI-model History (TokenEater does the same).
  Replaces the old combined picker.
- +7 Kit tests (byCast, byDayCast, summary, fable mapping). `swift test` 77/77 green.

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
