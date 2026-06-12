# ADR-0004: `UsageService.snapshot()`은 throw하지 않고 실패를 데이터로 담는다

- **Status:** Accepted
- **Date:** 2026-06-11

## Context

파이프라인은 실패할 길이 많다 — 미로그인(자격 없음), 토큰 만료, 오프라인, 디코딩 에러.
이걸 throw로 올리면 모든 소비자(메뉴바 앱, 위젯 timeline, CLI)가 각자 try/catch로
부분 실패를 처리해야 하고, 처리가 갈라지면 UI가 빈 화면이나 크래시로 떨어지기 쉽다.

## Decision

`UsageService.snapshot()`은 **절대 throw하지 않고** 항상 `UsageSnapshot`을 돌려준다.
모든 실패 모드는 `UsageSnapshot.error`(+ 가능한 부분 데이터)로 담는다. 특히 **토큰이
만료돼도 세션은 계속 스캔**한다(세션은 로컬 유도라 네트워크 없이도 유용). 소비자는 항상
스냅샷을 받는다고 가정하고 `error`가 있으면 그 메시지를, windows가 있으면 그걸 렌더한다.
`usage-cli`는 graceful 실패에도 **exit 0**으로 끝나 상태바·스모크 체크에 물리기 좋게 한다.

## Consequences

- ➕ 소비자 코드가 단순해지고 부분 실패 처리가 한 곳(`UsageService`)에 모인다.
- ➕ UI가 항상 우아하게 degrade — 만료여도 세션 목록은 보인다.
- ➖ 호출자가 `snapshot.error`를 능동적으로 봐야 한다(throw처럼 강제되지 않음).
- 불변식: 새 실패 경로를 추가할 때도 throw 대신 `error`로 흡수한다.

## Alternatives considered

- **`throws`로 전파** — Swift 관용에 맞지만 부분 실패(만료지만 세션은 있음)를 표현 못 하고
  소비자마다 처리가 갈라진다. 기각.
- **Result<Snapshot, Error>** — 여전히 "부분 성공"을 못 담는다. 기각.

## Affects

- `Sources/TokenMukbangKit/UsageService.swift`, `UsageSnapshot.swift`
- `Sources/usage-cli/main.swift`(exit 0 정책), `App/.../AppModel.swift`
- `CLAUDE.md`("never throws" 규칙), `ARCHITECTURE.md` §2
