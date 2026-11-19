struct BookSearchItem: Decodable {
    let isbn13: String
    let title: String
    let author: String
    let authors: [String]
    let publisher: String
    let publishedDate: String
    let thumbnailUrl: String
}
