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
        return BookSearchResponse(
            items: rankedBooks(result.items, matching: query), page: result.page, hasMore: result.hasMore
        )
    }

    func rankedBooks(_ books: [BookSearchItem], matching query: String) -> [BookSearchItem] {
        let keyword = normalized(query)
        let sorted = books.enumerated().map { index, book in
            (index: index, book: book, match: matchScore(for: book, keyword: keyword),
             information: informationScore(for: book))
        }.sorted { first, second in
            if first.match != second.match {
                return first.match > second.match
            }
            if first.match > 0, first.information != second.information {
                return first.information > second.information
            }
            return first.index < second.index
        }

        var seenISBNs = Set<String>()
        return sorted.compactMap { item in
            seenISBNs.insert(item.book.isbn).inserted ? item.book : nil
        }
    }

    private func matchScore(for book: BookSearchItem, keyword: String) -> Int {
        guard !keyword.isEmpty else { return 0 }

        let title = normalized(book.title)
        if title == keyword || book.isbn == keyword || "isbn\(book.isbn)" == keyword {
            return 4
        }
        if title.contains(keyword) { return 3 }

        let authors = book.authors.map(normalized)
        if authors.contains(keyword) { return 2 }
        return authors.contains { $0.contains(keyword) } ? 1 : 0
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                      locale: Locale(identifier: "ko_KR"))
            .precomposedStringWithCanonicalMapping
            .filter { $0.isLetter || $0.isNumber }
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
