# STEAM_IMPLEMENTATION_PLAN — 김 서림을 현 코드에 적용하는 계획

> **TL;DR:** [STEAM_DESIGN.md](STEAM_DESIGN.md)(김 서림 정본)를 현 SwiftUI 코드에 입히는 단계별 계획.
> 5개 슬라이스(S1 토큰/팔레트 → S2 김·응결 컴포넌트 → S3 메뉴바 → S4 팝오버 → S5 위젯), 각 슬라이스에
> 검증법. 03 유리국밥 자산(글래스/언더글로우 X — 아직 코드에 없음, 새로 추가)과 Liquid Vitals 자산
> (`RiskTone`/`GaugeBar`/`WindowRow` — 재사용)을 명확히 구분. **이 문서는 계획일 뿐 — 코드는 다음 단계에서.**

## 현 코드 매핑

대상 브랜치 = `design/concept-reports`(= main 기준). 모델별 스택 히스토리(`StackedTokenBarChart`,
`DS.modelColor`)는 이 브랜치엔 **없고** 오픈 PR #2(`feat/per-model-breakdown`)에 있다 — S6에서 합류.

| 코드 지점 (실제 존재) | 지금 무엇 | 김 서림에서 무엇으로 |
|---|---|---|
| `App/Shared/DesignSystem.swift` › `enum RiskTone` (`color`,`menuBarColor`,`contextColor`,`glyph`) | scheme-branched 위험색 resolver | **유지** + `steamTint(level:scheme:)`·`brothGlow(level:scheme:)` 추가(김 빛깔·언더글로우). ADR-0015 그대로. |
| `App/Shared/DesignSystem.swift` › `enum DS` (`heroFont`,`menuBarFont`,`outer`,…) | 타이포/스페이싱 토큰 | **유지** + frost/scrim/steam 토큰 추가(`DS.frostPanel` 등 or 신규 `Steam` enum). |
| `App/Shared/DesignSystem.swift` › `struct GaugeBar` | 6pt 위험색 게이지 | **유지**, 채움 한 단계 차분하게(위험 주채널은 김). over-tick 유지. |
| `App/Shared/DesignSystem.swift` › `struct DSSegmented` | 세그먼트 컨트롤 | 유지(팔레트만 글래스화). |
| `App/Shared/DesignSystem.swift` › `dsEyebrow()` | eyebrow 라벨 | 유지. |
| **(신규)** `App/Shared/SteamComponents.swift` | — (없음) | 새 파일에 z-stack 재사용 View들: **`SteamPlume`**(z3 김 blur plume)·**`Condensation`**(응결 물방울)·**`FrostPanel`/`GlassTile`**(z1/z2)·**`BrothGlow`**(z0). `App/Shared/`에 두는 이유: `DesignSystem.swift`처럼 앱·위젯 **두 타깃이 공유**(project.yml의 `Shared` glob으로 자동 포함, S2에서 별도 project 편집 불필요). |
| `App/ClaudeUsageWidgetApp/ClaudeUsageWidgetApp.swift` › `struct MenuBarLabel` | 비-template color NSImage로 `5h 85% 7d 47%` 렌더(현 시그니처: colored %) | 시그니처 교체: `▓ 85% · 3 ◐` scrim 캡슐 + 텍스트 위 미세 김 plume(`RiskTone.steamTint`). 렌더 경로(`ImageRenderer`+`isTemplate=false`) 재사용. |
| `App/ClaudeUsageWidgetApp/ClaudeUsageWidgetApp.swift` › `final class MenuBarAppearance` | 메뉴바 light/dark 추적(status 버튼 effectiveAppearance) | **유지**(김/스크림 색 분기에 그대로 사용). |
| `App/ClaudeUsageWidgetApp/Views/MenuContentView.swift` (팝오버 루트) | VStack(헤더/content/footer), `.background(.regularMaterial)` | z-stack 도입: z0 `BrothGlow` → `.regularMaterial`(z1) → 기존 content를 `GlassTile`(z2)로 → `SteamPlume`(z3) 오버레이 + `Condensation`. |
| `App/ClaudeUsageWidgetApp/Views/MonitoringViews.swift` › `struct WindowRow` | 라벨·게이지·우측 값 | 유지, GlassTile 안으로. 히어로 윈도우만 별도 타일+히어로 %. |
| `App/ClaudeUsageWidgetApp/Views/UsageRowView.swift` › `struct UsageRowView`,`struct SessionRowView` | 윈도우 row / 세션 row(risk dot=`RiskTone.contextColor`) | 유지, GlassTile 안으로. dot/색 그대로. |
| `App/ClaudeUsageWidgetApp/Views/HistoryViews.swift` | 히스토리 막대(`TokenBarChart`) | 유지(글래스화). 모델별 스택은 PR #2 합류 후. |
| `App/UsageWidgetExtension/UsageWidget.swift` › `SmallWidget`/`MediumWidget` | 위젯(스냅샷 read-only, ADR-0003) | 정적 김 한 프레임(`SteamPlume` 정적 모드) + 그릇 % 중심. 동적 금지. |
| `Sources/ClaudeUsageKit/**` | level enum만 emit(color-free, ADR-0001/0015) | **변경 없음** — 김/색은 전부 앱-측. |

## 슬라이스 단계

각 슬라이스는 독립 빌드 가능하고, 끝에 헤드리스 렌더 스크린샷으로 시각 확인(기존 `TMK_RENDER`/`PopoverRenderer`
파이프라인 재사용).

- **S1 — 토큰/팔레트.** `DesignSystem.swift`에 frost/scrim/steam/broth 토큰 + `RiskTone.steamTint`/`brothGlow`
  추가. 기존 `menuBarColor`는 muted 유지. *검증:* `swift build` + `DEVELOPER_DIR=… xcodebuild … build` green(색만 추가, 뷰 무변경이라 회귀 0).
- **S2 — 김·응결·글래스 컴포넌트(신규 View → `App/Shared/SteamComponents.swift`).** `SteamPlume`
  (RadialGradient/Ellipse + `.blur` + 상단 `.mask` fade), `Condensation`, `FrostPanel`/`GlassTile`, `BrothGlow`.
  단독 프리뷰로 4단계(calm/watch/warning/critical) 렌더. *검증:* xcodebuild green + 헤드리스 렌더로 4레벨 plume 스크린샷 → 김 밀도/빛깔 단계 확인.
- **S3 — 메뉴바.** `MenuBarLabel` 시그니처 교체(scrim 캡슐 + 미세 김). `MenuBarAppearance` 재사용. *검증:*
  `PopoverRenderer.renderMenuBar` 라이트/다크 스크린샷 → 김 줄기 + 가독성(불투명 scrim) 확인. 라이브 앱 메뉴바 육안.
- **S4 — 팝오버.** `MenuContentView`에 z-stack 적용(z0 BrothGlow → material → GlassTile content → SteamPlume +
  Condensation), 히어로 윈도우 타일화. 마스킹으로 김이 숫자/게이지 침범 안 하게. *검증:* `TMK_RENDER` classic
  라이트/다크 스크린샷 → §6 가독성 불변식 체크리스트 전 항목.
- **S5 — 위젯.** `UsageWidget.swift` Small/Medium에 정적 김 한 프레임 + 그릇 %. *검증:* xcodebuild(app+widget)
  green. (위젯 헤드리스 렌더는 별도 plumbing — 라이브 위젯 육안 또는 SwiftUI Preview.)
- **S6 — 모델 히스토리 합류(PR #2 의존).** `feat/per-model-breakdown` 머지 후 `StackedTokenBarChart`/
  `DS.modelColor`에 Steam 토큰 적용. *검증:* history 헤드리스 렌더.

> 의존성: S1 → S2 → (S3 ∥ S4) → S5. S6는 PR #2 머지 게이트. 각 슬라이스는 별도 커밋/PR 가능(작게).

## 문서 정합성 (코드 단계에서)
- 채택 시 `docs/design/DESIGN_SYSTEM.md`는 [ADR-0016] 따라 STEAM_DESIGN.md로 **대체**(상단에 superseded 배너 +
  링크) 또는 STEAM_DESIGN로 내용 이관. `CLAUDE.md`/`ARCHITECTURE.md`의 "Liquid Vitals" 언급을 김 서림으로 갱신.
- `CHANGELOG.md`에 비주얼 방향 전환 한 줄.

## 리스크 & 폴백
- **다겹 blur 성능(z0+material+z3):** 김 plume 정적 캐싱(`drawingGroup()`/사전 렌더), 동적은 critical 팝오버 한정.
- **위젯 정적:** 김의 "모락모락"은 한 프레임 정적으로 타협(ADR-0003 — 위젯은 스냅샷만). 손실 수용.
- **김이 콘텐츠 가림:** 상단/타일-사이 마스킹 + 숫자 scrim 격리(불변식). 각 슬라이스 검증에 가독성 체크 포함.
- **메뉴바 김 높이 부족(~22px):** 높이 대신 밀도·색으로 위험 표현(§4.1). 안 되면 scrim 캡슐 테두리 글로우로 폴백.
- **계획 ↔ PR #2 충돌:** 모델 히스토리는 S6로 격리, PR #2 머지 후 합류 — 그 전엔 현 히스토리 막대만 글래스화.
