import Foundation

enum QuickActionRequestStore {
    static let appGroupID = "group.com.ezpg.screenask"
    static let requestKey = "quick_action_image_path"

    static func readAndConsumeRequest() -> String? {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            return nil
        }
        guard let path = defaults.string(forKey: requestKey), !path.isEmpty else {
            return nil
        }
        defaults.removeObject(forKey: requestKey)
        return path
    }
}
