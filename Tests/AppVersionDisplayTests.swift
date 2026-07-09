@testable import SpotifyLyricsCore
import Foundation

func testAppVersionDisplay() {
    print("--- App Version Display Tests ---")

    do {
        let info: [String: Any] = [
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "45"
        ]

        checkEqual(AppVersionDisplay.marketingVersion(from: info), "v1.2.3", "uses marketing version only")
        print("  ✓ Marketing version only")
    }

    do {
        checkEqual(AppVersionDisplay.marketingVersion(from: [:]), "v0.0.0", "falls back when marketing version is unavailable")
        print("  ✓ Missing version fallback")
    }

    do {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotifyLyrics-AppVersionDisplayTests-\(UUID().uuidString).plist")
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleShortVersionString</key>
            <string>2.3.4</string>
        </dict>
        </plist>
        """
        try? plist.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        checkEqual(
            AppVersionDisplay.marketingVersion(from: nil, fallbackInfoPlistURL: tempURL),
            "v2.3.4",
            "uses fallback plist when bundle metadata is unavailable"
        )
        print("  ✓ Info.plist fallback")
    }
}
