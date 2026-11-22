import Foundation

enum APIConfiguration {
    static let baseURL = URL(string: "http://localhost:8081")!
}

struct AnonymousUserResponse: Decodable {
    let userId: String
    let accessToken: String
    let tokenType: String
}

struct ShelfItem: Decodable, Identifiable, Hashable {
    let isbn: String
    let title: String
    let authors: [String]
    let publisher: String?
    let coverUrl: String?
    let readingStatus: String
    let shelvedAt: String

    var id: String { isbn }
}

struct BookuhAPI {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func issueAnonymousUser(issuanceKey: String) async throws -> AnonymousUserResponse {
        var request = makeRequest(path: "api/v1/auth/anonymous")
        request.httpMethod = "POST"
        request.setValue(issuanceKey, forHTTPHeaderField: "Idempotency-Key")
        let response: AnonymousUserResponse = try await send(request)
        guard !response.userId.isEmpty, !response.accessToken.isEmpty,
              response.tokenType.caseInsensitiveCompare("Bearer") == .orderedSame else {
            throw APIError.invalidResponse
        }
        return response
    }

    func fetchBookshelf(accessToken: String) async throws -> [ShelfItem] {
        let request = try authenticatedRequest(path: "api/v1/bookshelf", accessToken: accessToken)
        let response: BookshelfResponse = try await send(request)
        return response.items
    }

    func addToBookshelf(book: BookSearchItem, accessToken: String) async throws -> ShelfItem {
        guard book.isbn.count == 13,
              book.isbn.utf8.allSatisfy({ (48...57).contains($0) }),
              !book.googleVolumeId.isEmpty else {
            throw APIError.invalidBook
        }
        var request = try authenticatedRequest(
            path: "api/v1/bookshelf/\(book.isbn)", accessToken: accessToken
        )
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AddShelfRequest(googleVolumeId: book.googleVolumeId))
        return try await send(request)
    }

    func talkToManager(_ input: ManagerTalkRequest, accessToken: String) async throws -> ManagerTalkResponse {
        var request = try managerRequest(path: "api/v1/manager/interpret", accessToken: accessToken)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(input)

        let response: ManagerTalkResponse = try await sendManager(request)
        guard response.operationId == input.operationId else {
            throw ManagerAPIError.invalidResponse
        }
        return response
    }

    func fetchManagerMessages(
        before: String? = nil,
        accessToken: String
    ) async throws -> ManagerMessagesResponse {
        var request = try managerRequest(path: "api/v1/manager/messages", accessToken: accessToken)
        if let before {
            guard let url = request.url,
                  var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw ManagerAPIError.invalidResponse
            }
            components.queryItems = [URLQueryItem(name: "before", value: before)]
            guard let url = components.url else { throw ManagerAPIError.invalidResponse }
            request.url = url
        }
        return try await sendManager(request)
    }

    private func managerRequest(path: String, accessToken: String) throws -> URLRequest {
        guard !accessToken.isEmpty else { throw ManagerAPIError.authRequired }
        return try authenticatedRequest(path: path, accessToken: accessToken)
    }

    private func sendManager<Value: Decodable>(_ request: URLRequest) async throws -> Value {
        do {
            return try await send(request)
        } catch APIError.http(401), APIError.http(403) {
            throw ManagerAPIError.authRequired
        } catch APIError.http(409) {
            throw ManagerAPIError.requestConflict
        } catch APIError.http(502), APIError.http(503), APIError.http(504) {
            throw ManagerAPIError.unavailable
        } catch APIError.invalidResponse {
            throw ManagerAPIError.invalidResponse
        }
    }

    private func makeRequest(path: String) -> URLRequest {
        var request = URLRequest(
            url: APIConfiguration.baseURL.appendingPathComponent(path),
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 20
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func authenticatedRequest(path: String, accessToken: String) throws -> URLRequest {
        guard !accessToken.isEmpty else { throw APIError.http(401) }
        var request = makeRequest(path: path)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send<Value: Decodable>(_ request: URLRequest) async throws -> Value {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw APIError.timedOut
            case .cancelled: throw APIError.cancelled
            default: throw APIError.connection
            }
        } catch {
            throw APIError.connection
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.http(httpResponse.statusCode)
        }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }
}

private struct AddShelfRequest: Encodable {
    let googleVolumeId: String
}

private struct BookshelfResponse: Decodable {
    let items: [ShelfItem]
}

enum APIError: LocalizedError {
    case connection
    case timedOut
    case cancelled
    case invalidResponse
    case invalidBook
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .connection:
            return "서버에 연결하지 못했어요. 연결을 확인한 뒤 다시 시도해 주세요."
        case .timedOut:
            return "응답이 오래 걸리고 있어요. 잠시 후 다시 시도해 주세요."
        case .cancelled:
            return "요청이 취소됐어요. 다시 시도해 주세요."
        case .invalidResponse:
            return "서버 응답을 읽지 못했어요. 잠시 후 다시 시도해 주세요."
        case .invalidBook:
            return "이 책의 정보를 확인하지 못했어요. 다른 판본을 선택해 주세요."
        case .http(let status):
            switch status {
            case 400:
                return "요청 정보를 확인하지 못했어요. 내용을 확인한 뒤 다시 시도해 주세요."
            case 401, 403:
                return "저장된 책장에 접속하지 못했어요. 잠시 후 다시 시도해 주세요."
            case 404:
                return "요청한 정보를 찾지 못했어요. 다시 불러온 뒤 시도해 주세요."
            case 409:
                return "현재 상태와 맞지 않는 요청이에요. 책장을 다시 불러온 뒤 시도해 주세요."
            case 429:
                return "요청이 많아 잠시 기다려야 해요. 조금 뒤 다시 시도해 주세요."
            default:
                return "서버에서 요청을 처리하지 못했어요. 잠시 후 다시 시도해 주세요."
            }
        }
    }
}

struct ManagerTalkRequest: Codable {
    let operationId: String
    let isbn: String?
    let clientTime: String
    let timeZone: String
    let message: String

    init(message: String, isbn: String?, now: Date = Date(), timeZone: TimeZone = .current) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        self.operationId = UUID().uuidString
        self.isbn = isbn
        self.clientTime = formatter.string(from: now)
        self.timeZone = timeZone.identifier
        self.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ManagerTalkResponse: Decodable {
    let operationId: String
    let clarifyingQuestion: String?
    let assistantMessage: String?
    let actions: [ManagerActionItem]?
}

struct ManagerMessagesResponse: Decodable {
    let items: [ManagerMessageItem]
    let nextCursor: String?
}

struct ManagerMessageItem: Decodable, Identifiable {
    let messageId: String
    let role: String
    let isbn: String?
    let text: String
    let createdAt: String

    var id: String { messageId }
}

enum ManagerAPIError: LocalizedError {
    case authRequired
    case requestConflict
    case unavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .authRequired:
            return "북어 대화에 접속하지 못했어요. 접속 정보를 확인해 주세요."
        case .requestConflict:
            return "요청이 처리 중이거나 내용이 달라졌어요. 잠시 후 같은 메시지로 다시 시도해 주세요."
        case .unavailable:
            return "북어가 지금 답하기 어려워요. 잠시 후 다시 시도해 주세요."
        case .invalidResponse:
            return "북어의 응답을 읽지 못했어요. 다시 시도해 주세요."
        }
    }
}

extension BookuhAPI {
    func feature<Value: Decodable>(
        _ path: String, token: String, method: String = "GET",
        query: [URLQueryItem] = [], body: [String: Any]? = nil, timeout: TimeInterval = 20
    ) async throws -> Value {
        var request = try authenticatedRequest(path: "api/v1/\(path)", accessToken: token)
        if !query.isEmpty {
            guard let url = request.url,
                  var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw APIError.invalidResponse
            }
            components.queryItems = query
            request.url = components.url
        }
        request.httpMethod = method
        request.timeoutInterval = timeout
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let failure = try? JSONDecoder().decode(FeatureFailure.self, from: data)
            throw FeatureError(status: http.statusCode, code: failure?.code)
        }
        let payload = http.statusCode == 204 ? Data("{}".utf8) : data
        guard let value = try? JSONDecoder().decode(Value.self, from: payload) else {
            throw APIError.invalidResponse
        }
        return value
    }

    func progress(isbn: String, token: String) async throws -> ReadingProgress {
        try await feature("bookshelf/\(isbn)/progress", token: token)
    }

    func saveProgress(isbn: String, version: Int, stage: String, scene: String?,
                      actionId: String, token: String) async throws -> ReadingProgress {
        var body: [String: Any] = [
            "actionId": actionId, "baseProgressVersion": version,
            "stage": stage, "timeZone": TimeZone.current.identifier
        ]
        if let scene { body["scene"] = scene }
        return try await feature("bookshelf/\(isbn)/progress", token: token, method: "PUT", body: body)
    }
}

struct FeatureItems<Item: Decodable>: Decodable { let items: [Item] }
struct EmptyFeatureResponse: Decodable {}
private struct FeatureFailure: Decodable { let code: String? }

struct FeatureError: LocalizedError {
    let status: Int
    let code: String?

    var errorDescription: String? {
        switch code {
        case "PROGRESS_REQUIRED": return "인물을 만나기 전에 읽은 지점을 기록해 주세요."
        case "PROGRESS_CHANGED": return "다른 곳에서 진도가 바뀌었어요. 최신 진도를 다시 확인해 주세요."
        case "CHAT_LOCKED": return "편지 답장을 더 받으면 채팅이 열려요."
        case "LETTER_PENDING": return "먼저 보낸 편지의 답장을 기다리고 있어요."
        case "LETTER_DUPLICATE": return "편지 내용이 바뀌었어요. 새 편지로 작성해 주세요."
        case "LETTER_NOT_PUBLISHED": return "아직 답장이 도착하지 않았어요."
        case "ACTION_CONFLICT": return "저장 요청의 내용이 달라졌어요. 다시 확인해 주세요."
        default: return APIError.http(status).localizedDescription
        }
    }
}

struct ReadingProgress: Decodable {
    struct Position: Decodable {
        let progressVersion: Int
        let stage: String
        let scene: String?
    }
    let progress: Position?
    let readingStatus: String
    let finishedOn: String?

    var description: String {
        switch progress?.stage {
        case "START": return "처음부터"
        case "SCENE": return progress?.scene ?? "읽는 중"
        case "FINISHED": return "완독"
        default: return "아직 기록한 진도가 없어요"
        }
    }
}

struct BookCharacterItem: Decodable, Identifiable, Hashable {
    let characterId: String
    let name: String
    let intro: String
    let requiredReplies: Int
    let replyCount: Int
    let chatUnlocked: Bool
    let activeLetterId: String?
    let latestUnreadLetterId: String?
    var id: String { characterId }
}

struct CharacterSelection: Decodable {
    let status: String
    let characters: [BookCharacterItem]
}

struct LetterItem: Decodable, Identifiable {
    let letterId: String
    let isbn: String
    let characterId: String
    let characterName: String
    let progressStage: String?
    let progressScene: String?
    let status: String
    let acceptedAt: String
    let publishedAt: String?
    let readAt: String?
    let kept: Bool
    let message: String
    let reply: String?
    var id: String { letterId }
}

struct CharacterTurn: Decodable, Identifiable {
    let turnId: String
    let status: String
    let message: String
    let reply: String?
    var id: String { turnId }
}

struct CharacterAnswer: Decodable {
    let turnId: String
    let reply: String
}

struct ReadingRecordItem: Decodable, Identifiable {
    let recordId: String
    let isbn: String
    let title: String
    let readingDate: String
    let timeBand: String?
    let durationMinutes: Int?
    let pagesRead: Int?
    var id: String { recordId }
}

struct ReadingRecordResult: Decodable {
    let status: String
    let pendingId: String?
}

struct ReadingStatistics: Decodable {
    struct Bucket: Decodable, Identifiable {
        let startDate: String
        let endDateExclusive: String
        let durationMinutes: Int?
        var id: String { startDate }
    }
    let period: String
    let startDate: String
    let endDateExclusive: String
    let durationMinutes: Int?
    let pagesRead: Int?
    let readingDayCount: Int
    let finishedBookCount: Int
    let dayMinutes: Int
    let nightMinutes: Int
    let buckets: [Bucket]
}
