# ADR-0007: 네이티브 Swift/SwiftUI/WidgetKit 스택을 쓴다

- **Status:** Accepted
- **Date:** 2026-06-11

## Context

TokenMukbang은 [TokenEater](https://github.com/AThevon/TokenEater)에서 영감을 받은 macOS
Claude 사용량 위젯이다. 핵심 표면은 **메뉴바 상주 + 데스크탑/알림센터 위젯**이며, "위젯이
주요"라는 제품 요구가 있다. 스택 후보는 (a) 네이티브 Swift, (b) Electron/웹(TS), (c) CLI/TUI
세 가지였고, 셋의 위젯·통합 가능성이 갈렸다.

## Decision

**Swift 6 + SwiftUI(`MenuBarExtra`) + WidgetKit** 네이티브 macOS 앱으로 만든다. 최소 타겟은
macOS 14(Sonoma). 진짜 WidgetKit 위젯·앱 빌드는 풀 Xcode(`xcodebuild`)가 필요하므로, 빌드 시
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`를 prefix해 시스템 `xcode-select`를
바꾸지 않고(`sudo` 불필요) 풀 Xcode를 활성화한다. 코어(`ClaudeUsageKit`)와 `usage-cli`는
Command Line Tools만으로도 빌드된다(ADR-0001).

## Consequences

- ➕ 원본 TokenEater에 충실한 네이티브 메뉴바 + WidgetKit 경험.
- ➕ macOS 통합(Keychain, App Group, AppleScript)이 1급 시민으로 자연스럽다.
- ➖ macOS 14+ 전용 — 크로스플랫폼 불가.
- ➖ 앱/위젯 빌드에 풀 Xcode 필요(코어/CLI는 CLT로 충분) — 빌드 토폴로지가 둘로 갈린다(ADR-0005).

## Alternatives considered

- **Electron/웹(TS)** — 크로스플랫폼·익숙한 스택이나 진짜 네이티브 WidgetKit 위젯 불가. "위젯이
  주요"라는 요구에 어긋나 기각.
- **CLI/TUI** — 가볍고 빠르지만 메뉴바·위젯 표면이 없음. `usage-cli`로 그 가치(헤드리스 점검)는
  코어에 흡수했으나 제품 본체로는 기각.

## Affects

- `App/` 전체, `Package.swift`, `README.md` Requirements/Build, `CLAUDE.md` Commands
- 빌드 방식: ADR-0005(XcodeGen), 배포: ADR-0010
