import SwiftUI
import ClaudeUsageKit

/// The Settings space: theme (4 presets + custom), thresholds, notifications (D1–D3).
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Wider inter-group spacing gives the stacked cards a clear rhythm (design-critique r3).
        VStack(alignment: .leading, spacing: 14) {
            // D1 — Theme
            section("테마") {
                DSSegmented(selection: $model.settings.theme,
                            options: Theme.allCases) { $0.label }

                if model.settings.theme == .custom {
                    HStack(spacing: 10) {
                        hexColorPicker("Calm", \.calmHex)
                        hexColorPicker("Warn", \.warningHex)
                        hexColorPicker("Crit", \.criticalHex)
                        hexColorPicker("Accent", \.accentHex)
                    }
                } else {
                    // Risk-ramp preview (calm→critical) — a meaningful preview of the chosen
                    // theme, not a row of toy dots (design-critique r2).
                    HStack(spacing: 8) {
                        Capsule()
                            .fill(LinearGradient(colors: [
                                Color(hex: model.settings.palette.calmHex),
                                Color(hex: model.settings.palette.watchHex),
                                Color(hex: model.settings.palette.warningHex),
                                Color(hex: model.settings.palette.criticalHex),
                            ], startPoint: .leading, endPoint: .trailing))
                            .frame(height: 8)
                            .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
                        Circle().fill(Color(hex: model.settings.palette.accentHex))
                            .frame(width: 10, height: 10)
                            .help("강조색")
                    }
                }
            }

            // D2 — Thresholds
            section("임계값 (완식 경고)") {
                threshold("Warning", value: $model.settings.thresholds.warning, color: Color(hex: model.settings.palette.warningHex))
                threshold("Critical", value: $model.settings.thresholds.critical, color: Color(hex: model.settings.palette.criticalHex))
            }

            // G1 — Temperament (smart color)
            section("기질 (식욕 성향)") {
                DSSegmented(selection: $model.settings.temperament,
                            options: Temperament.allCases) { $0.label }
            }

            // D3 — Notifications
            section("알림") {
                Text("서피스").font(.caption2).foregroundStyle(.tertiary)
                Toggle("5h", isOn: $model.settings.notifications.fiveHour)
                Toggle("7d", isOn: $model.settings.notifications.sevenDay)
                Toggle("Sonnet", isOn: $model.settings.notifications.sonnet)
                Text("이벤트").font(.caption2).foregroundStyle(.tertiary).padding(.top, 4)
                Toggle("과식 경고 (escalation)", isOn: $model.settings.notifications.escalation)
                Toggle("소화 완료 (recovery)", isOn: $model.settings.notifications.recovery)
                Toggle("페이스 경고", isOn: $model.settings.notifications.pacing)
                Toggle("새 상 차림 (reset)", isOn: $model.settings.notifications.reset)
                Toggle("추가 크레딧 (준비 중)", isOn: $model.settings.notifications.extraCredit)
                    .disabled(true)   // reserved — no extra-usage data source yet
                Toggle("토큰 만료", isOn: $model.settings.notifications.tokenExpiry)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.caption)
        }
    }

    /// Each settings group sits in a GlassTile so Settings shares the dashboard's card
    /// aesthetic (design-critique: unify Settings/History into card containers).
    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder _ content: @escaping () -> C) -> some View {
        GlassTile(scheme: scheme) {
            VStack(alignment: .leading, spacing: DS.intra) {
                Text(title).dsEyebrow()
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.section)
        }
    }

    private func threshold(_ label: String, value: Binding<Double>, color: Color) -> some View {
        HStack {
            Text(label).font(.caption).frame(width: 60, alignment: .leading)
            Slider(value: value, in: 10...100, step: 5).tint(color)
            Text("\(Int(value.wrappedValue))%").font(.caption.monospacedDigit()).frame(width: 38, alignment: .trailing)
        }
    }

    /// A swatch + hex field bound to one palette color of the custom palette.
    private func hexColorPicker(_ label: String, _ keyPath: WritableKeyPath<ThemePalette, String>) -> some View {
        VStack(spacing: 2) {
            Circle().fill(Color(hex: model.settings.customPalette[keyPath: keyPath]))
                .frame(width: 16, height: 16)
            TextField(label, text: Binding(
                get: { model.settings.customPalette[keyPath: keyPath] },
                set: { model.settings.customPalette[keyPath: keyPath] = $0 }
            ))
            .font(.caption2.monospacedDigit())
            .frame(width: 56)
            .textFieldStyle(.roundedBorder)
        }
    }
}
