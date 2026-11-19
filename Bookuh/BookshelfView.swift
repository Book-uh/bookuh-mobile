import SwiftUI

struct BookuhRootView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        if session.accessToken == nil {
            welcome
        } else {
            BookshelfView()
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
    @State private var books: [ShelfItem] = []
    @State private var isLoading = false
    @State private var needsReload = false
    @State private var errorMessage: String?
    @State private var isSearchPresented = false
    @State private var pendingAddedBook: ShelfItem?
    @State private var selectedBook: ShelfItem?
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    managerGuide

                    HStack {
                        Text("책과 나눈 이야기가 쌓이는 곳")
                            .font(BookuhTheme.bodyFont(size: 13))
                            .foregroundStyle(BookuhTheme.inkSoft)
                        Spacer()
                        Text("\(books.count)권")
                            .font(BookuhTheme.emphasizedFont(size: 13))
                            .foregroundStyle(BookuhTheme.green)
                    }

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
                            VStack(spacing: 16) {
                                Image(systemName: "books.vertical")
                                    .font(.system(size: 38))
                                    .foregroundStyle(BookuhTheme.green)
                                Text("첫 번째 책을 담아보세요")
                                    .font(BookuhTheme.titleFont(size: 21))
                                Text("제목이나 저자로 검색해\n함께 읽을 책을 골라보세요.")
                                    .font(BookuhTheme.bodyFont(size: 13))
                                    .foregroundStyle(BookuhTheme.inkSoft)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, minHeight: 280)
                            .accessibilityIdentifier("bookshelf.empty")
                        } else {
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(books) { book in
                                    NavigationLink {
                                        BookDetailView(shelfItem: book)
                                    } label: {
                                        shelfCard(book)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("bookshelf.book.\(book.isbn13)")
                                }
                            }
                        }
                    }
                }
                .padding(BookuhTheme.screenPadding)
            }
            .background(BookuhTheme.paper.ignoresSafeArea())
            .navigationTitle("내 책장")
            .toolbarBackground(BookuhTheme.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
                BookDetailView(shelfItem: book)
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
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await loadBookshelf() }
                }
            }
        }
    }

    private var managerGuide: some View {
        HStack(alignment: .center, spacing: 14) {
            BookuhMascot(size: 64)

            VStack(alignment: .leading, spacing: 7) {
                Text("북어")
                    .font(BookuhTheme.emphasizedFont(size: 13))
                    .foregroundStyle(BookuhTheme.green)
                Text(managerGuidance)
                    .font(BookuhTheme.bodyFont(size: 13))
                    .foregroundStyle(BookuhTheme.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(BookuhTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(BookuhTheme.card)
                    .frame(width: 10, height: 10)
                    .rotationEffect(.degrees(45))
                    .offset(x: -4)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bookshelf.managerGuide")
    }

    private var managerGuidance: String {
        if isLoading && books.isEmpty {
            return "책장을 살펴보고 있어요.\n잠시만 기다려 주세요."
        }
        if errorMessage != nil {
            return "책장을 확인하지 못했어요.\n아래에서 다시 불러와 주세요."
        }
        if books.isEmpty {
            return "안녕! 독서 매니저 북어예요.\n책 찾기를 눌러 첫 책을 담아볼까요?"
        }
        return "책장에 \(books.count)권이 모였어요.\n읽고 있는 책을 눌러 살펴보세요."
    }

    private func shelfCard(_ book: ShelfItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            BookCoverView(urlString: book.coverUrl ?? "", width: 96, height: 140)
                .frame(maxWidth: .infinity)
            Text(book.title)
                .font(BookuhTheme.emphasizedFont(size: 14))
                .foregroundStyle(BookuhTheme.ink)
                .lineLimit(2)
            Text(book.authors.joined(separator: ", "))
                .font(BookuhTheme.bodyFont(size: 11))
                .foregroundStyle(BookuhTheme.inkSoft)
                .lineLimit(1)
            Text(readingStatusTitle(book.readingStatus))
                .font(BookuhTheme.emphasizedFont(size: 10))
                .foregroundStyle(book.readingStatus == "FINISHED" ? BookuhTheme.wine : BookuhTheme.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(BookuhTheme.paperDeep)
                .clipShape(RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 244, alignment: .topLeading)
        .background(BookuhTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius)
                .stroke(BookuhTheme.line, lineWidth: 1)
        }
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
                books = try await BookuhAPI().fetchBookshelf(accessToken: token)
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
        Task { await loadBookshelf() }
    }
}

func readingStatusTitle(_ status: String) -> String {
    switch status {
    case "READING": return "읽는 중"
    case "FINISHED": return "완독"
    default: return "읽기 전"
    }
}
