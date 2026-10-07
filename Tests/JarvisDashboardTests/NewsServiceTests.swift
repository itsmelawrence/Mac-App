import Foundation
import Testing
@testable import JarvisDashboard

struct NewsServiceTests {
    @Test func parsesRSSAndRepairsBareAmpersandsInLinks() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <item>
              <title>Regional update</title>
              <link>https://example.com/story?source=feed&amp;medium=rss</link>
              <guid>story-1</guid>
              <pubDate>Wed, 07 Oct 2026 12:30:00 +0800</pubDate>
            </item>
          </channel>
        </rss>
        """

        let articles = try RSSNewsService().parse(
            data: Data(xml.utf8),
            sourceName: "Test News"
        )

        #expect(articles.count == 1)
        #expect(articles[0].id == "story-1")
        #expect(articles[0].title == "Regional update")
        #expect(articles[0].link.absoluteString.contains("source=feed&medium=rss"))
        #expect(articles[0].publishedAt != nil)
    }

    @Test func parsesHTMLFeedFallback() throws {
        let html = """
        <html><body><div class="item">
        <a target="_blank" href="https://example.com/story?id=7&source=feed">Local update&nbsp;</a>
        </div></body></html>
        """

        let articles = try RSSNewsService().parse(
            data: Data(html.utf8),
            sourceName: "Local News"
        )

        #expect(articles.count == 1)
        #expect(articles[0].title == "Local update")
        #expect(articles[0].link.absoluteString.contains("id=7&source=feed"))
    }
}
