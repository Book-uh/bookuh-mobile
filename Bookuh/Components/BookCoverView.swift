import CryptoKit
import SwiftUI
import UIKit

struct BookCoverView: View {
    let urlString: String
    let isbn: String?
    let width: CGFloat
    let height: CGFloat
    @State private var loadedCover: (urls: [URL], image: UIImage?)?

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

    private var coverURLs: [URL] {
        let primary = coverURL
        var urls = [primary].compactMap { $0 }
        if let isbn, isbn.utf8.count == 13, isbn.utf8.allSatisfy({ (48...57).contains($0) }),
           let fallback = URL(string: "https://books.google.com/books/content?vid=ISBN\(isbn)&printsec=frontcover&img=1&zoom=1"),
           fallback != primary {
            urls.append(fallback)
        }
        return urls
    }

    var body: some View {
        let urls = coverURLs
        Group {
            if let loadedCover, loadedCover.urls == urls {
                if let image = loadedCover.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    placeholder
                }
            } else if urls.isEmpty {
                placeholder
            } else {
                ProgressView()
                    .tint(BookuhTheme.green)
            }
        }
        .task(id: urls) { await loadCover(from: urls) }
        .frame(width: width, height: height)
        .background(BookuhTheme.paperDeep)
        .clipShape(RoundedRectangle(cornerRadius: BookuhTheme.coverCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: BookuhTheme.coverCornerRadius)
                .stroke(BookuhTheme.line, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    @MainActor
    private func loadCover(from urls: [URL]) async {
        for url in urls {
            guard !Task.isCancelled else { return }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  !isGooglePlaceholder(data, from: response.url ?? url),
                  let image = UIImage(data: data) else { continue }
            guard !Task.isCancelled else { return }
            loadedCover = (urls, image)
            return
        }
        guard !Task.isCancelled else { return }
        loadedCover = (urls, nil)
    }

    private func isGooglePlaceholder(_ data: Data, from url: URL) -> Bool {
        guard url.host?.hasPrefix("books.google.") == true, data.count == 1269 else { return false }
        // Google Books는 표지가 없어도 기본 PNG를 정상 응답으로 돌려준다.
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return digest == "e3f8c414b288cbdf4e6d1e00eb6d3826157d10a5b5628b9318f726ea490eca12"
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "book.closed")
                .font(.system(size: width > 80 ? 28 : 20))
            if width >= 50 {
                Text("표지 없음")
                    .font(BookuhTheme.bodyFont(size: 10))
            }
        }
        .foregroundStyle(BookuhTheme.inkSoft)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
