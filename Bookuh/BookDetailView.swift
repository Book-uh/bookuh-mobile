import SwiftUI

struct BookDetailView: View {
    @EnvironmentObject private var session: AppSession
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var addedBook: ShelfItem?
    private let searchBook: BookSearchItem?
    private let shelfBook: ShelfItem?
    private let managerBooks: [ShelfItem]
    private var onAdded: ((ShelfItem) -> Void)?

    init(book: BookSearchItem, onAdded: ((ShelfItem) -> Void)? = nil) {
        searchBook = book
        shelfBook = nil
        managerBooks = []
        self.onAdded = onAdded
    }

    init(shelfItem: ShelfItem, managerBooks: [ShelfItem] = []) {
        searchBook = nil
        shelfBook = shelfItem
        self.managerBooks = managerBooks.isEmpty ? [shelfItem] : managerBooks
        onAdded = nil
    }

    private var title: String { searchBook?.title ?? shelfBook?.title ?? "" }
    private var author: String { (searchBook?.authors ?? shelfBook?.authors ?? []).joined(separator: ", ") }
    private var cover: String { searchBook?.coverUrl ?? shelfBook?.coverUrl ?? "" }
    private var publisher: String { searchBook?.publisher ?? shelfBook?.publisher ?? "" }
    private var publishedYear: String { searchBook?.publishedYear.map(String.init) ?? "" }
    private var isOnShelf: Bool { addedBook != nil || searchBook?.isOnShelf == true }

    var body: some View {
        if let shelfBook {
            detail.modifier(ManagerChatEntry(books: managerBooks, initialBook: shelfBook))
        } else {
            detail
        }
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    BookCoverView(urlString: cover, width: 104, height: 150)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(BookuhTheme.titleFont(size: 21))
                            .foregroundStyle(BookuhTheme.ink)

                        if !author.isEmpty {
                            Text(author)
                                .font(BookuhTheme.bodyFont(size: 13))
                                .foregroundStyle(BookuhTheme.inkSoft)
                        }
                        if let shelfBook {
                            Text(readingStatusTitle(shelfBook.readingStatus))
                                .font(BookuhTheme.emphasizedFont(size: 12))
                                .foregroundStyle(BookuhTheme.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(BookuhTheme.greenTint)
                                .clipShape(RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !publisher.isEmpty || !publishedYear.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("책 정보")
                            .font(BookuhTheme.emphasizedFont())

                        if !publisher.isEmpty {
                            LabeledContent("출판사", value: publisher)
                        }

                        if !publishedYear.isEmpty {
                            LabeledContent("출간 연도", value: publishedYear)
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
        .safeAreaInset(edge: .bottom) {
            if searchBook != nil {
                VStack(spacing: 10) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(BookuhTheme.bodyFont(size: 12))
                            .foregroundStyle(BookuhTheme.inkSoft)
                    }
                    Button {
                        Task { await addBook() }
                    } label: {
                        HStack(spacing: 10) {
                            if isAdding { ProgressView().tint(BookuhTheme.card) }
                            Text(isAdding ? "책장에 담는 중" : isOnShelf ? "책장에 담았어요" : "내 책장에 담기")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(BookuhPrimaryButtonStyle())
                    .disabled(isAdding || isOnShelf)
                    .accessibilityIdentifier("book.add")
                }
                .padding(BookuhTheme.screenPadding)
                .background(BookuhTheme.paper)
            }
        }
        .interactiveDismissDisabled(isAdding)
        .navigationBarBackButtonHidden(isAdding)
    }

    @MainActor
    private func addBook() async {
        guard !isAdding, let book = searchBook else { return }
        guard let token = session.accessToken else {
            errorMessage = "접속 정보를 확인하지 못했어요. 다시 시도해 주세요."
            return
        }
        isAdding = true
        errorMessage = nil
        defer { isAdding = false }
        do {
            let saved = try await BookuhAPI().addToBookshelf(book: book, accessToken: token)
            addedBook = saved
            onAdded?(saved)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
