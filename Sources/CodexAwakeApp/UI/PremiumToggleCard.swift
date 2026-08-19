import SwiftUI

struct PremiumToggleCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    let language: AppLanguage
    @Binding var isOn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var hasKeyboardFocus: Bool

    var body: some View {
        Button {
            if reduceMotion {
                isOn.toggle()
            } else {
                withAnimation(.easeInOut(duration: 0.18)) { isOn.toggle() }
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CockpitPalette.silver)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(CockpitPalette.muted)
                        .lineLimit(3)
                }
                Spacer(minLength: 8)
                PremiumSwitchIndicator(isOn: isOn)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PremiumToggleButtonStyle(isOn: isOn, accent: accent))
        .focused($hasKeyboardFocus)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(CockpitPalette.ice, lineWidth: hasKeyboardFocus ? 2 : 0)
                .padding(-3)
        )
        .accessibilityLabel(title)
        .accessibilityValue(language.text(isOn ? "On" : "Off", isOn ? "Включено" : "Выключено"))
        .accessibilityHint(subtitle)
    }
}

struct PremiumSwitchIndicator: View {
    let isOn: Bool

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            Capsule()
                .fill(isOn ? CockpitPalette.ice : CockpitPalette.muted.opacity(0.28))
            Capsule()
                .stroke(
                    isOn ? CockpitPalette.iceDeep : CockpitPalette.separator,
                    lineWidth: contrast == .increased ? 2 : 1
                )
            Circle()
                .fill(Color.white)
                .padding(2.5)
                .overlay {
                    if differentiateWithoutColor, isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(CockpitPalette.iceDeep)
                    }
                }
                .offset(x: isOn ? 7 : -7)
        }
        .frame(width: 34, height: 20)
    }
}

private struct PremiumToggleButtonStyle: ButtonStyle {
    let isOn: Bool
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                isOn ? accent.opacity(0.075) : CockpitPalette.panelRaised.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isOn ? accent.opacity(0.34) : CockpitPalette.separator.opacity(0.62))
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}
