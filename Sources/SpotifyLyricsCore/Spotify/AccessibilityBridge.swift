import Foundation
import AppKit

/// Reads Spotify's UI state via macOS Accessibility APIs (AXUIElement).
///
/// Faster than AppleScript polling (~1-5ms vs ~50-200ms) and can access
/// UI elements not exposed via AppleScript, such as:
/// - Now Playing bar text (song title, artist, album)
/// - Playback progress bar position
/// - Like/dislike button state
/// - Queue visibility
///
/// Requires Accessibility permission (System Settings > Privacy > Accessibility).
public final class AccessibilityBridge {

    /// Playback info extracted from Spotify's Accessibility tree.
    public struct AXPlaybackInfo: Equatable {
        public let title: String
        public let artist: String
        public let isPlaying: Bool
        public let progress: Double?  // 0..1 normalized progress
        public let isLiked: Bool

        public init(title: String, artist: String, isPlaying: Bool, progress: Double?, isLiked: Bool) {
            self.title = title
            self.artist = artist
            self.isPlaying = isPlaying
            self.progress = progress
            self.isLiked = isLiked
        }
    }

    public init() {}

    // MARK: - Permission

    /// Check if Accessibility access is granted.
    public static var isAccessibilityEnabled: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt for Accessibility permission if not granted.
    public static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Spotify App Reference

    /// Find the Spotify process and return its AXUIElement.
    private func spotifyApp() -> AXUIElement? {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == "com.spotify.client"
        }
        guard let spotify = apps.first else { return nil }
        return AXUIElementCreateApplication(spotify.processIdentifier)
    }

    // MARK: - Read Playback Info

    /// Read the current playback info from Spotify's Accessibility tree.
    /// Returns nil if Spotify isn't running or Accessibility isn't enabled.
    public func getPlaybackInfo() -> AXPlaybackInfo? {
        guard Self.isAccessibilityEnabled else { return nil }
        guard let app = spotifyApp() else { return nil }

        // Get all windows
        guard let windows = getAttribute(app, attribute: kAXWindowsAttribute) as? [AXUIElement],
              let mainWindow = windows.first else {
            return nil
        }

        // Traverse the UI tree to find Now Playing elements
        var title = ""
        var artist = ""
        var isPlaying = false
        var progress: Double?
        var isLiked = false

        // Search for relevant UI elements in the window
        traverseTree(mainWindow) { element, role, elementTitle, elementValue in
            let roleStr = role as String? ?? ""
            let titleStr = elementTitle as String? ?? ""
            let valueStr = elementValue as? String ?? ""

            // Detect play/pause button
            if roleStr == "AXButton" {
                let desc = (getAttribute(element, attribute: kAXDescriptionAttribute) as? String) ?? ""
                if desc.lowercased().contains("pause") {
                    isPlaying = true
                } else if desc.lowercased().contains("play") && !desc.lowercased().contains("play") {
                    isPlaying = false
                }

                // Like button
                if titleStr.lowercased().contains("save") || desc.lowercased().contains("like") {
                    let pressed = getAttribute(element, attribute: kAXValueAttribute) as? Int
                    isLiked = pressed == 1
                }
            }

            // Detect slider (progress bar)
            if roleStr == "AXSlider" {
                if let value = getAttribute(element, attribute: kAXValueAttribute) as? Double {
                    // Spotify's progress slider typically has value 0-100
                    if value >= 0 && value <= 100 {
                        progress = value / 100.0
                    }
                }
            }

            // Detect static text elements in the Now Playing area
            if roleStr == "AXStaticText" || roleStr == "AXLink" {
                if !valueStr.isEmpty {
                    // Heuristic: first text element is title, second is artist
                    if title.isEmpty {
                        title = valueStr
                    } else if artist.isEmpty && valueStr != title {
                        artist = valueStr
                    }
                } else if !titleStr.isEmpty {
                    if title.isEmpty {
                        title = titleStr
                    } else if artist.isEmpty && titleStr != title {
                        artist = titleStr
                    }
                }
            }

            return true // continue traversal
        }

        guard !title.isEmpty else { return nil }

        return AXPlaybackInfo(
            title: title,
            artist: artist,
            isPlaying: isPlaying,
            progress: progress,
            isLiked: isLiked
        )
    }

    /// Read the focused element description (useful for debugging the AX tree).
    public func getFocusedElementInfo() -> String? {
        guard let app = spotifyApp() else { return nil }
        guard let focusedObj = getAttribute(app, attribute: kAXFocusedUIElementAttribute) else {
            return nil
        }
        // AXUIElement is a CFTypeRef, bridge via unsafeBitCast
        let focused: AXUIElement = unsafeBitCast(focusedObj, to: AXUIElement.self)

        let role = getAttribute(focused, attribute: kAXRoleAttribute) as? String ?? "unknown"
        let title = getAttribute(focused, attribute: kAXTitleAttribute) as? String ?? ""
        let value = getAttribute(focused, attribute: kAXValueAttribute)
        return "Role: \(role), Title: \(title), Value: \(String(describing: value))"
    }

    // MARK: - Window Info

    /// Get Spotify's main window position and size.
    public func getWindowFrame() -> NSRect? {
        guard let app = spotifyApp() else { return nil }
        guard let windows = getAttribute(app, attribute: kAXWindowsAttribute) as? [AXUIElement],
              let window = windows.first else { return nil }

        guard let position = getPointAttribute(window, attribute: kAXPositionAttribute),
              let size = getSizeAttribute(window, attribute: kAXSizeAttribute) else {
            return nil
        }

        return NSRect(origin: position, size: size)
    }

    // MARK: - AX Helpers

    private func getAttribute(_ element: AXUIElement, attribute: String) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return result == .success ? value : nil
    }

    private func getPointAttribute(_ element: AXUIElement, attribute: String) -> CGPoint? {
        guard let value = getAttribute(element, attribute: attribute) else { return nil }
        var point = CGPoint.zero
        if AXValueGetValue(value as! AXValue, .cgPoint, &point) {
            return point
        }
        return nil
    }

    private func getSizeAttribute(_ element: AXUIElement, attribute: String) -> CGSize? {
        guard let value = getAttribute(element, attribute: attribute) else { return nil }
        var size = CGSize.zero
        if AXValueGetValue(value as! AXValue, .cgSize, &size) {
            return size
        }
        return nil
    }

    /// Traverse the Accessibility tree depth-first.
    /// The visitor receives each element with its role, title, and value.
    /// Return false from the visitor to stop traversal.
    private func traverseTree(
        _ element: AXUIElement,
        depth: Int = 0,
        maxDepth: Int = 10,
        visitor: (AXUIElement, CFString?, CFString?, AnyObject?) -> Bool
    ) {
        guard depth < maxDepth else { return }

        let role = getAttribute(element, attribute: kAXRoleAttribute).flatMap { $0 as? NSString } as CFString?
        let titleAttr = getAttribute(element, attribute: kAXTitleAttribute).flatMap { $0 as? NSString } as CFString?
        let value = getAttribute(element, attribute: kAXValueAttribute)

        guard visitor(element, role, titleAttr, value) else { return }

        // Traverse children
        guard let children = getAttribute(element, attribute: kAXChildrenAttribute) as? [AXUIElement] else {
            return
        }

        for child in children {
            traverseTree(child, depth: depth + 1, maxDepth: maxDepth, visitor: visitor)
        }
    }
}
