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
- **WezTerm** — `wezterm cli list --format json`으로 pane 목록을 받아 `tty_name` 매칭 →
  `wezterm cli activate-pane`. 매칭 파서(`weztermPaneId`)는 순수 함수라 유닛 테스트한다.
- **kitty** — `kitty @ focus-window`(`allow_remote_control yes` 필요), best-effort.
- **tmux** — `tmux select-window -t <tty>`, best-effort.
- **VS Code 등 에디터 내장 터미널** — 세션 pid의 부모 프로세스 체인(`ps -axo pid=,ppid=,comm=`)을
  거슬러 올라가 호스트 에디터(Visual Studio Code / Cursor / Windsurf / VSCodium)를 식별하면 그 앱을
  `activate` 한다(특정 패널 포커스는 공개 API가 없어 안 함). Terminal/iTerm2 TTY 탭 매칭 스크립트는
  `activate` 부수효과가 있으므로 **에디터 호스트가 식별되면 그 스크립트보다 먼저 활성화하고 리턴**한다.
  ancestry 파서(`guiHostAppName`)는 순수 함수라 유닛 테스트한다. (세션 완료 알림 탭에서 재사용 — ADR-0022)
- **그 외 터미널** — 매칭 실패 시 iTerm2/Terminal 앱만 활성화(fallback).
- **모든 실패는 조용히 무시** — 포커스는 편의 기능이지 크래시 경로가 아니다.

지원 터미널은 `SupportedTerminal` enum(terminal/iterm2/tmux/kitty/wezterm)으로 관리한다.

AppleScript 실행은 `ProcessRunning` 프로토콜 뒤의 `osascript` 호출로 추상화하고(ADR-0006),
TTY→탭 매칭 파싱은 순수 함수로 두어 단위 테스트한다.

## Consequences

- ➕ Terminal.app·iTerm2·WezTerm(+ kitty/tmux best-effort)에서 세션→터미널 점프가 동작.
- ➕ 미지원 터미널에서도 graceful degradation(앱만 활성화 또는 무시), 절대 크래시 안 함.
- ➕ 매칭 로직이 결정론적으로 테스트 가능(프로토콜 주입).
- ➕ VS Code/Cursor 등 에디터 내장 터미널 세션도 호스트 앱을 앞으로 가져옴(best-effort, ADR-0022).
- ➖ VS Code 내장 터미널 등은 **앱만** 앞으로 — 특정 탭/패널 포커스는 신뢰성 있게 못 함(의도된 한계).
- ➖ 비샌드박스 앱이라(ADR-0002) AppleScript 자동화 권한 동의가 첫 실행 시 필요할 수 있음.

## Alternatives considered

- **모든 터미널 완전 지원** — 터미널마다 API/스크립팅이 제각각이라 비용 대비 가치 낮음. 기각.
- **포커스 기능 미제공** — 세션 목록의 실용성을 크게 떨어뜨림. 기각.

## Affects

- `Sources/TokenMukbangKit/Focus/TerminalFocus.swift`(`SupportedTerminal` enum, `weztermPaneId`, `guiHostAppName`), `Sessions/SessionDetector.swift`
- `App/TokenMukbang/`(세션 행 클릭 핸들러, `Overlay/` Agent Watchers 오버레이, 알림 탭 핸들러 ADR-0022), `ARCHITECTURE.md`(세션 섹션)
