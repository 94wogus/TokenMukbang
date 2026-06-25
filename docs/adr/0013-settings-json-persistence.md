# ADR-0013: 사용자 설정은 JSON 파일에 영속한다 (테마/임계값/알림)

- **Status:** Accepted
- **Date:** 2026-06-11

## Context

Settings space(TokenEater 패리티)는 테마(4프리셋+커스텀), warning/critical 임계값, 서피스별/이벤트별
알림 토글을 사용자가 바꾸고 **재실행해도 유지**되어야 한다. 영속 수단은 (a) UserDefaults, (b) JSON 파일
두 가지다. 또 설정 모델은 `TokenMukbangKit`(UI-free, ADR-0001)에 두어 테스트 가능해야 한다.

## Decision

설정은 `AppSettings`(Codable: `Theme`/`ThemePalette`(hex 문자열)/`RiskThresholds`/`NotificationSettings`)로
모델링하고, **`SettingsStore`가 JSON 파일(`settings.json`)로 저장/로드**한다. 디렉터리는 주입 가능(ADR-0006
seam)해 테스트는 임시 디렉터리로 round-trip 한다. 파일이 없으면 `AppSettings.default`를 돌려준다. 색은
`TokenMukbangKit`이 UI-free를 유지하도록 **hex 문자열**로 저장하고, App 레이어가 `Color(hex:)`로 매핑한다.

**임계값(warning/critical %)은 위험도 분류의 밴드 경계로 반영된다.** pacing은 유지한 채
`RiskScorer.score(...)`가 낸 0…1 점수를 `RiskScorer.level(forScore:thresholds:)`가 사용자 임계값으로
calm/watch/warning/critical에 매핑한다(watch = warning×0.6). 임계값은 `UsageService.snapshot(thresholds:)`로
주입돼 모든 `UsageSnapshot.Window`에 구워지므로 **메뉴바·팝오버 카드·위젯이 같은 레벨로 색칠**된다. 슬라이더를
바꾸면 네트워크 없이 기존 snapshot을 `UsageSnapshot.recolored(thresholds:)`로 즉시 재색칠한다
(`AppModel.settings.didSet`). (초기 ADR은 `level(percent:thresholds:)`(pacing 무시 순수 % 매핑)를 지목했으나
실제로는 배선되지 않았고, pacing 보존을 위해 score-band 방식으로 정착했다 — 그 순수 % 변형은 보조 API로 잔존.)

## Consequences

- ➕ 설정 모델/영속/임계값 로직이 전부 Kit에서 결정론적으로 테스트된다.
- ➕ JSON 파일은 `HistoryStore`(ADR-0011)/`SharedStore`(ADR-0003)와 같은 패턴 — 일관성.
- ➕ hex 문자열 저장으로 Kit이 SwiftUI에 의존하지 않는다(ADR-0001).
- ➖ UserDefaults보다 약간의 파일 I/O 코드. 단 위젯과 공유가 필요하면 같은 디렉터리 전략 재사용 가능.
- ⚠️ 설정 변경마다 `@Published settings.didSet`이 저장 — 슬라이더 드래그 시 잦은 쓰기(작은 파일이라 허용).

## Alternatives considered

- **UserDefaults** — 간단하나 Kit에서 테스트하려면 suite 주입이 필요하고, History/Shared와 패턴이 갈린다. 기각.
- **앱 레이어에 설정 보관** — Kit에서 임계값을 위험도에 반영하지 못하고 테스트가 어려워진다. 기각.

## Affects

- `Sources/TokenMukbangKit/Settings/AppSettings.swift`, `Risk/RiskScore.swift`
  (`level(forScore:thresholds:)` — 위험도 매핑; `level(percent:thresholds:)` — 보조 순수 % 변형)
- `Sources/TokenMukbangKit/UsageService.swift`(`snapshot(thresholds:)` → `windows(...)`),
  `UsageSnapshot.swift`(`recolored(thresholds:)`)
- `App/TokenMukbang/Views/SettingsView.swift`, `AppModel.swift`(settings + didSet save·recolor,
  `snapshot(thresholds:)` 호출)
- 같은 영속 패턴: ADR-0011(History), ADR-0003(Shared); seam: ADR-0006
