# ADR-0006: OS·네트워크 경계는 전부 주입 가능한 프로토콜 뒤에 둔다

- **Status:** Accepted
- **Date:** 2026-06-11

## Context

핵심 로직은 시스템 부작용에 의존한다 — Keychain(`security`), 세션 탐지(`ps`/`lsof`),
터미널 포커스(`osascript`), usage/profile 네트워크 호출. 이걸 `Process`/`URLSession`로
직접 호출하면 단위 테스트가 실제 자격·네트워크·실행 중 프로세스를 요구해 불안정해진다.
ADR-0001(테스트 가능한 Foundation-only 코어)을 실효화하려면 경계를 분리해야 한다.

## Decision

모든 OS·네트워크 경계를 `Sendable` 프로토콜 뒤에 두고 생성자 주입한다:

| 관심사 | 프로토콜 | 라이브 구현 |
|---|---|---|
| 서브프로세스 | `ProcessRunning` | `SystemProcessRunner` |
| 자격 | `CredentialProviding` | `SecurityCLICredentialStore` |
| HTTP | `HTTPTransport` | `URLSessionTransport` |
| OAuth API | `UsageFetching` | `ClaudeUsageClient` |

`UsageService`도 위 의존 + `now` 클럭을 주입받는다. 테스트·프리뷰는 가짜 구현을 넣어
실제 자격/네트워크 없이 전 파이프라인을 돌린다. 시스템·네트워크를 건드리는 새 로직은
`Process`/`URLSession`를 직접 부르지 말고 이 seam 중 하나(또는 새 프로토콜) 뒤에 둔다.

## Consequences

- ➕ 결정론적 단위 테스트(가짜 `ps` 출력, 가짜 HTTP 상태, 가짜 자격 등).
- ➕ 라이브 구현 교체 용이(예: ADR-0002의 `security`→`SecItem` 전환 시).
- ➖ 약간의 보일러플레이트(프로토콜 + 라이브 구현 + 주입).
- 절차: 외부 부작용 추가 시 seam을 먼저 만들고 그 뒤에 로직을 둔다.

## Alternatives considered

- **`Process`/`URLSession` 직접 호출** — 단순하지만 테스트가 실제 시스템 상태에 묶임. 기각.
- **전역 싱글턴 + 테스트용 스왑** — 동시성·Sendable·격리 문제. 생성자 주입이 깔끔. 기각.

## Affects

- `Sources/ClaudeUsageKit/Support/ProcessRunner.swift`, `Keychain/`, `API/`, `Sessions/`,
  `Focus/`, `UsageService.swift`
- `CLAUDE.md`(injection seams 규칙), `ARCHITECTURE.md` §3
