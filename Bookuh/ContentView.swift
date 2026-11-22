import SwiftUI

struct ContentView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    var onAdded: ((ShelfItem) -> Void)? = nil
    @State private var query: String
    private let initialQuery: String?
    @State private var books: [BookSearchItem] = []
    @State private var isSearching = false
    @State private var errorMessage: String? = nil
    @State private var lastSearchedQuery = ""
    @State private var hasSearched = false
    @State private var currentPage = 1
    @State private var hasMore = false
    @State private var isLoadingMore = false
    @State private var loadMoreError: String? = nil
    @FocusState private var isSearchFocused: Bool
    // 화면 확인용 임시 책 목록이다.
    private let sampleBooks = ["어린왕자", "데미안", "용의자 X의 헌신"]

    init(initialQuery: String? = nil, onAdded: ((ShelfItem) -> Void)? = nil) {
        self.initialQuery = initialQuery
        self.onAdded = onAdded
        _query = State(initialValue: initialQuery ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, BookuhTheme.screenPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 16)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: BookuhTheme.cardSpacing) {
                        if isSearching {
                            loadingState
                        } else if let errorMessage {
                            messageCard(
                                title: "검색 결과를 불러오지 못했어요",
                                message: errorMessage,
                                systemImage: "exclamationmark.magnifyingglass"
                            )
                            Button("다시 시도") {
                                Task {
                                    await searchBooks(searchTerm: lastSearchedQuery)
                                }
                            }
                            .buttonStyle(BookuhPrimaryButtonStyle())
                            .frame(maxWidth: .infinity)
                        } else if !hasSearched {
                            messageCard(
                                title: "어떤 책을 찾고 있나요?",
                                message: "제목이나 저자로 검색해\n함께 읽을 판본을 골라보세요.",
                                systemImage: "books.vertical"
                            )
                        } else if books.isEmpty {
                            messageCard(
                                title: "추가할 수 있는 책을 찾지 못했어요",
                                message: hasMore ? "다음 페이지에서 더 찾아볼 수 있어요." : "다른 제목이나 저자로 다시 찾아보세요.",
                                systemImage: "magnifyingglass"
                            )
                            loadMoreSection
                        } else {
                            HStack {
                                Text("\(lastSearchedQuery) 검색 결과")
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text("\(books.count)권")
                            }
                            .font(BookuhTheme.bodyFont(size: 12))
                            .foregroundStyle(BookuhTheme.inkSoft)
                            .padding(.bottom, 2)
                            .accessibilityElement(children: .combine)

                            ForEach(books, id: \.isbn) { book in
                                NavigationLink {
                                    BookDetailView(book: book, onAdded: onAdded)
                                } label: {
                                    BookSearchRow(book: book)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("책 상세를 엽니다")
                                .accessibilityIdentifier("book.search.result.\(book.isbn)")
                            }

                            loadMoreSection
                        }
                    }
                    .padding(.horizontal, BookuhTheme.screenPadding)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(BookuhTheme.paper.ignoresSafeArea())
            .bookuhNavigationTitle("책 담기")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if onAdded != nil {
                        Button("검색 닫기", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("book.search.close")
                    }
                }
            }
        }
        .task {
            if let initialQuery, !hasSearched {
                await searchBooks(searchTerm: initialQuery)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookuhShelfBookRemoved)) { notification in
            guard let isbn = notification.object as? String,
                  let index = books.firstIndex(where: { $0.isbn == isbn }) else { return }
            books[index].shelfState = "NOT_ADDED"
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(BookuhTheme.green)

                TextField("제목이나 저자를 입력하세요", text: $query)
                    .font(BookuhTheme.bodyFont())
                    .foregroundStyle(BookuhTheme.ink)
                    .tint(BookuhTheme.green)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isSearchFocused)
                    .onSubmit {
                        Task {
                            await searchBooks()
                        }
                    }
                    .accessibilityLabel("책 제목 또는 저자")
                    .accessibilityIdentifier("book.search.query")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 46)
            .background(BookuhTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius)
                    .stroke(BookuhTheme.green, lineWidth: 1.5)
            }

            Button(isSearching ? "검색 중" : "검색") {
                Task {
                    await searchBooks()
                }
            }
            .buttonStyle(BookuhPrimaryButtonStyle())
            .disabled(isSearching || isLoadingMore || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("책 검색")
            .accessibilityIdentifier("book.search.submit")
        }
    }

    @ViewBuilder
    private var loadMoreSection: some View {
        if isLoadingMore {
            ProgressView()
                .tint(BookuhTheme.green)
                .frame(maxWidth: .infinity, minHeight: 44)
        } else if let loadMoreError {
            VStack(spacing: 10) {
                Text(loadMoreError)
                    .font(BookuhTheme.bodyFont(size: 12))
                    .foregroundStyle(BookuhTheme.inkSoft)
                    .multilineTextAlignment(.center)
                Button("다시 시도") {
                    Task {
                        await loadMoreBooks()
                    }
                }
                .buttonStyle(BookuhPrimaryButtonStyle())
            }
            .frame(maxWidth: .infinity)
        } else if hasMore {
            Button("더 보기") {
                Task {
                    await loadMoreBooks()
                }
            }
            .buttonStyle(BookuhPrimaryButtonStyle())
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("book.search.more")
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(BookuhTheme.green)
            Text("책을 찾고 있어요")
                .font(BookuhTheme.bodyFont())
                .foregroundStyle(BookuhTheme.inkSoft)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private func messageCard(title: String, message: String, systemImage: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(BookuhTheme.green)
                .frame(width: 68, height: 68)
                .background(BookuhTheme.greenTint)
                .clipShape(RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))

            Text(title)
                .font(BookuhTheme.emphasizedFont(size: 16))
                .foregroundStyle(BookuhTheme.ink)

            Text(message)
                .font(BookuhTheme.bodyFont(size: 13))
                .foregroundStyle(BookuhTheme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(.horizontal, 12)
    }

    @MainActor
    private func searchBooks(searchTerm: String? = nil) async {
        let keyword = (searchTerm ?? query).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !keyword.isEmpty, !isSearching, !isLoadingMore else {
            return
        }

        isSearching = true
        isSearchFocused = false
        hasSearched = true
        lastSearchedQuery = keyword
        errorMessage = nil
        loadMoreError = nil
        books = []
        hasMore = false

        defer {
            isSearching = false
        }

        guard let token = session.accessToken else {
            errorMessage = "접속 정보를 확인하지 못했어요. 다시 시도해 주세요."
            return
        }

        do {
            let result = try await BookSearchAPI().search(query: keyword, page: 1, accessToken: token)
            books = result.items
            currentPage = result.page
            hasMore = result.hasMore
        } catch {
            errorMessage = searchErrorMessage(for: error)
        }
    }

    @MainActor
    private func loadMoreBooks() async {
        guard hasMore, !isSearching, !isLoadingMore, let token = session.accessToken else {
            return
        }

        isLoadingMore = true
        loadMoreError = nil

        defer {
            isLoadingMore = false
        }

        do {
            let result = try await BookSearchAPI().search(
                query: lastSearchedQuery, page: currentPage + 1, accessToken: token
            )
            let shownISBNs = Set(books.map(\.isbn))
            books.append(contentsOf: result.items.filter { !shownISBNs.contains($0.isbn) })
            currentPage = result.page
            hasMore = result.hasMore
        } catch {
            loadMoreError = searchErrorMessage(for: error)
        }
    }

    private func searchErrorMessage(for error: Error) -> String {
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
            return "인터넷 연결을 확인한 뒤 다시 시도해 주세요."
        }
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return "검색이 오래 걸리고 있어요. 잠시 후 다시 시도해 주세요."
        }
        return "연결을 확인한 뒤 잠시 후 다시 시도해 주세요."
    }
}
