import Foundation

struct GroqChatRequest: Encodable {
    let model: String
    let messages: [GroqMessage]
    let stream: Bool
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case maxTokens = "max_tokens"
    }
}

struct GroqMessage: Encodable {
    let role: String
    let content: [GroqContent]
}

enum GroqContent: Encodable {
    case imageURL(String)
    case text(String)

    enum CodingKeys: String, CodingKey {
        case type
        case imageURL = "image_url"
        case text
    }

    enum ImageURLCodingKeys: String, CodingKey {
        case url
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .imageURL(let value):
            try container.encode("image_url", forKey: .type)
            var image = container.nestedContainer(keyedBy: ImageURLCodingKeys.self, forKey: .imageURL)
            try image.encode(value, forKey: .url)
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)
        }
    }
}

struct GroqStreamChunk: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let delta: Delta
    }

    struct Delta: Decodable {
        let content: String?
    }
}
