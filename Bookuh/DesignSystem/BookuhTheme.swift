import SwiftUI

enum BookuhTheme {
    static let paper = Color(red: 251 / 255.0, green: 247 / 255.0, blue: 238 / 255.0)
    static let paperDeep = Color(red: 243 / 255.0, green: 237 / 255.0, blue: 222 / 255.0)
    static let card = Color(red: 255 / 255.0, green: 253 / 255.0, blue: 248 / 255.0)
    static let line = Color(red: 227 / 255.0, green: 218 / 255.0, blue: 198 / 255.0)
    static let ink = Color(red: 43 / 255.0, green: 42 / 255.0, blue: 36 / 255.0)
    static let inkSoft = Color(red: 119 / 255.0, green: 113 / 255.0, blue: 95 / 255.0)
    static let green = Color(red: 47 / 255.0, green: 93 / 255.0, blue: 70 / 255.0)
    static let greenDeep = Color(red: 35 / 255.0, green: 71 / 255.0, blue: 53 / 255.0)
    static let greenTint = Color(red: 233 / 255.0, green: 240 / 255.0, blue: 234 / 255.0)
    static let wine = Color(red: 138 / 255.0, green: 75 / 255.0, blue: 60 / 255.0)

    static let cornerRadius: CGFloat = 6
    static let coverCornerRadius: CGFloat = 4
    static let screenPadding: CGFloat = 20
    static let cardSpacing: CGFloat = 12

    static func titleFont(size: CGFloat = 20) -> Font {
        .custom("NotoSerifKR-Bold", size: size, relativeTo: .title2)
    }

    static func bodyFont(size: CGFloat = 15) -> Font {
        .custom("NotoSansKR-Regular", size: size, relativeTo: .body)
    }

    static func emphasizedFont(size: CGFloat = 14) -> Font {
        .custom("NotoSansKR-Bold", size: size, relativeTo: .body)
    }
}

struct BookuhPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BookuhTheme.emphasizedFont())
            .foregroundStyle(BookuhTheme.card)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(configuration.isPressed ? BookuhTheme.greenDeep : BookuhTheme.green)
            .clipShape(RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
            .opacity(isEnabled ? 1 : 0.45)
    }
}
