# ADR-0001: 모든 로직은 Foundation-only 패키지 `TokenMukbangKit`에 둔다

- **Status:** Accepted
- **Date:** 2026-06-11

## Context

이 프로덕트는 세 소비자를 가진다 — 메뉴바 앱(SwiftUI), WidgetKit 위젯, 그리고 헤드리스
`usage-cli`. 같은 로직(usage 파싱, risk, 세션 탐지, 컨텍스트 비율)을 세 곳에서 쓰는데,
UI 타겟에 로직을 두면 (1) 중복되고, (2) AppKit/SwiftUI/WidgetKit에 묶여 단위 테스트가
Xcode 시뮬레이터·UI 런타임을 요구하게 된다.

## Decision

usage/profile/risk/세션/컨텍스트/포맷팅 등 **모든 비-UI 로직을 SPM 패키지
`TokenMukbangKit`에 두고, 이 패키지는 오직 `Foundation`만 import** 한다. AppKit·SwiftUI·
WidgetKit 의존을 금지한다. 앱·위젯·CLI는 전부 이 한 패키지를 의존하며 로직을 복제하지
않는다. UI 타겟 간 공유가 필요한 코드는 `App/Shared/`에 두되 순수 UI 글루(예: hex→Color)로만 제한한다.

## Consequences

- ➕ 데이터/로직 레이어 전체가 일반 Swift 툴체인에서 단위 테스트 가능(현재 21 케이스).
- ➕ 세 소비자가 한 진실의 원천을 공유 — 동작 불일치가 구조적으로 차단된다.
- ➖ "UI에서 한 줄이면 될 것"도 패키지에 API를 추가해야 할 때가 있다(altitude 비용).
- 제약: `App/`에서 로직을 작성하고 있다면 거의 항상 `TokenMukbangKit`로 내려야 한다.

## Alternatives considered

- **앱 타겟에 로직 직접 작성** — 가장 빠르지만 중복 + UI 런타임 없이는 테스트 불가. 기각.
- **위젯이 자체 파이프라인 실행** — ADR-0003에서 별도로 기각(샌드박스 제약).

## Affects

- `Sources/TokenMukbangKit/**`, `Package.swift`, `App/Shared/`
- `CLAUDE.md` "Architecture — what you must respect", `ARCHITECTURE.md` §1
