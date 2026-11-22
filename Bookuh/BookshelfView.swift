import SwiftUI

struct BookuhRootView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        if session.accessToken == nil {
            welcome
        } else {
            TabView {
                BookshelfView()
                    .tabItem { Label("내 책장", systemImage: "books.vertical") }
                ReadingRecordsView()
                    .tabItem { Label("독서 기록", systemImage: "chart.bar") }
            }
        }
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                BookuhMascot(size: 96)
                    .padding(.top, 56)

                VStack(alignment: .leading, spacing: 14) {
                    Text("북어")
                        .font(BookuhTheme.titleFont(size: 34))
                    Text("책 속 인물과\n이야기를 나눠보세요")
                        .font(BookuhTheme.titleFont(size: 27))
                    Text("읽고 있는 책을 담고, 마지막으로 읽은 장면을 알려주세요. 그 시점의 인물을 만나 편지를 주고받을 수 있어요.")
                        .font(BookuhTheme.bodyFont(size: 14))
                        .foregroundStyle(BookuhTheme.inkSoft)
                        .lineSpacing(5)
                }

                VStack(alignment: .leading, spacing: 16) {
                    Label("읽고 싶은 책을 내 책장에 담아요", systemImage: "books.vertical")
                    Label("어디까지 읽었는지 북어에게 알려줘요", systemImage: "bookmark")
                    Label("편지로 인물과 가까워져요", systemImage: "envelope")
                }
                .font(BookuhTheme.bodyFont(size: 13))
                .foregroundStyle(BookuhTheme.green)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BookuhTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))

                if let message = session.errorMessage {
                    Text(message)
                        .font(BookuhTheme.bodyFont(size: 13))
                        .foregroundStyle(BookuhTheme.inkSoft)
                        .accessibilityIdentifier("session.error")
                }

                Button {
                    Task { await session.start() }
                } label: {
                    HStack(spacing: 10) {
                        if session.isStarting {
                            ProgressView().tint(BookuhTheme.card)
                        }
                        Text(session.isStarting ? "시작하는 중" : session.errorMessage == nil ? "시작하기" : "다시 시도")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(BookuhPrimaryButtonStyle())
                .disabled(session.isStarting)
                .accessibilityIdentifier("session.start")
            }
            .foregroundStyle(BookuhTheme.ink)
            .padding(BookuhTheme.screenPadding)
            .padding(.bottom, 32)
        }
        .background(BookuhTheme.paper.ignoresSafeArea())
    }
}

struct BookshelfView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var books: [ShelfItem] = []
    @State private var isLoading = false
    @State private var needsReload = false
    @State private var errorMessage: String?
    @State private var isSearchPresented = false
    @State private var pendingAddedBook: ShelfItem?
    @State private var selectedBook: ShelfItem?
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .topLeading),
              count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isLoading && books.isEmpty {
                        ProgressView("책장을 불러오고 있어요")
                            .tint(BookuhTheme.green)
                            .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        if let message = errorMessage {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("책장을 불러오지 못했어요")
                                    .font(BookuhTheme.emphasizedFont())
                                Text(message)
                                    .font(BookuhTheme.bodyFont(size: 13))
                                    .foregroundStyle(BookuhTheme.inkSoft)
                                Button("다시 시도") {
                                    Task { await loadBookshelf() }
                                }
                                .buttonStyle(BookuhPrimaryButtonStyle())
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(BookuhTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
                            .accessibilityIdentifier("bookshelf.error")
                        }

                        if books.isEmpty && errorMessage == nil {
                            emptyShelf
                        } else if !books.isEmpty {
                            shelf
                        }
                    }
                }
                .padding(.horizontal, BookuhTheme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .modifier(ManagerChatEntry(books: books, initialBook: nil, prompt: "읽은 곳을 말해줘요"))
            .background(BookuhTheme.paper.ignoresSafeArea())
            .bookuhNavigationTitle("내 책장")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSearchPresented = true
                    } label: {
                        Label("책 찾기", systemImage: "plus")
                    }
                    .accessibilityIdentifier("bookshelf.search")
                }
            }
            .navigationDestination(item: $selectedBook) { book in
                BookDetailView(shelfItem: book, managerBooks: books)
            }
            .sheet(isPresented: $isSearchPresented, onDismiss: finishAddingBook) {
                ContentView { book in
                    pendingAddedBook = book
                    isSearchPresented = false
                }
                .environmentObject(session)
            }
            .task { await loadBookshelf() }
            .refreshable { await loadBookshelf() }
            .onReceive(NotificationCenter.default.publisher(for: .bookuhRecordsChanged)) { _ in
                Task { await loadBookshelf() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .bookuhShelfBookRemoved)) { notification in
                guard let isbn = notification.object as? String else { return }
                books.removeAll { $0.isbn == isbn }
                if isLoading {
                    needsReload = true
                } else {
                    Task { await loadBookshelf() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await loadBookshelf() }
                }
            }
        }
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("\(books.count)권")
                    .font(BookuhTheme.emphasizedFont(size: 13))
                    .foregroundStyle(BookuhTheme.green)
                    .monospacedDigit()
                Spacer(minLength: 4)
                Text("최근 담은 순")
                    .font(BookuhTheme.bodyFont(size: 12))
                    .foregroundStyle(BookuhTheme.inkSoft)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(books) { book in
                    NavigationLink {
                        BookDetailView(shelfItem: book, managerBooks: books)
                    } label: {
                        shelfCard(book)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("bookshelf.book.\(book.isbn)")
                }
            }
        }
    }

    private var emptyShelf: some View {
        VStack(spacing: 14) {
            BookuhMascot(size: 56, animates: false)
                .accessibilityHidden(true)
            Text("첫 번째 책을 담아보세요")
                .font(BookuhTheme.titleFont(size: 21))
                .foregroundStyle(BookuhTheme.ink)
            Text("제목이나 저자로 함께 읽을 책을 찾을 수 있어요.")
                .font(BookuhTheme.bodyFont(size: 13))
                .foregroundStyle(BookuhTheme.inkSoft)
            Button("책 찾기", systemImage: "magnifyingglass") {
                isSearchPresented = true
            }
            .buttonStyle(BookuhPrimaryButtonStyle())
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 270)
        .accessibilityIdentifier("bookshelf.empty")
    }

    private func shelfCard(_ book: ShelfItem) -> some View {
        let statusColor: Color = switch book.readingStatus {
        case "READING": BookuhTheme.green
        case "FINISHED": BookuhTheme.walnut
        default: BookuhTheme.inkSoft
        }

        return VStack(alignment: .leading, spacing: 9) {
            BookCoverView(urlString: book.coverUrl ?? "", width: 110, height: 160)
                .shadow(color: BookuhTheme.walnut.opacity(0.18), radius: 6, x: 0, y: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background {
                    VStack(spacing: 0) {
                        BookuhTheme.paperDeep
                        BookuhTheme.walnut.opacity(0.52).frame(height: 3)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(BookuhTheme.emphasizedFont(size: 14))
                    .foregroundStyle(BookuhTheme.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                if !book.authors.isEmpty {
                    Text(book.authors.joined(separator: ", "))
                        .font(BookuhTheme.bodyFont(size: 12))
                        .foregroundStyle(BookuhTheme.inkSoft)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }
            }

            HStack(spacing: 5) {
                Circle()
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
                Text(readingStatusTitle(book.readingStatus))
                    .font(BookuhTheme.emphasizedFont(size: 11))
            }
            .foregroundStyle(statusColor)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @MainActor
    private func loadBookshelf() async {
        guard let token = session.accessToken else { return }
        if isLoading {
            needsReload = true
            return
        }
        isLoading = true
        defer { isLoading = false }
        repeat {
            needsReload = false
            errorMessage = nil
            do {
                let fetchedBooks = try await BookuhAPI().fetchBookshelf(accessToken: token)
                if !needsReload { books = fetchedBooks }
            } catch is CancellationError {
            } catch APIError.cancelled {
            } catch {
                errorMessage = error.localizedDescription
            }
        } while needsReload && !Task.isCancelled
    }

    private func finishAddingBook() {
        guard let book = pendingAddedBook else { return }
        pendingAddedBook = nil
        selectedBook = book
        NotificationCenter.default.post(name: .bookuhRecordsChanged, object: nil)
    }
}

func readingStatusTitle(_ status: String) -> String {
    switch status {
    case "READING": return "읽는 중"
    case "FINISHED": return "완독"
    default: return "읽기 전"
    }
}
