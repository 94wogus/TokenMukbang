import SwiftUI
import AppKit
import TokenMukbangKit

// 김 서림(Steam) z-stack 컴포넌트 (STEAM_DESIGN §스팀 시그니처, ADR-0016).
// z0 BrothGlow(바닥 언더글로우) · z3 SteamPlume(상단 김 워머스, 원형 없는 확산 워시) · GlassTile.
// 위험은 김의 밀도·빛깔로 — 숫자/게이지는 항상 이 레이어들 *위*의 불투명 콘텐츠에 둔다.
// 응결(Condensation) 물방울은 동그란 얼룩으로 보여 제거(디자인 피드백 2026-06-12).
// App/Shared/ 라 앱·위젯 두 타깃 공유(project.yml Shared glob).

/// z0 — 국물 언더글로우. 위험 hue의 라디얼이 바닥에서 차오르되, 프로스트 패널 *밑*에 깔려
/// 숫자를 절대 건드리지 않는다(배경).
struct BrothGlow: View {
    let level: String
    let isOver: Bool
    let scheme: ColorScheme

    var body: some View {
        let c = RiskTone.brothGlow(level: level, over: isOver, scheme: scheme)
        GeometryReader { geo in
            // A *floor* glow that rises and dies — confined to the lower region with a
            // steep falloff so it warms the base, not floods the whole panel (esp. over a
            // dark wallpaper where additive warmth reads stronger). (design-critique r2)
            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: c, location: 0.0),
                    .init(color: c.opacity(0.40), location: 0.45),
                    .init(color: .clear, location: 0.95),
                ]),
                center: .init(x: 0.5, y: 1.04),
                startRadius: 0,
                endRadius: geo.size.width * 0.78
            )
        }
        .allowsHitTesting(false)
    }
}

/// z3 — 김 워머스. 상단에서 아래로 *부드럽게 사라지는* 위험-틴트 확산 워시. 예전엔 흐린 타원
/// blob들을 겹쳤는데 동그란 얼룩처럼 보여 짜쳐서(디자인 피드백 2026-06-12) **원형 모양 전부 제거** —
/// 이제 가장자리 없는 순수 수직 그라디언트 한 겹. 위험 레벨이 알파를 결정, calm은 거의 안 보임.
struct SteamPlume: View {
    let level: String
    let isOver: Bool
    let scheme: ColorScheme

    var body: some View {
        let c = RiskTone.steamTint(level: level, over: isOver, scheme: scheme)
        // 가장자리 없는 수직 워시: 위는 따뜻하게, 아래로 자연스럽게 fade. 블롭/원 없음.
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: c, location: 0.0),
                .init(color: c.opacity(0.5), location: 0.45),
                .init(color: .clear, location: 1.0),
            ]),
            startPoint: .top, endPoint: .bottom
        )
        .blur(radius: 12)          // 띠 경계를 더 부드럽게(여전히 원형 아님)
        .allowsHitTesting(false)
    }
}

/// 솟은 프로스트 글래스 타일(z2) — 게이지·세션 묶음을 감싼다. 연속 코너 + 헤어라인 + 가는 specular.
struct GlassTile<Content: View>: View {
    let scheme: ColorScheme
    var radius: CGFloat = Steam.tileRadius
    @Environment(\.themeMood) private var mood
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let light = scheme == .light
        return content()
            // 솟은 유리 카드 = **적응형 material** + 진짜 유리 라이팅(광택·림광·두께·그림자).
            .background(.regularMaterial, in: shape)
            .background(mood.glassTint, in: shape)             // 테마 무드 살짝 (.clear=중성)
            // 보더는 거의 안 보이게 — 카드 구분은 그림자로(user 2026-06-12: 테두리 선 눈에 안 띄게).
            .overlay(shape.strokeBorder(.white.opacity(light ? 0.10 : 0.04), lineWidth: 0.5))
            // 상단 은은한 광택 sheen(유리에 비친 빛) — 부드럽게만.
            .overlay(alignment: .top) {
                LinearGradient(colors: [.white.opacity(light ? 0.18 : 0.10), .clear],
                               startPoint: .topLeading, endPoint: .center)
                    .clipShape(shape).allowsHitTesting(false)
            }
            // 떠 있는 느낌의 부드러운 드롭 섀도(하드 보더 대신 그림자로 분리).
            .shadow(color: .black.opacity(light ? 0.10 : 0.26), radius: 10, y: 4)
    }
}

/// 팝오버 전체를 감싸는 김 서림 배경. **레이어 순서 핵심**: 맨 뒤가 `.ultraThinMaterial`(데스크톱 프로스트),
/// 그 *위에* broth 글로우·틴트가 와야 라이브에서 보인다(material을 위에 깔면 다 덮인다). z3 김은 콘텐츠 위
/// 상단 빈 공간에만.
extension View {
    /// 팝오버 콘텐츠 배경을 **완전히 투명**하게 둔다 — 진짜 유리(데스크톱 굴절 + 살짝 blur)는 팝오버 패널의
    /// `NSGlassEffectView(.clear)`(ADR-0018)가 *뒤*에서 제공하므로, 여기에 어떤 베일도 얹으면 그 유리가
    /// 가려진다(user 2026-06-12: 완전 투명 + 살짝 blur). 위험/테마색은 카드(GlassTile)·게이지·칩이 든다.
    func steamBackground(level: String, isOver: Bool, scheme: ColorScheme, mood: ThemeMood) -> some View {
        self
    }
}
