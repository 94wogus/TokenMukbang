# TokenMukbang — Design Research Report

> **TL;DR:** 추천 방향은 **"Liquid Vitals, Instrument-Grade"** — Liquid Vitals(글래시-에어리, hero-% 우선)를 척추로 삼되, Cockpit Mono의 **모든 숫자 우측정렬 `.monospacedDigit()` 값 컬럼**과 **APCA-튜닝된 라이트모드 risk hex**를 이식하고, Counter Service의 eyebrow 리듬은 **단 1개 섹션 구분**으로 축소한 하이브리드다. 4-lens 평점에서 Liquid Vitals가 hierarchy·color 양쪽 최고점(7/7)을 받았고 기존 MenuBarExtra/SwiftUI 코드베이스에 가장 네이티브하게 얹힌다 — 다만 정렬 스캐폴드·라이트모드 대비·vibrancy 의존 구분 3가지 구멍을 다른 두 방향에서 보강한다.

핵심 원칙: **하나의 threshold 함수가 모든 표면을 구동**하고(`<0.5 safe / <0.8 warn / else danger`), **깊이는 머티리얼+틴트로(그림자/하드보더 금지)**, **숫자는 우측정렬 monospacedDigit**, **숫자+게이지는 항상 함께**, **리셋 카운트다운은 100%가 아니라 항상 노출**, **먹방 개성은 데이터 평면이 아닌 엣지에만**.

---

## 1. 리서치 요약 (Angle별)

### 1.1 네이티브 메뉴바 유틸리티 팝오버 (Raycast, iStat, Stats, Vitals, Bartender)
- **그림자 아닌 색-사다리로 깊이 표현.** Raycast는 드롭섀도우 0개 — 4단계 near-black 사다리로 elevation. TokenMukbang은 이 기법을 시스템 vibrancy 머티리얼 + 1~3% 틴트필로 번역해야 한다.
- **헤어라인 디바이더는 저-opacity로, 드물게.** 행마다 긋지 말고 기능 카테고리 사이에만(usage 블록 vs Agent-Watchers).
- **8px 그리드 + 타이트 내부 스케일.** 16 outer / 12 section / 8 row / 6-8 inner. ad-hoc 7·13은 developer-made 신호.
- **점진적 정보 레이어링** (iStat "glance → dropdown → hover"): 메뉴바=깔끔한 컬러 숫자, 팝오버=차분한 게이지, 디테일은 엣지/hover.
- **행 해부학: 아이콘-좌 / 라벨-중앙 / 값-우, 우측정렬 tabular 숫자.** 이것이 "polished vs developer-made"의 #1 신호. SF Mono / `.monospacedDigit()` 필수.
- **악센트 색은 드물고 의미적, 본문은 그레이스케일.** 색은 의미만 운반(green/amber/red). 먹방 색은 헤더 엣지에만.
- **단조 중첩 radius 어휘** (4/6/8/10/9999), **타입 계층은 디바이더 아닌 size+weight+color로.**
- **네이티브 메커닉이 기본기:** MenuBarExtra(.window)/NSHostingView로 즉시 열림 + 클릭아웃 dismiss. NSPopover 랙은 즉시 developer-made로 읽힘.
- **Vitals식 절제 + per-agent 60s 스파크라인:** 바
어 숫자 대신 추세를 작게.

### 1.2 메트릭/사용량/한도 대시보드 (Vercel, Grafana, Apple Watch, Screen Time, Copilot)
- **숫자 + 게이지는 항상 함께, 게이지 단독 금지.** '92% · 18.4k / 20k' — 큰 숫자가 BAN(eye lands first), 게이지는 보조.
- **신호등 임계값, green 기본** (≤70 green / 70-90 amber / ≥90 red), 하나의 함수에서 파생.
- **색은 단독 신호가 아님** (8% 적록색약): 아이콘/라벨/모양/굵기로 이중화.
- **방사형 게이지의 over-goal 오버랩** (Apple Watch): 100% 초과를 wrap으로 표현, clip 금지.
- **리셋 카운트다운은 100%가 아니라 선제적으로 항상 노출** — Claude Code/Codex/Copilot 이슈 전반의 #1 UX 갭. 'resets in 2h 13m' + hover 시 절대 시각.
- **추세는 스파크라인으로 메트릭과 페어**, 단독 차트 아님. History는 Screen Time식 stacked daily bar + 'other' 그레이.
- **투영("~Xh 후 소진")은 estimate** — 라벨링하고 노이즈 클 땐 숨김 (macOS 배터리 'time remaining' 제거 교훈).

### 1.3 현행 macOS 머티리얼/HIG (Sonoma → Tahoe 26 Liquid Glass)
- **메뉴바 라벨 색 제약 = #1 함정.** SwiftUI MenuBarExtra 이미지 라벨은 monochrome 템플릿 강제. 진짜 컬러 숫자는 non-template NSImage(isTemplate=false) 또는 NSStatusItem.attributedTitle 필요.
- **팝오버 머티리얼:** Tahoe 26은 팝오버 chrome이 이미 Liquid Glass — 루트에 glassEffect() 이중적용 금지. 데이터 행/게이지 뒤엔 절대 glass 금지(content layer는 머티리얼 위 차분하게).
- **하위호환:** `if #available(macOS 26.0, *)` 게이트 + `.ultraThinMaterial` fallback을 단일 `adaptiveGlass()` 헬퍼로.
- **동심 코너** (`.containerConcentric`, `ContainerRelativeShape`), **8pt 그리드**, **SF Pro 시맨틱 텍스트 스타일 + `.monospacedDigit()`**, **시맨틱 다이내믹 컬러.**

### 1.4 마스코트 앱의 엣지-개성 봉인 (Duolingo, Finch, Arc, Things, Raycast)
- **지배 법칙(Walter):** "감성 디자인은 절대 usability를 침해하면 안 된다" — 'accuracy > cuteness'의 출처.
- **개성은 타임라인/상태 경계에만**, 정상 데이터 뷰에는 없음. (Arc는 탭 0개일 때만 fidget 등장.)
- **빈 상태가 공인된 놀이터** — 오독할 숫자가 없으니 cuteness 비용 0.
- **카피/마이크로카피가 가장 싼 개성 채널** — 텍스트라 글리프를 손상 안 함.
- **닫힌 모듈형 캐릭터 시스템** = 일관·봉인 (Duolingo 모듈 rig). kaomoji는 이미 닫힌 face 집합.
- **베이비스키마 온기는 마찰 지점(한도 도달)에서 정확히 사용** — 차가운 'LIMIT REACHED' 대신.

### 1.5 컴팩트 팝오버 색+타이포 토큰 시스템 (Radix, Linear, Carbon, Apple)
- **risk = 3-stop 시맨틱 램프**(safe/warn/danger, +over), Apple 다크적응 시스템 컬러에 앵커. 기존 `UISupport.swift`의 `contextColor`(#34C759/#FF9F0A/#FF453A)가 이미 올바른 척추.
- **나머지는 3-role 시맨틱**(background/foreground/border)을 macOS 시맨틱(labelColor 등)에 매핑.
- **Radix 12-step 멘탈모델을 macOS 시맨틱에 매핑** — 11/12가 APCA 대비 backbone. 악센트(9-10)는 작은 텍스트로 쓰지 말 것.
- **타입 스케일은 iOS 아닌 macOS 메트릭**(Body 13pt). 6-rung + 3 weight(regular/medium/semibold)만.

### 1.6 작은 공간 데이터 시각화 (Tufte 스파크라인, 게이지, actual-vs-ideal)
- **bank to 45도, 크롬 제거**(축/그리드/범례/프레임 삭제). 숫자=정밀, 스파크라인=맥락.
- **endpoint + min/max 도트**, **정상/기준 밴드를 라인 뒤에** = actual-vs-ideal pace의 핵심.
- **게이지는 숫자 primary, 링 secondary.** 메뉴바 팝오버엔 needle 게이지 금지.
- **연속=line / 이산=micro-bar**, **콜드스타트 우아한 강등**(0pt=마스코트 빈상태, 1-3pt=도트/바, 고정 y-range).
- **History는 small-multiples**(동일 스케일, 공유 기준 밴드).

---

## 2. 종합 원칙 + 텐션

### 2.1 핵심 원칙 (수렴점)

| # | 원칙 |
|---|------|
| 1 | **하나의 threshold 함수가 모든 표면 구동** — `contextColor` 램프를 `RiskTone` enum으로 승격, 메뉴바·게이지·링·행이 한 함수에서 파생 |
| 2 | **깊이는 머티리얼+틴트, 그림자/하드보더 금지** — major region 사이 헤어라인 1개만 |
| 3 | **우측정렬 monospacedDigit 숫자 = #1 polish 신호** |
| 4 | **숫자+게이지 항상 함께, 게이지 단독 금지** |
| 5 | **리셋 카운트다운 항상 노출(100% 아님)** |
| 6 | **색은 단독 신호 아님** — 모양/글리프/굵기/숫자로 이중화 |
| 7 | **밀도 티어 = 점진적 레이어링** (메뉴바→Compact→Monitoring→History) |
| 8 | **8px 그리드, ad-hoc 값 금지** |
| 9 | **단조 중첩 radius, 시스템 코너는 동심** |
| 10 | **타입 계층은 size+weight+color**(macOS 메트릭, 3 weight만) |
| 11 | **개성은 타임라인/엣지에만, 데이터 평면 금지**(나쁜 소식 순간에 가장 온기) |
| 12 | **마스코트 = 닫힌 상태매핑 vocabulary**(content/nibbling/warning/stuffed/sleeping) |
| 13 | **네이티브 메커닉이 기본기** (즉시 열림 + 클릭아웃 dismiss) |
| 14 | **타이니-차트 절제**(크롬 제거, word-sized, endpoint 도트) |
| 15 | **앱+위젯+오버레이 단일 토큰 소스**(UISupport.swift) |

### 2.2 텐션 (충돌과 해소)

| 텐션 | 해소 |
|------|------|
| **컬러 메뉴바 숫자 ↔ SwiftUI 템플릿 강제** | non-template NSImage 또는 attributedTitle; 시스템 status color(라이트+다크 안전); 빌드시 설치된 macOS 검증 |
| **Liquid Glass 열정 ↔ 더블글래스/데이터층 mud** | 팝오버 루트에 glassEffect 금지; floating accent에만; `#available` 게이트 + `adaptiveGlass()` |
| **투영("~Xh 후") ↔ accuracy > cuteness** | 하드 숫자는 prominent·정밀; 투영은 hedged secondary, 노이즈 클 때 숨김 |
| **개성 예산 ↔ 차분한 데이터** | 개성은 카피에 + threshold/reset/empty/launch에만; 라이브 게이지엔 kaomoji 금지 |
| **Raycast 리터럴 hex ↔ 반투명 라이트+다크** | 기법만 채택, neutral은 macOS 시맨틱 위 머티리얼; raw hex는 위젯 fallback만 |
| **악센트 숫자 ↔ 작은 텍스트 대비 실패** | 읽는 숫자는 neutral, 악센트는 게이지/링/도트에만(메뉴바 글리프만 예외) |
| **line vs bar + 콜드스타트** | 연속=라인(≥5pt), 이산=micro-bar; MiniSparkline 임계값 강화 |
| **사용자 재배열 ↔ 고정스택 단순성** | 기본 glance는 단순, collapse/reorder는 Settings opt-in |

---

## 3. 제안 3방향

### 3.1 Liquid Vitals (글래시-에어리)
- **톤:** 차분한 시스템-네이티브 계기판이 vibrancy 위에 떠 있음. 밀도보다 호흡.
- **컬러 토큰:** neutral은 시맨틱(.regularMaterial / .labelColor / .secondaryLabelColor). card = white 6%/5% 틴트필. hairline = white 0.12/0.10 (major region에만). risk = 시스템 status(safe .systemGreen, warn .systemOrange, danger .systemRed), over(≥100%) = #FF2D55/#FF375F 핫 마젠타-레드. 게이지 트랙 = white 0.10.
- **타이포:** 6-rung, 3 weight. Display **28pt semibold SF Rounded .monospacedDigit**(hero % 단독, 유일한 데이터평면 온기). Title 15pt semibold. Value 13pt medium .monospacedDigit SF Pro 우측정렬. SF Rounded는 hero %와 kaomoji 칩만.
- **레이아웃:** 16 outer / 12 section / 8 row. 카드 대신 whitespace 구분, hairline은 Agent-Watchers 경계 1개만. 320px 팝오버: 헤더[kaomoji 24px | 'Session' | hero 28pt % 우] → 게이지+리셋(6pt 바 + countdown) → 스파크라인(≥5pt) → expandable breakdown. 메뉴바 '72%' non-template NSImage, danger 시 ▲.
- **개성:** kaomoji 칩이 닫힌 mood enum 1:1 매핑, steady-state 무애니메이션. 빈 History가 최대 마스코트 순간.
- **트레이드오프:** whitespace-우선 → 낮은 밀도(power user엔 sparse). 시스템 머티리얼 의존 → OS vibrancy 변화에 매 릴리즈 재검증 필요.

### 3.2 Cockpit Mono (컴팩트-덴스-프로)
- **톤:** iStat/Bartender급 계기 밀도. tabular monospaced 제어 표면, 장식 0.
- **컬러 토큰:** near-monochrome + 드문 악센트. 틴트필 사다리(card.1 4%, card.2 6%, hover 8%). risk는 **작은 텍스트 대비 튜닝** — safe #248A3D/#30D158, warn #B25000/#FF9F0A(라이트 깊은 오렌지), danger #C9342B/#FF453A, over #A21B3A/#FF375F. 악센트는 읽는 숫자에 절대 안 씀(게이지/링/도트만).
- **타이포:** Display 22pt semibold SF Pro(rounded 아님 — tabular 정밀과 맞바꿈). Body 12pt regular .monospacedDigit 전 숫자행. SF Rounded는 kaomoji 칩 1곳만.
- **레이아웃:** 16 outer / 8 section / 6 row. 300px(좁은 끝): 게이지 행 = [아이콘 | 'Session' | 바 5pt | '92%' | '·' | '18.4k/20k'] + 10pt 리셋 캡션. 동시 한도는 stacked micro-bar(한도별 고정 hue), maxed는 100% 초과 오버랩.
- **개성:** 가장 절제(Vitals급). 마스코트는 헤더 칩 + 빈상태 + 토스트만, dense 행 스택엔 절대 없음.
- **트레이드오프:** 최대 정보밀도 but 캐주얼 유저엔 인지부하·차가움. hero에 rounded 없어 데이터평면 온기 희생(먹방 charm 과소전달 위험). 라이트 hex 분기로 UISupport.swift 코드 증가.

### 3.3 Counter Service (웜-에디토리얼)
- **톤:** 따뜻한 먹방 점심 카운터, 그러나 영수증은 존중. 에디토리얼 타이포 계층 + 미세한 웜 neutral.
- **컬러 토큰:** 웜-틴트 neutral(card에 #8A6A4012 웜 오버레이). sand 악센트 #B5854B/#D9A86A는 **chrome 전용**(헤더 룰/eyebrow), risk 신호엔 절대 안 씀. risk는 정규 시맨틱 척추 유지(systemGreen/Orange/Red + over #FF2D55/#FF375F). sand와 risk는 역할 분리.
- **타이포:** SF Rounded를 더 많이(non-data 슬롯만). Display 26pt semibold SF Rounded. 10pt UPPERCASE letterspaced 'eyebrow'(에디토리얼 tell). 데이터 숫자는 SF Pro tabular 유지(rounded 아님).
- **레이아웃:** 340px(넓은 끝). 웜 배너 헤더[kaomoji 28px | 'Today at the counter' | hero 26pt %] + sand 룰. eyebrow 'SESSION' → 게이지(링) + 리셋 → 'BURN' → 스파크라인 → 'HISTORY' → small-multiples + 리셋 마커. 메뉴바는 엄격히 clean(온기/kaomoji 없음).
- **개성:** 가장 먹방-forward(28px 배너) but 여전히 엣지+카피 주도. 라이브 게이지/숫자는 SF Pro tabular 무표정. 빈 History가 최대 set-piece.
- **트레이드오프:** 최대 개성·최친근 but 웜 틴트가 다크모드/Reduce-Transparency에서 muddy 위험(near-zero로 떨어뜨려야). 넓은 폭·에디토리얼 break로 밀도↓. eyebrow+sand가 chrome 추가 → 'cuteness becomes chrome' 실패 위험.

---

## 4. 4-Lens 비평 점수

| 방향 | Hierarchy & 가독성 | Layout 구성·균형 | Color & 톤 적합 | SwiftUI 실현·네이티브 | 평균 |
|------|:---:|:---:|:---:|:---:|:---:|
| **Liquid Vitals** | **7** | 5 | **7** | 6 | **6.25** |
| **Cockpit Mono** | 5 | 6.5 | 7 | 6.5 | 6.25 |
| **Counter Service** | 5 | 6 | 6.5 | 6 | 5.875 |

**lens별 핵심 지적:**
- **Hierarchy:** Liquid Vitals의 hero-% focal + demoted-bar Z-flow가 "계층의 척추, 옳다"로 반복 호평. 단 kaomoji가 hero 행에서 LTR 진입점 충돌 + 'two rounded objects' 위반. Cockpit/Counter는 22-26pt hero가 first-landing 지배력 부족.
- **Layout:** Liquid Vitals(5)는 수평 값-컬럼 정렬 미정의 → "에어리가 sloppy로 읽힘". Cockpit의 tabular 값 컬럼이 최강 결정이나 6-요소 행은 내부 모순(바 mid-row가 trailing 값과 충돌).
- **Color:** Liquid Vitals·Cockpit 둘 다 risk를 시스템 색에 앵커 + 숫자 neutral 유지로 호평. Cockpit의 라이트모드 hex 심화는 "honest engineering". Counter의 sand는 warn-orange와 hue 근접 위험.
- **SwiftUI:** 셋 다 메뉴바 non-template NSImage 주장이 현행 Text+foregroundStyle 네이티브 경로 대비 후퇴. Counter의 웜 머티리얼 오버레이는 "core feasibility trap"(SwiftUI tint hook 없음). Cockpit의 over-100% 오버랩은 ProgressView 재구축 강제.

---

## 5. 최종 추천: "Liquid Vitals, Instrument-Grade"

**선택:** Liquid Vitals 척추(글래시-에어리 hero-우선) + Cockpit Mono의 tabular 값-컬럼 규율·APCA-튜닝 라이트모드 risk hex + Counter Service의 eyebrow를 1개 섹션 break로 강등한 하이브리드.

**근거:** Liquid Vitals가 glance-tool에 가장 중요한 두 lens(hierarchy 7, color 7) 최고점 + 기존 코드베이스에 가장 네이티브(시맨틱 색 + 단일 hairline = 카드 스택보다 framework-risk 낮다고 명시). 다만 자체 layout 점수(5)가 드러낸 3구멍 — 수평 정렬 미정의, 라이트모드 risk hex APCA 실패, whitespace-only 구분의 vibrancy 의존 — 을 다른 두 방향이 이미 해결했으므로 graft한다. Cockpit/Counter를 base에서 reject: Cockpit hero는 first-landing 지배력 없음 + 6-요소 행 모순, Counter 웜 머티리얼은 네이티브 tint hook 없고 Reduce-Transparency 외형 미정의 + 28px 배너가 온기를 center로.

### 5.1 최종 컬러 토큰

**서피스(시맨틱):**
- `surface.base` = `.regularMaterial` (팝오버 body, 절대 hand-glass 안 함, 머티리얼 이중스택 금지)
- `surface.card` = white 6%(L)/5%(D) 틴트필 (primary 구분자 아님, 절제 사용)
- `surface.hover` = white 10%/8%, `surface.selected` = controlAccent 14%
- `border.hairline` = white 0.12(L)/0.10(D), `.overlay(alignment:.bottom){ Color(.separatorColor).frame(height: 1/displayScale) }`로 sub-pixel 방지. major region seam 1개 + eyebrow seam 1개만
- `fg.primary/secondary/tertiary` = `Color(.labelColor / .secondaryLabelColor / .tertiaryLabelColor)`
- 게이지 트랙 = white 0.12(L)/**0.14(D)** (다크 fill-vs-track 분리 위해 bump)

**RISK 스케일 — scheme-branched, 앱사이드 `RiskTone` resolver(Kit 아님; Kit은 UI-free enum만, resolver가 `@Environment(\.colorScheme)` 읽음):**

| 레벨 | Light | Dark | 비고 |
|------|-------|------|------|
| safe | #1E7B34 | #30D158 | |
| watch | **#946800** | #FFD60A | 라이트는 다크 골드(#FFD60A는 흰 배경 최악 대비) |
| warn | #A8521A | #FF9F0A | burnt amber — danger와 5pt fill에서 구별 검증 |
| danger | #C0271E | #FF453A | pure red |
| over (≥100%) | #A21B3A | #FF375F | **+ 비색 cue 항상 페어**(바가 tick 넘어 break + ✕ 글리프) |

- risk 색은 **게이지 fill / 링 / endpoint 도트에만**, 작은 읽는 숫자엔 절대 안 씀.
- `controlAccentColor`는 non-risk affordance 전용, meaning 채널에서 **fenced out**(유저 설정값이라 warn/danger와 충돌 가능).
- 메뉴바: 같은 resolver tint + danger ▲ / over ✕ (그레이스케일·dimmed bar 생존).
- 위젯(시스템 외형 따름 → 같은 scheme 분기 필요): `.containerBackground(.fill.tertiary)` 선호, fallback #F2F2F7/#1C1C1E + 같은 risk hex.
- 기존 별도 `contextColor` 램프를 같은 resolver로 마이그레이션(병렬 risk 팔레트 2개 금지).

### 5.2 최종 타입 스케일 (6-rung, 3 weight, SF Rounded는 정확히 2객체)

| Rung | 스펙 | 용도 |
|------|------|------|
| Display | 28pt semibold **SF Rounded** .monospacedDigit | hero % 단독(유일 데이터평면 온기; 28→15pt가 유일한 명확 지배 step) |
| Title | 15pt semibold SF Pro | 섹션 헤더 |
| Eyebrow | 10pt medium UPPERCASE tracking~0.6 .tertiary SF Pro | major seam 1회만(섹션별 아님) |
| Body/Label | 13pt regular SF Pro, **라벨은 .secondary** | label-vs-value를 opacity+weight 2축 분리 |
| Value | 13pt medium .monospacedDigit SF Pro 우측정렬 tabular | 데이터 숫자(rounded 아님; hero와 둘 다 monospacedDigit → '큰 72%=작은 72%' 동일객체 read) |
| Reset | 13pt regular SF Pro .secondary .monospacedDigit **PERSISTENT** | primary 모니터링 데이터(10pt-tertiary-on-hover에서 승격), hover 시 절대 시각 |
| Caption | 10pt regular .tertiary | 타임스탬프만 |

### 5.3 핵심 레이아웃 무브

1. **헤더 = 2행(3-요소 줄다리기 아님):** 상단 = kaomoji 칩 20px + Title 좌, shared firstTextBaseline; hero 28pt % 우측정렬, 헤더 블록 전체에 수직 중앙. kaomoji가 hero 행에서 빠짐 → LTR 진입점 충돌 + 'two rounded objects' 위반 동시 해결.
2. **단일 우측 정렬 spine(16pt inset):** hero %, 모든 행 Value, used/limit, 리셋 카운트다운, 스파크라인 endpoint 도트가 한 invisible right gutter 공유 — Cockpit의 tabular 컬럼 이식. whitespace=수직 리듬, 공유 gutter=수평 정렬.
3. **demoted-bar Z-flow 보존:** hero %(우) → 6pt full-width 바(같은 숫자 보조 echo) → PERSISTENT 리셋 카운트다운(바 시작 아래 좌정렬 but 숫자는 right gutter). over-state: 바가 100% tick 넘어 break + ✕(hue split 비색 백업).
4. **메뉴바 ruthlessly clean:** 단일 .monospacedDigit % 토큰, scheme-aware risk tint, danger ▲ / over ✕. **SwiftUI Text + .foregroundStyle(riskColor) 유지**(기존 네이티브 경로) — hand-rasterize non-template NSImage 안 함(자동 dimming 손실, 컬러 숫자 요건은 Text로 이미 충족).
5. **멀티게이지/Compact 계층 정의(모든 방향이 남긴 갭):** 단일 hero 없을 때 눈은 최고-risk 게이지에 — 행을 risk 내림차순 정렬(최악 top-left), top 행 %에 1-rung 크기 bump(15pt semibold) relative hero, 게이지 컬럼 min-width 예약(긴 라벨이 바를 stub로 굶기는 것 방지). 동시 한도는 한도별 고정 neutral hue.
6. **region 구분 vibrancy 대비 강화:** whitespace 단독 의존 금지. major seam(usage ↔ Agent-Watchers)에 hairline 1개 + neutral eyebrow 1개; white-6% 카드 틴트가 밝은 데스크탑 위 edge 유지하는지 검증, Reduce-Transparency OFF 시 faint inner-shadow fallback. `.containerConcentric`/Tahoe-26 radius는 `#available` 점진 enhancement, 고정 radius(12 card / 8 inner pill / 9999 chip) baseline(deployment target macOS 14).

---
