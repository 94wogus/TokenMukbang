# ADR-0005: Xcode 프로젝트는 XcodeGen(`project.yml`)이 진실의 원천

- **Status:** Accepted
- **Date:** 2026-06-11

## Context

메뉴바 앱 + 위젯 extension은 SPM만으로 빌드할 수 없다(앱/extension 타겟, Info.plist,
entitlements, App Group, embed 관계 필요). `.xcodeproj`를 직접 손으로 관리하면 거대한
`project.pbxproj`가 머지 충돌·리뷰 불가능한 diff를 낳고, entitlement/번들 설정이 조용히
어긋나기 쉽다.

## Decision

앱/위젯 Xcode 프로젝트는 **XcodeGen 스펙 `App/project.yml`을 진실의 원천**으로 삼고,
`xcodegen generate`로 `App/TokenMukbang.xcodeproj`를 생성한다. 타겟·Info.plist·
entitlements(App Group, 위젯 샌드박스, `LSUIElement`)·embed 관계·SPM 패키지 의존을
전부 `project.yml`에 선언한다. **`.xcodeproj`를 손으로 편집하지 않는다** — 변경은
`project.yml`을 고치고 재생성한다. (생성물 `.xcodeproj`는 편의상 커밋한다.)

## Consequences

- ➕ 프로젝트 설정이 리뷰 가능한 선언적 YAML 한 곳에 모인다.
- ➕ entitlement/App Group/번들ID 같은 보안·통합 설정의 drift를 막는다.
- ➖ XcodeGen 설치 필요(`brew install xcodegen`), Xcode GUI에서 설정을 바꾸면 재생성 시
  날아간다 — GUI가 아니라 `project.yml`에서 바꿔야 한다.
- 절차: Bundle ID/App Group을 바꿀 땐 `project.yml`·entitlements·`SharedStore`를 함께
  고친다(ADR-0003 불변식, ADR-0010 §0).

## Alternatives considered

- **손으로 관리하는 `.xcodeproj`** — 머지 충돌·리뷰 불가·drift. 기각.
- **Tuist** — 더 강력하나 Swift 매니페스트+툴체인 무게가 이 작은 2-타겟 앱엔 과함. 기각.

## Affects

- `App/project.yml`, `App/TokenMukbang.xcodeproj`(생성물)
- `CLAUDE.md` Commands/Architecture, `ARCHITECTURE.md` §5, ADR-0010
