import SwiftUI

struct BookSearchRow: View {
    let book: BookSearchItem

    private var publicationSummary: String {
        let publisher = book.publisher.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = String(book.publishedDate.prefix(4))
        return [publisher, year].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BookCoverView(urlString: book.thumbnailUrl, width: 64, height: 92)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(BookuhTheme.emphasizedFont(size: 14))
                    .foregroundStyle(BookuhTheme.ink)
                    .lineLimit(3)

                if !book.author.isEmpty {
                    Text(book.author)
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

            Text("보기")
                .font(BookuhTheme.emphasizedFont(size: 13))
                .foregroundStyle(BookuhTheme.card)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(BookuhTheme.green)
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
