import Foundation

struct GroqClient {
    func streamVisionResponse(
        apiKey: String,
        model: String,
        systemPrompt: String,
        history: [MessageBuilder.ChatTurn],
        prompt: String,
        imageFileURL: URL,
        onDelta: @escaping @Sendable (String) async -> Void
    ) async throws {
        let base64 = try ImageEncoder.base64PNG(at: imageFileURL)
        let requestBody = MessageBuilder.makeVisionRequest(
            model: model,
            systemPrompt: systemPrompt,
            history: history,
            prompt: prompt,
            base64Image: base64
        )

        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if !(200..<300).contains(http.statusCode) {
            var body = ""
            for try await line in bytes.lines {
                body += line
                if body.count > 4000 { break }
            }
            let message = body.isEmpty ? "HTTP \(http.statusCode)" : "HTTP \(http.statusCode): \(body)"
            throw NSError(
                domain: NSURLErrorDomain,
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8) else { continue }
            if let chunk = try? JSONDecoder().decode(GroqStreamChunk.self, from: data),
               let delta = chunk.choices.first?.delta.content,
               !delta.isEmpty {
                await onDelta(delta)
            }
        }
    }
}
