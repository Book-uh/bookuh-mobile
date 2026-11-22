import CryptoKit
import SwiftUI

struct ManagerActionItem: Decodable, Identifiable {
    let actionId: String
    let type: String
    let isbn: String?
    let values: [String: ManagerActionValue]?

    var id: String { actionId }
}

enum ManagerActionValue: Decodable {
    case text(String)
    case number(Int)
    case object([String: ManagerActionValue])
    case null
    case unsupported

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            self = .null
        } else if let text = try? value.decode(String.self) {
            self = .text(text)
        } else if let number = try? value.decode(Int.self) {
            self = .number(number)
        } else if let object = try? value.decode([String: ManagerActionValue].self) {
            self = .object(object)
        } else {
            self = .unsupported
        }
    }

    var text: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    var object: [String: ManagerActionValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var json: Any? {
        switch self {
        case .number(let value): return value
        case .text(let value): return value
        case .null: return NSNull()
        default: return nil
        }
    }

    var query: String? {
        switch self {
        case .text(let value): return value
        case .number(let value): return String(value)
        default: return nil
        }
    }
}

struct ManagerBookLink: Identifiable {
    let id: String
    let title: String
    let reason: String?
    let query: String
}

@MainActor
final class ManagerActions: ObservableObject {
    struct Work {
        let action: ManagerActionItem
        let selectedISBN: String?
        let timeZone: String

        var isbn: String? { action.isbn ?? selectedISBN }
    }

    struct Edit {
        let changes: [String: ManagerActionValue]?

        var removesRecord: Bool { changes == nil }
        var action: String { removesRecord ? "삭제" : "수정" }

        func summary(for record: ReadingRecordItem) -> String? {
            guard let changes else { return nil }
            let fields = [("readingDate", "독서 날짜", Optional(record.readingDate)),
                          ("timeBand", "시간대", record.timeBand),
                          ("durationMinutes", "독서 시간(분)", record.durationMinutes.map(String.init)),
                          ("pagesRead", "읽은 페이지", record.pagesRead.map(String.init))]
            return fields.compactMap { key, label, previous in
                changes[key].map { value in
                    "\(label) \(displayValue(previous)) → \(displayValue(value.query))"
                }
            }.joined(separator: "\n")
        }

        private func displayValue(_ value: String?) -> String {
            switch value {
            case "DAY": return "낮"
            case "NIGHT": return "밤"
            default: return value ?? "기록 없음"
            }
        }
    }

    struct RecordChoice: Identifiable {
        let record: ReadingRecordItem
        let label: String

        var id: String { record.id }
    }

    enum Retry {
        case work(Work, offerRecordTime: Bool)
        case decision(String, Bool)
        case edit(ReadingRecordItem, Edit)
    }

    enum State {
        case loading
        case notice(String, recordTimeISBN: String? = nil)
        case failed(String, Retry?)
        case duplicate(String, String)
        case candidates([RecordChoice], Edit)
        case confirmation(RecordChoice, Edit)
        case shelfRemovalConfirmation(ShelfItem)
        case search(ManagerBookLink)

        var pendingQuestion: String? {
            switch self {
            case .duplicate(_, let message):
                return message
            case .candidates(let choices, let edit):
                return (["어느 독서 기록을 \(edit.action)할까요?"] + choices.map(\.label)).joined(separator: "\n")
            case .confirmation(let choice, let edit):
                return [choice.label, edit.summary(for: choice.record), "이 독서 기록을 \(edit.action)할까요?"]
                    .compactMap { $0 }.joined(separator: "\n")
            case .shelfRemovalConfirmation(let book):
                return "《\(book.title)》을 책장에서 뺄까요?"
            default:
                return nil
            }
        }
    }

    struct Card: Identifiable {
        let id: String
        let state: State
    }

    @Published private(set) var cards: [Card] = []
    @Published private(set) var restoredQuestions: [String] = []

    private let api: BookuhAPI
    private let defaults: UserDefaults
    private var confirmationStorageKey: String?
    private var progressVersions: [String: Int] = [:]
    private static let recordFields = ["readingDate", "timeBand", "durationMinutes", "pagesRead"]

    init(api: BookuhAPI, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
    }

    func restoreQuestions(for token: String) {
        let scope = SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
        let key = "bookuh.manager.pendingQuestions.\(scope)"
        guard confirmationStorageKey != key else { return }
        confirmationStorageKey = key
        cards = []
        restoredQuestions = defaults.stringArray(forKey: key) ?? []
    }

    func consume(_ actions: [ManagerActionItem], isbn: String?, timeZone: String, token: String) async {
        // 메시지 전송이 다음 작업을 만들면 앱 세션의 이전 확인 버튼을 닫는다
        restoreQuestions(for: token)
        cards = []
        restoredQuestions = []
        savePendingQuestions()
        progressVersions = [:]
        let offersRecordTime = !actions.contains { $0.type == "ADD_READING_RECORD" }
        for action in actions {
            let work = Work(action: action, selectedISBN: isbn, timeZone: timeZone)
            await run(work, offerRecordTime: offersRecordTime, token: token)
        }
    }

    func choose(_ choice: RecordChoice, edit: Edit, cardID: String) {
        set(.confirmation(choice, edit), for: cardID)
    }

    func dismiss(cardID: String) {
        set(.notice("변경을 취소했어요."), for: cardID)
    }

    func retry(_ operation: Retry, cardID: String, token: String) async {
        switch operation {
        case .work(let work, let offerRecordTime):
            await run(work, offerRecordTime: offerRecordTime, token: token)
        case .decision(let pendingID, let add):
            await decide(pendingID, add: add, cardID: cardID, token: token)
        case .edit(let record, let edit):
            await complete(record, edit: edit, cardID: cardID, token: token)
        }
    }

    func decide(_ pendingID: String, add: Bool, cardID: String, token: String) async {
        set(.loading, for: cardID)
        do {
            let result: ReadingRecordResult = try await api.feature(
                "reading-records/pending/\(pendingID)/decision", token: token, method: "POST",
                body: ["decision": add ? "ADD" : "CANCEL"])
            if result.status == "CREATED" {
                announceChange("독서 기록을 한 건 더 저장했어요.", cardID: cardID)
            } else if result.status == "CANCELLED" {
                set(.notice("독서 기록 추가를 취소했어요."), for: cardID)
            } else {
                throw APIError.invalidResponse
            }
        } catch {
            fail(error, retry: .decision(pendingID, add), cardID: cardID)
        }
    }

    func complete(_ record: ReadingRecordItem, edit: Edit, cardID: String, token: String) async {
        set(.loading, for: cardID)
        do {
            let path = "reading-records/\(record.id)"
            if let changes = edit.changes {
                let body = changes.compactMapValues(\.json)
                let updated: ReadingRecordItem = try await api.feature(
                    path, token: token, method: "PATCH", body: body)
                announceChange("독서 기록을 수정했어요. \(recordSummary(updated))", cardID: cardID)
            } else {
                let _: EmptyFeatureResponse = try await api.feature(path, token: token, method: "DELETE")
                announceChange("선택한 독서 기록을 삭제했어요.", cardID: cardID)
            }
        } catch {
            fail(error, retry: .edit(record, edit), cardID: cardID)
        }
    }

    func removeFromShelf(_ book: ShelfItem, cardID: String, token: String) async {
        guard let card = cards.first(where: { $0.id == cardID }),
              case .shelfRemovalConfirmation(let pendingBook) = card.state,
              pendingBook.isbn == book.isbn else { return }

        set(.loading, for: cardID)
        do {
            try await api.removeFromBookshelf(isbn: book.isbn, accessToken: token)
            set(.notice("《\(book.title)》을 책장에서 뺐어요. 다시 담으면 기록을 이어볼 수 있어요."),
                for: cardID)
            NotificationCenter.default.post(name: .bookuhShelfBookRemoved, object: book.isbn)
        } catch {
            set(.failed(error.localizedDescription, nil), for: cardID)
        }
    }

    private func run(_ work: Work, offerRecordTime: Bool, token: String) async {
        let action = work.action
        let values = action.values ?? [:]
        set(.loading, for: action.id)
        do {
            switch action.type {
            case "SET_PROGRESS":
                try await saveProgress(work, values: values, offerRecordTime: offerRecordTime, token: token)
            case "SET_READING_STATUS":
                try await saveStatus(work, values: values, token: token)
            case "ADD_READING_RECORD":
                try await addRecord(work, values: values, token: token)
            case "UPDATE_READING_RECORD", "DELETE_READING_RECORD":
                try await prepareEdit(work, values: values, token: token)
            case "REMOVE_SHELF_BOOK":
                try await prepareShelfRemoval(action, token: token)
            case "QUERY_STATS":
                try await loadStats(work, values: values, token: token)
            case "SEARCH_BOOK", "RECOMMEND_BOOK":
                let link = try makeBookLink(action, values: values)
                set(.search(link), for: action.id)
            default:
                throw ManagerActionError.incomplete
            }
        } catch {
            fail(error, retry: .work(work, offerRecordTime: offerRecordTime), cardID: action.id)
        }
    }

    private func prepareShelfRemoval(_ action: ManagerActionItem, token: String) async throws {
        guard let isbn = action.isbn, isISBN(isbn) else { throw ManagerActionError.bookRequired }
        let books = try await api.fetchBookshelf(accessToken: token)
        guard let book = books.first(where: { $0.isbn == isbn }) else {
            set(.notice("이미 책장에 없는 책이에요."), for: action.id)
            return
        }
        set(.shelfRemovalConfirmation(book), for: action.id)
    }

    private func saveProgress(_ work: Work, values: [String: ManagerActionValue],
                              offerRecordTime: Bool, token: String) async throws {
        let isbn = try requireISBN(work)
        guard let stage = values["stage"]?.text, ["START", "SCENE", "FINISHED"].contains(stage) else {
            throw ManagerActionError.incomplete
        }
        let version: Int
        if let attemptedVersion = progressVersions[work.action.id] {
            version = attemptedVersion
        } else {
            let existing = try await api.progress(isbn: isbn, token: token)
            version = existing.progress?.progressVersion ?? 0
            progressVersions[work.action.id] = version
        }
        var body: [String: Any] = ["stage": stage, "baseProgressVersion": version, "timeZone": work.timeZone,
                                   "actionId": work.action.id]
        if stage == "SCENE" {
            guard let scene = values["scene"]?.text, !scene.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ManagerActionError.incomplete
            }
            body["scene"] = scene
        }
        let progress: ReadingProgress = try await api.feature(
            "bookshelf/\(isbn)/progress", token: token, method: "PUT", body: body)
        announceChange("읽은 지점을 저장했어요. \(progress.description)",
                       cardID: work.action.id, recordTimeISBN: offerRecordTime ? isbn : nil)
    }

    private func saveStatus(_ work: Work, values: [String: ManagerActionValue], token: String) async throws {
        let isbn = try requireISBN(work)
        guard let status = values["status"]?.text, ["NOT_STARTED", "READING", "FINISHED"].contains(status) else {
            throw ManagerActionError.incomplete
        }
        let body = ["actionId": work.action.id, "status": status, "timeZone": work.timeZone]
        let result: ReadingProgress = try await api.feature(
            "bookshelf/\(isbn)/reading-status", token: token, method: "PUT", body: body)
        let label = ["NOT_STARTED": "읽기 전", "READING": "읽는 중", "FINISHED": "완독"][result.readingStatus]
        announceChange("독서 상태를 ‘\(label ?? result.readingStatus)’(으)로 바꿨어요.", cardID: work.action.id)
    }

    private func addRecord(_ work: Work, values: [String: ManagerActionValue], token: String) async throws {
        let isbn = try requireISBN(work)
        guard let date = values["readingDate"]?.text else { throw ManagerActionError.incomplete }
        var body = attributes(in: values, allowed: Self.recordFields + ["additionIntent"]).compactMapValues(\.json)
        body["actionId"] = work.action.id
        body["isbn"] = isbn
        let result: ReadingRecordResult = try await api.feature(
            "reading-records", token: token, method: "POST", body: body)
        switch result.status {
        case "CREATED":
            announceChange("독서 기록을 저장했어요.", cardID: work.action.id)
        case "NEEDS_CONFIRMATION":
            guard let pendingID = result.pendingId else { throw APIError.invalidResponse }
            let amounts = [values["durationMinutes"]?.query.map { "\($0)분" },
                           values["pagesRead"]?.query.map { "\($0)쪽" }].compactMap { $0 }.joined(separator: " · ")
            set(.duplicate(pendingID, "\(date) · \(amounts) 기록이 이미 있어요. 한 건 더 추가할까요?"),
                for: work.action.id)
        case "CANCELLED":
            set(.notice("독서 기록 추가를 취소했어요."), for: work.action.id)
        default:
            throw APIError.invalidResponse
        }
    }

    private func prepareEdit(_ work: Work, values: [String: ManagerActionValue], token: String) async throws {
        let match = values["match"]?.object ?? [:]
        var query = attributes(in: match, allowed: Self.recordFields)
            .compactMap { key, value in value.query.map { URLQueryItem(name: key, value: $0) } }
        if let isbn = work.isbn ?? match["isbn"]?.text {
            guard isISBN(isbn) else { throw ManagerActionError.incomplete }
            query.append(URLQueryItem(name: "isbn", value: isbn))
        }
        let matches: FeatureItems<ReadingRecordItem> = try await api.feature("reading-records", token: token, query: query)
        let choices = recordChoices(matches.items)
        guard let first = choices.first else {
            set(.notice("조건에 맞는 독서 기록이 없어요."), for: work.action.id)
            return
        }
        let edit: Edit
        if work.action.type == "DELETE_READING_RECORD" {
            edit = Edit(changes: nil)
        } else {
            let changes = attributes(in: values["changes"]?.object ?? [:], allowed: Self.recordFields)
            guard !changes.isEmpty else { throw ManagerActionError.incomplete }
            edit = Edit(changes: changes)
        }
        let state: State = choices.count == 1 ? .confirmation(first, edit) : .candidates(choices, edit)
        set(state, for: work.action.id)
    }

    private func recordChoices(_ records: [ReadingRecordItem]) -> [RecordChoice] {
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions.insert(.withFractionalSeconds)
        let iso8601WholeSeconds = ISO8601DateFormatter()
        return records.enumerated().map { index, record in
            let timeBand = ["DAY": "낮", "NIGHT": "밤"][record.timeBand ?? ""]
            let registeredTime = record.createdAt.flatMap {
                iso8601.date(from: $0) ?? iso8601WholeSeconds.date(from: $0)
            }.map {
                "등록 \($0.formatted(.dateTime.month().day().hour().minute().second().locale(Locale(identifier: "ko_KR"))))"
            }
            let bookLabel = records.count > 1 ? "\(index + 1)번 \(record.title)" : record.title
            let label = [bookLabel, recordSummary(record), timeBand, registeredTime]
                .compactMap { $0 }.joined(separator: " · ")
            return RecordChoice(record: record, label: label)
        }
    }

    private func loadStats(_ work: Work, values: [String: ManagerActionValue], token: String) async throws {
        guard let period = values["period"]?.text, ["WEEK", "MONTH"].contains(period) else {
            throw ManagerActionError.incomplete
        }
        let stats: ReadingStatistics = try await api.feature("reading-stats", token: token, query: [
            URLQueryItem(name: "period", value: period), URLQueryItem(name: "timeZone", value: work.timeZone)
        ])
        let periodTitle = period == "WEEK" ? "이번 주" : "이번 달"
        let duration = stats.durationMinutes.map(formatReadingMinutes) ?? "기록 없음"
        let pages = stats.pagesRead.map { "\($0)쪽" } ?? "기록 없음"
        set(.notice("\(periodTitle) 독서 시간 \(duration), 페이지 \(pages), 기록한 날 \(stats.readingDayCount)일, 완독 \(stats.finishedBookCount)권이에요."),
            for: work.action.id)
    }

    private func makeBookLink(_ action: ManagerActionItem, values: [String: ManagerActionValue]) throws -> ManagerBookLink {
        if action.type == "SEARCH_BOOK", let query = values["query"]?.text, !query.isEmpty {
            return ManagerBookLink(id: action.id, title: "\(query) 찾아보기", reason: nil, query: query)
        }
        if action.type == "RECOMMEND_BOOK", let title = values["title"]?.text, !title.isEmpty {
            let info = [values["author"]?.text, values["reason"]?.text].compactMap { $0 }.joined(separator: "\n")
            return ManagerBookLink(id: action.id, title: title, reason: info.isEmpty ? nil : info, query: title)
        }
        throw ManagerActionError.incomplete
    }

    private func attributes(in source: [String: ManagerActionValue], allowed: [String]) -> [String: ManagerActionValue] {
        source.filter { allowed.contains($0.key) && $0.value.json != nil }
    }

    private func requireISBN(_ work: Work) throws -> String {
        guard let isbn = work.isbn, isISBN(isbn) else { throw ManagerActionError.bookRequired }
        return isbn
    }

    private func isISBN(_ isbn: String) -> Bool {
        isbn.utf8.count == 13 && isbn.utf8.allSatisfy { (48...57).contains($0) }
    }

    private func set(_ state: State, for id: String) {
        let card = Card(id: id, state: state)
        if let index = cards.firstIndex(where: { $0.id == id }) {
            cards[index] = card
        } else {
            cards.append(card)
        }
        savePendingQuestions()
    }

    private func savePendingQuestions() {
        guard let key = confirmationStorageKey else { return }
        // 재실행한 화면에 보여줄 문구만 저장한다
        let questions = cards.compactMap { $0.state.pendingQuestion }
        if questions.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(questions, forKey: key)
        }
    }

    private func announceChange(_ message: String, cardID: String, recordTimeISBN: String? = nil) {
        set(.notice(message, recordTimeISBN: recordTimeISBN), for: cardID)
        NotificationCenter.default.post(name: .bookuhRecordsChanged, object: nil)
    }

    private func fail(_ error: Error, retry: Retry, cardID: String) {
        let canRetry = error is URLError || (error as? FeatureError).map { $0.status >= 500 } == true
        set(.failed(error.localizedDescription, canRetry ? retry : nil), for: cardID)
    }
}

private enum ManagerActionError: LocalizedError {
    case bookRequired
    case incomplete

    var errorDescription: String? {
        switch self {
        case .bookRequired: return "책을 고른 뒤 다시 말해 주세요."
        case .incomplete: return "처리할 정보를 확인하지 못했어요. 필요한 내용을 다시 말해 주세요."
        }
    }
}

struct ManagerActionCards: View {
    @ObservedObject var actions: ManagerActions
    let token: String?
    let onSearch: (ManagerBookLink) -> Void
    let onRecordTime: (String) -> Void

    var body: some View {
        ForEach(Array(actions.restoredQuestions.enumerated()), id: \.offset) { _, question in
            card {
                Text(question)
                Text("이 작업을 하려면 북어에게 다시 요청해 주세요.")
                    .foregroundStyle(BookuhTheme.inkSoft)
            }
        }
        ForEach(actions.cards) { card in
            self.card {
                content(card)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .font(BookuhTheme.bodyFont(size: 13))
            .foregroundStyle(BookuhTheme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(BookuhTheme.card, in: RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius).strokeBorder(BookuhTheme.line)
            }
    }

    @ViewBuilder
    private func content(_ card: ManagerActions.Card) -> some View {
        switch card.state {
        case .loading:
            ProgressView("요청을 확인하고 있어요")
        case .notice(let message, let isbn):
            Text(message)
            if let isbn {
                button("독서 시간도 기록하기") { onRecordTime(isbn) }
            }
        case .failed(let message, let retry):
            Text(message)
            if let retry, let token {
                button("다시 시도") { Task { await actions.retry(retry, cardID: card.id, token: token) } }
            }
        case .duplicate(let pendingID, let message):
            Text(message)
            if let token {
                HStack {
                    button("추가") { Task { await actions.decide(pendingID, add: true, cardID: card.id, token: token) } }
                    button("취소") { Task { await actions.decide(pendingID, add: false, cardID: card.id, token: token) } }
                }
            }
        case .candidates(let choices, let edit):
            Text("어느 독서 기록을 \(edit.action)할까요?")
            ForEach(choices) { choice in
                button(choice.label) { actions.choose(choice, edit: edit, cardID: card.id) }
            }
            button("취소") { actions.dismiss(cardID: card.id) }
        case .confirmation(let choice, let edit):
            Text(choice.label)
            if let summary = edit.summary(for: choice.record) {
                Text(summary)
            } else {
                Text("이 독서 기록을 삭제할까요?")
            }
            if let token {
                HStack {
                    button(edit.removesRecord ? "삭제" : "수정 확인") {
                        Task { await actions.complete(choice.record, edit: edit, cardID: card.id, token: token) }
                    }
                    button("취소") { actions.dismiss(cardID: card.id) }
                }
            }
        case .shelfRemovalConfirmation(let book):
            Text("《\(book.title)》을 책장에서 뺄까요?")
                .font(BookuhTheme.emphasizedFont(size: 13))
            if let publisher = book.publisher, !publisher.isEmpty {
                Text(publisher).foregroundStyle(BookuhTheme.inkSoft)
            }
            Text("읽은 지점, 독서 기록, 편지와 채팅은 보관돼요.")
            if let token {
                HStack(spacing: 8) {
                    Button("책장에서 빼기") {
                        Task { await actions.removeFromShelf(book, cardID: card.id, token: token) }
                    }
                    .buttonStyle(BookuhPrimaryButtonStyle())
                    .accessibilityIdentifier("manager.shelf.remove.confirm")
                    Button("취소") { actions.dismiss(cardID: card.id) }
                        .buttonStyle(BookuhOutlineButtonStyle())
                        .accessibilityIdentifier("manager.shelf.remove.cancel")
                }
            }
        case .search(let link):
            Text(link.title).font(BookuhTheme.emphasizedFont(size: 13))
            if let reason = link.reason { Text(reason) }
            button("이 책 찾아보기") { onSearch(link) }
        }
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(BookuhTheme.emphasizedFont(size: 13))
            .foregroundStyle(BookuhTheme.green)
            .multilineTextAlignment(.leading)
            .frame(minHeight: 44, alignment: .leading)
    }

}
