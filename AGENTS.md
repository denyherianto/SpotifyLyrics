# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Build & Run Commands

```bash
# Build release
swift build -c release --product SpotifyLyrics

# Build debug
swift build

# Run (build + launch)
./run.sh

# Run tests (custom harness, not XCTest)
swift run SpotifyLyricsTests
```

## Project Overview

SpotifyLyrics is a macOS menu bar app (Swift 6.0 toolchain, Swift 5 language mode) that overlays synced lyrics on top of Spotify. Zero external dependencies — Apple frameworks only. Minimum deployment: macOS 13.

### Targets (Package.swift)

| Target | Type | Path |
|--------|------|------|
| `SpotifyLyricsCore` | Library | `Sources/SpotifyLyricsCore/` |
| `SpotifyLyrics` | Executable | `Sources/App/` |
| `SpotifyLyricsTests` | Executable | `Tests/` |

## Architecture

### Data Flow

1. **Spotify polling** (`SpotifyPlayerManager`) — 300ms AppleScript + 100ms Accessibility polls with wall-clock interpolation between polls
2. **Lyrics fetch** (`LyricsManager`) — three-tier cache: in-memory dict → disk JSON → LRCLIB network API. Cache key: `"{artist}|{title}"` lowercased
3. **Enrichment** (`EnrichmentCoordinator`) — detects language, applies romanization (ICU) and/or translation (Apple Translation framework, macOS 26+)
4. **Overlay rendering** — `LyricsOverlayWindow` (NSPanel) hosts SwiftUI views with per-word karaoke fill animation

### Key Subsystems

- **Spotify bridge**: `AppleScriptBridge` (track info, playback control) + `AccessibilityBridge` (fast state: play/pause, like status). No Spotify Web API.
- **Lyrics**: `LRCParser` parses `.lrc` format (line timestamps `[mm:ss.xx]` + inline word tags `<mm:ss.xx>`). `SpeechRecognitionProvider` is a fallback.
- **Enrichment**: `LyricsEnrichmentProvider` protocol. `ICURomanizationProvider` (Japanese/CJK/Cyrillic/Arabic via CFStringTokenizer), `AppleTranslationProvider` (14+ languages).
- **Analysis**: `SoundClassifier` (mood/genre), `VisionAnalyzer` (album art color palette + OCR), `VocalActivityDetector` (singing vs instrumental).
- **Overlay UI**: `LyricsOverlayView` (full karaoke scroll), `MiniOverlayView` (single-line subtitle), `InstrumentalBreakView` (countdown to next vocal line). Animation modes: karaoke, smooth, spring, glow.
- **Settings**: `OverlayController` owns all persisted settings via UserDefaults `didSet`. Some settings (sync offset) are per-track.
- **App Intents**: Shortcuts support via `AppState.shared` singleton.

### Feature Gating

Apple AI features use `#if canImport(FoundationModels)` and `@available(macOS 26, *)`.

## Testing Conventions

Custom test harness (not XCTest). Assertion functions:
- `check(_ condition:)` — boolean assertion
- `checkEqual(_ a:, _ b:)` — equality assertion
- `checkApprox(_ a:, _ b:, accuracy:)` — floating-point comparison

Add new test files in `Tests/`, register them in `Tests/TestRunner.swift`'s `main()`.

## Architectural Constraints

- **No Spotify Web API** — all Spotify data comes via AppleScript + Accessibility bridge (no queue, playlist, or library access)
- **Predictive line switching** — `AppDelegate` schedules a timer at each next line's exact timestamp for smooth transitions (not just polling)
- **Combine bindings** — settings sync uses Combine with 300ms debounce for expensive operations like re-enrichment
