import Foundation

/// The cast: each Claude model is a 먹방 performer (ADR-0009).
public enum ModelCast: Sendable, CaseIterable, Equatable, Hashable {
    case opus     // 대식가 — 한 입이 크다
    case sonnet   // 평균인 — 밥 잘 먹는 보통 사람
    case haiku    // 소식좌 — 후루룩, 깨작거림
    case fable    // 미식가 — 새로 들어온 입맛 까다로운 손님

    /// Best-effort mapping from a model id (e.g. `claude-opus-4-8`, `claude-fable-5`,
    /// `seven_day_sonnet`). Order matters only in that families are mutually exclusive.
    public static func forModel(_ raw: String) -> ModelCast? {
        let s = raw.lowercased()
        if s.contains("opus") { return .opus }
        if s.contains("sonnet") { return .sonnet }
        if s.contains("haiku") { return .haiku }
        if s.contains("fable") { return .fable }
        return nil
    }

    public var label: String {
        switch self {
        case .opus: return "대식가"
        case .sonnet: return "평균인"
        case .haiku: return "소식좌"
        case .fable: return "미식가"
        }
    }

    public var face: String {
        switch self {
        case .opus: return "( ⊙o⊙)🍖"
        case .sonnet: return "( ˘▽˘)🍚"
        case .haiku: return "( ˙ᵕ˙)🥢"
        case .fable: return "( ´ ▽ ` )🍰"
        }
    }

    public var modelName: String {
        switch self {
        case .opus: return "Opus"
        case .sonnet: return "Sonnet"
        case .haiku: return "Haiku"
        case .fable: return "Fable"
        }
    }
}
