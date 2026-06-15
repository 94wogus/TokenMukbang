# 0019 — 메뉴바 UI를 일반 유리 NSWindow로 (커스텀 NSPanel 팝오버 대체)

- Status: Accepted
- Date: 2026-06-15
- Supersedes: ADR-0018 (커스텀 NSPanel 글래스 팝오버)
- Affects: ADR-0007(네이티브 스택), ADR-0015(앱 측 색), ADR-0016(Steam), ADR-0017(팝오버 IA)

## Context

ADR-0018은 `MenuBarExtra(.window)`가 behind-window 유리를 못 내서 **커스텀 borderless `NSPanel`**
(투명 + `.behindWindow` 비주얼이펙트)로 팝오버를 직접 구현했다. 유리는 얻었지만, borderless·transient·
status-item에 앵커된 팝업이라는 태생 때문에 끝없는 우회가 쌓였다(코드 주석에 이력이 남아 있다):

- 두 번째로 열면 패널이 갑자기 **불투명**해짐(특히 풀스크린 Space에서) → "매번 새로 생성"으로 회피.
- 탭 전환 시 높이가 바뀌면 패널이 위로 점프 → top-left 앵커링 + `resizeToFit` 수동 구현.
- `.popUpMenu` 레벨 + 전역 클릭 모니터로 바깥 클릭 시 닫기 → 다른 창과 공존 불가, 라이브 프리뷰 불가.
- 사용자 경험상 "되었다 안 되었다" 깜빡임이 반복됨.

사용자 피드백(2026-06-15): "제약이 너무 많다, 그냥 일반 창처럼 띄워라. 일반 창에서도 유리 되는 방법을 찾아라."

핵심 관찰: **우리가 직접 만든 일반 `NSWindow`는 시스템 소유가 아니므로 투명화할 수 있다.** ADR-0018이
막혔던 건 `MenuBarExtra`의 *시스템 소유* 창 때문이지, 일반 창의 한계가 아니었다. 별도 설정 창(이미 일반
`NSWindow`)이 멀쩡히 동작하던 것이 방증이다.

## Decision

메뉴바 팝오버(커스텀 `NSPanel`)를 폐기하고, **단일 일반 유리 `NSWindow`** 로 대체한다.

- **창**: `NSWindow([.titled, .closable, .fullSizeContentView])` + `titlebarAppearsTransparent` +
  `titleVisibility = .hidden` + `isMovableByWindowBackground`. 신호등 버튼이 콘텐츠 위에 뜨도록
  콘텐츠 상단에 여백을 둔다.
- **유리**: `isOpaque = false` + `backgroundColor = .clear` + SwiftUI `VisualEffectBackground`
  (`NSVisualEffectView(.behindWindow, .underWindowBackground, state: .active)`)를 콘텐츠 배경으로.
  데스크톱이 흐릿하게 비치는 진짜 glassmorphism은 그대로 유지(ADR-0016). 테마 wash(steamBackground)는
  이 블러 *위*에 얹혀 유리가 테마 색을 머금는다.
- **자동 사이징**: `NSWindow(contentViewController: NSHostingController)`로 SwiftUI 콘텐츠 크기에 창이
  맞춰진다(ADR-0018의 수동 `resizeToFit`/앵커링 제거).
- **블러 강도**: `AppSettings.glassOpacity`가 `VisualEffectBackground.alpha`로 들어가, SwiftUI
  반응형이라 설정 변경 시 **라이브** 반영(별도 KVO 불필요).
- **IA**: Now / History / **Settings**를 한 창에 통합하되 **사이드바(좌측 레일) + 디테일** 구조로
  간다(2026-06-15 갱신). 처음엔 상단 세그먼트 탭이었으나, 성격·높이가 크게 다른 섹션(컴팩트 라이브
  대시보드 vs 길쭉한 설정 폼)을 한 탭 컨테이너에 넣자 탭 전환 시 창 리사이즈/콘텐츠 정렬이 충돌해
  "대각선"으로 움직였다. 사이드바는 **각 디테일이 독립 스크롤**하므로 높이 차이가 무의미해지고, 창은
  자유 리사이즈된다. 기어 버튼·별도 설정 창 폐기(ADR-0017의 "기어→별도 설정 창"을 이 결정이 갱신).
  메뉴바 아이콘 클릭은 창 토글(앞이면 숨김, 아니면 앞으로).

## Consequences

- 깜빡임·stale-opaque·높이 점프·앵커링 버그가 **구조적으로 사라짐**(일반 창이라 그런 hack이 불필요).
- 창을 **이동·닫기** 가능, 다른 창과 공존 → 설정 바꾸며 라이브 프리뷰 가능.
- 잃는 것: 메뉴바 바로 아래에 transient하게 떠 바깥 클릭 시 자동으로 닫히는 "팝오버" UX. 대신 명시적
  토글/닫기(신호등). 사용자가 의도한 트레이드오프.
- `GlassPanel` 클래스, `present/dismiss/anchor/measureMaxTabHeight`, 별도 `settingsWindow` 제거.
- ADR-0018은 Superseded. ADR-0017의 "별도 ⌘, 설정 창" 부분도 본 ADR로 갱신(설정=탭).

## Alternatives considered

- **ADR-0018 유지 + 버그만 수정**: 누적된 우회의 근본 원인(시스템 의존적 borderless transient panel)이
  남아 재발 위험. 기각.
- **대시보드/설정을 별도 두 창**: 사용자는 "대시보드+설정 한 창"을 원함. 단일 창 + 탭으로.
- **SwiftUI `Window` scene + `.containerBackground`**: 창 유리 컨테이너 API는 macOS 15+. 배포 타깃
  macOS 14라 컨트롤러 소유 `NSWindow` + `VisualEffectBackground`로 14에서도 동작.
