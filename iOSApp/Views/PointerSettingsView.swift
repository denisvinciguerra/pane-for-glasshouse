import SwiftUI

struct PointerSettingsView: View {
    let includesMotion: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @AppStorage("phoneTouchpadSensitivity") private var touchSensitivity = 1.0
    @AppStorage("phoneTouchpadHaptics") private var touchHaptics = true
    @AppStorage("phonePointerSensitivity") private var motionSensitivity = 1.0
    @AppStorage("phonePointerHaptics") private var motionHaptics = true

    static let defaultSensitivity = 1.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    section("Touchpad", sensitivity: $touchSensitivity, vibration: $touchHaptics)
                    if includesMotion {
                        section("Motion", sensitivity: $motionSensitivity, vibration: $motionHaptics)
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 20)
            }
            .background(palette.bg)
            .navigationTitle(Text("Pointer settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(.manrope(13, .semibold))
                }
            }
        }
        .font(.manrope(11))
        .foregroundStyle(palette.fg)
        .tint(palette.fg)
        .presentationBackground(palette.bg)
    }

    private func section(_ title: LocalizedStringKey, sensitivity: Binding<Double>,
                         vibration: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionLabel(title)
                Spacer()
                // Back to the default speed; greyed while already there.
                PinsLink("Reset to 1×") { sensitivity.wrappedValue = Self.defaultSensitivity }
                    .disabled(abs(sensitivity.wrappedValue - Self.defaultSensitivity) < 0.05)
            }
            VStack(spacing: 8) {
                HStack {
                    Text("Sensitivity")
                    Spacer()
                    (Text(sensitivity.wrappedValue, format: .number.precision(.fractionLength(1))) + Text(verbatim: "×"))
                        .monospacedDigit()
                }
                Slider(value: sensitivity, in: 0.5...2.5, step: 0.1)
                    .accessibilityLabel(Text("Sensitivity"))
            }
            Toggle(isOn: vibration) { SettingsNote("Vibration") }
                .toggleStyle(PaneSwitchStyle(drawsLabel: true))
        }
    }
}
