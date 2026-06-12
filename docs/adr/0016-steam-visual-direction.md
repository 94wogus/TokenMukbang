# ADR-0016: 비주얼 방향을 "김 서림(Steam)"으로 채택하고 DESIGN_SYSTEM("Liquid Vitals")을 대체한다

- **Status:** Accepted
- **Date:** 2026-06-12
- **Supersedes:** (정식 ADR 아님) `docs/design/DESIGN_SYSTEM.md`의 "Liquid Vitals, Instrument-Grade" 비주얼 방향
- **Superseded by:** —

## Context

초기 UI("Liquid Vitals, Instrument-Grade", `docs/design/DESIGN_SYSTEM.md`)는 정보 위계는 잡혔지만
"개발자가 만든 듯하다"는 피드백이 있었다. 제대로 된 비주얼 방향을 잡기 위해 멀티 에이전트 디자인 리서치를
두 라운드 진행했다:

- **v1 — 12종 컨셉**(서로 다른 미학 가족: 스위스/글래스/레트로테크/플레이풀/인스트루먼트/캄·와일드카드).
  산출물·이미지는 `docs/design/concepts/_archive/v1-twelve/`.
- **v2 — 유리국밥(Glass Gukbap) 변주 6종**(채택된 글래스 방향을 그릇/빛/온도/깊이/페이스로 변주).
  산출물·이미지는 `docs/design/concepts/_archive/v2-glass-variations/`(채택안 제외).

사용자가 v1 #3 유리국밥 → v2 #4 **김 서림(Steam)**을 최종 선택했다. 이 결정과 그로 인한 기존 디자인
시스템 대체를 기록으로 남길 필요가 있다(대안이 있었고, 하나를 골랐고, 이유가 비자명 → ADR 대상).

## Decision

**TokenMukbang의 비주얼 방향을 "김 서림(Steam)"으로 채택한다.** 정본 스펙은 `docs/design/STEAM_DESIGN.md`,
적용 계획은 `docs/design/STEAM_IMPLEMENTATION_PLAN.md`. 핵심:

- 03 유리국밥의 DNA(프로스트 글래스 + 바닥 국물 언더글로우 + "숫자는 항상 불투명 scrim 위")를 상속하되,
  **시그니처를 "위로 솟는 김(steam wisp) + 응결"로 교체** — 위험을 글자색이 아니라 **김의 밀도·높이·빛깔**로 읽힌다.
- `docs/design/DESIGN_SYSTEM.md`("Liquid Vitals")의 **비주얼 방향을 STEAM_DESIGN.md가 대체**한다.
  코드 단계에서 DESIGN_SYSTEM.md는 superseded 배너 + STEAM_DESIGN 링크로 정리한다.
- 하부 메커니즘은 상속: **ADR-0015**(위험색 앱-측 scheme-branched `RiskTone`, Kit color-free)와
  **ADR-0009**(먹방 시점, "정확함>귀여움")는 그대로 유효 — 김 빛깔/언더글로우/메뉴바 틴트가 `RiskTone` 계열을
  거치고, 김은 콘텐츠 사이·상단 빈 공간에만 피어올라 숫자/게이지를 가리지 않는다.
- **ADR-0009 마스코트 채널은 변경 없음.** ADR-0009 §personality rule("마스코트 = 팝오버 헤더 칩·위젯·빈
  상태·이벤트 토스트 only, 데이터 플레인엔 X")는 그대로 유효하다. 김 서림은 **위험 신호 채널**(데이터 플레인)을
  김·빛으로 다루고, 카오모지 마스코트는 그 지정 채널에 그대로 공존한다 — 역할이 겹치지 않는다. STEAM_DESIGN의
  "이모지 없이 형태·빛으로만"은 위험 채널 한정 규칙이며 마스코트 폐지가 아니다(STEAM_DESIGN §먹방 참조).
- 이번 단계는 **문서/계획만**(코드·빌드 무변경). 구현은 STEAM_IMPLEMENTATION_PLAN의 슬라이스로 후속.

## Consequences

- ➕ 또렷하고 기억되는 비주얼 정체성("막 끓여 김 나는 한 그릇")이 생긴다 — 먹방 컨셉과 정합.
- ➕ 위험이 김 밀도(면적)+hue 이중 인코딩 → 색각 이상에서도 위험 판별 가능.
- ➕ 03 글래스 자산을 상속하고 김 레이어만 추가 → 구현 증분이 작다.
- ➖ z0+z1+z3 다겹 blur로 GPU 부담이 커진다 → 김 정적 캐싱, 동적 모락모락은 critical 팝오버 한정, 위젯은 정적.
- ➖ 김이 콘텐츠를 가릴 위험 → 마스킹(콘텐츠 위 금지) + 숫자 scrim 격리가 강제 불변식(STEAM_DESIGN §0/§6).
- ⚠️ `DESIGN_SYSTEM.md`·`CLAUDE.md`·`ARCHITECTURE.md`의 "Liquid Vitals" 언급은 코드 적용 단계에서 김 서림으로
  갱신해야 한다(현재는 문서 단계라 STEAM_DESIGN가 정본임을 명시만).
- ⚠️ 모델별 스택 히스토리(`StackedTokenBarChart`)는 오픈 PR #2(`feat/per-model-breakdown`)에 있어, 그 머지
  후 Steam 토큰을 입힌다(PLAN S6).

## Alternatives considered

- **v1 11종 / v2 5종의 다른 컨셉** — 각 보고서·렌더 이미지로 비교했고(아카이브 보존), 사용자가 유리국밥 →
  김 서림을 선택. 기각안도 이력으로 `_archive/`에 남겨 "왜 이걸 골랐나"를 추적 가능.
- **Liquid Vitals 유지** — 정확하나 기억성·정체성이 약하고 "개발자식"이라는 피드백. 기각(이 ADR이 대체).
- **03 유리국밥(메니스커스) 그대로** — 좋았으나 사용자가 "약간의 변주"를 원해 김 서림(시그니처 180° 반전)을 채택.

## Affects

- `docs/design/STEAM_DESIGN.md`(정본), `docs/design/STEAM_IMPLEMENTATION_PLAN.md`(계획)
- `docs/design/DESIGN_SYSTEM.md`(대체 대상 — 코드 단계에서 superseded 처리)
- `docs/design/concepts/`(04-steam 정본, 나머지 `_archive/`)
- 코드 적용 시: `App/Shared/DesignSystem.swift`, `App/ClaudeUsageWidgetApp/ClaudeUsageWidgetApp.swift`(`MenuBarLabel`),
  `Views/MenuContentView.swift`·`MonitoringViews.swift`·`UsageRowView.swift`·`HistoryViews.swift`,
  `App/UsageWidgetExtension/UsageWidget.swift`, `CLAUDE.md`/`ARCHITECTURE.md`/`CHANGELOG.md`
- 관계: ADR-0009(먹방)·ADR-0015(RiskTone) 상속·유효 / ADR-0003(위젯 read-only) 준수(위젯 정적 김)
