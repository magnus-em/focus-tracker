import SwiftUI

extension View {
    func glassCard<S: InsettableShape>(in shape: S) -> some View {
        background(shape.fill(.thinMaterial))
            .overlay(shape.strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5))
    }

    func glassCard(cornerRadius: CGFloat = 12) -> some View {
        glassCard(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func glassChrome() -> some View {
        background(.regularMaterial)
    }
}
