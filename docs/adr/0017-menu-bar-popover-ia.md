# 0017 — 메뉴바 팝오버 IA: 하단 탭 폐기, 상단 토글 + 별도 설정 창

- Status: Accepted
- Date: 2026-06-12

## Context

김 서림(Steam, ADR-0016) 구현 과정에서 팝오버 내비게이션을 **하단 5탭 → 3탭(Dashboard/History/Settings)**
세그먼트 바로 정리했었다. 그러나 실사용에서 두 문제가 드러났다:

1. **탭 전환 시 팝오버 높이가 바뀌어 하단 탭바의 Y 위치가 점프** → 같은 탭을 연달아 누르기가
   번거롭다(클릭 지점이 움직임).
2. 하단 탭바는 **iOS 패턴**이다. 네이티브 macOS 메뉴바 팝오버 레퍼런스(Control Center·배터리·
   Now Playing·iStat Menus·Stats·Itsycal·Dato·MeetingBar)를 조사한 결과(2026-06-12), 이들은:
   - 탭바를 **쓰지 않는다**(특히 하단). 팝오버는 "한 눈에 보는 상태" 면이다.
   - **설정은 별도 창**(⌘,)에 둔다 — 보통 기어 아이콘이 표준 Settings 창을 연다.
   - 2차 분석뷰는 **상단 세그먼트 토글**(같은 데이터의 다른 렌즈)이나 **별도 창**(무거운 분석)으로.
   - 하단은 내비게이션이 아니라 **얇은 유틸 풋터**(기어/새로고침/종료).

(출처: Apple HIG "The menu bar"; Stats #2194/#408; Itsycal/iStat Menus 설정 패턴; bjango
"Designing menu bar extras"; Steinberger "Showing Settings from macOS Menu Bar Items".)

## Decision

메뉴바 팝오버 IA를 네이티브 컨벤션으로 재구성한다:

- **하단 탭바 폐기.** 내비게이션은 **상단 세그먼트 토글 `현황 | 기록`**(`DashboardLayout` 2-케이스).
  토글은 헤더 바로 아래 **고정 위치** → 모드를 바꿔도 클릭 지점이 안 움직인다.
- **Settings는 팝오버 모드가 아니라 별도 macOS Settings 창**(⌘,). 헤더 우상단 **기어**가 연다.
  MenuBarExtra는 `.accessory` 앱이라 창을 앞으로 못 가져오므로, 기어가 **활성화 정책을 잠깐
  `.regular`로 올리고** `openSettings()` + `activate` → 창이 닫히면(`onDisappear`) 다시 `.accessory`.
- 팝오버는 **content-sized**(고정 높이 아님) + `maxHeight` 캡(긴 기록은 스크롤). 클릭 대상(토글)이
  상단 고정이므로 모드 전환 리사이즈는 무해.
- 하단은 **유틸 풋터**(새로고침·관전·종료)만, 헤어라인으로 콘텐츠와 분리.

## Consequences

- ➕ 네이티브 macOS 팝오버 형태에 부합 — 탭 점프 문제 제거, Settings가 표준 창으로.
- ➕ 팝오버가 글랜스 면으로 단순화, 설정의 복잡한 폼은 넓은 창에서 편집.
- ➖ MenuBarExtra의 Settings-창 열기 패턴(활성화 정책 토글)이 비자명 — 코드 주석으로 박제.
- ➖ `DashboardLayout`이 3→2 케이스로 축소(History는 토글로 유지, Settings는 enum에서 빠짐).
- 영향 문서/코드: `MenuContentView`(상단 토글·기어·풋터), `ClaudeUsageWidgetApp`(`Settings` 씬),
  `DashboardLayout`(2-케이스), `CLAUDE.md`/`README.md`/`CHANGELOG.md`.

## Alternatives considered

- **History도 별도 창**: iStat Menus/Stats가 무거운 분석을 창으로 빼는 방식. 더 네이티브하지만
  창 관리 코드가 늘고, 본 앱의 기록(7일 토큰 차트)은 토글로 충분히 가벼워 **상단 토글** 채택.
- **3탭 유지(상단으로 이동)**: 점프는 줄지만 여전히 탭 패러다임 + Settings가 팝오버에 박힘 → 기각.
