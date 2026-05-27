import Foundation

/// Decides whether the user's query needs web search or web scraping,
/// executes the tools if needed, and enriches the prompt with results.
enum ToolRouter {

    /// The outcome of tool routing — either the original prompt is passed through,
    /// or the prompt is augmented with web search / scrape results.
    struct RoutedPrompt {
        let enrichedPrompt: String
        /// Non-empty if a tool was invoked (for logging / UI feedback).
        let toolUsed: String?
    }

    // MARK: - Public

    /// Analyze the user prompt and, if web search or scraping is needed, execute
    /// the tools and return an enriched prompt. Otherwise return the original.
    ///
    /// This is a **client-side routing** approach — no Groq tool-calling API needed.
    /// The heuristic examines the prompt for signals that the user wants live web data.
    ///
    /// - Parameter history: The full chat history so far (used to resolve vague references
    ///   like "it", "this", "that" into concrete search queries).
    static func route(
        prompt: String,
        history: [MessageBuilder.ChatTurn],
        webSearchEnabled: Bool,
        imageSearchEnabled: Bool,
        apiKey: String,
        model: String,
        groqClient: GroqClient
    ) async -> RoutedPrompt {
        // 1. Check for explicit URL scraping request.
        if webSearchEnabled, let url = extractURL(from: prompt) {
            do {
                let pageText = try await WebSearchService.scrapePageText(urlString: url)
                let enriched = """
                The user asked about a web page. Here is the content scraped from \(url):

                ---BEGIN PAGE CONTENT---
                \(pageText)
                ---END PAGE CONTENT---

                User's question: \(prompt)

                IMPORTANT: Use ONLY the page content above to answer. Do NOT invent or fabricate any URLs.
                """
                return RoutedPrompt(enrichedPrompt: enriched, toolUsed: "Web Scrape: \(url)")
            } catch {
                let enriched = """
                \(prompt)

                [Note: Attempted to scrape \(url) but failed: \(error.localizedDescription). Answer using your knowledge but do NOT fabricate URLs.]
                """
                return RoutedPrompt(enrichedPrompt: enriched, toolUsed: "Web Scrape (failed)")
            }
        }

        // 2. Use LLM to decide if web search is needed and get the query.
        if webSearchEnabled {
            let routingSystemPrompt = """
            You are a search routing assistant.
            Determine if the user's latest query requires a web search.
            Consider chat history for context.

            RULES FOR SEARCHING:
            1. ALWAYS search if the user asks for "latest", "recent", "news", "updates", or "current" info. Your internal knowledge is outdated!
            2. ALWAYS search for specific facts you might not know confidently, prices, or sports scores.
            3. If search is needed, output ONLY the search query. DO NOT add "The search query is:" or quotes.
            4. Resolve pronouns (it, he, she, his, her, they, this) to their actual subjects from the chat history.

            RULES for NO SEARCH:
            1. If the user is just saying hello, thanking you, or asking general conversational questions.
            2. If the user is asking specifically about the visual contents of the image/screenshot.
            3. If NO search is needed, output EXACTLY: NONE

            EXAMPLES:
            History: [User: "who is sydney sweeney?", Assistant: "She is an actress..."]
            User: "her latest movie?"
            Output: sydney sweeney latest movie

            History: [User: "what's this image?", Assistant: "It's the Mandalorian."]
            User: "when is season 4?"
            Output: The Mandalorian season 4 release date

            User: "thanks!"
            Output: NONE

            User: "search for the weather in tokyo"
            Output: weather in tokyo
            """

            do {
                if let routingResponse = try await groqClient.generateSearchQuery(
                    apiKey: apiKey,
                    model: model, // Using the same model for routing as it is highly capable
                    systemPrompt: routingSystemPrompt,
                    history: history,
                    prompt: prompt
                ) {
                    var decision = routingResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Failsafe cleanup in case the model ignores the strict "no prefix" rule
                    let prefixesToRemove = ["the search query is:", "search query:", "search for:", "query:"]
                    for prefix in prefixesToRemove {
                        if decision.lowercased().hasPrefix(prefix) {
                            decision = String(decision.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    decision = decision.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) // strip quotes
                    
                    if !decision.isEmpty && decision.uppercased() != "NONE" {
                        // The LLM generated a search query
                        let searchQuery = decision
                        
                        let results = try await WebSearchService.search(query: searchQuery, maxResults: 5)
                        if !results.isEmpty {
                            var context = "Web search results for: \"\(searchQuery)\"\n\n"
                            for (i, r) in results.enumerated() {
                                context += "[\(i + 1)] \(r.title)\n    URL: \(r.url)\n    \(r.snippet)\n\n"
                            }

                            // Optionally scrape the top result for deeper context.
                            var scrapedContent = ""
                            if let firstURL = results.first?.url {
                                if let pageText = try? await WebSearchService.scrapePageText(urlString: firstURL, maxChars: 4000) {
                                    scrapedContent = """

                                    ---BEGIN TOP RESULT CONTENT (from: \(firstURL))---
                                    \(pageText)
                                    ---END TOP RESULT CONTENT---
                                    """
                                }
                            }

                            let enriched = """
                            The user asked a question that may require current web information. Below are real search results:

                            \(context)\(scrapedContent)

                            User's question: \(prompt)

                            CRITICAL RULES:
                            - Answer using ONLY the search results and scraped content provided above.
                            - When citing sources, use ONLY the exact URLs listed in the search results above. Copy them exactly.
                            - NEVER invent, fabricate, or guess URLs. If you don't have a relevant URL from the results, don't include one.
                            - If the search results don't contain relevant information, say "I couldn't find relevant results" and answer from your general knowledge without citing any URLs.
                            """
                            return RoutedPrompt(enrichedPrompt: enriched, toolUsed: "Web Search: \(searchQuery)")
                        }
                    }
                }
            } catch {
                // LLM routing failed or search failed; fall through to direct LLM response.
                print("ToolRouter routing error: \(error)")
            }
        }

        // 3. Image search (future placeholder — checklist item).
        // Image search integration would go here when enabled.

        // 4. No tool needed — pass through.
        return RoutedPrompt(enrichedPrompt: prompt, toolUsed: nil)
    }

    // MARK: - Helpers

    /// Extracts the first http/https URL found in the prompt.
    private static func extractURL(from text: String) -> String? {
        let pattern = #"https?://[^\s<>\"')\]]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else {
            return nil
        }
        return (text as NSString).substring(with: match.range)
    }
}
