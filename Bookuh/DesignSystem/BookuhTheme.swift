import SwiftUI

enum BookuhTheme {
    static let paper = Color(red: 251 / 255.0, green: 247 / 255.0, blue: 238 / 255.0)
    static let paperDeep = Color(red: 243 / 255.0, green: 237 / 255.0, blue: 222 / 255.0)
    static let card = Color(red: 255 / 255.0, green: 253 / 255.0, blue: 248 / 255.0)
    static let line = Color(red: 227 / 255.0, green: 218 / 255.0, blue: 198 / 255.0)
    static let walnut = Color(red: 74 / 255.0, green: 53 / 255.0, blue: 43 / 255.0)
    static let ink = walnut
    static let inkSoft = Color(red: 112 / 255.0, green: 88 / 255.0, blue: 73 / 255.0)
    static let green = Color(red: 47 / 255.0, green: 93 / 255.0, blue: 70 / 255.0)
    static let greenDeep = Color(red: 35 / 255.0, green: 71 / 255.0, blue: 53 / 255.0)
    static let greenTint = Color(red: 233 / 255.0, green: 240 / 255.0, blue: 234 / 255.0)

    static let cornerRadius: CGFloat = 6
    static let coverCornerRadius: CGFloat = 4
    static let screenPadding: CGFloat = 20
    static let cardSpacing: CGFloat = 12

    static func titleFont(size: CGFloat = 20) -> Font {
        .custom("NotoSerifKR-Bold", size: size, relativeTo: .title2)
    }

    static func bodyFont(size: CGFloat = 15, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        .custom("NotoSansKR-Regular", size: size, relativeTo: textStyle)
    }

    static func emphasizedFont(size: CGFloat = 14) -> Font {
        .custom("NotoSansKR-Bold", size: size, relativeTo: .body)
    }
}

extension View {
    func bookuhNavigationTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(BookuhTheme.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(BookuhTheme.titleFont(size: 19))
                        .foregroundStyle(BookuhTheme.walnut)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .accessibilityAddTraits(.isHeader)
                }
            }
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

struct BookuhOutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius)

        configuration.label
            .font(BookuhTheme.emphasizedFont())
            .foregroundStyle(isEnabled ? BookuhTheme.green : BookuhTheme.inkSoft)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(configuration.isPressed ? BookuhTheme.greenTint : BookuhTheme.card, in: shape)
            .overlay {
                shape.strokeBorder(isEnabled ? BookuhTheme.green : BookuhTheme.line,
                                   style: StrokeStyle(lineWidth: isEnabled ? 1.5 : 1, dash: isEnabled ? [] : [4]))
            }
            .contentShape(shape)
    }
}
