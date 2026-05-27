import Foundation

/// Lightweight web search using DuckDuckGo HTML endpoint (no API key required)
/// and basic page scraping via URLSession.
enum WebSearchService {

    struct SearchResult {
        let title: String
        let url: String
        let snippet: String
    }

    // MARK: - Web Search (DuckDuckGo HTML)

    /// Searches DuckDuckGo and returns up to `maxResults` search results.
    static func search(query: String, maxResults: Int = 5) async throws -> [SearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 15

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            return []
        }

        return parseSearchResults(html: html, maxResults: maxResults)
    }

    /// Parse DuckDuckGo HTML search results using regex.
    /// The HTML structure uses `<a class="result__a" …>` for titles/links
    /// and `<a class="result__snippet" …>` for snippets.
    private static func parseSearchResults(html: String, maxResults: Int) -> [SearchResult] {
        var results: [SearchResult] = []

        // Each result block lives inside <div class="result results_links results_links_deep …">
        // We extract title+URL from <a class="result__a" …> and snippet from <a class="result__snippet" …>
        let blockPattern = #"<div[^>]*class="[^"]*result[^"]*results_links[^"]*"[^>]*>(.*?)</div>\s*</div>"#
        guard let blockRegex = try? NSRegularExpression(pattern: blockPattern, options: [.dotMatchesLineSeparators]) else {
            return fallbackParseResults(html: html, maxResults: maxResults)
        }

        let nsHTML = html as NSString
        let blockMatches = blockRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        if blockMatches.isEmpty {
            return fallbackParseResults(html: html, maxResults: maxResults)
        }

        for match in blockMatches where results.count < maxResults {
            let blockRange = match.range(at: 1)
            let block = nsHTML.substring(with: blockRange)

            let title = extractFirstMatch(in: block, pattern: #"<a[^>]*class="result__a"[^>]*>(.*?)</a>"#)
            let href = extractFirstMatch(in: block, pattern: #"<a[^>]*class="result__a"[^>]*href="([^"]*)"[^>]*>"#)
            let snippet = extractFirstMatch(in: block, pattern: #"<a[^>]*class="result__snippet"[^>]*>(.*?)</a>"#)

            let cleanTitle = stripHTML(title)
            let cleanSnippet = stripHTML(snippet)
            let cleanURL = resolveDDGRedirect(href)

            guard !cleanTitle.isEmpty, !cleanURL.isEmpty else { continue }
            results.append(SearchResult(title: cleanTitle, url: cleanURL, snippet: cleanSnippet))
        }

        return results
    }

    /// Fallback parser: extract all result__a links and result__snippet text pairs.
    private static func fallbackParseResults(html: String, maxResults: Int) -> [SearchResult] {
        var results: [SearchResult] = []

        let titlePattern = #"<a[^>]*class="result__a"[^>]*href="([^"]*)"[^>]*>(.*?)</a>"#
        let snippetPattern = #"<a[^>]*class="result__snippet"[^>]*>(.*?)</a>"#

        guard let titleRegex = try? NSRegularExpression(pattern: titlePattern, options: [.dotMatchesLineSeparators]),
              let snippetRegex = try? NSRegularExpression(pattern: snippetPattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }

        let nsHTML = html as NSString
        let titleMatches = titleRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        let snippetMatches = snippetRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        for i in 0..<min(titleMatches.count, maxResults) {
            let tm = titleMatches[i]
            let href = nsHTML.substring(with: tm.range(at: 1))
            let title = stripHTML(nsHTML.substring(with: tm.range(at: 2)))
            let snippet: String
            if i < snippetMatches.count {
                snippet = stripHTML(nsHTML.substring(with: snippetMatches[i].range(at: 1)))
            } else {
                snippet = ""
            }
            let cleanURL = resolveDDGRedirect(href)
            guard !title.isEmpty, !cleanURL.isEmpty else { continue }
            results.append(SearchResult(title: title, url: cleanURL, snippet: snippet))
        }

        return results
    }

    // MARK: - Web Page Scraper

    /// Fetches a web page and returns its text content (HTML tags stripped).
    /// Truncates to `maxChars` to keep the LLM context manageable.
    static func scrapePageText(urlString: String, maxChars: Int = 6000) async throws -> String {
        guard let url = URL(string: urlString) else {
            return "[Error: Invalid URL]"
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 15

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            return "[Error: Could not decode page]"
        }

        let text = extractMainText(from: html)
        if text.count <= maxChars {
            return text
        }
        return String(text.prefix(maxChars)) + "\n… [truncated]"
    }

    // MARK: - Helpers

    private static func extractFirstMatch(in text: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return ""
        }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else {
            return ""
        }
        let groupCount = match.numberOfRanges
        if groupCount > 1 {
            return nsText.substring(with: match.range(at: 1))
        }
        return nsText.substring(with: match.range)
    }

    private static func stripHTML(_ html: String) -> String {
        var text = html
            .replacingOccurrences(of: "<br>", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        // Remove remaining HTML tags.
        if let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            text = tagRegex.stringByReplacingMatches(
                in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: ""
            )
        }
        // Collapse whitespace.
        if let wsRegex = try? NSRegularExpression(pattern: "\\s+", options: []) {
            text = wsRegex.stringByReplacingMatches(
                in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: " "
            )
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// DuckDuckGo redirect URLs look like: //duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com&…
    private static func resolveDDGRedirect(_ rawHref: String) -> String {
        if rawHref.contains("duckduckgo.com/l/") || rawHref.contains("duckduckgo.com/l?") {
            if let components = URLComponents(string: rawHref.hasPrefix("//")
                    ? "https:" + rawHref : rawHref),
               let uddg = components.queryItems?.first(where: { $0.name == "uddg" })?.value {
                return uddg
            }
        }
        // Sometimes href is already the final URL.
        if rawHref.hasPrefix("http://") || rawHref.hasPrefix("https://") {
            return rawHref
        }
        return rawHref
    }

    /// Remove <script>, <style>, <nav>, <footer>, <header> blocks, then strip tags.
    private static func extractMainText(from html: String) -> String {
        var cleaned = html
        // Remove script, style, nav, footer, header blocks.
        let blocksToRemove = ["script", "style", "nav", "footer", "header", "noscript", "iframe"]
        for tag in blocksToRemove {
            if let regex = try? NSRegularExpression(
                pattern: "<\(tag)[^>]*>.*?</\(tag)>",
                options: [.dotMatchesLineSeparators, .caseInsensitive]
            ) {
                cleaned = regex.stringByReplacingMatches(
                    in: cleaned,
                    range: NSRange(location: 0, length: (cleaned as NSString).length),
                    withTemplate: ""
                )
            }
        }
        return stripHTML(cleaned)
    }
}
