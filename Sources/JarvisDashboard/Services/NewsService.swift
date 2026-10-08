import Foundation

struct NewsArticle: Identifiable, Sendable {
    let id: String
    let title: String
    let link: URL
    let publishedAt: Date?
    let sourceName: String
}

struct NewsSource: Identifiable, Hashable, Sendable {
    enum Category: String, CaseIterable, Identifiable, Hashable {
        case philippines = "Philippines"
        case world = "World"

        var id: Self { self }
    }

    let id: String
    let name: String
    let feedURL: URL
    let category: Category

    static let defaults: [NewsSource] = [
        NewsSource(
            id: "gma-breaking",
            name: "GMA News",
            feedURL: URL(string: "https://www.gmanetwork.com/news/breaking/rss/")!,
            category: .philippines
        ),
        NewsSource(
            id: "bbc-world",
            name: "BBC News",
            feedURL: URL(string: "https://feeds.bbci.co.uk/news/world/rss.xml")!,
            category: .world
        )
    ]
}

protocol NewsProviding: Sendable {
    func articles(from source: NewsSource) async throws -> [NewsArticle]
}

struct NewsAPIService: Sendable {
    func articles(category: NewsSource.Category, apiKey: String) async throws -> [NewsArticle] {
        var components = URLComponents(string: "https://newsapi.org/v2/top-headlines")!
        var queryItems = [URLQueryItem(name: "pageSize", value: "20")]
        if category == .philippines {
            queryItems.append(URLQueryItem(name: "country", value: "ph"))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue("JARVIS-Dashboard/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try parse(data: data)
    }

    func parse(data: Data) throws -> [NewsArticle] {
        let response = try JSONDecoder.newsAPI.decode(NewsAPIResponse.self, from: data)
        guard response.status == "ok" else { throw URLError(.cannotParseResponse) }

        return response.articles.compactMap { article in
            guard let url = URL(string: article.url), !article.title.isEmpty else { return nil }
            return NewsArticle(
                id: url.absoluteString,
                title: article.title,
                link: url,
                publishedAt: article.publishedAt,
                sourceName: article.source.name
            )
        }
    }
}

private struct NewsAPIResponse: Decodable {
    struct Article: Decodable {
        struct Source: Decodable { let name: String }
        let source: Source
        let title: String
        let url: String
        let publishedAt: Date?
    }

    let status: String
    let articles: [Article]
}

private extension JSONDecoder {
    static let newsAPI: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

struct RSSNewsService: NewsProviding {
    func articles(from source: NewsSource) async throws -> [NewsArticle] {
        var request = URLRequest(url: source.feedURL)
        request.setValue("JARVIS-Dashboard/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try parse(data: data, sourceName: source.name)
    }

    func parse(data: Data, sourceName: String) throws -> [NewsArticle] {
        let rawText = String(decoding: data, as: UTF8.self)
        if rawText.range(of: "<html", options: .caseInsensitive) != nil {
            return parseHTML(rawText, sourceName: sourceName)
        }

        let delegate = RSSParserDelegate(sourceName: sourceName)
        let parser = XMLParser(data: sanitisedXMLData(data))
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? URLError(.cannotParseResponse)
        }
        return delegate.articles
    }

    private func parseHTML(_ html: String, sourceName: String) -> [NewsArticle] {
        let pattern = #"<a\b[^>]*\bhref=[\"']([^\"']+)[\"'][^>]*>(.*?)</a>"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }

        let range = NSRange(html.startIndex..., in: html)
        return expression.matches(in: html, range: range).compactMap { match in
            guard let linkRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else { return nil }

            let rawLink = String(html[linkRange])
            let cleanTitle = decodeHTMLEntities(
                String(html[titleRange]).replacingOccurrences(
                    of: #"<[^>]+>"#,
                    with: "",
                    options: .regularExpression
                )
            )
            guard !cleanTitle.isEmpty, let link = URL(string: rawLink) else { return nil }

            return NewsArticle(
                id: link.absoluteString,
                title: cleanTitle,
                link: link,
                publishedAt: nil,
                sourceName: sourceName
            )
        }
    }

    private func decodeHTMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitisedXMLData(_ data: Data) -> Data {
        let xml = String(decoding: data, as: UTF8.self)
        let repaired = xml.replacingOccurrences(
            of: #"&(?!(?:amp|lt|gt|quot|apos|#\d+|#x[0-9A-Fa-f]+);)"#,
            with: "&amp;",
            options: .regularExpression
        )
        return Data(repaired.utf8)
    }
}

private final class RSSParserDelegate: NSObject, XMLParserDelegate {
    private let sourceName: String
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentGUID = ""
    private var currentDate = ""
    private var isInsideItem = false

    private(set) var articles: [NewsArticle] = []

    init(sourceName: String) {
        self.sourceName = sourceName
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        if elementName == "item" {
            isInsideItem = true
            currentTitle = ""
            currentLink = ""
            currentGUID = ""
            currentDate = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideItem else { return }
        switch currentElement {
        case "title": currentTitle += string
        case "link": currentLink += string
        case "guid": currentGUID += string
        case "pubDate": currentDate += string
        default: break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        defer { currentElement = "" }
        guard elementName == "item" else { return }
        isInsideItem = false

        let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let linkText = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let link = URL(string: linkText) else { return }

        let guid = currentGUID.trimmingCharacters(in: .whitespacesAndNewlines)
        articles.append(
            NewsArticle(
                id: guid.isEmpty ? link.absoluteString : guid,
                title: title,
                link: link,
                publishedAt: Self.dateFormatter.date(from: currentDate.trimmingCharacters(in: .whitespacesAndNewlines)),
                sourceName: sourceName
            )
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()
}
