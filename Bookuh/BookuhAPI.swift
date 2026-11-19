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
    let isbn13: String
    let title: String
    let authors: [String]
    let publisher: String?
    let coverUrl: String?
    let readingStatus: String
    let shelvedAt: String

    var id: String { isbn13 }
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
        return try await send(request)
    }

    func addToBookshelf(book: BookSearchItem, accessToken: String) async throws -> ShelfItem {
        guard book.isbn13.count == 13,
              book.isbn13.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw APIError.invalidBook
        }
        var request = try authenticatedRequest(
            path: "api/v1/bookshelf/\(book.isbn13)", accessToken: accessToken
        )
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AddShelfRequest(
            title: book.title,
            authors: book.authors,
            publisher: nonempty(book.publisher),
            publishedYear: publicationYear(book.publishedDate),
            coverUrl: nonempty(book.thumbnailUrl)
        ))
        return try await send(request)
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

    private func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func publicationYear(_ value: String) -> Int? {
        let prefix = value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4)
        guard prefix.count == 4,
              prefix.utf8.allSatisfy({ (48...57).contains($0) }),
              let year = Int(prefix), (1...9999).contains(year) else {
            return nil
        }
        return year
    }
}

private struct AddShelfRequest: Encodable {
    let title: String
    let authors: [String]
    let publisher: String?
    let publishedYear: Int?
    let coverUrl: String?
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
