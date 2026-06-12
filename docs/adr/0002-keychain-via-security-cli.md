# ADR-0002: OAuth 토큰은 `security` CLI로 Keychain에서 읽는다 (읽기 전용)

- **Status:** Accepted
- **Date:** 2026-06-11

## Context

usage/profile API를 호출하려면 Claude Code가 Keychain 서비스
`Claude Code-credentials`(top-level `claudeAiOauth`)에 저장한 OAuth access token이
필요하다. macOS에서 Keychain 항목을 읽는 길은 (a) `Security.framework`의 `SecItem*` API,
(b) `/usr/bin/security` CLI 두 가지다. CLI/헤드리스 컨텍스트에서 GUI 비밀번호 프롬프트
없이, 그리고 토큰을 노출하지 않고 읽어야 한다.

## Decision

`/usr/bin/security find-generic-password -s "Claude Code-credentials" -w`로 항목을
**읽기 전용**으로 가져온다(`SecurityCLICredentialStore`). 호출 터미널의 Keychain 접근을
재사용하므로 헤드리스에서 GUI 프롬프트를 피한다. 절대 항목을 수정/삭제하지 않으며,
access token은 어디에도 출력·로깅하지 않는다. 접근은 `CredentialProviding` 프로토콜
뒤에 두어(ADR-0006) 테스트에서 가짜로 대체하고, 추후 `SecItem` 구현으로 교체할 여지를 남긴다.

## Consequences

- ➕ 헤드리스에서 동작, GUI 프롬프트 없음, 추가 entitlement 불필요.
- ➕ 읽기 전용이라 사용자의 로그인 상태를 건드릴 위험이 없다.
- ➖ 서브프로세스 실행 비용 + `security` 출력 파싱 의존(JSON envelope 디코딩).
- ➖ 앱이 샌드박스를 못 켠다(서브프로세스 실행 때문) — ADR-0003과 맞물림.
- 보안 불변식: **token은 stdout/로그/스냅샷 어디에도 나타나선 안 된다.**

## Alternatives considered

- **`SecItem*` API** — 샌드박스/서명 시 더 정석이나 GUI 프롬프트·entitlement 복잡도.
  프로토콜 뒤에 두었으니 필요하면 후속 ADR로 교체 가능. 지금은 기각.
- **Claude Code의 토큰 파일을 직접 읽기** — 위치·포맷이 비공개 구현 디테일이라 취약. 기각.

## Affects

- `Sources/TokenMukbangKit/Keychain/Credentials.swift`
- `CLAUDE.md`(토큰 미출력 불변식), `README.md` Privacy 섹션
