import SwiftUI
import UIKit

enum Theme {
    static let background = Color(red: 0.043, green: 0.043, blue: 0.063)   // #0B0B10
    static let surface    = Color(red: 0.105, green: 0.105, blue: 0.135)   // #1B1B22
    static let surfaceHi  = Color(red: 0.155, green: 0.155, blue: 0.190)   // #282830
    static let stroke     = Color.white.opacity(0.08)
    static let accent     = Color(red: 0.898, green: 0.098, blue: 0.227)   // #E5193A
    static let accentDeep = Color(red: 0.690, green: 0.040, blue: 0.140)   // #B00A24
    static let text       = Color.white
    static let text2      = Color.white.opacity(0.62)

    static let accentGradient = LinearGradient(colors: [accent, accentDeep],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)

    static let uiAccent     = UIColor(red: 0.898, green: 0.098, blue: 0.227, alpha: 1)
    static let uiBackground = UIColor(red: 0.043, green: 0.043, blue: 0.063, alpha: 1)
}

extension View {
    func glow(_ color: Color = Theme.accent, radius: CGFloat = 12, opacity: Double = 0.6) -> some View {
        shadow(color: color.opacity(opacity), radius: radius)
    }

    func card() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.stroke))
    }
}

enum SafeArea {
    static var insets: UIEdgeInsets {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        return window?.safeAreaInsets ?? .zero
    }
}
