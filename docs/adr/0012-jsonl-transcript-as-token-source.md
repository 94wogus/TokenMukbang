# ADR-0012: 실제 토큰 소비량은 Claude Code JSONL 트랜스크립트에서 읽는다

- **Status:** Accepted
- **Date:** 2026-06-11

## Context

TokenEater 패리티의 History 브라우저는 "토큰 소비량 over time"(모델별/프로젝트별/일별)을 보여준다.
그러나 OAuth `/api/oauth/usage`(ADR-0004)는 **한도 대비 사용률(%)**만 주고 **절대 토큰 수**는 주지
않는다. 절대 토큰 소비량은 Claude Code가 `~/.claude/projects/<encoded-cwd>/*.jsonl` 트랜스크립트의
assistant 턴 `message.usage`에 남기는 값에만 있다(세션 탐지 ADR과 같은 소스).

## Decision

**토큰 소비 데이터는 JSONL 트랜스크립트를 tail-read해서 얻는다.** `ClaudeUsageKit`의 `JSONLParser`가
각 줄을 파싱해 `TokenEvent`(timestamp, model, input/output/cache 토큰, project=cwd lastPathComponent)를
추출하고, `TokenHistory`가 일별/모델별/프로젝트별로 집계한다(heaviestDay/topProject/total). 파일 접근은
`allEvents(claudeHome:)`의 `claudeHome` 파라미터로 주입 가능하게 두어(ADR-0006 seam) 테스트는 fixture로
한다. 파싱은 best-effort — non-assistant 줄·malformed JSON·누락 timestamp는 조용히 건너뛴다.

## Consequences

- ➕ API가 못 주는 **절대 토큰 소비량**을 얻어 토큰 History 브라우저·차트·top project를 그릴 수 있다.
- ➕ 순수 파싱/집계라 결정론적으로 테스트된다(UTC 캘린더 버킷).
- ➖ 트랜스크립트 포맷은 Claude Code 내부 구현이라 바뀌면 파서도 따라가야 한다(방어적 파싱으로 완화).
- ⚠️ 사용률(%)은 여전히 API(ADR-0004)에서, 토큰 수는 JSONL에서 — 두 데이터 소스가 공존한다.

## Alternatives considered

- **API만 사용** — 절대 토큰 수가 없어 토큰 History 불가. 기각.
- **자체 토큰 카운팅** — 부정확하고 모델 토크나이저 의존. 트랜스크립트의 실측값이 정확. 기각.

## Affects

- `Sources/ClaudeUsageKit/History/{JSONLParser,TokenHistory}.swift`
- 세션 탐지(ADR-0006 seam, 같은 `~/.claude/projects/` 소스), 사용률 API(ADR-0004)
- History 브라우저 UI(`App/`), `ARCHITECTURE.md` History 섹션
