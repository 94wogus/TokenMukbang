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

/// POV-correct copy. ❌ "사용량 80%" → ⭕ "80% 완식".
public enum MukbangCopy {
    /// Headline phrasing for a window: `42% 완식`.
    public static func headline(utilization: Double) -> String {
        "\(Formatting.percent(utilization)) 완식"
    }

    /// Reset countdown as digestion: `소화 중... 2h 13m`.
    public static func reset(to date: Date, from now: Date) -> String {
        "소화 중... \(Formatting.countdown(to: date, from: now))"
    }

    /// One-line status for the popover/menu, given a zone.
    public static func status(for zone: MukbangZone) -> String {
        switch zone {
        case .tasting: return "깨작깨작. 아직 여유"
        case .cruising: return "오물오물. 정상 페이스"
        case .overeating: return "우적우적. 페이스 빠름"
        case .inhaling: return "씹지도 않음. 빨간불"
        case .finished: return "잘 먹었습니다"
        case .digesting: return "배 두드리며 소화 중"
        }
    }

    public static func event(_ event: MukbangEvent) -> String {
        switch event {
        case .finished: return "( ˘ω˘ )🙏 잘 먹었습니다"
        case .freshTable: return "🍚 새 상 차림! 다음 회차 시작"
        case .paceWarning(let h): return "이 속도면 \(h)시간 뒤 완식합니다"
        case .spoonDropped: return "( ;-;) 숟가락을 떨어뜨렸습니다"
        case .backToKitchen: return "주방에 다시 다녀와야 합니다 (claude /login)"
        }
    }
}
