import SwiftUI

struct DexButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(configuration.isPressed ? Color.accentColor.opacity(0.28) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(configuration.isPressed ? Color.accentColor.opacity(0.8) : Color.clear, lineWidth: 1))
            .shadow(color: configuration.isPressed || reduceMotion ? .clear : .black.opacity(0.12), radius: 2, y: 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

extension View { func dexInteractive() -> some View { buttonStyle(DexButtonStyle()) } }
