import CryptoKit
import SwiftUI

private struct ConversationDraft: Codable {
    let id: String
    let message: String

    init(id: String = UUID().uuidString, message: String) {
        self.id = id
        self.message = message
    }
}

private enum ConversationDraftStorage {
    static func key(token: String, isbn: String, character: String, action: String) -> String {
        let scope = SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
        return "bookuh.conversation.\(scope).\(isbn).\(character).\(action)"
    }

    static func load(from key: String) -> ConversationDraft? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ConversationDraft.self, from: data)
    }

    static func save(_ draft: ConversationDraft?, to key: String) {
        if let draft, let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

struct CharacterLettersView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let book: ShelfItem
    let books: [ShelfItem]
    let character: BookCharacterItem?
    var initialLetterId: String? = nil

    @State private var letters: [LetterItem] = []
    @State private var opened: Set<String> = []
    @State private var draft = ""
    @State private var pending: ConversationDraft?
    @State private var busy = false
    @State private var didLoad = false
    @State private var refreshID = UUID()
    @State private var focusedLetterID: String?
    @State private var readingProgress: ReadingProgress?
    @State private var returnedToComposer = false
    @State private var error: String?
    @State private var loadError: String?
    @FocusState private var isWriting: Bool
    private let composerID = "letter.composer"

    private var awaitingReply: Bool { letters.contains { $0.status != "PUBLISHED" } }
    private var canWrite: Bool { character != nil && didLoad && !awaitingReply }
    private var message: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var replyCount: Int {
        didLoad ? letters.filter { $0.status == "PUBLISHED" }.count : (character?.replyCount ?? 0)
    }
    private var isViewingArrival: Bool {
        guard let initialLetterId, !returnedToComposer else { return false }
        return !didLoad || letters.contains(where: { $0.id == initialLetterId })
    }
    private var displayedLetters: [LetterItem] {
        isViewingArrival ? letters.filter { $0.id == initialLetterId } : letters
    }
    private var title: String {
        guard let character else { return "간직한 편지" }
        return isViewingArrival ? "\(character.name)의 답장" : "\(character.name)에게"
    }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let notice = error ?? loadError {
                        Text(notice).foregroundStyle(BookuhTheme.walnut)
                        Button("편지함 다시 불러오기") { Task { await load() } }
                    }
                    if !didLoad && loadError == nil {
                        ProgressView("편지를 불러오고 있어요")
                    }
                    if let character, canWrite && !isViewingArrival {
                        composer(for: character)
                            .id(composerID)
                    }
                    if let character, !isViewingArrival {
                        relationship(for: character)
                    }
                    if didLoad && letters.isEmpty && character == nil {
                        Text("간직한 편지가 없어요").foregroundStyle(BookuhTheme.inkSoft)
                    }
                    if character != nil && !letters.isEmpty && !isViewingArrival {
                        Text("편지함")
                            .font(BookuhTheme.titleFont(size: 18))
                            .foregroundStyle(BookuhTheme.ink)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(displayedLetters) { letter in
                        letterCard(letter) {
                            if isViewingArrival {
                                returnedToComposer = true
                            } else {
                                focusComposer(in: scroll)
                            }
                        }
                        .id(letter.id)
                    }
                    Text("AI가 인물을 해석한 대화예요")
                        .font(BookuhTheme.bodyFont(size: 12))
                        .foregroundStyle(BookuhTheme.inkSoft)
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(BookuhTheme.paperDeep,
                                    in: RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
                }
                .padding(BookuhTheme.screenPadding)
            }
            .onChange(of: focusedLetterID) { _, target in
                if let target, !isViewingArrival { scroll.scrollTo(target, anchor: .top) }
            }
            .onChange(of: returnedToComposer) { _, returned in
                if returned { focusComposer(in: scroll) }
            }
        }
        .background(BookuhTheme.paper.ignoresSafeArea())
        .bookuhNavigationTitle(title)
        .modifier(ManagerChatEntry(books: books, initialBook: book))
        .refreshable {
            await load()
            await loadProgress()
        }
        .task(id: session.accessToken) { await loadProgress() }
        .onReceive(NotificationCenter.default.publisher(for: .bookuhRecordsChanged)) { _ in
            Task { await loadProgress() }
        }
        .task(id: session.accessToken) {
            restoreDraft()
            await load()
            guard character != nil else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                if !busy && (letters.contains(where: { $0.status == "PROCESSING" })
                             || !didLoad || (pending != nil && error != nil)) {
                    await load()
                }
            }
        }
    }

    private func focusComposer(in scroll: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
            scroll.scrollTo(composerID, anchor: .top)
        }
        isWriting = true
    }

    @ViewBuilder
    private func relationship(for character: BookCharacterItem) -> some View {
        if replyCount >= character.requiredReplies {
            NavigationLink {
                CharacterChatView(book: book, books: books, character: character)
            } label: {
                Label("채팅하기", systemImage: "bubble.left.and.bubble.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BookuhOutlineButtonStyle())
        } else {
            Label("채팅 열기 · 답장 \(replyCount)/\(character.requiredReplies)", systemImage: "lock.fill")
                .font(BookuhTheme.emphasizedFont())
                .foregroundStyle(BookuhTheme.inkSoft)
        }
    }

    private func composer(for character: BookCharacterItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(character.name)에게")
                    .font(BookuhTheme.titleFont(size: 18))
                    .accessibilityAddTraits(.isHeader)
                TextField("여기에 마음을 적어보세요…", text: $draft, axis: .vertical)
                    .font(BookuhTheme.titleFont(size: 16))
                    .lineSpacing(7)
                    .lineLimit(7...11)
                    .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
                    .focused($isWriting)
                    .disabled(busy)
                    .accessibilityLabel("보낼 편지 내용")
                    .accessibilityIdentifier("letter.draft")
            }
            .foregroundStyle(BookuhTheme.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .modifier(LetterStationery())

            HStack(alignment: .top, spacing: 12) {
                if let readingProgress {
                    Text("진도 · \(readingProgress.description)")
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                ViewThatFits(in: .horizontal) {
                    Label("답장까지 약 2분", systemImage: "hourglass")
                        .fixedSize(horizontal: true, vertical: false)
                    Text("약 2분 후 답장")
                }
            }
            .font(BookuhTheme.bodyFont(size: 12))
            .foregroundStyle(BookuhTheme.inkSoft)

            Button {
                Task { await send() }
            } label: {
                Text(busy ? "보내는 중" : (pending?.message == message ? "전송 다시 시도" : "편지 보내기"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BookuhPrimaryButtonStyle())
            .disabled(busy || message.isEmpty)
        }
    }

    private func letterCard(_ letter: LetterItem, onNextLetter: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if letter.status == "PUBLISHED" {
                replyView(for: letter, onNextLetter: onNextLetter)
            }
            sentLetter(letter)
        }
    }

    private func sentLetter(_ letter: LetterItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(letter.characterName)에게 보낸 편지").font(BookuhTheme.emphasizedFont())
            if let accepted = Date.ISO8601FormatStyle(includingFractionalSeconds: true).parseIfValid(letter.acceptedAt) {
                Text(accepted, format: .dateTime.month().day())
                    .font(BookuhTheme.bodyFont(size: 12)).foregroundStyle(BookuhTheme.inkSoft)
            }
            if let scene = letter.progressScene, !scene.isEmpty {
                Text("읽은 지점 · \(scene)").font(BookuhTheme.bodyFont(size: 12)).foregroundStyle(BookuhTheme.inkSoft)
            } else if letter.progressStage == "START" || letter.progressStage == "FINISHED" {
                Text(letter.progressStage == "START" ? "읽은 지점 · 처음부터" : "읽은 지점 · 완독")
                    .font(BookuhTheme.bodyFont(size: 12)).foregroundStyle(BookuhTheme.inkSoft)
            }
            Text(letter.message).font(BookuhTheme.titleFont(size: 15)).lineSpacing(4)
            if letter.status == "FAILED" {
                Divider()
                Text("답장을 준비하지 못했어요").foregroundStyle(BookuhTheme.inkSoft)
                Button("답장 다시 시도") { Task { await retry(letter) } }
                    .buttonStyle(BookuhOutlineButtonStyle())
                    .disabled(busy)
            } else if letter.status == "PROCESSING" {
                Divider()
                Label("답장을 기다리고 있어요", systemImage: "envelope").foregroundStyle(BookuhTheme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(BookuhTheme.card, in: RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius).strokeBorder(BookuhTheme.line))
    }

    private func replyView(for letter: LetterItem, onNextLetter: @escaping () -> Void) -> some View {
        let isOpen = opened.contains(letter.id)
        let isUnread = letter.readAt == nil
        let showsEnvelope = isUnread || isOpen || letter.id == initialLetterId
        let showsArrival = isUnread && !isOpen

        return VStack(alignment: .leading, spacing: 14) {
            if showsEnvelope {
                VStack(spacing: 10) {
                    Button {
                        Task { await open(letter) }
                    } label: {
                        LetterEnvelope(isOpen: isOpen)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy && !isOpen)
                    .allowsHitTesting(!isOpen)
                    .accessibilityHidden(isOpen)
                    .accessibilityLabel("\(letter.characterName)의 답장 봉투 열기")
                    .accessibilityIdentifier("letter.envelope.\(letter.id)")

                    Text(showsArrival ? "답장이 도착했어요" : "\(letter.characterName)의 답장")
                        .font(BookuhTheme.titleFont(size: 20))
                        .foregroundStyle(showsArrival ? BookuhTheme.replyRed : BookuhTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                    if !isOpen {
                        Text("봉투를 눌러 열어보세요")
                            .font(BookuhTheme.bodyFont(size: 13))
                            .foregroundStyle(BookuhTheme.inkSoft)
                    }
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            } else {
                Button {
                    Task { await open(letter) }
                } label: {
                    Label("\(letter.characterName)의 답장 다시 읽기", systemImage: "envelope")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(BookuhOutlineButtonStyle())
                .disabled(busy)
            }

            if isOpen {
                if let reply = letter.reply {
                    Text(reply)
                        .font(BookuhTheme.titleFont(size: 16))
                        .foregroundStyle(BookuhTheme.ink)
                        .lineSpacing(8)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 22)
                        .modifier(LetterStationery())
                        .transition(.opacity)
                }
                replyActions(for: letter, onNextLetter: onNextLetter)
                if isUnread && error != nil {
                    Button("읽음 다시 표시") { Task { await mark(letter, key: "read") } }
                        .disabled(busy)
                }
            }
        }
    }

    private func replyActions(for letter: LetterItem, onNextLetter: @escaping () -> Void) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))

        return layout {
            if letter.kept {
                Label("간직했어요", systemImage: "bookmark.fill")
                    .font(BookuhTheme.emphasizedFont())
                    .foregroundStyle(BookuhTheme.green)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                Button {
                    Task { await mark(letter, key: "keepsake") }
                } label: {
                    Text("간직하기").frame(maxWidth: .infinity)
                }
                .buttonStyle(BookuhOutlineButtonStyle())
                .disabled(busy)
            }
            if canWrite {
                Button(action: onNextLetter) {
                    Text("다음 편지 쓰기").frame(maxWidth: .infinity)
                }
                .buttonStyle(BookuhPrimaryButtonStyle())
                .disabled(busy)
            }
        }
        .multilineTextAlignment(.center)
    }

    @MainActor
    private func loadProgress() async {
        guard let token = session.accessToken, character != nil else { return }
        if let progress = try? await BookuhAPI().progress(isbn: book.isbn, token: token), !Task.isCancelled {
            readingProgress = progress
        }
    }

    @MainActor
    private func restoreDraft() {
        guard let token = session.accessToken, let character else { return }
        let key = ConversationDraftStorage.key(token: token, isbn: book.isbn, character: character.id, action: "letter")
        pending = ConversationDraftStorage.load(from: key)
        if let pending { draft = pending.message }
    }

    @MainActor
    private func load() async {
        guard let token = session.accessToken else { return }
        let loadID = UUID()
        refreshID = loadID
        let query = [URLQueryItem(name: "isbn", value: book.isbn),
                     URLQueryItem(name: character == nil ? "kept" : "characterId",
                                  value: character?.id ?? "true")]
        do {
            let response: FeatureItems<LetterItem> = try await BookuhAPI().feature("letters", token: token, query: query)
            guard refreshID == loadID, !Task.isCancelled else { return }
            let previous = Dictionary(uniqueKeysWithValues: letters.map { ($0.id, $0.status) })
            letters = response.items
            didLoad = true
            loadError = nil
            if let pending, let character, letters.contains(where: { $0.message == pending.message }) {
                let key = ConversationDraftStorage.key(token: token, isbn: book.isbn, character: character.id, action: "letter")
                ConversationDraftStorage.save(nil, to: key)
                if message == pending.message { draft = "" }
                self.pending = nil
                error = nil
            }
            if let arrived = letters.first(where: { $0.status == "PUBLISHED" && previous[$0.id] == "PROCESSING" }) {
                focusedLetterID = arrived.id
                NotificationCenter.default.post(name: .bookuhLettersChanged, object: nil)
            }
        } catch {
            if refreshID == loadID && !Task.isCancelled { loadError = error.localizedDescription }
        }
    }

    @MainActor
    private func send() async {
        guard let token = session.accessToken, let character, !busy, !message.isEmpty else { return }
        busy = true
        error = nil
        defer { busy = false }
        let outgoing: ConversationDraft
        if let pending, pending.message == message {
            outgoing = pending
        } else {
            outgoing = ConversationDraft(message: message)
        }
        let key = ConversationDraftStorage.key(token: token, isbn: book.isbn, character: character.id, action: "letter")
        pending = outgoing
        ConversationDraftStorage.save(outgoing, to: key)
        do {
            let sent: LetterItem = try await BookuhAPI().feature(
                "letters", token: token, method: "POST",
                body: ["clientLetterId": outgoing.id, "isbn": book.isbn, "characterId": character.id, "message": outgoing.message]
            )
            if !letters.contains(where: { $0.id == sent.id }) { letters.insert(sent, at: 0) }
            draft = ""
            isWriting = false
            pending = nil
            ConversationDraftStorage.save(nil, to: key)
            NotificationCenter.default.post(name: .bookuhLettersChanged, object: nil)
            await load()
        } catch {
            self.error = error.localizedDescription
            await load()
        }
    }

    @MainActor
    private func retry(_ letter: LetterItem) async {
        guard let token = session.accessToken, !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        let key = ConversationDraftStorage.key(token: token, isbn: book.isbn, character: letter.characterId,
                                              action: "letter-retry.\(letter.id)")
        let retryId = UserDefaults.standard.string(forKey: key) ?? UUID().uuidString
        UserDefaults.standard.set(retryId, forKey: key)
        do {
            let response: LetterItem = try await BookuhAPI().feature(
                "letters/\(letter.id)/retry", token: token, method: "POST", body: ["retryId": retryId]
            )
            UserDefaults.standard.removeObject(forKey: key)
            if let index = letters.firstIndex(where: { $0.id == letter.id }) {
                letters[index] = response
            }
            NotificationCenter.default.post(name: .bookuhLettersChanged, object: nil)
            await load()
        } catch {
            self.error = error.localizedDescription
            await load()
        }
    }

    @MainActor
    private func open(_ letter: LetterItem) async {
        guard letter.status == "PUBLISHED", !busy, !opened.contains(letter.id) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.42)) { _ = opened.insert(letter.id) }
        if letter.readAt == nil { await mark(letter, key: "read") }
    }

    @MainActor
    private func mark(_ letter: LetterItem, key: String) async {
        guard let token = session.accessToken, !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let _: EmptyFeatureResponse = try await BookuhAPI().feature(
                "letters/\(letter.id)/\(key)", token: token, method: "PUT"
            )
            await load()
            NotificationCenter.default.post(name: .bookuhLettersChanged, object: nil)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct LetterStationery: ViewModifier {
    @ScaledMetric private var ruleInterval: CGFloat

    init(ruleInterval: CGFloat = 30) {
        _ruleInterval = ScaledMetric(wrappedValue: ruleInterval, relativeTo: .body)
    }

    func body(content: Content) -> some View {
        let edge = RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius)

        content
            .background {
                ZStack {
                    edge.fill(BookuhTheme.card)
                    Canvas { context, size in
                        var rules = Path()
                        for y in stride(from: ruleInterval, to: size.height, by: ruleInterval) {
                            rules.move(to: CGPoint(x: 0, y: y))
                            rules.addLine(to: CGPoint(x: size.width, y: y))
                        }
                        context.stroke(rules, with: .color(BookuhTheme.line.opacity(0.7)), lineWidth: 0.5)
                    }
                    .clipShape(edge)
                    .accessibilityHidden(true)
                }
                .background {
                    edge.fill(BookuhTheme.line)
                        .offset(y: 3)
                }
            }
            .overlay {
                edge.strokeBorder(BookuhTheme.line)
                    .allowsHitTesting(false)
            }
    }
}

private struct LetterEnvelope: View {
    let isOpen: Bool

    var body: some View {
        let edge = RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius)

        ZStack {
            edge.fill(BookuhTheme.paperDeep)

            Canvas { context, size in
                var folds = Path()
                folds.move(to: CGPoint(x: 0, y: size.height))
                folds.addLine(to: CGPoint(x: size.width / 2, y: size.height * 0.54))
                folds.addLine(to: CGPoint(x: size.width, y: size.height))
                context.stroke(folds, with: .color(BookuhTheme.line), lineWidth: 0.8)
            }
            .clipShape(edge)

            edge.strokeBorder(BookuhTheme.line, lineWidth: 1.2)

            LetterEnvelopeFlap()
                .fill(BookuhTheme.line)
                .rotation3DEffect(.degrees(isOpen ? 124 : 0), axis: (x: 1, y: 0, z: 0),
                                  anchor: .top, perspective: 0.45)

            if !isOpen {
                BookuhMascot(size: 34, animates: false)
                    .offset(y: 6)
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
            }
        }
        .aspectRatio(1.62, contentMode: .fit)
        .frame(maxWidth: 250)
        .padding(.top, isOpen ? 56 : 0)
        .accessibilityHidden(true)
    }
}

private struct LetterEnvelopeFlap: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.height * 0.54))
            path.closeSubpath()
        }
    }
}

struct CharacterChatView: View {
    @EnvironmentObject private var session: AppSession
    let book: ShelfItem
    let books: [ShelfItem]
    let character: BookCharacterItem
    @State private var turns: [CharacterTurn] = []
    @State private var draft = ""
    @State private var pending: ConversationDraft?
    @State private var busy = false
    @State private var loadError: String?
    @State private var sendError: String?
    @FocusState private var isWriting: Bool

    private var message: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("AI가 인물을 해석한 대화예요").foregroundStyle(BookuhTheme.inkSoft)
                    if let loadError {
                        Text(loadError).foregroundStyle(BookuhTheme.walnut)
                        Button("대화 다시 불러오기") { Task { await load() } }
                    }
                    ForEach(turns) { turn in
                        bubble(turn.message, own: true)
                        if let reply = turn.reply { bubble(reply, own: false) }
                        if turn.status == "FAILED" && pending == nil {
                            Button("답장 다시 요청") {
                                pending = ConversationDraft(id: turn.id, message: turn.message)
                                Task { await send() }
                            }
                            .disabled(busy)
                        }
                    }
                    if let pending, !turns.contains(where: { $0.id == pending.id }) {
                        bubble(pending.message, own: true)
                    }
                    if busy {
                        ProgressView("답장을 기다리고 있어요")
                    } else if pending != nil {
                        Text(sendError ?? "답장을 받지 못한 메시지가 있어요.")
                            .foregroundStyle(BookuhTheme.walnut)
                        HStack(spacing: 16) {
                            Button("다시 보내기") { Task { await send() } }
                                .accessibilityIdentifier("character.chat.retry")
                            Button("메시지 수정", action: editPendingMessage)
                                .accessibilityIdentifier("character.chat.editPending")
                        }
                    }
                    Color.clear.frame(height: 1).id("character.end")
                }
                .padding(BookuhTheme.screenPadding)
            }
            .onChange(of: turns.last?.reply) { _, _ in scroll.scrollTo("character.end", anchor: .bottom) }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(alignment: .bottom) {
                TextField("메시지", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(10).background(BookuhTheme.card)
                    .disabled(pending != nil)
                    .focused($isWriting)
                    .accessibilityIdentifier("character.chat.message")
                Button("보내기") {
                    pending = ConversationDraft(message: message)
                    draft = ""
                    Task { await send() }
                }
                .buttonStyle(BookuhPrimaryButtonStyle())
                .disabled(busy || pending != nil || message.isEmpty)
            }
            .padding(.horizontal, BookuhTheme.screenPadding)
            .padding(.vertical, 8)
            .background(BookuhTheme.paperDeep)
        }
        .background(BookuhTheme.paper.ignoresSafeArea())
        .bookuhNavigationTitle(character.name)
        .modifier(ManagerChatEntry(books: books, initialBook: book))
        .task(id: session.accessToken) {
            if let token = session.accessToken {
                pending = ConversationDraftStorage.load(from: draftKey(token))
            }
            await load()
        }
        .refreshable { await load() }
    }

    private func draftKey(_ token: String) -> String {
        ConversationDraftStorage.key(token: token, isbn: book.isbn, character: character.id, action: "chat")
    }

    private func editPendingMessage() {
        guard let token = session.accessToken, let pending, !busy else { return }
        draft = pending.message
        self.pending = nil
        sendError = nil
        ConversationDraftStorage.save(nil, to: draftKey(token))
        isWriting = true
    }

    private func bubble(_ text: String, own: Bool) -> some View {
        Text(text)
            .foregroundStyle(own ? BookuhTheme.card : BookuhTheme.ink)
            .padding(12)
            .background(own ? BookuhTheme.green : BookuhTheme.card,
                        in: RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
            .frame(maxWidth: .infinity, alignment: own ? .trailing : .leading)
    }

    @MainActor
    private func load() async {
        guard let token = session.accessToken else { return }
        do {
            let response: FeatureItems<CharacterTurn> = try await BookuhAPI().feature(
                "roleplay/turns", token: token,
                query: [.init(name: "isbn", value: book.isbn), .init(name: "characterId", value: character.id)]
            )
            guard !Task.isCancelled else { return }
            loadError = nil
            turns = response.items
            if let pending, turns.contains(where: { $0.id == pending.id && $0.status == "SUCCEEDED" }) {
                self.pending = nil
                ConversationDraftStorage.save(nil, to: draftKey(token))
                sendError = nil
            }
        } catch {
            if !Task.isCancelled { loadError = error.localizedDescription }
        }
    }

    @MainActor
    private func send() async {
        guard let token = session.accessToken, let pending, !busy else { return }
        busy = true
        sendError = nil
        ConversationDraftStorage.save(pending, to: draftKey(token))
        defer { busy = false }
        do {
            let answer: CharacterAnswer = try await BookuhAPI().feature(
                "roleplay/replies", token: token, method: "POST",
                body: ["turnId": pending.id, "isbn": book.isbn,
                       "character": ["source": "SHARED_AI_PROFILE", "characterId": character.id],
                       "message": pending.message], timeout: 90
            )
            let item = CharacterTurn(turnId: answer.turnId, status: "SUCCEEDED", message: pending.message, reply: answer.reply)
            if let index = turns.firstIndex(where: { $0.id == answer.turnId }) {
                turns[index] = item
            } else {
                turns.append(item)
            }
            self.pending = nil
            ConversationDraftStorage.save(nil, to: draftKey(token))
            await load()
        } catch {
            sendError = error.localizedDescription
            await load()
        }
    }
}

private extension Date.ISO8601FormatStyle {
    func parseIfValid(_ value: String) -> Date? {
        (try? parse(value)) ?? (try? Date.ISO8601FormatStyle().parse(value))
    }
}
