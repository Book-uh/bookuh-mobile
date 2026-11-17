import Foundation

struct BookSearchAPI {
    func search(query: String) async throws -> [BookSearchItem] {
        guard var components = URLComponents(
            string: "http://localhost:8081/api/v1/books/search"
        ) else {
            throw URLError(.badURL)
        }

        components.queryItems = [
            URLQueryItem(name: "query", value: query)
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let books = try JSONDecoder().decode([BookSearchItem].self, from: data)

        let rankedBooks = books.enumerated().sorted { first, second in
            let firstScore = informationScore(for: first.element)
            let secondScore = informationScore(for: second.element)

            if firstScore == secondScore {
                return first.offset < second.offset
            }
            return firstScore > secondScore
        }.map { $0.element }

        var seenISBNs = Set<String>()
        return rankedBooks.filter { book in
            seenISBNs.insert(book.isbn13).inserted
        }
    }

    private func informationScore(for book: BookSearchItem) -> Int {
        let fields = [book.thumbnailUrl, book.author, book.publisher, book.publishedDate]
        return fields.filter { field in
            !field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }
}
