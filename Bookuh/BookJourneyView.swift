import SwiftUI

struct BookJourneyView: View {
    @EnvironmentObject private var session: AppSession
    let book: ShelfItem
    let books: [ShelfItem]
    let updateStatus: (String) -> Void

    @State private var reading: ReadingProgress?
    @State private var error: String?
    @State private var characterStatus: String?
    @State private var isEditing = false
    @State private var openCharacters = false
    @State private var showsProgressRequirement = false
    @State private var continueAfterSave = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            progressCard

            VStack(alignment: .leading, spacing: 10) {
                if characterStatus == "NO_CANDIDATES" {
                    Text("이 책의 인물을 찾기 어려워요.")
                        .font(BookuhTheme.bodyFont(size: 13))
                        .foregroundStyle(BookuhTheme.inkSoft)
                } else if characterStatus == "PREPARING" {
                    Text("책 속 인물을 준비하고 있어요.")
                        .font(BookuhTheme.bodyFont(size: 13))
                        .foregroundStyle(BookuhTheme.inkSoft)
                }

                Button {
                    if reading?.progress == nil {
                        showsProgressRequirement = true
                    } else {
                        openCharacters = true
                    }
                } label: {
                    Label("인물 만나기", systemImage: "person.2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BookuhPrimaryButtonStyle())
                .disabled(reading == nil || characterStatus == "NO_CANDIDATES")
                .accessibilityIdentifier("book.characters.open")
            }
        }
        .task { await load() }
        .task { await prepareCharacters() }
        .onReceive(NotificationCenter.default.publisher(for: .bookuhRecordsChanged)) { _ in
            Task { await load() }
        }
        .navigationDestination(isPresented: $openCharacters) {
            BookCharactersView(book: book, books: books)
        }
        .alert("인물을 만나기 전, 읽은 지점을 알려주세요", isPresented: $showsProgressRequirement) {
            Button("지점 기록하고 계속") {
                continueAfterSave = true
                isEditing = true
            }
            Button("나중에", role: .cancel) {}
        } message: {
            Text("책 속 인물이 지금 읽은 장면에 맞춰 답할 수 있도록 첫 진도를 기록해 주세요.")
        }
        .sheet(isPresented: $isEditing, onDismiss: {
            if continueAfterSave && reading?.progress != nil { openCharacters = true }
            continueAfterSave = false
        }) {
            if let reading {
                ProgressEditor(
                    book: book, books: books, current: reading, continuesToCharacters: continueAfterSave
                ) { updated in
                    self.reading = updated
                    updateStatus(updated.readingStatus)
                } onCancel: {
                    continueAfterSave = false
                }
            }
        }
    }

    private var progressCard: some View {
        let scene = reading?.progress?.stage == "SCENE" ? reading?.progress?.scene : nil

        return VStack(alignment: .leading, spacing: 8) {
            Text(scene == nil ? "읽은 지점" : "여기까지 읽었어요")
                .font(scene == nil ? BookuhTheme.titleFont(size: 17) : BookuhTheme.bodyFont(size: 14))
                .foregroundStyle(scene == nil ? BookuhTheme.ink : BookuhTheme.inkSoft)
                .accessibilityAddTraits(.isHeader)

            if let reading {
                if let scene {
                    Text("“\(scene)”")
                        .font(BookuhTheme.titleFont(size: 17))
                        .foregroundStyle(BookuhTheme.ink)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(reading.description)
                        .font(BookuhTheme.bodyFont(size: 14))
                        .foregroundStyle(reading.progress == nil ? BookuhTheme.inkSoft : BookuhTheme.ink)
                }

                Button {
                    isEditing = true
                } label: {
                    progressAction(reading.progress == nil ? "읽은 지점 기록" : "진도 바꾸기")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("book.progress.edit")
            } else if let error {
                Text(error)
                    .font(BookuhTheme.bodyFont(size: 14))
                    .foregroundStyle(BookuhTheme.inkSoft)
                Button {
                    Task { await load() }
                } label: {
                    progressAction("다시 불러오기")
                }
                .buttonStyle(.plain)
            } else {
                ProgressView("읽은 지점을 불러오고 있어요")
                    .font(BookuhTheme.bodyFont(size: 14))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BookuhTheme.card, in: RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius).strokeBorder(BookuhTheme.line))
    }

    private func progressAction(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(BookuhTheme.emphasizedFont())
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(BookuhTheme.green)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    @MainActor
    private func prepareCharacters() async {
        guard let token = session.accessToken else { return }
        characterStatus = "PREPARING"
        do {
            repeat {
                let result: CharacterSelection = try await BookuhAPI().feature(
                    "books/\(book.isbn)/characters/resolve", token: token, method: "POST",
                    body: ["mode": "PREPARE"], timeout: 90
                )
                characterStatus = result.status
                if result.status == "PREPARING" { try await Task.sleep(for: .seconds(2)) }
            } while characterStatus == "PREPARING" && !Task.isCancelled
        } catch {
            if !Task.isCancelled { characterStatus = "FAILED" }
        }
    }

    @MainActor
    private func load() async {
        guard let token = session.accessToken else { return }
        do {
            let current = try await BookuhAPI().progress(isbn: book.isbn, token: token)
            reading = current
            updateStatus(current.readingStatus)
            error = nil
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}

private struct ProgressEditor: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    let book: ShelfItem
    let books: [ShelfItem]
    let current: ReadingProgress
    let continuesToCharacters: Bool
    let onSave: (ReadingProgress) -> Void
    let onCancel: () -> Void

    @State private var stage: Stage?
    @State private var scene: String
    @State private var version: Int
    @State private var actionId = UUID().uuidString
    @State private var sending = false
    @State private var isManagerPresented = false
    @State private var checkingManagerProgress = false
    @State private var error: String?

    private enum Stage: String, CaseIterable, Identifiable {
        case start = "START"
        case scene = "SCENE"
        case finished = "FINISHED"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .start: return "처음부터"
            case .scene: return "읽은 장면 기록"
            case .finished: return "다 읽었어"
            }
        }
    }

    init(book: ShelfItem, books: [ShelfItem], current: ReadingProgress, continuesToCharacters: Bool,
         onSave: @escaping (ReadingProgress) -> Void, onCancel: @escaping () -> Void) {
        self.book = book
        self.books = books
        self.current = current
        self.continuesToCharacters = continuesToCharacters
        self.onSave = onSave
        self.onCancel = onCancel
        _stage = State(initialValue: current.progress.flatMap { Stage(rawValue: $0.stage) })
        _scene = State(initialValue: current.progress?.scene ?? "")
        _version = State(initialValue: current.progress?.progressVersion ?? 0)
    }

    private var trimmed: String { scene.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isBusy: Bool { sending || checkingManagerProgress }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.title)
                            .font(BookuhTheme.bodyFont(size: 14))
                            .foregroundStyle(BookuhTheme.inkSoft)
                        Text("어디까지 읽었어요?")
                            .font(BookuhTheme.titleFont(size: 24))
                            .accessibilityAddTraits(.isHeader)
                    }

                    managerEntry

                    VStack(alignment: .leading, spacing: 10) {
                        Text("직접 기록")
                            .font(BookuhTheme.emphasizedFont())
                            .accessibilityAddTraits(.isHeader)
                        ForEach(Stage.allCases) { option in
                            stageOption(option)
                            if option == .scene && stage == .scene {
                                sceneInput
                            }
                        }
                    }
                    .disabled(isBusy)
                    if let error {
                        Text(error)
                            .font(BookuhTheme.bodyFont(size: 13))
                            .foregroundStyle(BookuhTheme.walnut)
                    }
                }
                .foregroundStyle(BookuhTheme.ink)
                .padding(BookuhTheme.screenPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await save() }
                } label: {
                    Text(sending ? "저장 중" : continuesToCharacters ? "저장하고 인물 만나기" : "읽은 지점 저장")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BookuhPrimaryButtonStyle())
                .disabled(isBusy || stage == nil || (stage == .scene && trimmed.isEmpty))
                .accessibilityIdentifier("progress.save")
                .padding(.horizontal, BookuhTheme.screenPadding)
                .padding(.vertical, 10)
                .background(BookuhTheme.paper)
            }
            .background(BookuhTheme.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { onCancel(); dismiss() }.disabled(isBusy)
                }
            }
        }
        .interactiveDismissDisabled()
        .sheet(isPresented: $isManagerPresented, onDismiss: {
            Task { await refreshAfterManager() }
        }) {
            ManagerChatView(books: books.isEmpty ? [book] : books, initialBook: book)
        }
        .onChange(of: stage) { _, _ in actionId = UUID().uuidString }
        .onChange(of: scene) { _, _ in actionId = UUID().uuidString }
    }

    private var managerEntry: some View {
        Button {
            isManagerPresented = true
        } label: {
            HStack(spacing: 12) {
                BookuhMascot(size: 38, animates: false)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("북어에게 말하기")
                        .font(BookuhTheme.emphasizedFont(size: 15))
                        .foregroundStyle(BookuhTheme.green)
                    Text("“쪽지를 찾은 장면까지 읽었어”처럼 말하면 북어가 기록해요.")
                        .font(BookuhTheme.bodyFont(size: 13))
                        .foregroundStyle(BookuhTheme.inkSoft)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BookuhTheme.green)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(BookuhTheme.greenTint,
                        in: RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityIdentifier("progress.manager")
    }

    private func stageOption(_ option: Stage) -> some View {
        let selected = stage == option
        return Button {
            stage = option
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? BookuhTheme.green : BookuhTheme.inkSoft)
                    .accessibilityHidden(true)
                Text(option.title)
                    .font(BookuhTheme.emphasizedFont())
                    .foregroundStyle(BookuhTheme.ink)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(selected ? BookuhTheme.greenTint : BookuhTheme.card,
                        in: RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius)
                .strokeBorder(selected ? BookuhTheme.green : BookuhTheme.line))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("progress.stage.\(option.rawValue)")
    }

    private var sceneInput: some View {
        TextField("예: 쪽지를 찾은 장면", text: $scene, axis: .vertical)
            .font(BookuhTheme.bodyFont())
            .lineLimit(3...6)
            .padding(12)
            .background(BookuhTheme.card, in: RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius).strokeBorder(BookuhTheme.line))
            .accessibilityLabel("마지막으로 읽은 장면")
            .accessibilityIdentifier("progress.scene")
    }

    @MainActor
    private func refreshAfterManager() async {
        guard let token = session.accessToken else { return }
        checkingManagerProgress = true
        defer { checkingManagerProgress = false }
        do {
            let updated = try await BookuhAPI().progress(isbn: book.isbn, token: token)
            if let position = updated.progress, position.progressVersion != version {
                onSave(updated)
                dismiss()
            }
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    @MainActor
    private func save() async {
        guard !isBusy, let stage, let token = session.accessToken,
              stage != .scene || !trimmed.isEmpty else { return }
        sending = true
        error = nil
        defer { sending = false }
        do {
            let updated = try await BookuhAPI().saveProgress(
                isbn: book.isbn, version: version, stage: stage.rawValue,
                scene: stage == .scene ? trimmed : nil, actionId: actionId, token: token
            )
            onSave(updated)
            NotificationCenter.default.post(name: .bookuhRecordsChanged, object: nil)
            dismiss()
        } catch let failure as FeatureError where failure.code == "PROGRESS_CHANGED" {
            if let updated = try? await BookuhAPI().progress(isbn: book.isbn, token: token) {
                version = updated.progress?.progressVersion ?? 0
                actionId = UUID().uuidString
                error = "현재 진도는 ‘\(updated.description)’예요. 수정하려면 저장을 다시 눌러 주세요."
            } else {
                error = failure.localizedDescription
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct BookCharactersView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let book: ShelfItem
    let books: [ShelfItem]
    @State private var characters: [BookCharacterItem] = []
    @State private var status = "PREPARING"
    @State private var loading = false
    @State private var needsRefresh = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("AI가 인물을 해석한 대화예요")
                    .font(BookuhTheme.bodyFont(size: 13)).foregroundStyle(BookuhTheme.inkSoft)
                if let error {
                    Text(error)
                    Button("다시 시도") { Task { await load() } }
                } else if status == "PREPARING" {
                    ProgressView("책 속 인물을 준비하고 있어요")
                } else if characters.isEmpty {
                    Text("인물을 찾기 어려워요")
                }

                ForEach(characters) { character in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(character.name).font(BookuhTheme.titleFont(size: 20))
                        Text(character.intro).font(BookuhTheme.bodyFont())
                        if let unread = character.latestUnreadLetterId {
                            NavigationLink {
                                CharacterLettersView(book: book, books: books, character: character, initialLetterId: unread)
                            } label: {
                                Label("답장 도착", systemImage: "envelope.fill")
                                    .font(BookuhTheme.emphasizedFont())
                                    .foregroundStyle(BookuhTheme.replyRed)
                            }
                        }
                        characterActions(for: character)
                        if !character.chatUnlocked {
                            Text("채팅 열기 · 답장 \(character.replyCount)/\(character.requiredReplies)")
                                .font(BookuhTheme.bodyFont(size: 12))
                                .foregroundStyle(BookuhTheme.inkSoft)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(BookuhTheme.card, in: RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
                }
            }
            .padding(BookuhTheme.screenPadding)
        }
        .background(BookuhTheme.paper.ignoresSafeArea())
        .bookuhNavigationTitle("인물 만나기")
        .modifier(ManagerChatEntry(books: books, initialBook: book))
        .task { await load() }
        .refreshable { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .bookuhLettersChanged)) { _ in
            Task { await load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookuhRecordsChanged)) { _ in
            Task { await load() }
        }
    }

    private func characterActions(for character: BookCharacterItem) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))
        let letterTitle = character.activeLetterId == nil ? "편지 쓰기" : "편지함"

        return layout {
            NavigationLink {
                CharacterLettersView(book: book, books: books, character: character)
            } label: {
                Text(letterTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BookuhPrimaryButtonStyle())

            NavigationLink {
                CharacterChatView(book: book, books: books, character: character)
            } label: {
                HStack(spacing: 6) {
                    if !character.chatUnlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .accessibilityHidden(true)
                    }
                    Text("채팅하기")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(BookuhOutlineButtonStyle())
            .disabled(!character.chatUnlocked)
        }
        .multilineTextAlignment(.center)
    }

    @MainActor
    private func load() async {
        guard let token = session.accessToken else { return }
        if loading {
            needsRefresh = true
            return
        }
        loading = true
        defer { loading = false }
        repeat {
            needsRefresh = false
            error = nil
            do {
                repeat {
                    let response: CharacterSelection = try await BookuhAPI().feature(
                        "books/\(book.isbn)/characters/resolve", token: token, method: "POST",
                        body: ["mode": "SELECT"], timeout: 90
                    )
                    guard !Task.isCancelled else { return }
                    status = response.status
                    characters = response.characters
                    if status == "PREPARING" { try await Task.sleep(for: .seconds(2)) }
                } while status == "PREPARING"
                if status == "FAILED" { error = "인물을 준비하지 못했어요." }
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        } while needsRefresh && !Task.isCancelled
    }
}

extension Notification.Name {
    static let bookuhRecordsChanged = Notification.Name("bookuh.recordsChanged")
    static let bookuhLettersChanged = Notification.Name("bookuh.lettersChanged")
}
