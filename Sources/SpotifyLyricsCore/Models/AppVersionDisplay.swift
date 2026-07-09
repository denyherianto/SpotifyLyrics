import Foundation

public enum AppVersionDisplay {
    public static func marketingVersion(from infoDictionary: [String: Any]?) -> String {
        guard let rawVersion = infoDictionary?["CFBundleShortVersionString"] as? String else {
            return "v0.0.0"
        }

        let version = rawVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else { return "v0.0.0" }
        return version.hasPrefix("v") ? version : "v\(version)"
    }

    public static func marketingVersion(from infoDictionary: [String: Any]?, fallbackInfoPlistURL: URL) -> String {
        let bundledVersion = marketingVersion(from: infoDictionary)
        if bundledVersion != "v0.0.0" {
            return bundledVersion
        }

        guard
            let data = try? Data(contentsOf: fallbackInfoPlistURL),
            let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let fallbackInfoDictionary = propertyList as? [String: Any]
        else {
            return bundledVersion
        }

        return marketingVersion(from: fallbackInfoDictionary)
    }

    public static func currentMarketingVersion() -> String {
        let infoPlistURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Info.plist")

        return marketingVersion(from: Bundle.main.infoDictionary, fallbackInfoPlistURL: infoPlistURL)
    }
}
