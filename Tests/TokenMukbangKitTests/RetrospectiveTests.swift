import XCTest
@testable import TokenMukbangKit

final class RetrospectiveTests: XCTestCase {

    // A fake subprocess runner that captures arguments and returns a canned result
    // (or throws, to simulate the `claude` CLI being absent). ADR-0006 seam.
    final class FakeRunner: ProcessRunning, @unchecked Sendable {
        var capturedExecutable: String?
        var capturedArguments: [String] = []
        var callCount = 0
        let result: ProcessResult?      // nil → throw (CLI absent / launch failure)

        init(result: ProcessResult?) { self.result = result }

        struct Boom: Error {}
        func run(executable: String, arguments: [String]) throws -> ProcessResult {
            callCount += 1
            capturedExecutable = executable
            capturedArguments = arguments
            guard let result else { throw Boom() }
            return result
        }
    }

    private let utc = TokenHistory.utcCalendar

    /// ISO-8601 string `parseISO8601` round-trips (plain, no fractional seconds).
    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    private func ev(_ ts: Date, _ model: String, _ project: String, _ tok: Int) -> TokenEvent {
        TokenEvent(timestamp: ts, model: model, inputTokens: tok, outputTokens: 0,
                   cacheReadTokens: 999, cacheCreationTokens: 0, project: project)
    }

    // MARK: S1 — RetrospectiveBuilder (A: metadata)

    func testBuildMetadataAggregatesProjectsCastsAndTotal() {
        let start = Date(timeIntervalSince1970: 10 * 86_400)   // day 10
        let end = start.addingTimeInterval(86_400)
        let events = [
            ev(start.addingTimeInterval(3600), "claude-opus-4-8", "alpha", 100),
            ev(start.addingTimeInterval(7200), "claude-sonnet-4-6", "alpha", 30),
            ev(start.addingTimeInterval(7200), "claude-opus-4-8", "beta", 20),
            ev(end.addingTimeInterval(3600), "claude-opus-4-8", "alpha", 500),   // next day, excluded
        ]
        let s = RetrospectiveBuilder().buildMetadata(events: events, periodStart: start, periodEnd: end)
        XCTAssertEqual(s.totalConsumed, 150)                  // 100+30+20 (cache reads excluded)
        XCTAssertEqual(s.projects.first?.project, "alpha")    // heaviest first
        XCTAssertEqual(s.projects.first?.tokens, 130)
        XCTAssertEqual(s.casts.first?.castName, "Opus")       // opus 120 > sonnet 30
        XCTAssertEqual(s.casts.first?.tokens, 120)
        XCTAssertNil(s.topics)                                // A never fills B
    }

    func testBuildMetadataHourlyDistribution() {
        let start = Date(timeIntervalSince1970: 10 * 86_400)  // 00:00 UTC
        let end = start.addingTimeInterval(86_400)
        let events = [
            ev(start.addingTimeInterval(3600), "claude-opus-4-8", "a", 10),     // hour 1
            ev(start.addingTimeInterval(3600), "claude-opus-4-8", "a", 5),      // hour 1
            ev(start.addingTimeInterval(20 * 3600), "claude-opus-4-8", "a", 7), // hour 20
        ]
        let s = RetrospectiveBuilder().buildMetadata(events: events, periodStart: start, periodEnd: end)
        XCTAssertEqual(s.hourly.count, 24)
        XCTAssertEqual(s.hourly[1], 15)
        XCTAssertEqual(s.hourly[20], 7)
        XCTAssertEqual(s.hourly[5], 0)
    }

    /// hourly buckets follow the injected calendar's zone: the same events land in +09:00-shifted
    /// buckets under an Asia/Seoul calendar (this is what makes the retrospective's "WHEN" match
    /// the user's display zone instead of UTC).
    func testBuildMetadataHourlyRespectsCalendarZone() {
        let start = Date(timeIntervalSince1970: 10 * 86_400)  // 00:00 UTC
        let events = [
            ev(start.addingTimeInterval(3600), "claude-opus-4-8", "a", 10),      // 01:00 UTC = 10:00 KST
            ev(start.addingTimeInterval(20 * 3600), "claude-opus-4-8", "a", 7),  // 20:00 UTC = 05:00 KST (+1d)
        ]
        var seoul = Calendar(identifier: .gregorian)
        seoul.timeZone = TimeZone(identifier: "Asia/Seoul")!
        // Widen the window so both events stay in-period after the +9h shift.
        let s = RetrospectiveBuilder().buildMetadata(
            events: events, periodStart: start, periodEnd: start.addingTimeInterval(2 * 86_400), calendar: seoul)
        XCTAssertEqual(s.hourly[10], 10)   // 01:00 UTC → 10:00 KST
        XCTAssertEqual(s.hourly[5], 7)     // 20:00 UTC → 05:00 KST
        XCTAssertEqual(s.hourly[1], 0)     // nothing at UTC-hour 1 anymore
    }

    func testBuildMetadataBaselineDeltaVsPriorWindow() {
        let start = Date(timeIntervalSince1970: 10 * 86_400)
        let end = start.addingTimeInterval(86_400)
        let prior = start.addingTimeInterval(-43_200)         // within prior window
        let events = [
            ev(start.addingTimeInterval(3600), "claude-opus-4-8", "a", 200),   // current: 200
            ev(prior, "claude-opus-4-8", "a", 100),                            // prior: 100
        ]
        let s = RetrospectiveBuilder().buildMetadata(events: events, periodStart: start, periodEnd: end)
        XCTAssertEqual(s.totalConsumed, 200)
        XCTAssertEqual(s.baselineDeltaPercent ?? 0, 100, accuracy: 0.0001)     // +100% vs prior
    }

    func testBaselineDeltaNilWhenNoPriorData() {
        let start = Date(timeIntervalSince1970: 10 * 86_400)
        let end = start.addingTimeInterval(86_400)
        let s = RetrospectiveBuilder().buildMetadata(
            events: [ev(start.addingTimeInterval(60), "claude-opus-4-8", "a", 10)],
            periodStart: start, periodEnd: end)
        XCTAssertNil(s.baselineDeltaPercent)
    }

    // MARK: S2 — ClaudeCLISummarizer (B: content via claude CLI)

    func testSummarizerParsesSuccessfulOutput() async {
        let out = """
        You focused on auth refactoring and retrospective design.
        - auth token handling
        - retrospective ADR
        """
        let runner = FakeRunner(result: ProcessResult(exitCode: 0, standardOutput: out, standardError: ""))
        let sut = ClaudeCLISummarizer(runner: runner, claudePath: "/fake/claude")
        let now = Date(timeIntervalSince1970: 1000)
        let topics = await sut.summarize(digest: "- did some auth work", now: now)
        XCTAssertEqual(topics?.summary, "You focused on auth refactoring and retrospective design.")
        XCTAssertEqual(topics?.themes, ["auth token handling", "retrospective ADR"])
        XCTAssertEqual(topics?.source, .claudeCLI)
        XCTAssertEqual(topics?.generatedAt, now)
    }

    func testSummarizerReturnsNilWhenCLIAbsent() async {
        let runner = FakeRunner(result: nil)   // throws → CLI absent / launch failure
        let sut = ClaudeCLISummarizer(runner: runner, claudePath: "/fake/claude")
        let topics = await sut.summarize(digest: "- something", now: Date())
        XCTAssertNil(topics)
    }

    func testSummarizerReturnsNilOnNonZeroExit() async {
        let runner = FakeRunner(result: ProcessResult(exitCode: 1, standardOutput: "", standardError: "boom"))
        let sut = ClaudeCLISummarizer(runner: runner, claudePath: "/fake/claude")
        let topics = await sut.summarize(digest: "- something", now: Date())
        XCTAssertNil(topics)
    }

    func testSummarizerReturnsNilOnEmptyDigestWithoutRunning() async {
        let runner = FakeRunner(result: ProcessResult(exitCode: 0, standardOutput: "x", standardError: ""))
        let sut = ClaudeCLISummarizer(runner: runner, claudePath: "/fake/claude")
        let topics = await sut.summarize(digest: "   \n  ", now: Date())
        XCTAssertNil(topics)
        XCTAssertEqual(runner.callCount, 0)   // never spends a CLI call on an empty digest
    }

    func testSummarizerReturnsNilWhenOutputHasNoUsableLine() async {
        let runner = FakeRunner(result: ProcessResult(exitCode: 0, standardOutput: "   \n\n  ", standardError: ""))
        let sut = ClaudeCLISummarizer(runner: runner, claudePath: "/fake/claude")
        let topics = await sut.summarize(digest: "- something", now: Date())
        XCTAssertNil(topics)
    }

    /// ADR-0002: the summarizer must never pass the OAuth token. It only ever sends
    /// `-p` + the prompt (instruction + digest), nothing resembling a credential.
    func testSummarizerNeverPassesTokenOnlyPromptArgs() async {
        let runner = FakeRunner(result: ProcessResult(exitCode: 0, standardOutput: "ok summary", standardError: ""))
        let sut = ClaudeCLISummarizer(runner: runner, claudePath: "/fake/claude")
        _ = await sut.summarize(digest: "- inspected the keychain reader", now: Date())
        XCTAssertEqual(runner.capturedExecutable, "/fake/claude")
        XCTAssertEqual(runner.capturedArguments.count, 2)
        XCTAssertEqual(runner.capturedArguments.first, "-p")
        let prompt = runner.capturedArguments[1]
        XCTAssertTrue(prompt.contains("inspected the keychain reader"))   // digest is the payload
        // No credential material in the args.
        for arg in runner.capturedArguments {
            XCTAssertFalse(arg.lowercased().contains("authorization"))
            XCTAssertFalse(arg.contains("Bearer"))
            XCTAssertFalse(arg.contains("sk-ant"))
        }
    }

    // MARK: S2 — TranscriptDigest (content extraction, period-scoped)

    func testTranscriptDigestExtractsUserPromptsInPeriod() {
        let start = Date(timeIntervalSince1970: 10 * 86_400)
        let end = start.addingTimeInterval(86_400)
        let inRange = iso(start.addingTimeInterval(3600))
        let outRange = iso(end.addingTimeInterval(3600))
        let transcript = """
        {"type":"user","timestamp":"\(inRange)","cwd":"/Users/me/alpha","message":{"role":"user","content":"refactor the auth module"}}
        {"type":"assistant","timestamp":"\(inRange)","message":{"role":"assistant","model":"claude-opus-4-8","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
        {"type":"user","timestamp":"\(outRange)","cwd":"/Users/me/alpha","message":{"role":"user","content":"this is tomorrow, exclude me"}}
        {"type":"user","cwd":"/Users/me/beta","message":{"role":"user","content":[{"type":"text","text":"block-form prompt"}]}}
        """
        let prompts = TranscriptDigest.userPrompts(fromTranscript: transcript, periodStart: start, periodEnd: end)
        XCTAssertTrue(prompts.contains(.init(project: "alpha", text: "refactor the auth module")))
        XCTAssertFalse(prompts.contains { $0.text.contains("tomorrow") })   // out of period
        XCTAssertTrue(prompts.contains(.init(project: "beta", text: "block-form prompt")))  // cwd → project
    }

    /// The fix for project skew: the digest must round-robin across projects so a chatty
    /// project can't monopolize the budget and the summary stays cross-project.
    func testDigestAssembleBalancesAcrossProjects() {
        let byProject = [
            "njtransit": (1...20).map { "nj prompt \($0)" },   // chatty project
            "blog": ["blog prompt 1"],
            "tokenmukbang": ["tmk prompt 1"],
        ]
        let digest = TranscriptDigest.assemble(byProject: byProject,
                                               order: ["njtransit", "blog", "tokenmukbang"],
                                               maxChars: 200)   // tight budget
        // Even with a tight budget, the small projects appear (round-robin), not just njtransit.
        XCTAssertTrue(digest.contains("[blog]"))
        XCTAssertTrue(digest.contains("[tokenmukbang]"))
        XCTAssertTrue(digest.contains("[njtransit]"))
    }

    /// Window-mismatch fix: `limitTo` confines the sample to the coached projects, so a
    /// prompt-only project (present in transcripts but absent from the metrics/Menu) can't
    /// leak into the coach's input and get cited.
    func testDigestAssembleLimitsToAllowedProjects() {
        let byProject = [
            "njtransit": ["nj 1"],
            "blog": ["blog 1"],
            "ts-stack-study": ["prompt-only, ~0 tokens"],   // not in metrics/Menu
        ]
        let digest = TranscriptDigest.assemble(byProject: byProject,
                                               order: ["njtransit", "blog", "ts-stack-study"],
                                               maxChars: 4_000,
                                               limitTo: ["njtransit", "blog"])
        XCTAssertTrue(digest.contains("[njtransit]"))
        XCTAssertTrue(digest.contains("[blog]"))
        XCTAssertFalse(digest.contains("[ts-stack-study]"))   // filtered out
    }

    // MARK: S3 — RetrospectiveStore (app-only cache)

    private func tempDir() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("retro-test-\(UUID().uuidString)", isDirectory: true)
        return dir
    }

    func testStoreRoundTripPersistsTopics() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = RetrospectiveStore(directory: dir)
        let start = Date(timeIntervalSince1970: 10 * 86_400)
        let summary = RetrospectiveSummary(
            periodStart: start, periodEnd: start.addingTimeInterval(86_400),
            totalConsumed: 150,
            projects: [.init(project: "alpha", tokens: 150)],
            casts: [.init(castName: "Opus", tokens: 150)],
            hourly: Array(repeating: 0, count: 24),
            baselineDeltaPercent: 12.5,
            topics: RetroTopics(summary: "auth work", themes: ["t1"], generatedAt: start, source: .claudeCLI))
        store.save(summary)

        let loaded = RetrospectiveStore(directory: dir).summary(for: start)
        XCTAssertEqual(loaded?.totalConsumed, 150)
        XCTAssertEqual(loaded?.topics?.summary, "auth work")
        XCTAssertEqual(loaded?.baselineDeltaPercent ?? 0, 12.5, accuracy: 0.0001)
    }

    func testStoreDayKeyCacheHitAndMiss() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = RetrospectiveStore(directory: dir)
        let day = Date(timeIntervalSince1970: 10 * 86_400)
        let other = Date(timeIntervalSince1970: 20 * 86_400)
        store.save(RetrospectiveSummary(periodStart: day, periodEnd: day.addingTimeInterval(86_400),
                                        totalConsumed: 1, projects: [], casts: [],
                                        hourly: Array(repeating: 0, count: 24), baselineDeltaPercent: nil))
        XCTAssertNotNil(store.summary(for: day))      // cache hit
        XCTAssertNil(store.summary(for: other))       // cache miss
    }

    // MARK: plainTextReport (copy-to-clipboard)

    func testPlainTextReportIncludesMetadataAndTopics() {
        let start = Date(timeIntervalSince1970: 10 * 86_400)
        let summary = RetrospectiveSummary(
            periodStart: start, periodEnd: start.addingTimeInterval(86_400),
            totalConsumed: 262_500,
            projects: [.init(project: "arkraft", tokens: 157_500), .init(project: "alpha", tokens: 105_000)],
            casts: [.init(castName: "Opus", tokens: 262_500)],
            hourly: { var h = Array(repeating: 0, count: 24); h[23] = 262_500; return h }(),
            baselineDeltaPercent: 13,
            topics: RetroTopics(summary: "Focused on auth + retro.", themes: ["auth", "retro ADR"],
                                generatedAt: start, source: .claudeCLI))
        let report = summary.plainTextReport()
        XCTAssertTrue(report.contains("262.5k eaten"))
        XCTAssertTrue(report.contains("↑13% vs usual"))
        XCTAssertTrue(report.contains("arkraft: 157.5k"))
        XCTAssertTrue(report.contains("Opus: 262.5k"))
        XCTAssertTrue(report.contains("Busiest around 23:00 UTC"))   // default zone = UTC
        XCTAssertTrue(report.contains("Focused on auth + retro."))
        XCTAssertTrue(report.contains("- auth"))

        // The label carries the zone, not "UTC", when a display zone is passed. (The bucket index
        // itself is fixed by whatever calendar built `hourly` — re-bucketing is tested at build level.)
        let seoul = TimeZone(identifier: "Asia/Seoul")!
        let zoned = summary.plainTextReport(timeZone: seoul)
        XCTAssertFalse(zoned.contains("23:00 UTC"))
        XCTAssertTrue(zoned.contains("Busiest around 23:00 \(RetrospectiveSummary.zoneAbbrev(seoul))"))
    }

    func testPlainTextReportOmitsTopicsWhenNotGenerated() {
        let start = Date(timeIntervalSince1970: 10 * 86_400)
        let summary = RetrospectiveSummary(
            periodStart: start, periodEnd: start.addingTimeInterval(86_400),
            totalConsumed: 100, projects: [.init(project: "a", tokens: 100)], casts: [],
            hourly: Array(repeating: 0, count: 24), baselineDeltaPercent: nil)
        let report = summary.plainTextReport()
        XCTAssertFalse(report.contains("What you focused on"))
        XCTAssertTrue(report.contains("Total: 100 eaten"))
    }

    // MARK: RetrospectiveMetrics (coaching signal)

    private func tev(_ ts: Date, _ model: String, _ project: String, _ input: Int, _ cacheRead: Int,
                     output: Int = 0, cacheCreate: Int = 0) -> TokenEvent {
        TokenEvent(timestamp: ts, model: model, inputTokens: input, outputTokens: output,
                   cacheReadTokens: cacheRead, cacheCreationTokens: cacheCreate, project: project)
    }

    func testMetricsBuildPerProjectSignals() {
        let start = Date(timeIntervalSince1970: 10 * 86_400)
        let end = start.addingTimeInterval(86_400)
        let events = [
            tev(start.addingTimeInterval(3600), "claude-opus-4-8", "njtransit", 1000, 5000), // 1 turn, big
            tev(start.addingTimeInterval(3600), "claude-opus-4-8", "blog", 100, 0),
            tev(start.addingTimeInterval(7200), "claude-opus-4-8", "blog", 100, 0),
        ]
        let m = RetrospectiveMetrics.build(events: events,
                                           promptCounts: ["njtransit": 1, "blog": 4],
                                           periodStart: start, periodEnd: end)
        XCTAssertEqual(m.projects.first?.project, "njtransit")     // heaviest first (1000 > 200)
        XCTAssertEqual(m.projects.first?.tokensPerPrompt, 1000)    // 1000 consumed / 1 prompt → low steering
        XCTAssertEqual(m.projects.first?.cachePerTurn, 5000)       // context-size proxy only (not a cost)
        let blog = m.projects.first { $0.project == "blog" }
        XCTAssertEqual(blog?.tokensPerPrompt, 50)                  // 200 / 4
        XCTAssertEqual(m.totalConsumed, 1200)
        XCTAssertEqual(m.totalPrompts, 5)
        XCTAssertEqual(m.opusShare, 1.0, accuracy: 0.0001)
    }

    /// "drain" must decompose into output + fresh-input + cache-write, and exclude cache-read.
    func testMetricsDrainDecomposition() {
        let start = Date(timeIntervalSince1970: 10 * 86_400)
        let end = start.addingTimeInterval(86_400)
        let m = RetrospectiveMetrics.build(
            events: [tev(start.addingTimeInterval(3600), "claude-opus-4-8", "njtransit",
                         1000, 9000, output: 500, cacheCreate: 200)],
            promptCounts: ["njtransit": 1], periodStart: start, periodEnd: end)
        let p = try! XCTUnwrap(m.projects.first)
        XCTAssertEqual(p.output, 500)
        XCTAssertEqual(p.freshInput, 1000)
        XCTAssertEqual(p.cacheWrite, 200)
        XCTAssertEqual(p.cacheRead, 9000)                          // huge cache-read…
        XCTAssertEqual(p.consumed, 1700)                           // …but drain excludes it (500+1000+200)
    }

    func testMetricsCoachInputTextHasKeySignals() {
        let start = Date(timeIntervalSince1970: 10 * 86_400)
        let end = start.addingTimeInterval(86_400)
        let m = RetrospectiveMetrics.build(
            events: [tev(start.addingTimeInterval(3600), "claude-opus-4-8", "njtransit",
                         1000, 9000, output: 500, cacheCreate: 200)],
            promptCounts: ["njtransit": 1], periodStart: start, periodEnd: end)
        let text = m.coachInputText()
        XCTAssertTrue(text.contains("Opus 100%"))
        XCTAssertTrue(text.contains("njtransit"))
        XCTAssertFalse(text.contains("Plan:"))  // no plan line when not provided
        // Plan-aware: the plan label is surfaced so the coach can frame cost as window-burn.
        XCTAssertTrue(m.coachInputText(planLabel: "Max").contains("Plan: Max"))
    }

    /// Framing fix: cache-read/turn must NOT be foregrounded as a cost; "drain" leads instead.
    func testCoachInputTextForegroundsDrainNotCacheRead() {
        let start = Date(timeIntervalSince1970: 10 * 86_400)
        let end = start.addingTimeInterval(86_400)
        let m = RetrospectiveMetrics.build(
            events: [tev(start.addingTimeInterval(3600), "claude-opus-4-8", "njtransit",
                         1000, 9000, output: 500, cacheCreate: 200)],
            promptCounts: ["njtransit": 1], periodStart: start, periodEnd: end)
        let text = m.coachInputText()
        XCTAssertTrue(text.contains("drain"))            // drain decomposition is the headline
        XCTAssertTrue(text.contains("cache-write"))      // a real drain component is shown
        XCTAssertFalse(text.contains("/turn"))           // cache-read/turn is no longer foregrounded
        XCTAssertFalse(text.contains("cache-read "))     // no "cache-read N%" cost-style metric
    }

    func testEmptyStoreReturnsNil() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(RetrospectiveStore(directory: dir).summary(for: Date()))
    }
}
