# Architecture Decision Records

이 디렉터리는 claude-usage-widget(TokenMukbang)의 **아키텍처·제품 결정**을 기록한다. 절차·작성법·
문서 정합성 규칙은 [`.claude/rules/adr.md`](../../.claude/rules/adr.md)에 있다. 새 ADR은
[`0000-template.md`](0000-template.md)를 복사해 시작하고, 아래 색인에 한 줄 추가한다.

> **결정이 바뀌면** 기존 ADR을 덮어쓰지 말고 새 ADR로 supersede 하고, 그 결정을 언급하는
> 문서·코드(`CLAUDE.md`, `ARCHITECTURE.md`, `README.md`, 코드 주석 …)를 같은 작업에서 함께
> 최신화한다. — `.claude/rules/adr.md` §4

## 색인

| # | 결정 | Status | Date | 한 줄 요약 (무슨 결정인지) |
|---|------|--------|------|---------------------------|
| [0001](0001-foundation-only-core-package.md) | Foundation-only 코어 패키지 `TokenMukbangKit` | Accepted | 2026-06-11 | 모든 비-UI 로직을 Foundation만 쓰는 SPM 패키지에 둔다(앱·위젯·CLI 공유) |
| [0002](0002-keychain-via-security-cli.md) | Keychain은 `security` CLI로 읽기 전용 | Accepted | 2026-06-11 | OAuth 토큰을 `/usr/bin/security`로 읽기만, 토큰은 절대 노출 안 함 |
| [0003](0003-app-writes-widget-reads-snapshot.md) | 앱이 스냅샷 write, 위젯은 read only | Accepted | 2026-06-11 | 앱만 파이프라인 실행→App Group 파일, 위젯은 그 파일만 읽음 |
| [0004](0004-usageservice-never-throws.md) | `UsageService.snapshot()`은 throw 안 함 | Accepted | 2026-06-11 | 실패를 throw 대신 `UsageSnapshot.error` 데이터로 담아 우아하게 degrade |
| [0005](0005-xcodegen-as-project-source-of-truth.md) | XcodeGen `project.yml`이 진실의 원천 | Accepted | 2026-06-11 | `.xcodeproj`는 손으로 안 고치고 `App/project.yml`에서 생성 |
| [0006](0006-inject-system-boundaries-behind-protocols.md) | OS·네트워크 경계는 프로토콜 뒤 주입 | Accepted | 2026-06-11 | Process/Keychain/HTTP/API를 Sendable 프로토콜로 추상화→테스트 가능 |
| [0007](0007-native-swift-stack.md) | 네이티브 Swift/SwiftUI/WidgetKit 스택 | Accepted | 2026-06-11 | Electron/CLI 대신 네이티브(macOS 14+), 빌드는 `DEVELOPER_DIR` 풀 Xcode |
| [0008](0008-best-effort-terminal-focus.md) | 세션→터미널 포커스는 best-effort | Accepted | 2026-06-11 | TTY 매칭으로 Terminal/iTerm2 탭 포커스, 그 외엔 앱만 활성화·실패 무시 |
| [0009](0009-mukbang-product-concept.md) | TokenMukbang 먹방 제품 컨셉 | Accepted | 2026-06-11 | 시청자/BJ POV + 터미널 출신 마스코트 + "완식" 카피 규칙 (컨셉 정본) |
| [0010](0010-sign-notarize-homebrew-cask-distribution.md) | 서명+공증 .dmg를 Homebrew Cask로 | Accepted | 2026-06-11 | Developer ID 서명·공증→GitHub Release→brew cask 한 줄 설치 (런북 포함) |
| [0011](0011-local-history-persistence.md) | 로컬 히스토리 영속화 (7일 롤링) | Accepted | 2026-06-11 | 사용량 샘플을 JSON에 append+prune → 스파크라인/그래프/히스토리 브라우저 |
| [0012](0012-jsonl-transcript-as-token-source.md) | 토큰 소비량은 JSONL 트랜스크립트에서 | Accepted | 2026-06-11 | 절대 토큰 수를 `~/.claude/projects/*.jsonl`에서 파싱·집계 (API는 %만) |
| [0013](0013-settings-json-persistence.md) | 사용자 설정 JSON 영속화 | Accepted | 2026-06-11 | 테마/임계값/알림을 `AppSettings`+`SettingsStore`(JSON, hex 색)로 저장 |
| [0014](0014-dispatch-source-reactive-file-watch.md) | DispatchSource 반응형 파일 와처 | Accepted | 2026-06-11 | 자격 파일 변경을 `FileWatcher`(DispatchSource)로 즉시 감지→refresh (폴링 보완) |
| [0015](0015-app-side-scheme-branched-risk-color.md) | 위험색은 앱 UI 계층에서 scheme 분기 해석 | Accepted | 2026-06-11 | Kit 은 risk 레벨만 emit, 앱 `RiskTone` 이 라이트/다크별 `Color` 해석 (디자인 시스템) |
| [0016](0016-steam-visual-direction.md) | 비주얼 방향 "김 서림(Steam)" 채택 | Accepted | 2026-06-12 | 멀티에이전트 리서치(v1 12종·v2 6종) 끝 김 서림 채택, `DESIGN_SYSTEM`(Liquid Vitals) 대체 → `STEAM_DESIGN.md` |
| [0017](0017-menu-bar-popover-ia.md) | 메뉴바 팝오버 IA: 하단 탭 폐기 | Accepted | 2026-06-12 | 네이티브 컨벤션 리서치 끝 하단 탭바 폐기 → 상단 `현황\|기록` 토글 + 기어→별도 ⌘, 설정 창 |
| [0018](0018-custom-nspanel-glass-popover.md) | 팝오버를 커스텀 NSPanel 글래스로 | Superseded by 0019 | 2026-06-12 | MenuBarExtra는 behind-window 유리 불가 → 직접 NSStatusItem + 투명 NSPanel + NSVisualEffect(.behindWindow,.active) |
| [0019](0019-normal-glass-window.md) | 메뉴바 UI를 일반 유리 NSWindow로 | Accepted | 2026-06-15 | NSPanel 우회(깜빡임/stale/앵커링) 누적 → 우리 소유 일반 창은 투명화 가능, 유리 유지하며 교체 + Now/History/Settings 단일 창 통합 |

> 위 표의 "한 줄 요약"만 훑어도 어떤 결정이 어디 있는지 보이게 유지한다 — 결정이 바뀌면 해당 행의
> ADR을 찾아 supersede/수정하고 이 표를 갱신한다.

## 상태(Status) 범례

- **Accepted** — 현재 유효한 결정.
- **Proposed** — 논의 중, 미확정.
- **Rejected** — 검토했으나 채택 안 함(파일은 이력으로 남김).
- **Superseded by ADR-NNNN** — 새 ADR이 대체. 대체 ADR로 링크.
- **Deprecated** — 더는 적용 안 됨(대체 ADR 없음).

## 결정이 바뀌면 (supersede 워크플로)

1. **사소한 정정**(오타·링크·표현) → 해당 ADR을 in-place 수정(결정 자체는 안 바뀜).
2. **결정 자체가 바뀜** → 기존 ADR 본문을 덮어쓰지 않는다. 새 번호의 ADR(`NNNN-*.md`, 4자리
   순차, 번호 재사용 금지)을 만들고, 기존 ADR의 Status를 `Superseded by ADR-NNNN`으로 바꾼 뒤
   **양방향 링크**(새 ADR엔 `Supersedes ADR-MMMM`)를 건다. 이력이 보존돼 "왜 바꿨나"가 추적된다.
3. 새 ADR 추가 시 **이 색인 표에 행을 추가**하고, `.claude/rules/adr.md` §4 표대로 그 결정을
   언급하는 문서(`CLAUDE.md`·`ARCHITECTURE.md`·`README.md`·`CHANGELOG.md`·코드 주석)를 함께 갱신한다.

## 작성 규칙 (요약)

- 파일명: `NNNN-kebab-title.md` (4자리 0패딩, 순차 증가, 재사용 금지). 색인만 `README.md`, 템플릿만 `0000-template.md`.
- 형식: MADR-lite — `Status / Context / Decision / Consequences` (+ 선택 `Alternatives considered` / `Affects`).
- ADR엔 TL;DR을 붙이지 않는다(자체 템플릿 우선). 다이어그램은 ```mermaid``` 블록.
- 자세한 절차·정합성 규칙은 [`.claude/rules/adr.md`](../../.claude/rules/adr.md).
