import SwiftUI

@MainActor
final class ManagerChatStore: ObservableObject {
    @Published private(set) var messages: [ManagerMessageItem] = []
    @Published private(set) var nextCursor: String?
    @Published private(set) var isLoadingLatest = false
    @Published private(set) var isLoadingOlder = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var historyError: String?
    @Published private(set) var olderError: String?
    @Published private(set) var isSending = false
    @Published private(set) var pendingRequest: ManagerTalkRequest?
    @Published private(set) var sendError: String?
    @Published private(set) var recentExchange: (message: String, reply: String)?
    @Published private(set) var bottomUpdate = 0

    private let api: BookuhAPI

    init(api: BookuhAPI = BookuhAPI()) {
        self.api = api
    }

    var canSend: Bool {
        !isSending && !isLoadingLatest && !isLoadingOlder && pendingRequest == nil
    }

    func loadLatest(accessToken: String) async {
        guard !isSending, !isLoadingLatest, !isLoadingOlder else { return }
        await refreshLatest(accessToken: accessToken)
    }

    func loadOlder(accessToken: String) async {
        guard !isLoadingLatest, !isLoadingOlder, !isSending, let cursor = nextCursor else { return }
        isLoadingOlder = true
        olderError = nil
        defer { isLoadingOlder = false }

        do {
            let page = try await api.fetchManagerMessages(before: cursor, accessToken: accessToken)
            let currentIDs = Set(messages.map(\.id))
            messages = page.items.filter { !currentIDs.contains($0.id) } + messages
            nextCursor = page.nextCursor
        } catch APIError.http(400) {
            isLoadingOlder = false
            await refreshLatest(accessToken: accessToken)
        } catch {
            if !Task.isCancelled { olderError = error.localizedDescription }
        }
    }

    func send(message: String, isbn: String?, accessToken: String) async {
        guard canSend else { return }
        let request = ManagerTalkRequest(message: message, isbn: isbn)
        guard !request.message.isEmpty else { return }
        pendingRequest = request
        await sendPending(accessToken: accessToken)
    }

    func sendPending(accessToken: String) async {
        guard !isSending, !isLoadingLatest, !isLoadingOlder, let request = pendingRequest else { return }
        isSending = true
        sendError = nil
        bottomUpdate += 1
        defer { isSending = false }

        do {
            let response = try await api.talkToManager(request, accessToken: accessToken)
            guard let reply = response.assistantMessage,
                  !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ManagerAPIError.invalidResponse
            }
            pendingRequest = nil
            recentExchange = (request.message, reply)
            bottomUpdate += 1
            await refreshLatest(accessToken: accessToken)
        } catch {
            sendError = error.localizedDescription
            bottomUpdate += 1
        }
    }

    func takeFailedMessage() -> String? {
        guard !isSending, sendError != nil, let request = pendingRequest else { return nil }
        pendingRequest = nil
        sendError = nil
        return request.message
    }

    private func refreshLatest(accessToken: String) async {
        isLoadingLatest = true
        historyError = nil
        defer { isLoadingLatest = false }

        do {
            let page = try await api.fetchManagerMessages(accessToken: accessToken)
            messages = page.items
            nextCursor = page.nextCursor
            recentExchange = nil
            olderError = nil
            hasLoaded = true
            bottomUpdate += 1
        } catch {
            if !Task.isCancelled { historyError = error.localizedDescription }
        }
    }
}

struct ManagerChatEntry: ViewModifier {
    let books: [ShelfItem]
    let initialBook: ShelfItem?
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    isPresented = true
                } label: {
                    BookuhMascot(size: 54)
                        .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("북어 부르기")
                .accessibilityIdentifier("manager.open")
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, BookuhTheme.screenPadding)
                .padding(.vertical, 8)
            }
            .sheet(isPresented: $isPresented) {
                ManagerChatView(books: books, initialBook: initialBook)
            }
    }
}

struct ManagerChatView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var chat: ManagerChatStore
    @FocusState private var isComposing: Bool
    @State private var draft = ""
    @State private var selectedBook: ShelfItem?
    @State private var hasPulledTowardOlder = false
    @State private var previousAnchor: String?
    private let books: [ShelfItem]
    private let bottomID = "manager.chat.bottom"

    init(books: [ShelfItem], initialBook: ShelfItem?) {
        self.books = books
        _selectedBook = State(initialValue: initialBook)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                bookPicker
                Divider().overlay(BookuhTheme.line)
                historyView
                composer
            }
            .background(BookuhTheme.paper.ignoresSafeArea())
            .navigationTitle("북어")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(BookuhTheme.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .task {
            guard let token = session.accessToken else { return }
            await chat.loadLatest(accessToken: token)
        }
    }

    private var bookPicker: some View {
        HStack(spacing: 12) {
            BookuhMascot(size: 36)
            Menu {
                Button("책 선택 안 함") { selectedBook = nil }
                ForEach(books) { book in
                    Button(book.title) { selectedBook = book }
                }
            } label: {
                HStack(spacing: 7) {
                    Text(selectedBook?.title ?? "책 선택")
                        .font(BookuhTheme.emphasizedFont(size: 13))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(BookuhTheme.green)
            }
            .disabled(books.isEmpty)
            .accessibilityIdentifier("manager.book")
            Spacer()
        }
        .padding(.horizontal, BookuhTheme.screenPadding)
        .padding(.vertical, 10)
    }

    private var historyView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    olderControl
                    if chat.isLoadingLatest && !chat.hasLoaded && chat.messages.isEmpty {
                        ProgressView("대화를 불러오고 있어요")
                            .font(BookuhTheme.bodyFont(size: 13))
                            .padding(.vertical, 24)
                    } else if chat.hasLoaded && chat.messages.isEmpty
                                && chat.pendingRequest == nil && chat.recentExchange == nil {
                        bubble("안녕! 책이나 독서에 관해 뭐든 말해줘요.", isUser: false)
                    }
                    if let error = chat.historyError {
                        statusNotice(error, buttonTitle: "대화 다시 불러오기") {
                            guard let token = session.accessToken else { return }
                            Task { await chat.loadLatest(accessToken: token) }
                        }
                    }
                    ForEach(chat.messages) { item in
                        bubble(item.text, isUser: item.role == "USER")
                            .id(item.id)
                    }
                    if let exchange = chat.recentExchange {
                        bubble(exchange.message, isUser: true)
                        bubble(exchange.reply, isUser: false)
                    }
                    if let request = chat.pendingRequest {
                        bubble(request.message, isUser: true)
                        if chat.isSending {
                            ProgressView("북어가 답하고 있어요")
                                .font(BookuhTheme.bodyFont(size: 13))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if let error = chat.sendError {
                        statusNotice(error, buttonTitle: "다시 보내기") {
                            guard let token = session.accessToken else { return }
                            Task { await chat.sendPending(accessToken: token) }
                        }
                        Button("메시지 수정") {
                            if let message = chat.takeFailedMessage() {
                                draft = message
                                isComposing = true
                            }
                        }
                        .font(BookuhTheme.emphasizedFont(size: 13))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .disabled(!draft.isEmpty)
                    }
                    Color.clear.frame(height: 1).id(bottomID)
                }
                .padding(.horizontal, BookuhTheme.screenPadding)
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { value in
                if value.translation.height > 0 { hasPulledTowardOlder = true }
            })
            .onAppear { proxy.scrollTo(bottomID, anchor: .bottom) }
            .onChange(of: chat.bottomUpdate) { _, _ in
                previousAnchor = nil
                hasPulledTowardOlder = false
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
            .onChange(of: chat.messages.first?.id) { _, _ in
                guard let anchor = previousAnchor else { return }
                proxy.scrollTo(anchor, anchor: .top)
                previousAnchor = nil
            }
        }
    }

    @ViewBuilder
    private var olderControl: some View {
        if chat.isLoadingOlder {
            ProgressView("이전 대화를 불러오고 있어요")
                .font(BookuhTheme.bodyFont(size: 12))
        } else if let error = chat.olderError {
            statusNotice(error, buttonTitle: "이전 대화 다시 불러오기", action: loadOlder)
        } else if chat.nextCursor != nil {
            Button("이전 대화 불러오기", action: loadOlder)
                .font(BookuhTheme.emphasizedFont(size: 12))
                .disabled(chat.isSending || chat.isLoadingLatest)
                .accessibilityIdentifier("manager.older")
                .onAppear {
                    if hasPulledTowardOlder { loadOlder() }
                }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("북어에게 메시지", text: $draft, axis: .vertical)
                .font(BookuhTheme.bodyFont())
                .foregroundStyle(BookuhTheme.ink)
                .lineLimit(1...5)
                .focused($isComposing)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(BookuhTheme.card, in: RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius)
                        .strokeBorder(BookuhTheme.line, lineWidth: 1)
                }
                .accessibilityIdentifier("manager.compose")
            Button("보내기", action: send)
                .buttonStyle(BookuhPrimaryButtonStyle())
                .disabled(!chat.canSend || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("manager.send")
        }
        .padding(.horizontal, BookuhTheme.screenPadding)
        .padding(.vertical, 10)
        .background(BookuhTheme.paperDeep)
    }

    private func bubble(_ text: String, isUser: Bool) -> some View {
        Text(text)
            .font(BookuhTheme.bodyFont())
            .foregroundStyle(isUser ? BookuhTheme.card : BookuhTheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(isUser ? BookuhTheme.green : BookuhTheme.card,
                        in: RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius)
                    .strokeBorder(isUser ? Color.clear : BookuhTheme.line, lineWidth: 1)
            }
            .padding(isUser ? .leading : .trailing, 42)
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            .accessibilityLabel((isUser ? "나: " : "북어: ") + text)
    }

    private func statusNotice(_ text: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(BookuhTheme.bodyFont(size: 12))
                .foregroundStyle(BookuhTheme.inkSoft)
            Button(buttonTitle, action: action)
                .font(BookuhTheme.emphasizedFont(size: 13))
                .frame(minHeight: 44, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadOlder() {
        guard let token = session.accessToken, !chat.isSending, !chat.isLoadingLatest,
              !chat.isLoadingOlder, chat.nextCursor != nil else { return }
        previousAnchor = chat.messages.first?.id
        hasPulledTowardOlder = false
        Task { await chat.loadOlder(accessToken: token) }
    }

    private func send() {
        guard let token = session.accessToken, chat.canSend else { return }
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        let isbn = selectedBook?.isbn
        draft = ""
        isComposing = false
        Task { await chat.send(message: message, isbn: isbn, accessToken: token) }
    }
}
