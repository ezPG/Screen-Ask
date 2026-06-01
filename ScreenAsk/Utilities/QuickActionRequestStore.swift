import Foundation

enum QuickActionRequestStore {
    static let appGroupID = "group.com.ezpg.screenask"
    static let requestKey = "quick_action_image_paths"

    static func readAndConsumeRequest() -> [String]? {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            return nil
        }
        
        if let paths = defaults.stringArray(forKey: requestKey), !paths.isEmpty {
            defaults.removeObject(forKey: requestKey)
            return paths
        }
        
        // Fallback for older single string key if necessary
        let oldKey = "quick_action_image_path"
        if let singlePath = defaults.string(forKey: oldKey), !singlePath.isEmpty {
            defaults.removeObject(forKey: oldKey)
            return [singlePath]
        }
        
        return nil
    }
}
