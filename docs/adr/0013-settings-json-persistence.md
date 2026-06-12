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
임계값은 `RiskScorer.level(percent:thresholds:)`로 위험도 분류에 반영된다.

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

- `Sources/TokenMukbangKit/Settings/AppSettings.swift`, `Risk/RiskScore.swift`(`level(percent:thresholds:)`)
- `App/TokenMukbang/Views/SettingsView.swift`, `AppModel.swift`(settings + didSet save)
- 같은 영속 패턴: ADR-0011(History), ADR-0003(Shared); seam: ADR-0006
