# ADR-0022: 세션 완료 알림은 트랜스크립트 `stop_reason`을 reactively 감시해 보낸다

- **Status:** Accepted
- **Date:** 2026-06-26

## Context

여러 Claude Code 세션을 동시에 돌릴 때, 사용자는 "어떤 세션이 작업을 끝내면 알림을 받고,
그 알림을 누르면 그 세션의 터미널로 점프"하길 원했다(원문: "작업 완료되면 알람을 받고 싶음 …
누르면 그 창으로 갈 수 있나?"). 특히 그 세션이 **VS Code 내장 터미널**에서 도는 경우가 잦다.

기존에 알림은 사용량 스냅샷 비교(edge-triggered)로만 발생했고(escalation/recovery/pacing/
reset/tokenExpiry — `NotificationDecider`), 세션 단위 "작업 종료" 신호는 없었다. 두 가지 힘이
설계를 좌우했다:

1. **타이밍.** 사용량 폴은 5분 간격(ADR-0014의 reactive 보강이 있어도 기본은 폴)이라,
   한 작업이 폴 사이에 시작·종료하면 알림이 누락되거나 수 분 늦는다 — "끝나면 바로"라는
   요구를 못 채운다.
2. **"끝남"의 정의.** 트랜스크립트 `.jsonl` 마지막 assistant 메시지의 `stop_reason`이
   `end_turn`/`stop_sequence`면 턴이 진짜 끝나 사용자 입력 대기 상태고, `tool_use`거나
   마지막 줄이 `user`면 아직 작업 중이다. 이 신호는 실제 트랜스크립트에 항상 존재한다.

## Decision

**각 활성 세션의 트랜스크립트 파일을 `FileWatcher`(ADR-0014)로 reactively 감시**하고,
`working → idle` 전이가 감지되면(= assistant가 `end_turn`/`stop_sequence`로 턴 종료) **세션
완료 알림을 보낸다.** 알림 탭 시 **그 세션의 터미널을 포커스**한다(ADR-0008 재사용).

- **"끝남" 판정은 순수 함수로 Kit에 둔다** — `SessionActivityReader.activity(...)`가
  트랜스크립트 텍스트에서 `SessionActivity`(`working`/`idle`)를 도출한다(ADR-0001, 유닛
  테스트). 마지막 assistant 메시지의 `stop_reason ∈ {end_turn, stop_sequence}` ⇒ `idle`,
  그 외 전부(`tool_use`, 마지막 줄이 `user`, `stop_reason` null/스트리밍 중) ⇒ `working`.
- **오케스트레이션은 앱에 둔다** — `SessionActivityWatcher`(App)가 스냅샷의 세션 목록에 맞춰
  세션별 `FileWatcher`를 reconcile(추가/제거)하고, 변경 콜백에서 활성 상태를 다시 읽어
  **edge-triggered**로 `working→idle`일 때만 알림을 1회 보낸다. 새 세션은 **현재 상태로
  seed(알림 없이)** 하여 "앱 시작 시 이미 쉬고 있던 세션"의 헛알림을 막는다.
- **전 세션 대상, 세션 단위 토글.** 모든 활성 세션의 완료를 알린다(긴 작업 한정 아님).
  `NotificationSettings.sessionFinished`(기본 on)로 켜고 끈다 — 윈도우 surface 칩(5h/7d/
  Sonnet)과 무관한 세션 스코프 토글.
- **알림 탭 → 포커스.** 완료 알림은 `userInfo`에 세션 식별자(pid/tty/cwd)를 실어 보내고,
  `NotificationCoordinator`(`UNUserNotificationCenterDelegate`)가 탭을 받아 `ActiveSession`을
  복원해 `TerminalFocus.focus(...)`를 호출한다(ADR-0008).
- **VS Code 등 에디터 내장 터미널은 best-effort로 "앱만 앞으로"** — ADR-0008을 확장해,
  세션 pid의 부모 프로세스 체인(`ps -axo pid=,ppid=,comm=`)을 거슬러 올라가 호스트 에디터
  (Visual Studio Code / Cursor / Windsurf / VSCodium 등)를 식별하면 그 앱을 `activate`한다.
  특정 split 패널 포커스는 공개 API가 없어 하지 않는다(의도된 한계).

이 기능은 사용자 콘텐츠를 기기 밖으로 보내지 않는다 — 트랜스크립트를 **로컬에서 읽어
`stop_reason`만 본다**(ADR-0020의 egress와 무관). 위젯이 읽는 `SharedStore` 스냅샷 스키마도
바꾸지 않는다(활성 상태는 앱 전용 — ADR-0003 유지).

## Consequences

- ➕ 세션이 끝나는 **즉시** 알림(폴 대기 없음) — `FileWatcher`가 `end_turn` 기록 시점에 깬다.
- ➕ 알림 탭으로 그 세션 터미널로 점프(기존 `TerminalFocus` 재사용). VS Code 세션은 앱만 앞으로.
- ➕ 판정 로직이 순수·결정론적(유닛 테스트). 오케스트레이션은 기존 `FileWatcher`/알림 인프라 위에.
- ➖ 빠른 Q&A 한 턴도 `working→idle`이라 알림이 뜬다(전 세션 대상 선택의 결과). 필요하면
  추후 "최소 작업 시간" 게이트를 추가할 수 있다(이번 스코프 아님).
- ➖ 변경 콜백마다 트랜스크립트를 다시 읽는다(메시지 단위 append라 빈도는 낮지만 파일 전체 스캔).
  대형 트랜스크립트에서 비효율 여지 — 현재는 단순성 우선.
- ➖ VS Code는 특정 패널이 아니라 앱 전체만 포커스 — ADR-0008과 동일한 의도된 한계.

## Alternatives considered

- **5분 사용량 폴에 얹기** — `NotificationDecider`에 세션 상태 diff를 추가. 인프라는 가장
  적게 들지만 폴 사이 시작·종료를 놓치고 최대 5분 지연 → "끝나면 바로" 요구 미충족. 기각.
- **세션 활성 상태를 `UsageSnapshot.Session`에 넣고 위젯과 공유** — 위젯 표시까지 열리지만
  스냅샷 스키마(ADR-0003)를 넓히고, 어차피 알림 타이밍은 폴에 묶인다. 이번엔 앱 전용 watcher로.
- **VS Code 패널까지 정밀 포커스(`vscode://` URI/확장)** — 앱 범위를 넘는 별도 작업. best-effort
  "앱만 앞으로"로 충분하다고 판단(사용자도 이 범위 선택). 향후 별도 ADR 여지.

## Affects

- `Sources/TokenMukbangKit/Sessions/SessionActivity.swift` — `SessionActivity` + 순수 파서.
- `Sources/TokenMukbangKit/Focus/TerminalFocus.swift` — GUI 호스트 ancestry walk(`guiHostAppName`),
  포커스 시 에디터 우선 활성화 (ADR-0008 확장).
- `Sources/TokenMukbangKit/Notifications/NotificationDecider.swift` — `NotificationEvent.sessionFinished`.
- `Sources/TokenMukbangKit/Settings/AppSettings.swift` — `NotificationSettings.sessionFinished` + forgiving decode.
- `App/TokenMukbang/SessionActivityWatcher.swift` — reactive per-session watcher (오케스트레이션).
- `App/TokenMukbang/NotificationService.swift` — `deliverSessionFinished` + `NotificationCoordinator` 탭 핸들러.
- `App/TokenMukbang/AppModel.swift` — watcher 소유·reconcile·델리게이트 배선.
- `App/TokenMukbang/Views/SettingsView.swift` — Alerts 탭 "Session finished" 토글.
- `CLAUDE.md` (알림/포커스 규칙), `ARCHITECTURE.md`, `README.md`, `CHANGELOG.md`, `docs/adr/0008-*`.
