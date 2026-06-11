import Foundation

/// The cast: each Claude model is a 먹방 performer (ADR-0009).
public enum ModelCast: Sendable, CaseIterable, Equatable {
    case opus     // 대식가 — 한 입이 크다
    case sonnet   // 평균인 — 밥 잘 먹는 보통 사람
    case haiku    // 소식좌 — 후루룩, 깨작거림

    /// Best-effort mapping from a model id (e.g. `claude-opus-4-8`, `seven_day_sonnet`).
    public static func forModel(_ raw: String) -> ModelCast? {
        let s = raw.lowercased()
        if s.contains("opus") { return .opus }
        if s.contains("sonnet") { return .sonnet }
        if s.contains("haiku") { return .haiku }
        return nil
    }

    public var label: String {
        switch self {
        case .opus: return "대식가"
        case .sonnet: return "평균인"
        case .haiku: return "소식좌"
        }
    }

    public var face: String {
        switch self {
        case .opus: return "( ⊙o⊙)🍖"
        case .sonnet: return "( ˘▽˘)🍚"
        case .haiku: return "( ˙ᵕ˙)🥢"
        }
    }

    public var modelName: String {
        switch self {
        case .opus: return "Opus"
        case .sonnet: return "Sonnet"
        case .haiku: return "Haiku"
        }
    }
}
