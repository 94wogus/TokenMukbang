import SwiftUI
import ClaudeUsageKit

/// The Settings space: theme (4 presets + custom), thresholds, notifications (D1–D3).
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // D1 — Theme
            section("테마") {
                Picker("", selection: $model.settings.theme) {
                    ForEach(Theme.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()

                if model.settings.theme == .custom {
                    HStack(spacing: 10) {
                        hexColorPicker("Calm", \.calmHex)
                        hexColorPicker("Warn", \.warningHex)
                        hexColorPicker("Crit", \.criticalHex)
                        hexColorPicker("Accent", \.accentHex)
                    }
                } else {
                    HStack(spacing: 6) {
                        ForEach([model.settings.palette.calmHex, model.settings.palette.watchHex,
                                 model.settings.palette.warningHex, model.settings.palette.criticalHex,
                                 model.settings.palette.accentHex], id: \.self) { hex in
                            Circle().fill(Color(hex: hex)).frame(width: 14, height: 14)
                        }
                    }
                }
            }

            // D2 — Thresholds
            section("임계값 (완식 경고)") {
                threshold("Warning", value: $model.settings.thresholds.warning, color: Color(hex: model.settings.palette.warningHex))
                threshold("Critical", value: $model.settings.thresholds.critical, color: Color(hex: model.settings.palette.criticalHex))
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

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
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
