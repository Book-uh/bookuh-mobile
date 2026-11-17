import SwiftUI

struct BookDetailView: View {
    let book: BookSearchItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    BookCoverView(urlString: book.thumbnailUrl, width: 104, height: 150)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(book.title)
                            .font(BookuhTheme.titleFont(size: 21))
                            .foregroundStyle(BookuhTheme.ink)

                        if !book.author.isEmpty {
                            Text(book.author)
                                .font(BookuhTheme.bodyFont(size: 13))
                                .foregroundStyle(BookuhTheme.inkSoft)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !book.publisher.isEmpty || !book.publishedDate.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("책 정보")
                            .font(BookuhTheme.emphasizedFont())

                        if !book.publisher.isEmpty {
                            LabeledContent("출판사", value: book.publisher)
                        }

                        if !book.publishedDate.isEmpty {
                            LabeledContent("출간일", value: book.publishedDate)
                        }
                    }
                    .font(BookuhTheme.bodyFont(size: 13))
                    .foregroundStyle(BookuhTheme.ink)
                    .padding(16)
                    .background(BookuhTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius)
                            .stroke(BookuhTheme.line, lineWidth: 1)
                    }
                }
            }
            .padding(BookuhTheme.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(BookuhTheme.paper.ignoresSafeArea())
        .navigationTitle("책 상세")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(BookuhTheme.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
