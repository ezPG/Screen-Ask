import Foundation

enum MessageBuilder {
    struct ChatTurn {
        let role: String
        let text: String
    }

    static func makeVisionRequest(
        model: String,
        systemPrompt: String,
        history: [ChatTurn],
        prompt: String,
        base64Images: [String]
    ) -> GroqChatRequest {
        let normalizedSystemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        var messages: [GroqMessage] = []
        if !normalizedSystemPrompt.isEmpty {
            messages.append(
                GroqMessage(role: "system", content: [.text(normalizedSystemPrompt)])
            )
        }

        // Provide screenshot context once at the beginning of each request.
        var contextContents: [GroqContent] = []
        for base64 in base64Images {
            let dataURL = "data:image/png;base64,\(base64)"
            contextContents.append(.imageURL(dataURL))
        }
        contextContents.append(.text("Screenshot context for this chat."))
        
        messages.append(
            GroqMessage(role: "user", content: contextContents)
        )

        for turn in history where !turn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(
                GroqMessage(role: turn.role, content: [.text(turn.text)])
            )
        }

        messages.append(
            GroqMessage(role: "user", content: [.text(prompt)])
        )

        return GroqChatRequest(
            model: model,
            messages: messages,
            stream: true,
            maxTokens: 1024
        )
    }

    static func makeTextRequest(
        model: String,
        systemPrompt: String,
        history: [ChatTurn],
        prompt: String
    ) -> GroqChatRequest {
        var messages: [GroqMessage] = []
        let normalizedSystemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedSystemPrompt.isEmpty {
            messages.append(
                GroqMessage(role: "system", content: [.text(normalizedSystemPrompt)])
            )
        }

        for turn in history where !turn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(
                GroqMessage(role: turn.role, content: [.text(turn.text)])
            )
        }

        messages.append(
            GroqMessage(role: "user", content: [.text(prompt)])
        )

        return GroqChatRequest(
            model: model,
            messages: messages,
            stream: false,
            maxTokens: 100 // We only need a short search query string
        )
    }
}
