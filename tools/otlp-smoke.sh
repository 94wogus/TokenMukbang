#!/usr/bin/env bash
# otlp-smoke.sh — end-to-end smoke test for the local OTLP receiver (ADR-0023).
#
# Builds the app, launches its headless TMK_OTLP_TEST branch (a loopback OTLP receiver
# that prints each ingest to stdout), POSTs realistic OTLP/HTTP JSON fixtures to
# /v1/metrics and /v1/logs, and asserts the receiver decoded + ingested them. No GUI,
# no Keychain, no network egress — proves the NWListener + Kit decoder pipeline works.
#
# Usage: tools/otlp-smoke.sh        (exit 0 = pass)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="$REPO/.build/snapshot-derived"
PORT="${OTLP_SMOKE_PORT:-14318}"

cd "$REPO/App" && xcodegen generate >/dev/null && cd "$REPO"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project App/TokenMukbang.xcodeproj -scheme TokenMukbang \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO build >/dev/null

APP="$DERIVED/Build/Products/Debug/TokenMukbang.app/Contents/MacOS/TokenMukbang"
LOG="$(mktemp)"
TMK_OTLP_TEST="$PORT" "$APP" >"$LOG" 2>&1 &
APP_PID=$!
trap 'kill "$APP_PID" 2>/dev/null || true; rm -f "$LOG" "$METRICS" "$LOGS"' EXIT

# Wait for the receiver to announce it's listening.
for _ in $(seq 1 50); do grep -q OTLP_TEST_READY "$LOG" && break; sleep 0.1; done
grep -q OTLP_TEST_READY "$LOG" || { echo "FAIL: receiver never became ready"; cat "$LOG"; exit 1; }

METRICS="$(mktemp)"; LOGS="$(mktemp)"
cat >"$METRICS" <<'JSON'
{"resourceMetrics":[{"resource":{"attributes":[
  {"key":"service.name","value":{"stringValue":"claude-code"}},
  {"key":"user.email","value":{"stringValue":"me@quantit.io"}}]},
  "scopeMetrics":[{"scope":{"name":"com.anthropic.claude_code"},"metrics":[
    {"name":"claude_code.token.usage","sum":{"dataPoints":[
      {"asInt":"1250","timeUnixNano":"1719753600000000000","attributes":[
        {"key":"type","value":{"stringValue":"input"}}]}]}},
    {"name":"claude_code.cost.usage","sum":{"dataPoints":[
      {"asDouble":0.025,"timeUnixNano":"1719753600000000000","attributes":[]}]}}]}]}]}
JSON
cat >"$LOGS" <<'JSON'
{"resourceLogs":[{"resource":{"attributes":[
  {"key":"service.name","value":{"stringValue":"claude-code"}}]},
  "scopeLogs":[{"scope":{"name":"com.anthropic.claude_code"},"logRecords":[
    {"timeUnixNano":"1719753600123456789","attributes":[
      {"key":"event.name","value":{"stringValue":"claude_code.api_request"}},
      {"key":"prompt","value":{"stringValue":"SHOULD BE DROPPED"}}]}]}]}]}
JSON

curl -s -X POST --data-binary @"$METRICS" -H 'Content-Type: application/json' "http://127.0.0.1:$PORT/v1/metrics" >/dev/null
curl -s -X POST --data-binary @"$LOGS"    -H 'Content-Type: application/json' "http://127.0.0.1:$PORT/v1/logs"    >/dev/null
sleep 0.3

echo "--- receiver stdout ---"; grep INGESTED "$LOG" || true
grep -q "INGESTED kind=metrics metrics=2 events=0" "$LOG" || { echo "FAIL: metrics not ingested"; exit 1; }
grep -q "INGESTED kind=logs metrics=0 events=1"    "$LOG" || { echo "FAIL: logs not ingested"; exit 1; }
echo "PASS: loopback OTLP receiver ingested 2 metrics + 1 event (content dropped in decoder)"
