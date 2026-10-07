import Foundation
import Testing
@testable import JarvisDashboard

struct NewsAPIServiceTests {
    @Test func parsesNewsAPIResponse() throws {
        let data = Data(#"""
        {
          "status": "ok",
          "totalResults": 1,
          "articles": [{
            "source": {"id": null, "name": "Example News"},
            "author": null,
            "title": "A useful headline",
            "description": null,
            "url": "https://example.com/story",
            "urlToImage": null,
            "publishedAt": "2026-10-07T12:30:00Z",
            "content": null
          }]
        }
        """#.utf8)

        let articles = try NewsAPIService().parse(data: data)

        #expect(articles.count == 1)
        #expect(articles[0].title == "A useful headline")
        #expect(articles[0].sourceName == "Example News")
        #expect(articles[0].publishedAt != nil)
    }
}
