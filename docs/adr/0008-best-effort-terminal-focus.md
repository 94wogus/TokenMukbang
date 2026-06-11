# ADR-0008: 세션→터미널 포커스는 best-effort로 한다

- **Status:** Accepted
- **Date:** 2026-06-11

## Context

TokenMukbang은 실행 중인 Claude Code 세션을 인식해(활성 `claude` 프로세스 + 트랜스크립트 →
context fraction) 목록으로 보여준다. 사용자는 "세션을 클릭하면 그 터미널 창으로 전환"을 원했다.
문제는 세션이 어떤 터미널(Terminal.app, iTerm2, VS Code 내장, 기타)에서 도는지, 그 특정 탭을
포커스할 수 있는지가 터미널마다 다르다는 점이다.

## Decision

**best-effort 포커스**로 구현한다. `claude` 프로세스의 controlling TTY(`ps`)를 알아내고:

- **Terminal.app / iTerm2** — AppleScript(`osascript`)로 각 탭의 tty를 조회해 TTY가 매칭되는
  탭/창을 포커스한다.
- **그 외 터미널** — 매칭 실패 시 해당 앱을 활성화(fallback).
- **모든 실패는 조용히 무시** — 포커스는 편의 기능이지 크래시 경로가 아니다.

AppleScript 실행은 `ProcessRunning` 프로토콜 뒤의 `osascript` 호출로 추상화하고(ADR-0006),
TTY→탭 매칭 파싱은 순수 함수로 두어 단위 테스트한다.

## Consequences

- ➕ Terminal.app·iTerm2에서 세션→터미널 점프가 매끄럽게 동작.
- ➕ 미지원 터미널에서도 graceful degradation(앱만 활성화 또는 무시), 절대 크래시 안 함.
- ➕ 매칭 로직이 결정론적으로 테스트 가능(프로토콜 주입).
- ➖ VS Code 내장 터미널 등은 특정 탭 포커스를 신뢰성 있게 못 함 — 의도된 한계.
- ➖ 비샌드박스 앱이라(ADR-0002) AppleScript 자동화 권한 동의가 첫 실행 시 필요할 수 있음.

## Alternatives considered

- **모든 터미널 완전 지원** — 터미널마다 API/스크립팅이 제각각이라 비용 대비 가치 낮음. 기각.
- **포커스 기능 미제공** — 세션 목록의 실용성을 크게 떨어뜨림. 기각.

## Affects

- `Sources/ClaudeUsageKit/Focus/TerminalFocus.swift`, `Sessions/SessionDetector.swift`
- `App/ClaudeUsageWidgetApp/`(세션 행 클릭 핸들러), `ARCHITECTURE.md`(세션 섹션)
