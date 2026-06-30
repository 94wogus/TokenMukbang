import XCTest
@testable import TokenMukbangKit

/// OTLP/HTTP JSON decoding + framing + store. Fixtures mirror the exact shape Claude Code
/// emits (int64 as strings, content fields present-but-dropped) per ADR-0023.
final class OTLPDecoderTests: XCTestCase {
    // A metrics export: token.usage (asInt as STRING) + cost.usage (asDouble), with resource attrs.
    private let metricsJSON = """
    {
      "resourceMetrics": [{
        "resource": { "attributes": [
          {"key":"service.name","value":{"stringValue":"claude-code"}},
          {"key":"service.version","value":{"stringValue":"1.2.3"}},
          {"key":"session.id","value":{"stringValue":"sess-abc"}},
          {"key":"user.email","value":{"stringValue":"me@quantit.io"}},
          {"key":"os.type","value":{"stringValue":"darwin"}}
        ]},
        "scopeMetrics": [{
          "scope": {"name":"com.anthropic.claude_code"},
          "metrics": [
            {"name":"claude_code.token.usage","unit":"tokens","sum":{"dataPoints":[
              {"asInt":"1250","timeUnixNano":"1719753600000000000","attributes":[
                {"key":"type","value":{"stringValue":"input"}},
                {"key":"model","value":{"stringValue":"claude-sonnet-4-6"}}
              ]}
            ],"isMonotonic":true}},
            {"name":"claude_code.cost.usage","unit":"USD","sum":{"dataPoints":[
              {"asDouble":0.025,"timeUnixNano":"1719753600000000000","attributes":[
                {"key":"model","value":{"stringValue":"claude-sonnet-4-6"}}
              ]}
            ]}}
          ]
        }]
      }]
    }
    """

    func testDecodeMetricsValuesAndSource() {
        let samples = OTLPDecoder.decodeMetrics(Data(metricsJSON.utf8))
        XCTAssertEqual(samples.count, 2)

        let token = samples.first { $0.name == "claude_code.token.usage" }!
        XCTAssertEqual(token.value, .int(1250))                          // string "1250" → Int64
        XCTAssertEqual(token.attributes["type"]?.stringValue, "input")
        XCTAssertEqual(token.attributes["model"]?.stringValue, "claude-sonnet-4-6")
        XCTAssertEqual(token.source.userEmail, "me@quantit.io")
        XCTAssertEqual(token.source.serviceName, "claude-code")
        XCTAssertEqual(token.source.appVersion, "1.2.3")
        // timeUnixNano 1719753600000000000 ns == 1719753600 s
        XCTAssertEqual(token.timestamp.timeIntervalSince1970, 1_719_753_600, accuracy: 0.001)

        let cost = samples.first { $0.name == "claude_code.cost.usage" }!
        XCTAssertEqual(cost.value, .double(0.025))
    }

    // A logs export: api_request (metadata) + user_prompt carrying a `prompt` content field.
    private let logsJSON = """
    {
      "resourceLogs": [{
        "resource": {"attributes":[
          {"key":"service.name","value":{"stringValue":"claude-code"}},
          {"key":"session.id","value":{"stringValue":"sess-abc"}}
        ]},
        "scopeLogs": [{
          "scope": {"name":"com.anthropic.claude_code"},
          "logRecords": [
            {"timeUnixNano":"1719753600123456789","body":{"stringValue":"claude_code.api_request"},
             "attributes":[
               {"key":"event.name","value":{"stringValue":"claude_code.api_request"}},
               {"key":"model","value":{"stringValue":"claude-sonnet-4-6"}},
               {"key":"cost_usd","value":{"doubleValue":0.015}},
               {"key":"input_tokens","value":{"intValue":500}},
               {"key":"request_id","value":{"stringValue":"req-1"}}
             ]},
            {"timeUnixNano":"1719753601000000000","body":{"stringValue":"claude_code.user_prompt"},
             "attributes":[
               {"key":"event.name","value":{"stringValue":"claude_code.user_prompt"}},
               {"key":"prompt_length","value":{"intValue":42}},
               {"key":"prompt","value":{"stringValue":"SECRET PROMPT TEXT"}}
             ]}
          ]
        }]
      }]
    }
    """

    func testDecodeLogsEventsAndMetadata() {
        let events = OTLPDecoder.decodeLogs(Data(logsJSON.utf8))
        XCTAssertEqual(events.count, 2)
        let api = events.first { $0.name == "claude_code.api_request" }!
        XCTAssertEqual(api.attributes["model"]?.stringValue, "claude-sonnet-4-6")
        XCTAssertEqual(api.attributes["cost_usd"]?.doubleValue, 0.015)
        XCTAssertEqual(api.attributes["input_tokens"]?.intValue, 500)   // number intValue
        XCTAssertEqual(api.source.sessionID, "sess-abc")
    }

    func testContentFieldsAreDropped() {
        let events = OTLPDecoder.decodeLogs(Data(logsJSON.utf8))
        let prompt = events.first { $0.name == "claude_code.user_prompt" }!
        XCTAssertEqual(prompt.attributes["prompt_length"]?.intValue, 42)  // metadata kept
        XCTAssertNil(prompt.attributes["prompt"])                         // content DROPPED
        XCTAssertFalse(prompt.attributes.values.contains(.string("SECRET PROMPT TEXT")))
    }

    func testGarbageIsEmptyNotCrash() {
        XCTAssertTrue(OTLPDecoder.decodeMetrics(Data("not json".utf8)).isEmpty)
        XCTAssertTrue(OTLPDecoder.decodeLogs(Data("{}".utf8)).isEmpty)
    }

    func testKindForPath() {
        XCTAssertEqual(OTLPDecoder.kind(forPath: "/v1/metrics"), .metrics)
        XCTAssertEqual(OTLPDecoder.kind(forPath: "http://x/v1/logs"), .logs)
        XCTAssertNil(OTLPDecoder.kind(forPath: "/v1/traces"))
    }
}

final class OTLPHTTPTests: XCTestCase {
    func testParseCompletePostRequest() {
        let body = #"{"resourceMetrics":[]}"#
        let raw = "POST /v1/metrics HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let parsed = OTLPHTTP.parseRequest(Data(raw.utf8))
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.request.method, "POST")
        XCTAssertEqual(parsed?.request.path, "/v1/metrics")
        XCTAssertEqual(parsed?.request.body, Data(body.utf8))
        XCTAssertEqual(parsed?.consumed, raw.utf8.count)
    }

    func testIncompleteHeadersNeedMoreBytes() {
        XCTAssertNil(OTLPHTTP.parseRequest(Data("POST /v1/logs HTTP/1.1\r\nContent-Len".utf8)))
    }

    func testIncompleteBodyNeedsMoreBytes() {
        let raw = "POST /v1/logs HTTP/1.1\r\nContent-Length: 100\r\n\r\n{\"partial\":"
        XCTAssertNil(OTLPHTTP.parseRequest(Data(raw.utf8)))   // body shorter than Content-Length
    }

    func testOKResponseIsWellFormed() {
        let s = String(data: OTLPHTTP.okResponse(), encoding: .utf8)!
        XCTAssertTrue(s.hasPrefix("HTTP/1.1 200 OK"))
        XCTAssertTrue(s.hasSuffix("{}"))
    }
}

final class ClaudeSettingsConfiguratorTests: XCTestCase {
    private func tempFile() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tmk-cfg-\(UUID().uuidString)")
            .appendingPathComponent("settings.json").path
    }

    func testApplyMergesAndPreservesOtherKeys() {
        let existing: [String: Any] = [
            "permissions": ["allow": ["Bash"]],          // unrelated top-level key
            "env": ["MY_VAR": "keep", "PATH": "/x"],       // unrelated env keys
        ]
        let merged = ClaudeSettingsConfigurator.apply(enabled: true, port: 4318, into: existing)
        let env = merged["env"] as! [String: Any]
        XCTAssertEqual(env["MY_VAR"] as? String, "keep")                       // preserved
        XCTAssertEqual(env["OTEL_EXPORTER_OTLP_ENDPOINT"] as? String, "http://127.0.0.1:4318")
        XCTAssertEqual(env["OTEL_EXPORTER_OTLP_PROTOCOL"] as? String, "http/json")
        XCTAssertNotNil(merged["permissions"])                                 // top-level preserved
    }

    func testDisableRemovesOnlyOurKeys() {
        let existing: [String: Any] = ["env": [
            "MY_VAR": "keep",
            "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
            "OTEL_EXPORTER_OTLP_ENDPOINT": "http://127.0.0.1:4318",
        ]]
        let off = ClaudeSettingsConfigurator.apply(enabled: false, port: 4318, into: existing)
        let env = off["env"] as! [String: Any]
        XCTAssertEqual(env["MY_VAR"] as? String, "keep")            // unrelated key stays
        XCTAssertNil(env["CLAUDE_CODE_ENABLE_TELEMETRY"])           // ours removed
        XCTAssertNil(env["OTEL_EXPORTER_OTLP_ENDPOINT"])
    }

    func testDisableDropsEmptiedEnv() {
        let existing: [String: Any] = ["env": ["CLAUDE_CODE_ENABLE_TELEMETRY": "1"]]
        let off = ClaudeSettingsConfigurator.apply(enabled: false, port: 4318, into: existing)
        XCTAssertNil(off["env"])   // env became empty → dropped entirely
    }

    func testConfigureWritesAndRoundTrips() throws {
        let path = tempFile()
        XCTAssertEqual(ClaudeSettingsConfigurator.configure(enabled: true, port: 4318, settingsPath: path), .wrote)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let env = obj["env"] as! [String: Any]
        XCTAssertEqual(env["OTEL_EXPORTER_OTLP_ENDPOINT"] as? String, "http://127.0.0.1:4318")
        // Idempotent: a second identical configure is a no-op.
        XCTAssertEqual(ClaudeSettingsConfigurator.configure(enabled: true, port: 4318, settingsPath: path), .unchanged)
    }

    func testConfigureNeverClobbersUnparseableFile() throws {
        let path = tempFile()
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = "{ // a JSONC comment the parser rejects\n  \"env\": {} }"
        try original.write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertEqual(ClaudeSettingsConfigurator.configure(enabled: true, port: 4318, settingsPath: path), .needsManualEdit)
        // The file must be byte-for-byte untouched — we never destroy a config we can't read.
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), original)
    }

    func testConfigureDisableOnMissingFileIsNoop() {
        XCTAssertEqual(ClaudeSettingsConfigurator.configure(enabled: false, port: 4318, settingsPath: tempFile()), .unchanged)
    }
}

final class TelemetryStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tmk-telemetry-\(UUID().uuidString)", isDirectory: true)
        return url
    }

    private func metric(at t: Date) -> TelemetryMetricSample {
        TelemetryMetricSample(name: "claude_code.token.usage", value: .int(10), timestamp: t,
                              attributes: [:], source: TelemetrySource())
    }

    func testAppendLoadRoundTrip() {
        let store = TelemetryStore(directory: tempDir())
        let now = Date(timeIntervalSince1970: 1_000_000)
        store.append(metrics: [metric(at: now)], events: [], now: now)
        let loaded = store.load()
        XCTAssertEqual(loaded.metrics.count, 1)
        XCTAssertEqual(loaded.metrics.first?.value, .int(10))
    }

    func testRetentionPrunesOldSamples() {
        let store = TelemetryStore(directory: tempDir(), retention: 60)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let old = metric(at: now.addingTimeInterval(-120))   // outside 60s window
        let fresh = metric(at: now.addingTimeInterval(-10))
        store.append(metrics: [old, fresh], events: [], now: now)
        XCTAssertEqual(store.load().metrics.count, 1)
    }
}
