# ADR-0011: 사용량 히스토리를 로컬 JSON에 7일 롤링으로 영속한다

- **Status:** Accepted
- **Date:** 2026-06-11

## Context

TokenEater 패리티(7일 스파크라인, 사용량 그래프, 모델별 히스토리 브라우저)를 구현하려면 시간에 따른
사용량을 **누적 저장**해야 한다. 라이브 스냅샷(ADR-0003)은 "지금 이 순간"만 담으므로 추세를 그릴 수
없다. 저장 방식·위치·보존 기간·위젯에서의 접근을 정해야 한다.

## Decision

`ClaudeUsageKit`의 **`HistoryStore`**가 폴링마다 `HistorySample`(capturedAt + windowKind→utilization)을
로컬 JSON 파일(`history.json`)에 **append**하고, **7일**(가장 긴 윈도우와 일치)보다 오래된 샘플을 **prune**
한다. 파일 위치는 Application Support의 `ClaudeUsageWidget/`(미서명/dev 폴백; ADR-0003의 SharedStore와
동일 패턴), 디렉터리는 테스트를 위해 주입 가능하다(ADR-0006 seam 스타일). 집계 로직 `Sparkline.series`와
필터 `HistoryFilter`도 Kit에 두어 단위 테스트한다(ADR-0001). 앱은 매 refresh에서 `record(snapshot)`로
기록한다.

**위젯은 히스토리 파일을 직접 읽지 않는다**(샌드박스 제약, ADR-0003과 동일). 대신 앱이 헤드라인 윈도우의
스파크라인 값을 `UsageSnapshot.headlineSparkline`에 담아 공유 캐시에 써주고, 위젯은 그걸 렌더한다.

## Consequences

- ➕ 추세 UI(스파크라인/그래프/브라우저)가 가능해진다. append-only라 단순·견고.
- ➕ 집계/필터가 순수 로직이라 결정론적으로 테스트된다.
- ➕ 7일 prune으로 파일 크기가 자연히 제한된다.
- ➖ 폴링 간격(60s)만큼만 해상도가 있다(촘촘하지 않음). 버킷 평균으로 완화.
- ⚠️ 위젯 스파크라인은 앱이 채워주는 `headlineSparkline`에 의존 — 앱이 한 번도 안 돌면 위젯엔 추세가 없다.
- ⚠️ 히스토리 파일과 SharedStore 스냅샷은 별도 파일이다(둘 다 같은 디렉터리).

## Alternatives considered

- **SharedStore 스냅샷만 사용** — 깊이 있는 히스토리를 못 담는다(현재 값만). 기각.
- **Core Data / SQLite** — 시계열 append-prune 한 종류엔 과한 무게. 기각.
- **UserDefaults** — 시계열 누적 저장 용도가 아니다. 기각.

## Affects

- `Sources/ClaudeUsageKit/History/{HistoryStore,HistoryAnalytics}.swift`, `UsageSnapshot.headlineSparkline`
- `App/ClaudeUsageWidgetApp/AppModel.swift`(record/sparkline), `Views/HistoryViews.swift`,
  `App/Shared/UISupport.swift`(MiniSparkline), `App/UsageWidgetExtension/UsageWidget.swift`
- 데이터 흐름: ADR-0003(앱 write/위젯 read), 경계 주입: ADR-0006
