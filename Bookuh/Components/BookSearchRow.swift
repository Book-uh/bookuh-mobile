import SwiftUI

struct BookSearchRow: View {
    let book: BookSearchItem

    private var publicationSummary: String {
        [book.publisher, book.publishedYear.map(String.init)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BookCoverView(urlString: book.coverUrl ?? "", width: 64, height: 92)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(BookuhTheme.emphasizedFont(size: 14))
                    .foregroundStyle(BookuhTheme.ink)
                    .lineLimit(3)

                if !book.authors.isEmpty {
                    Text(book.authors.joined(separator: ", "))
                        .font(BookuhTheme.bodyFont(size: 12))
                        .foregroundStyle(BookuhTheme.inkSoft)
                        .lineLimit(2)
                }

                if !publicationSummary.isEmpty {
                    Text(publicationSummary)
                        .font(BookuhTheme.bodyFont(size: 12))
                        .foregroundStyle(BookuhTheme.inkSoft)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(book.isOnShelf ? "책 보기" : "담기")
                .font(BookuhTheme.emphasizedFont(size: 13))
                .foregroundStyle(book.isOnShelf ? BookuhTheme.green : BookuhTheme.card)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(book.isOnShelf ? BookuhTheme.greenTint : BookuhTheme.green)
                .clipShape(RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BookuhTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius)
                .stroke(BookuhTheme.line, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
        .accessibilityElement(children: .combine)
    }
}
