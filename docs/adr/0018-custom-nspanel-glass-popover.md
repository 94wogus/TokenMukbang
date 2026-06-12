# 0018 — 팝오버를 커스텀 NSPanel 글래스로 (MenuBarExtra 대체)

- Status: Accepted
- Date: 2026-06-12
- Affects: ADR-0007(네이티브 스택), ADR-0015(앱 측 색), ADR-0017(팝오버 IA)

## Context

김 서림(Steam, ADR-0016) 방향의 핵심은 **진짜 glassmorphism** — 팝오버 배경에 *뒤 데스크톱/창이
흐릿하게 비치는* 유리다. 이를 `MenuBarExtra(.window)` 팝오버에서 구현하려 했으나 실패했다:

- `MenuBarExtra(.window)`의 팝오버 창은 **시스템이 소유**하며 불투명 머티리얼을 깔아둔다.
  그 뒤에 `NSVisualEffectView(.behindWindow)`를 넣어도 시스템 머티리얼이 위에서 합성돼
  **데스크톱까지 블러가 닿지 못한다.** 이 창을 투명화하는 public API가 없다.
- macOS 26 Liquid Glass(`NSGlassEffectView`)도 *창 뒤 데스크톱*을 샘플링하는 모드가 없다(전경
  컨트롤용). 다만 *투명 창의 최하단 레이어*로 깔면 데스크톱이 비치지만, **시스템 활성/비활성 상태를
  따라가** 풀스크린 Space에서 우리 패널이 비활성이면 회색 프로스트로 변한다(강제 active 노브 없음).

(근거: Apple `NSVisualEffectView`/`NSGlassEffectView`/`MenuBarExtraStyle` 문서, WWDC25 #310/#323,
ghostty PR #8801, 라이브 검증 2026-06-12.)

## Decision

**`MenuBarExtra` 씬을 제거하고, 상태바와 팝오버를 직접 소유한다.**

- **상태바**: `AppDelegate`가 `NSStatusItem`을 생성. 버튼 이미지 = `MenuBarLabel`을 `ImageRenderer`로
  렌더한 색 이미지(`$snapshot`/벽지-appearance 변경 시에만 갱신 — 매 변경 렌더는 버벅임 유발).
  벽지-적응 색은 버튼 `effectiveAppearance` KVO(`MenuBarAppearance`)로 유지(MenuBarExtraAccess 불필요).
- **팝오버**: borderless·`isOpaque=false`(영구 오버라이드)·`backgroundColor=.clear` `NSPanel`.
  contentView = 컨테이너( 최하단 **`NSVisualEffectView(.behindWindow, .underWindowBackground,
  state=.active)`** + 그 위 `NSHostingController(MenuContentView)` ). `.state=.active`로 **항상
  active 렌더**(풀스크린 비활성 회색 방지). 블러 레이어 `alphaValue`(`blurStrength`)로 투명도/블러 조절.
  깔끔한 가우시안 블러(굴절 아님) — 뒤 글자가 덜 뭉개진다.
- **크기**: 두 탭(현황/기록)을 오프스크린으로 측정해 **더 큰 높이로 고정**(Option B). 탭 전환 시
  창 리사이즈 0 → 즉각·무버벅. 짧은 탭은 footer를 ZStack으로 바닥 고정.
- **설정**: 컨트롤러 소유 `NSWindow`(SwiftUI `Settings` 씬 폐기 — 재오픈 불안정). 닫히면
  `willCloseNotification`으로 `.accessory` 복귀(Dock 아이콘 숨김). 기어가 연다.
- **종료 방지**: `applicationShouldTerminateAfterLastWindowClosed=false`(설정 창 닫아도 앱 유지).

## Consequences

- ➕ 진짜 behind-window 유리(데스크톱 블러)가 *모든* 화면·풀스크린에서 일관(`.state=.active`).
- ➕ 팝오버 표시·크기·설정 창을 완전히 제어 → 탭 전환/재오픈/높이 버그를 근본적으로 잡음.
- ➕ `MenuBarExtraAccess` 의존성 제거(project.yml에서 삭제).
- ➖ AppKit 윈도잉 코드(`StatusItemController`/`GlassPanel`)가 늘어난다 — 비자명한 부분은 주석으로 박제.
- ➖ `MenuBarLabel`을 SwiftUI 라벨이 아니라 상태바 버튼 이미지로 렌더(ADR-0015 색 해석은 그대로 앱 측).
- 영향 코드/문서: `StatusItemController.swift`(신규), `TokenMukbang.swift`, `App/project.yml`,
  `ARCHITECTURE.md`, `CLAUDE.md`, `README.md`, `CHANGELOG.md`.

## Alternatives considered

- **MenuBarExtra 유지 + NSVisualEffectView(.behindWindow)**: 시스템 불투명 머티리얼이 막아 데스크톱
  블러 불가 — 기각(라이브 검증).
- **macOS 26 `NSGlassEffectView`(.clear, 투명 창 최하단)**: 데스크톱이 비치고 굴절도 예쁘지만 풀스크린
  Space에서 비활성 회색 전환을 막을 수 없음(강제 active 노브 없음) → 일관성 위해 기각, behind-window
  `NSVisualEffectView`로.
