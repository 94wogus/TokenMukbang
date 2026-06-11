# ADR-0015: 위험도 색은 앱 UI 계층에서 scheme-branched 로 해석한다 (Kit은 레벨만 emit)

- **Status:** Accepted
- **Date:** 2026-06-11
- **Supersedes:** (없음 — ADR-0001 의 "Kit은 색을 모른다" 정신을 구체화/강화)

## Context

초기 구현에서 `ClaudeUsageKit` 은 위험도(risk)를 색으로 환산해 `UsageSnapshot.Window.riskHex`
(고정 hex 문자열)로 내보냈고, UI(앱·위젯)는 그 hex 를 그대로 칠했다. 두 가지 문제가 있었다.

1. **라이트/다크 대응이 불가능.** 단일 hex 는 한 scheme 에서만 균형이 맞는다. 예컨대 watch
   노랑이 다크에서 형광(#FFD60A)으로 튀어 critical 빨강보다 더 강하게 읽혔다 — 정보 위계가
   색 때문에 뒤집힌다. scheme 분기는 본질적으로 **UI 환경(`@Environment(\.colorScheme)`)**
   에 의존하므로 Foundation-only 인 Kit 에서는 해석할 수 없다.
2. **색이 의미 채널을 벗어나 새는 것을 막을 단일 지점이 없었다.** "위험색은 게이지 fill·dot·
   퍼센트 같은 *의미 채널*에만 타고, 작은 본문 텍스트엔 안 칠한다"는 디자인 시스템 규칙
   (`docs/design/DESIGN_SYSTEM.md` §1)을 강제하려면 색 해석이 한 곳에 모여 있어야 한다.

ADR-0001(Foundation-only 코어)은 이미 "Kit 은 AppKit/SwiftUI 를 import 하지 않는다"고 정했고,
`Color` 는 SwiftUI 타입이다. 따라서 색 해석은 원래 UI 계층의 몫이었는데, hex 를 Kit 에서 만들던
관행이 그 경계를 흐리고 있었다.

## Decision

**위험도 색 해석을 앱 UI 계층의 단일 resolver `RiskTone`(`App/Shared/DesignSystem.swift`)으로
옮기고, scheme 별로 분기한다. `ClaudeUsageKit` 은 색을 만들지 않고 의미 레벨만 내보낸다.**

- Kit 의 `UsageSnapshot.Window` 는 `riskLevel: String`(`RiskLevel` rawValue — calm/watch/
  warning/critical)과 `isOver: Bool` 만 emit 한다. (기존 `riskHex` 는 위젯 스냅샷 직렬화 호환을
  위해 필드로 남되, **UI 는 그것을 칠하는 데 쓰지 않는다.**)
- `RiskTone.color(level:over:scheme:)` 가 `(레벨, over, 라이트/다크)` → `Color` 를 해석하는
  **유일한** 지점이다. 컨텍스트 채움(세션)도 `RiskTone.contextColor(fraction:scheme:)` 로 같은
  팔레트를 재사용한다 — 두 번째 위험 팔레트를 만들지 않는다.
- 모든 UI 표면(팝오버 5 레이아웃·메뉴바·위젯·오버레이)은 `@Environment(\.colorScheme)` 를 읽어
  `RiskTone` 에 넘긴다. 게이지는 공용 `GaugeBar` 컴포넌트가 그린다.
- 색은 의미 채널(게이지 fill / dot / glanceable 표면의 퍼센트)에만 탄다. 팝오버의 본문/값
  텍스트는 중립(`labelColor`), glanceable 표면(메뉴바·위젯 small)에서는 숫자 자체가 신호이므로
  퍼센트를 위험색으로 칠한다.

## Consequences

- **(+)** 라이트/다크 각각에서 팔레트 균형을 독립 튜닝할 수 있다(다크 watch 를 `#D9B225` 로
  낮춰 critical 과의 위계 회복). 같은 화면이 두 scheme 에서 같은 제품으로 읽힌다.
- **(+)** "색은 의미 채널에만" 규칙이 한 파일에서 강제된다. 색이 새면 `RiskTone` 호출부만 보면 된다.
- **(+)** ADR-0001 의 계층 경계가 더 깨끗해진다 — `Color`(SwiftUI)는 UI 계층에만 존재.
- **(−)** UI 가 위험색을 쓰려면 항상 `scheme` 을 전달해야 한다(보일러플레이트). 컴포넌트
  (`GaugeBar`, `RiskTone`)로 감싸 완화한다.
- **(−)** `Window.riskHex` 가 "직렬화엔 있으나 UI 는 안 쓰는" 유휴 필드로 남는다. 위젯 스냅샷
  포맷을 바꿀 때 정리 후보다.
- **제약(불변식):** 새 UI 에서 위험색이 필요하면 hex 를 직접 박지 말고 `RiskTone` 을 거친다.
  Kit 에 색/`Color` 를 다시 들이지 않는다(ADR-0001).

## Alternatives considered

- **Kit 이 라이트/다크 두 hex 를 모두 emit.** Kit 이 색 의미를 알게 되고 scheme 개념이 데이터
  계층으로 새며, 팔레트 변경 때 Kit 을 건드려야 한다 — ADR-0001 위반. 기각.
- **UI 에서 `Color(hex:)` 를 그때그때 분기.** 색 규칙이 여러 뷰에 흩어져 "의미 채널에만" 규칙을
  강제할 단일 지점이 사라진다. 기각.
- **Asset Catalog 의 동적 `Color` 사용.** scheme 분기는 공짜지만 위험 레벨↔색 매핑·over 상태·
  컨텍스트 fraction 매핑 로직을 코드로 두는 편이 테스트·가독성에 유리. 기각.

## Affects

- `App/Shared/DesignSystem.swift` (`RiskTone`, `GaugeBar`, `DSSegmented`, `DS` 토큰)
- `Sources/ClaudeUsageKit/UsageSnapshot.swift` (`Window.riskLevel`/`isOver`), `UsageService.swift`
- `App/ClaudeUsageWidgetApp/` 의 모든 뷰 + `ClaudeUsageWidgetApp.swift`(`MenuBarLabel`)
- `App/UsageWidgetExtension/UsageWidget.swift`
- `docs/design/DESIGN_SYSTEM.md` §1, `CLAUDE.md`(Risk 도메인 노트), `CHANGELOG.md`
