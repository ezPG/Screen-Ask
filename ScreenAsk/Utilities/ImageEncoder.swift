import Foundation

enum ImageEncoder {
    static func base64PNG(at fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        return data.base64EncodedString()
    }
}
