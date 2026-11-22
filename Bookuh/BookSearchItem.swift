struct BookSearchItem: Decodable {
    let isbn: String
    let googleVolumeId: String
    let title: String
    let authors: [String]
    let publisher: String?
    let publishedYear: Int?
    let coverUrl: String?
    var shelfState: String

    var isOnShelf: Bool { shelfState == "ON_SHELF" }
}

struct BookSearchResponse: Decodable {
    let items: [BookSearchItem]
    let page: Int
    let hasMore: Bool
}
