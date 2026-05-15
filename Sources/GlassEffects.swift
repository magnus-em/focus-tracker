import SwiftUI
import AppKit

// Makes the hosting NSWindow AND its NSHostingView transparent so glassEffect
// refracts the actual desktop behind the popover, not a white panel.
struct WindowTransparencyConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            // NSHostingView (the SwiftUI host) sits as a subview of contentView
            // and has its own opaque background — clear it too.
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
            window.contentView?.subviews.forEach { sub in
                sub.wantsLayer = true
                sub.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    @ViewBuilder
    func glassCard<S: InsettableShape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(shape.fill(.thinMaterial))
                .overlay(shape.strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5))
        }
    }

    func glassCard(cornerRadius: CGFloat = 12) -> some View {
        glassCard(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    // Full-popover background: real Liquid Glass on macOS 26, material on older.
    @ViewBuilder
    func popoverBackground() -> some View {
        if #available(macOS 26.0, *) {
            self
                .background(WindowTransparencyConfigurator().frame(width: 0, height: 0))
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            self.background(.regularMaterial)
        }
    }

    // Kept for any other callers.
    @ViewBuilder
    func glassChrome() -> some View {
        if #available(macOS 26.0, *) {
            self.background(.clear)
        } else {
            self.background(.regularMaterial)
        }
    }

    @ViewBuilder
    func glassChip(in shape: some InsettableShape = Capsule()) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(shape.fill(.thinMaterial))
        }
    }

    // Tab chip: only the selected tab gets the tinted glass pill.
    // Unselected tabs are plain icons — matches iOS 26 tab bar best practice.
    @ViewBuilder
    func glassTabChip(selected: Bool, tint: Color = Color.accentColor) -> some View {
        if selected {
            if #available(macOS 26.0, *) {
                self.glassEffect(.regular.interactive().tint(tint), in: Capsule())
            } else {
                self.background(Capsule().fill(tint.opacity(0.12)))
            }
        } else {
            self
        }
    }
}

@ViewBuilder
func glassChipGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    if #available(macOS 26.0, *) {
        GlassEffectContainer { content() }
    } else {
        content()
    }
}
