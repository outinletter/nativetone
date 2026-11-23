import SwiftUI
import UIKit

/// "Ink & ivory": a restrained, editorial look. Navy ink on warm paper, brass as the only accent.
enum Theme {
    static let paper = Color(light: 0xF7F4EC, dark: 0x0B1426)      // screen background
    static let surface = Color(light: 0xFFFFFF, dark: 0x121F38)    // cards and inputs
    static let hairline = Color(light: 0xD9D2C0, dark: 0x2A3A5C)   // 1pt rules and borders
    static let primary = Color(light: 0x0F2347, dark: 0xC9A96B)    // buttons, selected state
    static let onPrimary = Color(light: 0xF8F5EE, dark: 0x0B1426)
    static let gold = Color(light: 0x9A7B3F, dark: 0xC9A96B)       // eyebrows, rules
    static let danger = Color(light: 0x9B2C2C, dark: 0xE08A8A)

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Small tracked caps label used above sections.
    static func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.8)
            .foregroundStyle(gold)
    }

    /// Applies serif titles to navigation bars and an opaque paper tab bar.
    static func applyAppearance() {
        let serifTitle: (CGFloat, UIFont.Weight) -> UIFont = { size, weight in
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            let desc = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
            return UIFont(descriptor: desc, size: size)
        }
        let paper = UIColor(paper)

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = paper
        nav.shadowColor = UIColor(hairline)
        nav.titleTextAttributes = [.font: serifTitle(17, .semibold)]
        nav.largeTitleTextAttributes = [.font: serifTitle(32, .semibold)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav

        // iOS 26+: leave the tab bar alone so the system draws its Liquid Glass.
        if #available(iOS 26, *) { return }
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = paper
        tab.shadowColor = UIColor(hairline)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

/// Solid ink button with a small radius.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .tracking(0.4)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.primary, in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(Theme.onPrimary)
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.35)
    }
}

/// Hairline-outlined secondary button.
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundStyle(Theme.primary)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.primary.opacity(0.35), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// White card with a hairline border and square-ish corners.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline, lineWidth: 1))
    }
}
