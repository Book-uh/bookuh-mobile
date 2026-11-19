import SwiftUI

struct ContentView: View {
    @Environment(\.dismiss) private var dismiss
    var onAdded: ((ShelfItem) -> Void)? = nil
    @State private var query = ""
    @State private var books: [BookSearchItem] = []
    @State private var isSearching = false
    @State private var errorMessage: String? = nil
    @State private var lastSearchedQuery = ""
    @State private var hasSearched = false
    @FocusState private var isSearchFocused: Bool
    // 화면 확인용 임시 책 목록이다.
    private let sampleBooks = ["어린왕자", "데미안", "용의자 X의 헌신"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("책 담기")
                        .font(BookuhTheme.titleFont())
                        .foregroundStyle(BookuhTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if onAdded != nil {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(BookuhTheme.inkSoft)
                        }
                        .accessibilityLabel("검색 닫기")
                    }
                }
                .padding(.horizontal, BookuhTheme.screenPadding)
                .padding(.top, 10)
                .padding(.bottom, 12)

                searchBar
                    .padding(.horizontal, BookuhTheme.screenPadding)
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
                                title: "검색 결과가 없어요",
                                message: "다른 제목이나 저자로 다시 찾아보세요.",
                                systemImage: "magnifyingglass"
                            )
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

                            ForEach(books, id: \.isbn13) { book in
                                NavigationLink {
                                    BookDetailView(book: book, onAdded: onAdded)
                                } label: {
                                    BookSearchRow(book: book)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("책 상세를 엽니다")
                                .accessibilityIdentifier("book.search.result.\(book.isbn13)")
                            }
                        }
                    }
                    .padding(.horizontal, BookuhTheme.screenPadding)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(BookuhTheme.paper.ignoresSafeArea())
            .navigationTitle("책 담기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(BookuhTheme.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
            .disabled(isSearching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("책 검색")
            .accessibilityIdentifier("book.search.submit")
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

        guard !keyword.isEmpty, !isSearching else {
            return
        }

        isSearching = true
        isSearchFocused = false
        hasSearched = true
        lastSearchedQuery = keyword
        errorMessage = nil
        books = []

        defer {
            isSearching = false
        }

        do {
            books = try await BookSearchAPI().search(query: keyword)
        } catch {
            if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
                errorMessage = "인터넷 연결을 확인한 뒤 다시 시도해 주세요."
            } else if let urlError = error as? URLError, urlError.code == .timedOut {
                errorMessage = "검색이 오래 걸리고 있어요. 잠시 후 다시 시도해 주세요."
            } else {
                errorMessage = "연결을 확인한 뒤 잠시 후 다시 시도해 주세요."
            }
        }
    }
}
