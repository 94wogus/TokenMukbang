import TokenMukbangKit
import Foundation

// Headless full-pipeline runner. `--print` (default) runs Keychain → API →
// sessions and prints a readable summary. Never prints the access token.
// Exits 0 even on graceful failures (missing/expired creds, offline) so it can
// be wired into status bars and smoke checks without spurious non-zero exits.

let args = Set(CommandLine.arguments.dropFirst())
let asJSON = args.contains("--json")

let snapshot = await UsageService().snapshot()

if asJSON {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(snapshot), let str = String(data: data, encoding: .utf8) {
        print(str)
    }
    exit(0)
}

let now = Date()

print("Claude Usage" + (snapshot.planLabel.map { " · \($0) plan" } ?? ""))
print(String(repeating: "─", count: 32))

if let error = snapshot.error {
    print("⚠️  \(error)")
} else if snapshot.windows.isEmpty {
    print("No usage windows reported.")
} else {
    for w in snapshot.windows {
        let frac = w.utilization / 100.0
        let zone = MukbangZone.forUtilization(w.utilization)
        let line = String(
            format: "%@ %-10@ %@ %5@  %@  [%@]",
            zone.restingFace as NSString,
            w.label as NSString,
            Formatting.bar(fraction: frac) as NSString,
            MukbangCopy.headline(utilization: w.utilization) as NSString,
            MukbangCopy.reset(to: w.resetsAt, from: now) as NSString,
            zone.label as NSString
        )
        print(line)
    }
}

print(String(repeating: "─", count: 32))
if snapshot.sessions.isEmpty {
    print("No active Claude Code sessions.")
} else {
    print("Active sessions:")
    for s in snapshot.sessions {
        let ctx = s.contextFraction.map { "ctx \(Formatting.percent(fraction: $0))" } ?? "ctx —"
        let tty = s.tty ?? "—"
        print("  ● \(s.projectName)  \(ctx)  (\(tty), pid \(s.pid))")
    }
}

exit(0)
