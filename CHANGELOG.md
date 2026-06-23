# Changelog

All notable changes to this project are documented here.

## [Unreleased]

### Added — Now 탭 "Value / 세이브" 카드 (2026-06-23, ADR-0021)
정액 구독으로 **"API 종량제였으면 얼마"** 를 보여줘 세이브액/배수를 가늠하게 한다:
- **무엇** — Now 탭 미니 윈도우(7D·Sonnet 7D)와 SESSIONS 사이에 카드. 청구주기 토큰을 **모델 정가**로
  환산: input×in + output×out + cache-write×in×1.25 + cache-read×in×0.1. headline은 `apiEquivalent`
  (cache-read 포함 = API가 실제 청구할 값), 보조로 `costExclCacheRead`("fresh work"). 모델별($) 분해.
- **가격** — raw 모델 id로 매칭(Opus 버전별 $5/$25 vs 구버전 $15/$75, Sonnet $3/$15, Haiku $1/$5,
  Fable $10/$50). 가격 모르는 모델(mock/synthetic)은 비용 제외·토큰만 카운트.
- **설정** — Settings → General에 "Subscription" 섹션: 월 정액($, 기본 $200=Max 20×) + 청구일
  (1–28, 끄면 rolling 30일). `AppSettings.billingPeriodStart`가 기간 시작을 표시 타임존 기준으로 계산.
- **로컬·앱 전용** — 추정은 `TokenEvent`(ADR-0012) 로컬 집계뿐. `claude` CLI·네트워크 무관, 위젯
  `SharedStore`에도 안 들어감. `AppModel.valueEstimate`는 토큰 로드+설정 변경 시에만 재계산(렌더당 X).
- 신규 `Sources/TokenMukbangKit/Value/`(`ModelPricing`·`ValueEstimate`). 테스트 +9.

### Fixed — 회고 코칭 후속: 메뉴↔코치 프로젝트 컷 불일치 + 데이터에 없는 인과 단정 (2026-06-23, ADR-0020)
직전 프레이밍 교정 후 실사용에서 드러난 잔여 2건:
- **컷오프 정합(이슈 1)**: 코치는 top-10, Copy 리포트는 top-8, 인앱 Menu는 top-5를 보여줘 —
  코치가 9·10위 실토큰 프로젝트(예: `adr-onprem-ip-boundary`)를 언급해도 사용자 Menu엔 안 보이는
  불일치. 세 표시면의 상한을 단일 상수 `RetrospectiveMetrics.maxListedProjects`(=10)로 통일
  (`RetrospectiveReport`/`RetrospectiveView`가 이 상수를 참조). 이전 `assemble(limitTo:)` 필터는
  토큰 0 프롬프트-only 누수만 막았고 이 실토큰 컷 차이는 못 막았던 것.
- **인과 단정 금지(이슈 2)**: 지표엔 턴-간격 타이밍이 없는데 코치가 "cache-write는 >5분 idle gap
  때문"처럼 **데이터에 없는 메커니즘을 단정**하던 약한 버릇 — `ClaudeCLISummarizer` 프롬프트에
  "원인/메커니즘을 데이터 없이 단정 금지(불확실하면 likely/check whether)" hard-rule 추가.
- 테스트 +1(코치 ↔ 리포트 프로젝트 컷 정합). ADR-0020 §1 in-place 보강.

### Fixed — 회고 코칭의 "캐시 리드가 한도를 갉아먹는다" 거꾸로 된 프레이밍 + 데이터 누수 (2026-06-23, ADR-0020)
코치가 비용 인과를 거꾸로 잡던 문제와, 메뉴엔 없는 프로젝트를 인용하던 문제를 함께 교정:
- **프레이밍 교정(a)**: cache *read* 는 한도에 거의 카운트되지 않는(≈0.1×, ITPM 미카운트) near-free
  재사용인데, 코치 프롬프트/지표가 `cache-read/turn`을 전면에 내세워 "캐시 리드가 5h/7d 한도를
  태운다"는 **방향이 반대인** TL;DR을 유발했다. 지표를 **drain = output + fresh-input + cache-write**
  분해로 바꿔 한도를 실제로 태우는 요인을 전면화하고(`RetrospectiveMetrics.Project`에
  `output`/`freshInput`/`cacheWrite` 추가), cache-read는 "컨텍스트 크기 proxy(near-free, 한도 미카운트)"
  로 강등. 프롬프트(`ClaudeCLISummarizer`)에 올바른 드레인 순위(모델 티어→output→uncached input→
  cache-write)와 **"임의 multiplier 발명 금지 / 데이터에 있는 프로젝트만 인용" hard-rule** 추가
  ("4540 times"류 환각·존재하지 않는 프로젝트 인용 차단).
- **데이터 누수 교정(b)**: 코치 입력의 sample prompts가 토큰 거의 0인(프롬프트만 있는) 프로젝트까지
  포함해, 코치가 지표 테이블/메뉴엔 없는 프로젝트를 언급하던 윈도우 불일치 해소 —
  `TranscriptDigest.assemble(limitTo:)`로 sample을 코치가 집계하는 프로젝트
  (`RetrospectiveMetrics.coachedProjects`)로 제한.
- 테스트 +3(drain 분해, drain-우선/cache-read 미전면화, sample allowlist). ADR-0020 §1 in-place 교정.

### Changed — 회고(Retrospective) 시간 표현도 표시 타임존 적용 (2026-06-17)
표시 타임존 기능 직후, **회고만 UTC로 남아** "Busiest around 8:00 UTC" 같은 모순이 보이던 것 해소 —
회고 전반의 시간 표현을 표시 타임존(`AppSettings.resolvedTimeZone`)으로 통일:
- **"어제" 경계 + hourly 버킷**: `AppModel.loadRetrospective`가 `displayCalendar`를 `RetrospectiveBuilder.yesterday`에 주입 — 회고의 "어제"와 시간대별 집계가 UTC가 아니라 사용자 벽시계 기준.
- **"WHEN" / dateLabel / Copy 리포트**: `RetrospectiveSummary.dateLabel`·신규 `busiestHourLabel`·`plainTextReport`가 `timeZone`을 받아 라벨링(기본 UTC 유지 — 테스트 결정성). "8:00 UTC" → "8:00 \<zone\>"(예: GMT+9).
- **코치 입력**: `RetrospectiveMetrics.build`에 `displayCalendar`, `coachInputText`에 `timeZone` 전달 — 로컬 `claude` CLI에 보내는 "busiest" 시각도 사용자 존.
- 전수 점검 결과 **reset 카운트다운류(`Formatting.countdown`/`MukbangCopy.reset`/위젯/CLI)는 순수 간격 계산이라 타임존 무관** — 변경 없음. 테스트 +2(회고 hourly 존 버킷팅, plainTextReport 존 라벨).

### Added — 표시 타임존을 설정 가능하게 (2026-06-17)
차트·일자 버킷·시각 라벨이 UTC 기준이라 다른 타임존 사용자에게는 "하루"의 경계가 어긋나 보이던 문제 해결:
- **Settings → 새 General 탭**에 타임존 섹션 — 이 Mac의 감지된 타임존을 표시하고, 기본은 "Follow system
  time zone"(시스템 따라가기). 끄면 **전체 IANA 타임존을 검색**해 임의 기준 타임존으로 변경 가능
  (`TimeZonePicker`, 검색 필드 + 스크롤 목록 + 현재 오프셋 표시).
- `AppSettings.timeZoneIdentifier`(옵셔널, nil=시스템 따라가기) 추가 — 관용적 디코드라 기존 `settings.json`
  은 그대로 로드(다른 설정 보존). `resolvedTimeZone` / `followsSystemTimeZone` / `displayCalendar` 파생.
- `AppModel.displayCalendar`를 `TokenHistory.byDay/byDayCast/heaviestDay`(History 차트·"Biggest feast"·
  peak day)에 주입 — 일자 버킷이 선택한 타임존의 벽시계 기준으로 재계산. 차트 라벨 포매터도 같은 존으로
  맞춰 막대와 라벨이 일치(`historyDayLabel`). **리셋 카운트다운은 순수 간격 계산이라 영향 없음.**
- Kit 집계는 테스트 결정성을 위해 기본 `TokenHistory.utcCalendar`를 유지(앱만 표시 존을 주입).
- 테스트: AppSettings 타임존(기본/오버라이드/관용 디코드/라운드트립) + 타임존별 일자 버킷팅 6종 추가.

### Changed — 회고 코칭 plan-aware 프레이밍 (2026-06-17, ADR-0020)
회고 코치가 비용 조언을 플랜에 맞게 프레이밍한다. 코치 입력에 플랜 라벨(예: Max)을 넣어,
구독 플랜이면 Opus 남발의 비용을 *$ 요금*이 아니라 **5h/7d 사용량 윈도우를 더 빨리 소진**(한도에
빨리 도달)으로 설명 — 이 앱이 추적하는 바로 그 한도와 정합. `RetrospectiveMetrics.coachInputText`가
`planLabel` 파라미터를 받고, `AppModel`이 `snapshot.planLabel`을 전달. (pay-per-token API는 $ 유지.)

### Added — 회고(Retrospective) 기능 구현 (2026-06-17, ADR-0020, S1~S4)
설계(ADR-0020/VISION/PLAN)에 이어 회고 기능을 실제 구현 — "사용량 미터 → 사용 습관 거울"의 첫 기능:
- **Kit `Retrospective/`** (Foundation-only, ADR-0001): `RetrospectiveBuilder`(A층 — 어제의
  프로젝트별·모델별·시간대별 토큰 + 기준선 대비 델타, `TokenHistory`/`HistoryStore` 재사용·중복 0),
  `RetrospectiveMetrics`(사용 패턴 지표 — 프로젝트별 토큰·프롬프트수·프롬프트당 토큰·turn당
  cache-read·모델·시간), `RetrospectiveSummarizing` seam + `ClaudeCLISummarizer`(**B층 코치** — 위
  지표 + 균형 샘플을 로컬 `claude` CLI로 분석, ADR-0006), `TranscriptDigest`(프로젝트 라운드로빈
  균형 샘플링 + `[project]` 라벨), `RetrospectiveStore`(앱 전용 캐시, `SharedStore` 아님, ADR-0003),
  `RetrospectiveSummary`/`RetroTopics`/`plainTextReport`(복사용) DTO.
- **B는 "주제 나열"이 아니라 "사용 패턴 코치"**: 토큰을 *얼마나 효율적으로* 쓰는지 진단하고
  개선 액션(모델 선택·컨텍스트 위생·자동화 균형·페이싱)을 제안. raw 프롬프트 대신 패턴 지표를
  주어 turn 수 많은 자동 세션(ralph 등) 편향을 제거(VISION/ADR-0020 §B 갱신).
- **불변식 보존**: OAuth 토큰 미재활용(CLI 자기 인증, ADR-0002) · 콘텐츠 요약 위젯 노출 0(누수 grep 0) ·
  **on-demand 전용**(`AppModel.generateRetrospectiveTopics()`만 토큰 소비, 60초 폴링 `refresh()`는 미호출 —
  먹방 역설). A층은 토큰-free라 폴링/로드시 즉시 표시.
- **UI**: 단일 유리 창(ADR-0019)에 **Retro** 레일 추가(`DashboardLayout.retrospective` +
  `RetrospectiveView`). 영문 먹방 보이스("Yesterday's plate"·"eaten"·"What you chewed on"), on-demand
  "Generate review" 버튼이 토큰 소비를 명시, `claude` 부재 시 A-only graceful degrade.
  생성 후에도 **Regenerate**(재생성, 캐시 덮어쓰기)·**Copy**(전체 회고를 plain-text로 클립보드 복사,
  `RetrospectiveSummary.plainTextReport` — Kit, 페이지 레벨 배치) 지원 + 토픽 텍스트 선택 복사.
  코치 첫 줄은 **TL;DR 배지**(가장 큰 개선 기회 한 줄)로 강조, 아래에 액션 팁.
- **테스트 +14**(`RetrospectiveTests`): A 집계·기준선, 가짜 `ProcessRunning`으로 CLI 정상/부재/malformed/
  빈 digest(미실행)/토큰-미포함 인자, Store 왕복·캐시. `swift test` 92/92 · app+widget `xcodebuild` green.
- 문서 동기화: ARCHITECTURE(seam 표·회고 흐름·모듈맵 "planned"→구현), CLAUDE.md·README §Privacy/기능 갱신.

### Added — 회고(Retrospective) 설계 + 제품 방향 재정의 (2026-06-17, ADR-0020, 설계 문서만)
POSIWID("the purpose of a system is what it does")를 출발점으로 제품을 **"사용량 미터 →
사용 습관 거울"** 로 확장하는 방향을 정립하고, 첫 기능인 **회고**의 경계 결정·구현 계획을 설계
문서로 남김(코드 변경 없음):
- **ADR-0020 신설**: 회고의 콘텐츠 분석(B층 — 주제/스타일)을 **로컬 `claude` CLI**로 한다
  (`ProcessRunning` seam, ADR-0006). 콘텐츠가 클라우드로 가지만 **수신자 불변**(그 대화는 발생
  당시 이미 Anthropic을 거침)이 정당화. 불변식: OAuth 토큰 미사용(CLI 자기 인증, ADR-0002 보존)·
  **on-demand 전용**(먹방 역설)·콘텐츠 요약 **앱 전용 저장**(위젯 노출 금지, ADR-0003 확장).
  A층(메타데이터)은 `TokenHistory`/`HistoryStore`(ADR-0011/0012) **재사용**.
- **`docs/VISION.md` 신설**: POSIWID 렌즈 + 세 층위 거울(A/B/C) + 로드맵(M1 회고 → M2 주간 식단
  결산 → M3 실시간 코칭) + 프라이버시 자세. ADR-0009 먹방 컨셉("주간 식단 결산")과 정합.
- **`docs/RETROSPECTIVE_PLAN.md` 신설**: 5 슬라이스(S1 Kit RetrospectiveBuilder → S2 claude CLI
  seam → S3 앱전용 RetrospectiveStore → S4 on-demand UI[마일스톤] → S5 테스트·문서) + 의존
  그래프 + 측정 가능한 성공기준.
- **문서 정합성**(`.claude/rules/adr.md §4`): ADR 색인·ADR-0002/0003 교차링크·`CLAUDE.md`·
  `ARCHITECTURE.md`(§3 seam 표 + 회고 흐름)·`README.md` §Privacy(콘텐츠 egress 정직화) 동기화.

### Changed — 메인 창 구조를 사이드바(좌측 레일 + 디테일)로 (2026-06-15, ADR-0019 갱신)
상단 탭 구조가 성격·높이가 다른 섹션을 한 컨테이너에 욱여넣어 탭 전환 시 리사이즈/정렬이 충돌(인디케이터가
"대각선"으로 이동)하던 문제를 **구조적으로 해결** — macOS 사이드바 앱 패턴으로 전환(전문가 컨벤션 리서치):
- **`AppShellView`**: 좌측 레일(Now/History/Settings, 아이콘 + 선택 시 accent 하이라이트, 상단 로고 마크 +
  "{plan} plan" 서브타이틀, 하단 새로고침/관전/종료) + 우측 **디테일(각자 독립 스크롤)**. 탭 전환 메커니즘
  자체가 사라져 대각선/리사이즈/여백 문제 소멸. 높이 차이는 그냥 스크롤일 뿐.
- 창은 **자유 리사이즈**(가로·세로, 최소 600×440) + 크기 저장(`setFrameAutosaveName`). behind-window 유리 +
  테마 wash + accent 틴트는 창 전체에.
- 브랜드: 테마 accent 앱-아이콘 풍 로고(`fork.knife`) + 워드마크 + 플랜 서브타이틀(플로팅 pill 폐기).
- 정리: 탭 시절의 `MainWindowRoot`/`DSSegmented` 슬라이드/측정·진단 하니스 제거. `swift test` 78/78 · 빌드 green.

### Changed — 메뉴바 UI를 일반 유리 NSWindow로 (2026-06-15, ADR-0019 supersedes ADR-0018)
커스텀 borderless NSPanel 팝오버(ADR-0018)의 깜빡임/stale-opaque/높이점프/앵커링 우회가 누적돼,
**우리 소유 일반 창은 투명화 가능**하다는 점을 살려 **일반 유리 NSWindow**로 전환:
- `NSWindow([.titled,.closable,.fullSizeContentView])` + 투명 타이틀바 + `isOpaque=false` +
  SwiftUI `VisualEffectBackground`(`NSVisualEffectView(.behindWindow,.underWindowBackground)`)로
  behind-window 유리 유지(ADR-0016). `contentViewController`로 자동 사이징.
- **Now / History / Settings 단일 창 통합** — 상단 세그먼트 탭. 기어 버튼·별도 설정 창 폐기(ADR-0017
  "기어→별도 ⌘, 창"을 본 결정이 갱신). 메뉴바 클릭은 창 토글(앞이면 숨김, 뒤면 앞으로).
- 창 **이동/닫기** 가능, 다른 창과 공존 → 설정 라이브 프리뷰 가능. 블러 강도(`glassOpacity`)는
  `VisualEffectBackground.alpha`로 SwiftUI 반응형 → 라이브.
- `GlassPanel`/present·dismiss·anchor·measure·settingsWindow 전부 제거. 탭 슬라이드 인디케이터는
  내용과 분리(pill만 slide, 내용 즉시 전환)해 전환 중 두 탭 겹침 글리치 해소.
- 문서 동기화: ADR-0019 신설 + ADR-0018 Superseded + 색인/ARCHITECTURE 갱신.

### Added — 유리 블러 사용자 조절(라이브) + 알림 UI 리디자인 + 프리뷰 미니-팝오버 (2026-06-15)
- **배경 유리 블러 슬라이더 (라이브)**: 팝오버 behind-window 블러 베일 알파를 `AppSettings.glassOpacity`
  (0.2…1.0, 기본 0.70)로 노출 — 그동안 `GlassPanel`에 하드코딩이던 값. Appearance 탭 "Glass" 섹션에서 조절.
  설정 창을 열어도 **팝오버를 닫지 않아**(openSettingsWindow 가 더는 dismiss 안 함) 슬라이더를 움직이면
  열린 팝오버의 블러가 **실시간** 갱신(`GlassPanel.updateBlur`, `model.$settings.glassOpacity` 구독). 테마/
  wash 는 SwiftUI 라 이미 실시간. 전역 클릭 모니터는 *타 앱* 클릭에만 반응하므로 설정 창 조작이 팝오버를
  닫지 않음. `AppSettings`에 **forgiving Codable**(`decodeIfPresent`) 추가 — 새 필드가 기존 `settings.json`을
  무효화해 전체 설정이 리셋되는 일 방지. (ADR-0018 결정 자체는 불변 — blurStrength 주입점만 추가.)
- **프리뷰 = 미니 팝오버**: Appearance 프리뷰를 section 카드가 아니라 **faux 데스크톱 + 테마 wash(baseWash) +
  히어로 카드** 3층 ZStack 으로 바꿔, 테마 바꾸면 카드뿐 아니라 **유리 영역 배경색까지** 바뀌게(user 2026-06-15).
- **알림 설정 리디자인**: 투박하던 스위치 평면 나열을 → Surfaces는 선택형 **칩**(5h/7d/Sonnet, accent 틴트),
  Events는 **아이콘 타일 + 제목/부제 + 스위치** 행(iOS 설정 idiom)으로. 이벤트별 색/심볼·한 줄 설명 추가.

### Changed — 전체 영문화(글로벌) + 설정 탭 분리: Appearance / Alerts (2026-06-15)
글로벌 배포 위해 **사용자-노출 텍스트 전부 영어**로 전환 + 설정 IA를 탭으로 정리:
- **영문화**: 먹방 보이스는 유지하되 영어로 — `MukbangCopy`(`73% eaten`·`Digesting ·`·`Clean plate!`·
  `At this pace, all gone in Nh.`·`Dropped the spoon.`), `MukbangZone`/`ModelCast` 라벨(Tasting…Digesting /
  Big Eater·Regular·Light Eater·Gourmet), `DashboardLayout`(Now / History), 알림 카피(NotificationDecider),
  History(Model mix·Fresh tokens·Reheated·Biggest feast·Hungriest project·Other), 위젯/오버레이/툴팁/
  윈도우 타이틀. **테마 이름도 영문**: 숯불→Ember·말차→Matcha·한지→Paper·간장→Jade·오방→Ocean·흑백→Mono
  (enum case 명은 유지, label만 변경 — 영속 설정 호환). 토큰 만료 감지의 `만료` 문자열 매칭 제거(에러는 영문).
- **설정 탭 분리**: "외형(테마)"과 "임계값/알림"은 성격이 달라 한 스크롤에 섞여 있던 걸 상단 세그먼트
  토글 **Appearance / Alerts** 두 탭으로 분리(user 2026-06-15). Appearance=테마 갤러리+라이브 프리뷰+커스텀,
  Alerts=임계값+알림. `SettingsView(initialTab:)`로 렌더 검증(`live-settings-alerts.png` 추가).
- 테스트 동기화(MukbangTests·NotificationDeciderTests·TokenHistoryTests 영문 단언). `swift test` 78/78 · 빌드 green.

### Changed — 설정 창 프리미엄화: 비주얼 테마 갤러리 + 라이브 프리뷰 (2026-06-15, settings-premiumize)
"없어보이던" 설정 창을 다른 앱(macOS 외형 설정·Raycast·VS Code) 수준의 **테마 갤러리**로 재설계:
- **테마 = 자기-프리뷰 스와치 그리드**(3열). 좁은 7-way `DSSegmented`(텍스트만 우겨넣어 빈약) 대체.
  스와치마다 그 방을 미니어처로 렌더 — `baseWash`(방) + 프로스트 카드(`glassTint` over material) +
  accent 점 + heat-ramp 게이지 + 위험 4점. 선택 시 accent 링 + 체크 배지. 고를 때 결과가 보임.
- **라이브 프리뷰**: 선택 테마를 실제 히어로 카드 크롬(GlassTile+StatusChip+GaugeBar)에 적용해 73%
  샘플로 표시 — 평면 스와치가 아니라 진짜 결과를 미리 봄.
- **Custom = 네이티브 컬러 웰**(SwiftUI `ColorPicker`, 옛 hex 텍스트필드 대체). `Color.hexString`로
  `accentHex` 왕복(UISupport).
- **섹션 IA 정비**: 외형/임계값/알림에 SF Symbol 아이콘 + eyebrow 헤더, 간격 리듬 정리. 임계값 슬라이더
  틴트는 선택 테마의 `riskWarning`/`riskCritical`을 따름.
- 검증 렌더 추가: `live-settings-{dark,light,custom}.png`(WindowSnapshot). 색 값/위험 문법 불변
  (ADR-0015 그대로) — 순수 표현 레이어 변경. 빌드 green.

### Changed — 테마 시스템 재설계: 큐레이션 6 rooms (2026-06-13, theme-palette-redesign)
대충이고 특색 없던 테마(Classic/Mint/Sunset/Mono/Custom)를 **정체성이 확 사는 큐레이션 6방 + Custom**
으로 재설계. 색 해석은 전부 앱 측 `ThemeMood`(ADR-0015), Kit은 색-free 유지:
- **6 rooms = 서로 다른 색상환 영역**: 숯불(ember 오렌지)·말차(옐로-그린)·한지(버밀리언, light-first)·
  간장(단청 제이드 + 소이브라운)·오방(블루)·흑백(무채색). 옛 raw value(classic/mint/sunset)는 가까운
  방으로 Codable 마이그레이션(`Theme.init(from:)`).
- 각 방이 **완결 팔레트**: 분위기(`baseWash`·`glassTint`·`accent`) + 위험 4단계(`riskCalm…Critical`+
  `riskOver`, light/dark) + 데이터 식별색(accent로 `dataTint` 만큼 당김). 위험 의미 불변(calm→critical
  순서·빨강=위험); **mono 는 calm/watch/warning 명도 램프 + critical/over instrument-red**(VU 미터
  red-peak — 거의-흰 critical 이 안전처럼 읽힌 문제 해소, 빨강=위험 불변식 mono도 충족).
- **테마가 보이는 자리**: 선택 탭 pill에 accent 틴트+언더라인(가장 중앙 레버), 카드 `glassTint`,
  패널 `baseWash`(alpha↑하되 behind-window 글래스 ADR-0018은 비침). 이전엔 accent가 어디에도 안 보여
  테마가 동일하게 보였던 게 근본 원인 — 이번에 해소.
- 검증 렌더 확장: `live-theme-*`(dark) + `live-themelight-*`(light, 한지/흑백 native scheme 검증) +
  `live-themehist-*`. 문서 동기화(STEAM_DESIGN 테마 섹션 추가). `swift test` 78/78 · 빌드 green.

### Changed — TokenMukbang 전면 리네임 (2026-06-12, ADR-0010 §0 완료)
코드 전체에서 옛 `ClaudeUsage*` 브랜딩 제거 → **TokenMukbang**으로 정렬:
- SPM 패키지 `ClaudeUsageKit`→`TokenMukbangKit`(+`Sources/`·`Tests/`·모든 `import`).
- 앱/위젯 타깃·디렉토리 `ClaudeUsageWidgetApp`/`UsageWidgetExtension`→`TokenMukbang`/`TokenMukbangWidget`.
- 번들 ID `com.claudeusagewidget.*`→`com.tokenmukbang.*`, App Group `group.com.claudeusagewidget`→
  `group.com.tokenmukbang`(project.yml ×2 + `SharedStore.appGroupID`), `CFBundleDisplayName`→TokenMukbang.
- 유일하게 남긴 `Claude`는 `ClaudeAPIClient`(과거 `ClaudeUsageClient`) — *Claude*의 OAuth API 클라이언트라 의도적.
- 문서 동기화(CLAUDE 네이밍 노트·ADR-0010 §0·ARCHITECTURE 등). 빌드 green(app+widget) · `swift test` 77/77.

### Changed — 진짜 glass 팝오버: 커스텀 NSPanel로 재구성 (2026-06-12, ADR-0018)
라이브 피드백 + Apple/ghostty 리서치 끝, `MenuBarExtra`로는 behind-window 유리(뒤 데스크톱 블러)가
원천 불가임을 확인하고 **상태바·팝오버를 직접 소유**하도록 전환:
- **`MenuBarExtra` 제거** → `AppDelegate`가 `NSStatusItem` 생성, 라벨은 `MenuBarLabel`을 버튼 이미지로 렌더
  (`$snapshot`/appearance 변경 시만 — 매 변경 렌더가 버벅임이라). `MenuBarExtraAccess` 의존성 삭제.
- **팝오버 = borderless 투명 `NSPanel`** + contentView 최하단 `NSVisualEffectView(.behindWindow,
  .underWindowBackground, state=.active)` + `NSHostingController(MenuContentView)`. `.state=.active`로
  풀스크린에서도 회색 프로스트 안 끼고 일관. `blurStrength`(blur alphaValue)로 투명도/블러 다이얼.
- **고정 높이(Option B)**: 두 탭 높이를 오프스크린 측정해 큰 쪽으로 고정 → 탭 전환 시 리사이즈 0(무버벅),
  footer는 ZStack으로 바닥 고정.
- **설정 = 컨트롤러 소유 NSWindow** (SwiftUI `Settings` 씬 재오픈 불안정 → 폐기). 닫히면 `.accessory` 복귀.
  `applicationShouldTerminateAfterLastWindowClosed=false`(설정 닫아도 앱 유지).
- **가독성·폴리시**: 헤더 Max/기어를 프로스트 칩으로(투명 유리 위 가독), 아이브로우 `.tertiary→.secondary`,
  카드 하드 보더 제거(소프트 엣지+그림자), 탭 라벨 굵기 고정(전환 시 글자 안 들썩), 김/베일 제거(유리 그대로).
- 빌드 green(app+widget) · `swift test` 77/77.

### Changed — 분위기 테마 + 차트/위험색 테마 연동 + 기질 제거 (2026-06-12)
- **분위기 테마**: 테마가 baseWash·유리 틴트·accent를 바꿈(`ThemeMood`). 위험색은 의미 유지하되 약하게
  테마-틴트(게이지·세션 점·칩), 모델 식별색은 테마 쪽으로 톤 이동(Mono=그레이스케일). 기타는 중성.
- **기질(Temperament) 제거**: 설정에서 삭제(라이브 파이프라인 미연결 + 모호). 스코어러는 `.balanced` 기본.
- **게이지 히트램프 복원**: 단색 → calm→…→현재 티어로 *데워지는* amber→red 램프(개념 목업).

### Changed — 메뉴바 팝오버 IA 재구성 + 라이브 피드백 (2026-06-12, ADR-0017)
실제 앱 실행 + 네이티브 컨벤션 리서치(Control Center·iStat Menus·Stats·Itsycal 등) 반영:
- **하단 탭바 폐기 → 상단 `현황 | 기록` 세그먼트 토글**(위치 고정 → 탭 점프 제거). `DashboardLayout` 3→2 케이스.
- **Settings → 별도 macOS 설정 창(⌘,)**. 헤더 기어가 연다(accessory 앱이라 활성화 정책을 잠깐 `.regular`로
  올렸다 창 닫히면 `.accessory` 복귀). 팝오버는 content-sized + `maxHeight` 캡.
- **게이지 히트램프 그라데이션 복원**(`RiskTone.gaugeRamp`) — 단색 폐기, calm→…→현재 티어로 *데워지는*
  amber→red 램프(개념 목업 04-steam의 의미 복원).
- **자체 베이스 워시**(`Steam.baseWash`) — 팝오버가 데스크톱 벽지에 의존하지 않고 자기 색/깊이를 가짐(밋밋함 해결).
  라이트모드 국물 글로우 alpha ~절반(밝은 배경 peach stain 방지). 검증 도구에 *평범한 데스크톱*(neutralDark/Light)
  백드롭 추가 — 컬러풀 벽지로 과대포장하던 렌더를 정직하게.

### Changed — 디자인 크리틱 반영 (자체 비평 루프, 2026-06-12)
병렬 디자인-크리틱 에이전트(IA·계층·색·네이티브)를 *충실 렌더*(TMK_SNAPSHOT, 실제 material/blur)
위에 돌려 두 라운드 반영:
- **탭 5→3 통합**: 중복 뷰모드였던 Compact/Focus 제거 → 진짜 목적지 셋(**Dashboard / History / Settings**).
  `DashboardLayout` 재정의(+SF Symbol). MODEL HISTORY는 History 탭에만(대시보드 중복 제거).
- **중복 제거**: 페이스 경고/에러 배너를 전 탭 → 대시보드 한정. 헤더 `Max`를 고스트(아웃라인) 칩으로 강등.
- **색 통일·탈채도**: `RiskTone.color`를 desaturate + L\*-밴딩으로 — calm 틸그린 / watch 앰버골드 /
  warning 오커 / **critical 쿨 크림슨 `#C23B4E`**(토마토수프 오렌지레드 폐기). 모델 식별 팔레트도 탈채도.
- **김/국물 절제**: 김 plume alpha **≤0.22 캡**, 국물 0.62→0.40 + *바닥 그라디언트*로 가둠(검은 배경 범람 수정).
  게이지 fill에 density ramp(시작 옅게→선단 엠버) 추가.
- **네이티브 폴리시**: 하단 크롬 축소(탭바=SF Symbol+라벨 세그먼트, 액션=아이콘 전용 한 줄). 종료 빨강 중립화
  (빨강은 위험 채널 전용). GlassTile 보더/스페큘러 scheme-적응 + 그림자 부드럽게. 코너 28/22→18/14.
  Settings 섹션을 GlassTile 카드로 묶음.
- 빌드 green(app+widget) · `swift test` 77/77.

### Changed — 김 서림(Steam) 비주얼 방향 (ADR-0016, supersedes "Liquid Vitals")
- **디자인 방향 전환**: 멀티에이전트 리서치(v1 12종·v2 유리국밥 변주 6종, `docs/design/concepts/`) 끝
  **김 서림(Steam)** 채택 — 위험을 hue가 아니라 *김의 밀도·높이·빛깔*로. 정본 `docs/design/STEAM_DESIGN.md`,
  계획 `STEAM_IMPLEMENTATION_PLAN.md`, 결정 ADR-0016. `DESIGN_SYSTEM.md`("Liquid Vitals") supersede.
- **토큰(S1)**: `RiskTone.steamTint`(김 plume 색·alpha) + `brothGlow`(z0 언더글로우) + `enum Steam`
  표면 토큰(frostPanel/frostTile/scrimNumber/ink/edgeLens/hairline/condensation). `RiskTone`(ADR-0015) 상속.
- **컴포넌트(S2)**: `App/Shared/SteamComponents.swift` — `BrothGlow`·`SteamPlume`(상단 fade 마스크)·
  `Condensation`·`GlassTile` + `.steamBackground(level:isOver:scheme:)`.
- **팝오버(S4)**: 히어로/모니터링/세션을 솟은 `GlassTile` 3겹으로 + z3 김 + z0 broth. 위험↑일수록 김 짙어짐,
  숫자/게이지는 레이어 위 가독 불변.
- **위젯(S5)**: `containerBackground`를 정적 김(broth+프로스트+김 한 프레임, ADR-0003)으로.
- **메뉴바(S3)**: 기존 "5h/7d 둘 다 + 색 %" 라벨 유지 + warning↑일 때만 텍스트 *뒤* 은은한 김 haze(윤곽 아님).
- 빌드 green(app+widget) · `swift test` 77/77.

### Fixed / Added — per-model History breakdown
- **Fable mapping (bug)**: `claude-fable-5` wasn't matched by `ModelCast.forModel` (only
  opus/sonnet/haiku) → ~24% of recent tokens were uncategorized and invisible to the model
  filter. Added `ModelCast.fable` (미식가); unmapped models now fall into an explicit "기타" bucket.
- **Per-model breakdown (Kit)**: `TokenHistory.byCast` (consumed tokens per cast, 기타 incl.) +
  `byDayCast` (per-day model segments) + `summary` (active/cached + cache-hit + Δ vs previous period).
- **History UI redesign**: the daily bar chart is now **stacked by model** (`StackedTokenBarChart`) so
  each day's bar shows its model composition, over a summary header (신선/재가열 tokens + 캐시 적중률 +
  trend badge) and a per-model legend (color · model · total). Model-identity colors via `DS.modelColor`.
  Purely token-based — the API utilization % is a different, **account-wide** metric (covers claude.ai
  web etc., not just CLI), so it's not mixed into the per-CLI-model History (TokenEater does the same).
  Replaces the old combined picker.
- +7 Kit tests (byCast, byDayCast, summary, fable mapping). `swift test` 77/77 green.

### Changed — UI redesign ("Liquid Vitals, Instrument-Grade" design system)
- **Design system** (`docs/design/DESIGN_RESEARCH.md` + `docs/design/DESIGN_SYSTEM.md`):
  scheme-branched risk palette resolved app-side (`RiskTone` in `App/Shared/DesignSystem.swift`);
  Kit stays color-free, emitting only `Window.riskLevel` (rawValue) + `isOver`. 6-rung type scale,
  8pt spacing grid, demoted 6pt `GaugeBar`, single eyebrow + single hairline seam, reusable
  `DSSegmented` control (replaces `Picker(.segmented)`, which mis-renders and reads non-native).
- **Menu bar — typography carries the signal**: one `Text(AttributedString)` with per-run styling —
  `5h`/`7d` unit labels 10pt @ 50% opacity (context), value+% 13pt **bold, risk-tinted** by state.
  Removed the ▲/✕ glyph (color is the cue). Shows **5h + 7d** both, `.monospacedDigit` (no jitter).
  Mascot no longer in the menu bar (popover header chip + widget only).
- **Popover redesign**: hero 28pt % top-right + demoted bar; compact `WindowRow`s on a shared
  right value-column; sessions show a risk-colored dot (the meaning channel) with **neutral** ctx%
  + aligned tty columns; custom footer tab bar; pacing graph hides until ≥2 trend points.
- Dark-mode `watch` toned from neon `#FFD60A` → `#D9B225` (it out-shouted critical red).
- Poll interval 60s → **300s** (was hitting OAuth 429s).

### Added — full TokenEater parity (in progress)
- **Token-consumption data (ADR-0012)**: `JSONLParser` reads real token counts from
  `~/.claude/projects/*.jsonl` (TokenEvent); `TokenHistory` aggregates by day/model/project +
  heaviest-day + top-project — the data behind TokenEater's token History browser.
- **Monitoring space (Area B)**: `PacingCalculator` (equilibrium = elapsed%, delta,
  isAheadOfPace) in Kit `Risk/`; `MonitoringView` with flippable `FlipTile` (front %완식 /
  back sparkline), `PacingEquilibriumView` (sparkline + dashed equilibrium line + delta),
  peak-day + top-project callouts. Classic layout = Monitoring space.
- **Token History browser (Area C)**: `Timeframe` (24h/7d/30d/90d) + `HistoryFilter.tokenEvents`
  (by timeframe + model) in Kit; `HistoryBrowserView` now shows a `TokenBarChart` of daily token
  consumption with hover detail + timeframe/model pickers + heaviest-day/top-project.
- **Settings space (Area D)**: Kit `Settings/AppSettings` — `Theme` (4 presets + custom palette),
  `RiskThresholds` (+ `RiskScorer.level(percent:thresholds:)`), `NotificationSettings`
  (per-surface + per-event), `SettingsStore` (JSON persistence, injectable dir). App `SettingsView`
  (theme picker + custom hex colors + threshold sliders + notification toggles) as a 5th layout;
  theme accent applied to the popover.
- **Notifications (Area E)**: Kit `NotificationDecider` (edge-triggered alerts — escalation /
  recovery / pacing / reset / token-expiry — gated by per-surface + per-event settings, 먹방 copy);
  App `NotificationService` delivers via `UNUserNotificationCenter`, driven from each poll.
- **Agent Watchers floating overlay (Area F)**: Kit `TerminalFocus` extended with
  `SupportedTerminal` (Terminal/iTerm2/tmux/kitty/WezTerm) + WezTerm pane matching by tty; App
  `OverlayController`/`AgentWatcherOverlay` — floating `NSPanel` with dock-like hover, Frost/Neon
  styles, 2-second session scan, click-to-focus-terminal. Toggle from the popover footer.
- **Smart-color temperament (Area G)**: `Temperament` (Confident/Balanced/Suspicious) +
  `RiskScorer.score(…, temperament:)` with early-window confidence damping; Settings picker.
- **Reactive refresh (Area H)**: `FileWatcher` (`DispatchSource`) refreshes immediately when
  Claude Code rewrites its credential file, complementing the 60s poll.
- **Update check + cask (Area I)**: `UpdateChecker` (GitHub `/releases/latest` parse + semver
  compare); `Casks/token-mukbang.rb` Homebrew cask (signed/notarized DMG release is ADR-0010).

### Added — TokenEater feature parity + 먹방 personality
- **먹방 personality (ADR-0009)**: `MukbangZone`/`MukbangFace` (pacing zones, faces, chew
  frames), `MukbangCopy` (완식 POV copy + event lines), `ModelCast` (대식가/평균인/소식좌);
  menu-bar SF Mono mascot that chews on each refresh; popover mascot + status line;
  widget "NN% 완식" framing; `usage-cli --print` 먹방 voice.
- **Smart coloring**: pacing-aware risk (windowStart = resetsAt − window duration) +
  `PaceForecast` "이 속도면 N시간 뒤 완식" warning.
- **Dashboard**: 4 layouts (Classic / Compact / Focus / History) with a segmented picker.
- **History (ADR-0011)**: `HistoryStore` (7-day rolling JSON), `Sparkline.series` bucketing,
  `HistoryFilter` (by ModelCast + timeframe), `HistoryBrowserView`, dashboard usage graphs,
  and a widget sparkline via `UsageSnapshot.headlineSparkline`.
- 19 new unit tests (40 total). All `swift build` / `swift test` / `xcodebuild` green.

## [0.1.0] — 2026-06-11

First working version — a native macOS menu-bar app + WidgetKit widget that monitors
Claude usage, inspired by [TokenEater](https://github.com/AThevon/TokenEater).

### Added
- **`TokenMukbangKit`** — UI-framework-free Swift package holding all logic:
  - Keychain credential reader (`Claude Code-credentials`, read-only, via `security`).
  - OAuth client for `GET /api/oauth/usage` and `/api/oauth/profile`, with ISO-8601
    (fractional-second) date decoding.
  - `Usage` / `Profile` / `RateLimitWindow` Codable models (`5h`, `7d`, `Opus 7d`,
    `Sonnet 7d` windows).
  - Risk scorer blending absolute utilization with pacing → 4-level color mapping.
  - Active Claude Code session detection (`ps` + `lsof` + transcript dirs) with
    context-window fraction from the last assistant `usage` block (≥200k ⇒ 1M window).
  - Best-effort terminal focus: TTY → Terminal.app / iTerm2 tab via AppleScript.
  - `SharedStore` App Group cached-snapshot bridge (app writes, widget reads).
  - `UsageService` orchestrator producing a single `UsageSnapshot`; never throws —
    missing/expired/offline states are surfaced as `snapshot.error`.
- **`usage-cli`** — headless `--print` / `--json` full-pipeline runner (exit 0 even on
  graceful failure; the access token is never printed).
- **Menu-bar app** (`TokenMukbang`) — SwiftUI `MenuBarExtra` with a risk-tinted
  headline, a dropdown panel (usage windows + clickable active-session rows), and a
  60-second refresh loop that re-caches the snapshot and reloads widget timelines.
- **WidgetKit widget** (`TokenMukbangWidget`) — `systemSmall` + `systemMedium` reading
  the cached snapshot (no Keychain/network from the widget sandbox).
- **XcodeGen** project spec (`App/project.yml`) generating the app + widget extension
  targets with correct Info.plist / entitlements (App Group, widget sandbox, `LSUIElement`).
- 21 unit tests covering decoding, risk, context fraction, session parsing, TTY matching,
  formatting, and the orchestrator's graceful-failure paths.

### Verified
- `swift build`, `swift test` (21 pass), `swift run usage-cli --print` (live, no token
  leak), `xcodegen generate`, and `xcodebuild ... BUILD SUCCEEDED` (app + widget) all green.

### Not yet (planned at 0.1.0 — history/sparklines/layouts since landed, see [Unreleased])
- Notifications, preferences UI, auto-launch, code-signed/notarized distribution.
