# ADR-0021: Value/세이브는 "API 정가 환산" 으로 추정한다

- **Status:** Accepted
- **Date:** 2026-06-23

## Context

이 앱은 토큰 *소비*를 보여준다(History, 회고 — ADR-0012/0020). 하지만 정액 구독
(Max/Pro/Team) 사용자가 진짜 궁금한 건 **"내가 이 정액으로 실제 얼마어치를 쓰고 있나"** 다 —
같은 토큰 트래픽을 종량제(API)로 냈으면 얼마였을지를 정액과 비교하면 "세이브액 / 몇 배 가치"가
나온다. 데이터는 이미 있다: `TokenEvent`(ADR-0012)가 턴별로 `inputTokens`·`outputTokens`·
`cacheReadTokens`·`cacheCreationTokens`·`model`을 들고 있다.

설계가 비자명한 지점이 셋이다:

1. **무슨 "비용"으로 환산하나** — Anthropic의 실제 원가는 알 수 없다. 공개된 **API 정가**가
   유일하게 검증 가능한 기준이다.
2. **cache-read를 넣나** — cache *read* 는 한도엔 거의 안 잡히지만(ADR-0020 프레이밍), API
   종량제에선 0.1×로 *과금된다*. 그런데 cache-read 토큰량이 압도적이라(heavy 유저는 수십억/월)
   0.1×라도 전체 환산액의 다수를 차지한다 → headline이 cache-read에 휘둘릴 수 있다.
3. **기간을 어떻게 자르나** — 세이브는 청구주기(월) 개념인데 사용자마다 청구일이 다르다.

## Decision

**Now 탭에 "Value/세이브" 카드**를 추가한다. 순수 집계는 Kit에 두고 단위 테스트한다(ADR-0001):
`ModelPricing`(모델→정가 + 캐시 배수) + `ValueEstimate`(기간 내 `TokenEvent` 환산).

1. **API 정가 환산.** 비용 = Σ(input×inPrice + output×outPrice + cacheWrite×inPrice×1.25 +
   cacheRead×inPrice×0.1). 가격은 **raw 모델 id로 매칭**(cast 아님) — Opus 버전별로 다르다
   (현행 4.5–4.8 = $5/$25, 구버전 4.0/4.1/3 = $15/$75). cache **write** = 입력가의 1.25×
   (5분 TTL — Claude Code 통상값; 1h TTL이면 2×지만 통상 케이스를 가정하고 UI에 명시),
   cache **read** = 0.1×. 가격을 모르는 모델(`mock-claude`/`<synthetic>`)은 비용에서 제외하고
   토큰만 `unpricedTokens`로 센다.
2. **두 숫자를 정직하게 보여준다.** `apiEquivalent`(cache-read 포함 — API가 실제 청구할 값)를
   headline으로, `costExclCacheRead`(output+fresh-input+cache-write = "fresh work")를 보조로.
   cache-read가 전체를 지배하는 착시를 막기 위함 — ADR-0020에서 정한 "cache-read는 near-free"
   프레이밍과 일관된다(싸지만 양이 커서 절대액은 큼, 둘 다 진실).
3. **청구주기 산정은 설정값으로.** `AppSettings.subscriptionMonthlyCost`(USD, 기본 $200=Max 20×;
   `0`이면 카드가 "설정에서 입력하세요"로 degrade) + `billingCycleDay`(1–28, nil=rolling 30일).
   `billingPeriodStart(now:calendar:)`가 기간 시작을 계산하고, 표시 타임존 캘린더(ADR-timezone)를 쓴다.
4. **앱 전용·로컬 전용 — 신규 egress 없음.** 추정은 로컬 `TokenEvent` 집계뿐이다. `claude` CLI도
   네트워크도 타지 않는다(ADR-0020의 egress와 무관). 위젯 `SharedStore`에도 안 들어간다.
5. **렌더당 재계산 금지.** 이벤트 수가 많아(heavy 유저 수만/기간) `AppModel.valueEstimate`는
   토큰 로드 + 설정 변경 시에만 재계산하고 SwiftUI 렌더마다 스캔하지 않는다.
6. **A/B 새로고침.** 카드를 세션 중에도 라이브로 유지하되 풀 재파싱을 매번 하지 않는다.
   **(B) 5분 폴링은 증분** — `EventCache.update(previous:)`가 이전 in-memory 스냅샷 대비
   `(size,mtime)`이 바뀐 파일만 재파싱(디스크 캐시 I/O 없음, 히스토리 크기와 무관하게 일정 비용).
   **(A) 수동 ↻ 버튼·런치는 전체** — `EventCache.load()`가 디스크 캐시 기반 전체 재빌드로 권위 있게
   재동기화(증분 드리프트 self-heal). 풀 캐시를 폴링마다 읽으면 히스토리가 커질수록 비싸지므로
   B를 분리했다.

## Consequences

- ➕ 정액 사용자가 **"내 $200이 API로 치면 얼마"** 를 한눈에 본다 — 제품의 "거울" 방향(VISION) 강화.
- ➕ 신규 데이터/인증/네트워크 표면 **없음**(ADR-0012 `TokenEvent` 재사용, 로컬 집계).
- ➖ **정가는 추정**이다 — Anthropic 실제 원가가 아니라 "종량제였으면" 값이다. UI가 "at API rates"로
   명시해 오해를 막는다.
- ⚠️ **가격표는 외부 사실** — 모델 가격이 바뀌면 `ModelPricing`을 갱신해야 한다(코드 한 곳).
- ⚠️ **cache TTL 가정** — 1.25×(5분)을 가정한다. Claude Code가 1h TTL을 쓰면 cache-write 항목이
   실제보다 과소 추정된다(UI 각주로 고지).

## Alternatives considered

- **실제 구독 원가 역산**: Anthropic이 공개 안 함 → 불가. 기각.
- **cache-read 제외(fresh work만)**: headline을 안정시키지만 "API가 실제 청구할 값"을 과소 표시.
  → 둘 다 보여주는 것으로 타협(full headline + fresh 보조).
- **회고(어제) 카드에 넣기**: 사용자가 처음 요청한 위치지만 세이브는 *월* 개념이라 "어제" 회고와
  스코프가 안 맞음 → **Now 탭**(상시 대시보드, 청구주기 스코프)으로. 회고는 일 단위 유지.
- **고정 단가(모델 무시)**: Opus/Sonnet/Haiku/Fable 단가차가 7–10배라 부정확 → 모델별 정가.

## Affects

- 신규 `Sources/TokenMukbangKit/Value/`: `ModelPricing`, `ValueEstimate`.
- `Sources/TokenMukbangKit/Settings/AppSettings.swift`: `subscriptionMonthlyCost`·`billingCycleDay`·
  `billingPeriodStart`.
- `App/TokenMukbang/AppModel.swift`: `valueEstimate` + `recomputeValueEstimate()`.
- `App/TokenMukbang/Views/MenuContentView.swift`: Now 탭 `valueCard`(미니 윈도우↔SESSIONS 사이).
- `App/TokenMukbang/Views/SettingsView.swift`: General 탭 "Subscription" 섹션.
- 테스트 `Tests/TokenMukbangKitTests/ValueTests.swift`.
