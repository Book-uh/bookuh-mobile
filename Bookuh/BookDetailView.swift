import SwiftUI

struct BookDetailView: View {
    @EnvironmentObject private var session: AppSession
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var addedBook: ShelfItem?
    @State private var currentReadingStatus: String?
    @State private var matchedShelfBook: ShelfItem?
    private let searchBook: BookSearchItem?
    private let shelfBook: ShelfItem?
    private let managerBooks: [ShelfItem]
    private let coverHeight: CGFloat = 150
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
    private var savedBook: ShelfItem? { shelfBook ?? matchedShelfBook }
    private var isOnShelf: Bool { savedBook != nil || addedBook != nil || searchBook?.isOnShelf == true }

    private func booksForManager(_ book: ShelfItem) -> [ShelfItem] {
        managerBooks.isEmpty ? [book] : managerBooks
    }

    var body: some View {
        Group {
            if let savedBook {
                detail.modifier(ManagerChatEntry(books: booksForManager(savedBook), initialBook: savedBook))
            } else {
                detail
            }
        }
        .task { await loadSavedSearchBook() }
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    BookCoverView(urlString: cover, width: 104, height: coverHeight)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(BookuhTheme.titleFont(size: 21))
                            .foregroundStyle(BookuhTheme.ink)

                        if !author.isEmpty {
                            Text(author)
                                .font(BookuhTheme.bodyFont(size: 13))
                                .foregroundStyle(BookuhTheme.inkSoft)
                        }
                        if let savedBook {
                            Text(readingStatusTitle(currentReadingStatus ?? savedBook.readingStatus))
                                .font(BookuhTheme.emphasizedFont(size: 12))
                                .foregroundStyle(BookuhTheme.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(BookuhTheme.greenTint)
                                .clipShape(RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
                        }

                        if !publisher.isEmpty || !publishedYear.isEmpty {
                            Spacer(minLength: 6)

                            VStack(alignment: .leading, spacing: 4) {
                                if !publisher.isEmpty {
                                    Text("출판사")
                                        .font(BookuhTheme.emphasizedFont(size: 11))
                                    Text(publisher)
                                }
                                if !publishedYear.isEmpty {
                                    Text("\(publishedYear)년 출간")
                                }
                            }
                            .font(BookuhTheme.bodyFont(size: 12))
                            .foregroundStyle(BookuhTheme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: coverHeight, alignment: .topLeading)
                }

                if let savedBook {
                    BookJourneyView(book: savedBook, books: booksForManager(savedBook)) { status in
                        currentReadingStatus = status
                    }
                    keptLettersLink(for: savedBook)
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
            if searchBook != nil && savedBook == nil {
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

    private func keptLettersLink(for book: ShelfItem) -> some View {
        NavigationLink {
            CharacterLettersView(book: book, books: booksForManager(book), character: nil)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "envelope")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(BookuhTheme.green)
                    .frame(width: 36, height: 36)
                    .background(BookuhTheme.paperDeep, in: RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
                    .accessibilityHidden(true)

                Text("간직한 편지")
                    .font(BookuhTheme.emphasizedFont(size: 15))
                    .foregroundStyle(BookuhTheme.ink)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BookuhTheme.inkSoft)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(BookuhTheme.card, in: RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius).strokeBorder(BookuhTheme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("book.letters.kept")
    }

    @MainActor
    private func loadSavedSearchBook() async {
        guard matchedShelfBook == nil, let book = searchBook, book.isOnShelf,
              let token = session.accessToken else { return }
        do {
            matchedShelfBook = try await BookuhAPI().feature("bookshelf/\(book.isbn)", token: token)
            errorMessage = nil
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
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
