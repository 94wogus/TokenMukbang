# ADR-0014: 자격 파일 변경은 DispatchSource로 반응형 감지한다

- **Status:** Accepted
- **Date:** 2026-06-11

## Context

앱은 60초 폴링(ADR-0003)으로 사용량을 갱신한다. 하지만 사용자가 `claude /login`으로 토큰을 갱신하면
다음 폴링까지 최대 60초 동안 만료 상태가 유지된다. TokenEater처럼 **자격 파일이 바뀌는 즉시** 반응해
갱신하면 UX가 좋아진다. 파일 변경 감지 수단은 (a) `DispatchSource` 파일시스템 이벤트, (b) `kqueue`
직접, (c) `FSEvents`, (d) 폴링만 유지 중에서 고른다.

## Decision

`ClaudeUsageKit`의 **`FileWatcher`(`DispatchSource.makeFileSystemObjectSource`)**로 자격 파일
(`~/.claude/.credentials.json`)을 `O_EVTONLY`로 열어 `.write/.delete/.rename/.extend` 이벤트를 감지하고,
이벤트 시 `onChange`로 즉시 refresh를 트리거한다(폴링은 그대로 백업). 주입 가능한 `FileWatching`
프로토콜(ADR-0006) 뒤에 두어 앱은 추상화에 의존한다. 파일이 없으면 `start()`가 false를 돌려주며
조용히 비활성(이 머신처럼 자격이 Keychain에만 있는 경우).

## Consequences

- ➕ 토큰 갱신/만료 변화에 60초 지연 없이 즉시 반응.
- ➕ `DispatchSource`는 Foundation/Dispatch만 써서 Kit이 UI-free 유지(ADR-0001).
- ➕ `FileWatching` seam으로 테스트 가능(임시 파일 write → 이벤트 발화 검증).
- ➖ 파일 기반이라 자격이 Keychain에만 있고 파일이 없으면 watch가 동작 안 함(폴링이 커버).
- ⚠️ `@unchecked Sendable` — 내부 `fd`/`source` 변이는 호출자(앱 @MainActor)와 cancel 핸들러로 분리해 관리.

## Alternatives considered

- **폴링만 유지** — 단순하나 최대 60초 지연. 기각.
- **`kqueue` 직접** — 저수준, `DispatchSource`가 같은 일을 더 안전하게 한다. 기각.
- **`FSEvents`** — 디렉터리 트리 감시에 적합하나 단일 파일엔 과함. 기각.

## Affects

- `Sources/ClaudeUsageKit/Support/FileWatcher.swift`(`FileWatching` 프로토콜 + `FileWatcher`)
- `App/ClaudeUsageWidgetApp/AppModel.swift`(`startCredentialWatch`), 폴링: ADR-0003, seam: ADR-0006
