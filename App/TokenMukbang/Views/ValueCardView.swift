import SwiftUI
import TokenMukbangKit

/// Now-tab **Value / Savings** card (ADR-0021): what this billing period's tokens would cost at
/// API list rates vs the user's flat subscription. **Always rendered** — the frame shows even
/// before token data is ready (loading) or when the period has no priced usage, so the feature
/// never silently disappears. Cache reads dominate the full number, so we also surface the
/// "fresh work" cost (excl. cache reuse) as an honest second figure.
///
/// Shared so both the live window (`NowDashboard` in `AppShellView`) and `MenuContentView`
/// render the identical card — keeping it in one place is what fixes the earlier bug where the
/// card lived only in `MenuContentView` and never appeared in the actual `AppShellView` window.
struct ValueCardView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GlassTile(scheme: scheme) {
            VStack(alignment: .leading, spacing: DS.intra) {
                HStack(alignment: .firstTextBaseline) {
                    Text("VALUE").dsEyebrow()
                    Spacer()
                    Text(periodLabel).font(DS.captionFont).foregroundStyle(.tertiary)
                }
                if let v = model.valueEstimate, v.apiEquivalent > 0 {
                    body(v)
                } else if model.isLoadingTokens {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("Reading your usage…").font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    Text("No priced usage in this period yet.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(DS.section)
        }
    }

    @ViewBuilder
    private func body(_ v: ValueEstimate) -> some View {
        let sub = model.settings.subscriptionMonthlyCost
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(ValueEstimate.dollars(v.apiEquivalent)).font(.system(size: 24, weight: .bold))
            Text("at API rates").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if sub > 0 {
                // The "몇 배 썼나" headline — the wow number, sized up and labeled so its
                // meaning (× your plan's worth) reads at a glance, not just a bare "93×".
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(ValueEstimate.multipleLabel(v.multiple(subscription: sub)))
                        .font(.system(size: 18, weight: .heavy, design: .rounded).monospacedDigit())
                    Text("your plan").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.green)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Color.green.opacity(0.16), in: Capsule())
            }
        }
        if sub > 0 {
            // You pay / saving — the dollar amounts carry the weight: deep ink for what you
            // pay, vivid green for what you save (both bold); the connective text stays quiet.
            (Text("You pay ").foregroundStyle(.secondary)
             + Text(ValueEstimate.dollars(sub)).fontWeight(.bold).foregroundStyle(.primary)
             + Text(" → saving ").foregroundStyle(.secondary)
             + Text(ValueEstimate.dollars(v.savings(subscription: sub))).fontWeight(.bold).foregroundStyle(.green))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Set your plan price in Settings → General to see savings.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Text("Fresh work only (excl. cache reuse): \(ValueEstimate.dollars(v.costExclCacheRead))")
            .font(.caption2).foregroundStyle(.tertiary)
        ForEach(v.lines.filter { $0.priced }.prefix(3)) { line in
            HStack(spacing: 8) {
                Text(line.name).font(DS.captionFont)
                Spacer()
                Text(ValueEstimate.dollars(line.cost)).font(DS.captionFont.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "since the 15th" / "last 30d" — what window the card aggregates.
    private var periodLabel: String {
        if let day = model.settings.billingCycleDay { return "since the \(ordinal(min(max(day, 1), 28)))" }
        return "last 30d"
    }

    private func ordinal(_ n: Int) -> String {
        let suffix: String
        if (11...13).contains(n % 100) { suffix = "th" }
        else { switch n % 10 { case 1: suffix = "st"; case 2: suffix = "nd"; case 3: suffix = "rd"; default: suffix = "th" } }
        return "\(n)\(suffix)"
    }
}
