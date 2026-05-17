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
        base64Image: String
    ) -> GroqChatRequest {
        let dataURL = "data:image/png;base64,\(base64Image)"
        let normalizedSystemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        var messages: [GroqMessage] = []
        if !normalizedSystemPrompt.isEmpty {
            messages.append(
                GroqMessage(role: "system", content: [.text(normalizedSystemPrompt)])
            )
        }

        // Provide screenshot context once at the beginning of each request.
        messages.append(
            GroqMessage(role: "user", content: [
                .imageURL(dataURL),
                .text("Screenshot context for this chat.")
            ])
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
}
