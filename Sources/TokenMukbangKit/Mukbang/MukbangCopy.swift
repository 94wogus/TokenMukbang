import Foundation

/// Events the mascot narrates. The POV never breaks (ADR-0009): the user is a
/// viewer, Claude is the 먹방 BJ — usage is something Claude *eats*, not something
/// the user *spends*.
public enum MukbangEvent: Sendable, Equatable {
    case finished                    // 한도 소진
    case freshTable                  // 리셋 완료
    case paceWarning(hoursToFull: Int)  // 이 속도면 N시간 뒤 완식
    case spoonDropped                // API 에러
    case backToKitchen               // 토큰 갱신 필요
}

/// POV-correct copy. ❌ "80% used" → ⭕ "80% eaten".
public enum MukbangCopy {
    /// Headline phrasing for a window: `42% eaten`.
    public static func headline(utilization: Double) -> String {
        "\(Formatting.percent(utilization)) eaten"
    }

    /// Reset countdown as digestion: `Digesting · 2h 13m`. (Middot, not `...` — the ellipsis
    /// read as a truncation bug on the hero card, design-critique r4.)
    public static func reset(to date: Date, from now: Date) -> String {
        "Digesting · \(Formatting.countdown(to: date, from: now))"
    }

    /// One-line status for the popover/menu, given a zone.
    public static func status(for zone: MukbangZone) -> String {
        switch zone {
        case .tasting: return "Just nibbling — plenty left."
        case .cruising: return "Munching along — steady pace."
        case .overeating: return "Chowing down — pace is quick."
        case .inhaling: return "Not even chewing — red zone."
        case .finished: return "Clean plate!"
        case .digesting: return "Belly full, digesting."
        }
    }

    public static func event(_ event: MukbangEvent) -> String {
        switch event {
        case .finished: return "( ˘ω˘ )🙏 Clean plate!"
        case .freshTable: return "🍚 Fresh table — next round!"
        case .paceWarning(let h): return "At this pace, all gone in \(h)h."
        case .spoonDropped: return "( ;-;) Dropped the spoon."
        case .backToKitchen: return "Gotta pop back to the kitchen (claude /login)."
        }
    }
}
