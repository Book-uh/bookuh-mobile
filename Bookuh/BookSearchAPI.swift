import Foundation

struct BookSearchAPI {
    private static let pageSize = 10

    func search(query: String, page: Int, accessToken: String) async throws -> BookSearchResponse {
        guard var components = URLComponents(
            url: APIConfiguration.baseURL.appendingPathComponent("api/v1/books/search"),
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }

        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "size", value: String(Self.pageSize))
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let result = try JSONDecoder().decode(BookSearchResponse.self, from: data)

        let rankedBooks = result.items.enumerated().sorted { first, second in
            let firstScore = informationScore(for: first.element)
            let secondScore = informationScore(for: second.element)

            if firstScore == secondScore {
                return first.offset < second.offset
            }
            return firstScore > secondScore
        }.map { $0.element }

        var seenISBNs = Set<String>()
        let books = rankedBooks.filter { book in
            seenISBNs.insert(book.isbn).inserted
        }
        return BookSearchResponse(items: books, page: result.page, hasMore: result.hasMore)
    }

    private func informationScore(for book: BookSearchItem) -> Int {
        let filledFields = [
            book.coverUrl != nil,
            !book.authors.isEmpty,
            book.publisher != nil,
            book.publishedYear != nil
        ]
        return filledFields.filter { $0 }.count
    }
}
