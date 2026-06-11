import Foundation

/// The pacing "zones" the mascot moves through as a usage window fills.
/// Mapping follows ADR-0009 (먹방 product concept).
public enum MukbangZone: Sendable, CaseIterable, Equatable {
    case tasting      // 0–25%  간 보는 중
    case cruising     // 25–60% 순항
    case overeating   // 60–85% 과식 주의
    case inhaling     // 85–100% 흡입
    case finished     // 100%   완식
    case digesting    // 리셋 대기 (소화 중)

    /// Resolve the eating zone from a 0...100 utilization.
    public static func forUtilization(_ utilization: Double) -> MukbangZone {
        switch utilization {
        case ..<25: return .tasting
        case ..<60: return .cruising
        case ..<85: return .overeating
        case ..<100: return .inhaling
        default: return .finished
        }
    }

    public var label: String {
        switch self {
        case .tasting: return "간 보는 중"
        case .cruising: return "순항"
        case .overeating: return "과식 주의"
        case .inhaling: return "흡입"
        case .finished: return "완식"
        case .digesting: return "소화 중"
        }
    }

    /// The mascot's resting (non-chewing) face for this zone.
    public var restingFace: String {
        switch self {
        case .tasting: return "( ˙ᵕ˙ )"
        case .cruising: return "( ˘▽˘)っ"
        case .overeating: return "(•̀ ω •́ )"
        case .inhaling: return "(ﾟ◇ﾟ)"
        case .finished: return "( ˘ω˘ )"
        case .digesting: return "( ﹃ )"
        }
    }

    /// Bowls grow as the feast intensifies (color warnings, but felt in the body).
    public var bowls: String {
        switch self {
        case .tasting: return "🥄"
        case .cruising: return "🍚"
        case .overeating: return "🍚🍚"
        case .inhaling: return "🍚🍚🍚"
        case .finished: return "🙏"
        case .digesting: return "zzZ"
        }
    }
}

/// Composes the mascot's faces, chewing animation frames, and the menu-bar string.
/// Riskier zones chew faster (shorter interval) — felt before the color warning.
public enum MukbangFace {
    /// The base chew cycle (one bite per usage refresh): 대기 → 발견 → 앙 → 꿀꺽.
    public static func chewFrames(for zone: MukbangZone) -> [String] {
        switch zone {
        case .finished:
            return ["( ˘ω˘ )🙏"]
        case .digesting:
            return ["( ﹃ )zzZ"]
        default:
            let f = zone.restingFace
            return ["\(f)", "\(f)●", "( o⊂●", "\(f) ✦"]
        }
    }

    /// Seconds per chew frame for the UI; smaller = faster chewing (more urgent).
    public static func chewInterval(for zone: MukbangZone) -> Double {
        switch zone {
        case .tasting: return 0.45
        case .cruising: return 0.35
        case .overeating: return 0.22
        case .inhaling: return 0.12
        case .finished, .digesting: return 0.0   // not chewing
        }
    }

    /// Menu-bar headline: face + percent, e.g. `( ˘▽˘)っ 42%`.
    public static func menuBarText(utilization: Double) -> String {
        let zone = MukbangZone.forUtilization(utilization)
        return "\(zone.restingFace) \(Formatting.percent(utilization))"
    }
}
