import Foundation

enum MessageBuilder {
    static func makeVisionRequest(model: String, prompt: String, base64Image: String) -> GroqChatRequest {
        let dataURL = "data:image/png;base64,\(base64Image)"
        return GroqChatRequest(
            model: model,
            messages: [
                GroqMessage(role: "user", content: [
                    .imageURL(dataURL),
                    .text(prompt)
                ])
            ],
            stream: true,
            maxTokens: 1024
        )
    }
}
