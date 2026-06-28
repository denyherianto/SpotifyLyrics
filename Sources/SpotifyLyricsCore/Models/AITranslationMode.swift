import Foundation
#if canImport(FoundationModels) && compiler(>=6.2)
import FoundationModels
#endif

/// Controls how on-device AI (Apple Intelligence) is used for translation.
public enum AITranslationMode: String, CaseIterable {
    /// AI translates all lyrics directly (best quality, uses more resources).
    case primary
    /// Apple Translation first, AI improves in background (balanced).
    case refine
    /// AI disabled, Apple Translation only (fastest, lowest resource usage).
    case off

    public var displayName: String {
        switch self {
        case .primary: return "Primary"
        case .refine:  return "Refine"
        case .off:     return "Off"
        }
    }

    /// Check if Apple Intelligence is available and enabled on this device.
    /// Requires macOS 26+ with Apple Intelligence enabled in System Settings.
    public static var isAIAvailable: Bool {
        #if canImport(FoundationModels) && compiler(>=6.2)
        guard #available(macOS 26, *) else { return false }
        return SystemLanguageModel.default.availability == .available
        #else
        return false
        #endif
    }
}
