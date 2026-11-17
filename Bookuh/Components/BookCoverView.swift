import SwiftUI

struct BookCoverView: View {
    let urlString: String
    let width: CGFloat
    let height: CGFloat

    private var coverURL: URL? {
        let address = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty,
              var components = URLComponents(string: address),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else {
            return nil
        }

        if scheme == "http" {
            components.scheme = "https"
        }
        return components.url
    }

    var body: some View {
        Group {
            if let coverURL {
                AsyncImage(url: coverURL) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            BookuhTheme.paperDeep
                            ProgressView()
                                .tint(BookuhTheme.green)
                        }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .background(BookuhTheme.paperDeep)
        .clipShape(RoundedRectangle(cornerRadius: BookuhTheme.coverCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: BookuhTheme.coverCornerRadius)
                .stroke(BookuhTheme.line, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "book.closed")
                .font(.system(size: width > 80 ? 28 : 20))
            Text("표지 없음")
                .font(BookuhTheme.bodyFont(size: 10))
        }
        .foregroundStyle(BookuhTheme.inkSoft)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
