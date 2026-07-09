<p align="center">
  <img src="Assets/spotify-lyrics-avatar.png" width="180" alt="SpotifyLyrics mascot"/>
</p>

<h1 align="center">SpotifyLyrics</h1>

<p align="center">
  <strong>Spotify lyrics, but native. A floating karaoke overlay for macOS.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue" alt="macOS 13+"/>
  <img src="https://img.shields.io/badge/Swift-6.0-orange" alt="Swift 6.0 toolchain"/>
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License"/>
</p>

---

SpotifyLyrics is a lightweight macOS menu bar app that puts synced lyrics on top of Spotify as a polished, always-available overlay. It feels like karaoke mode for your desktop: live scrolling, word-level fill, translations, romanization, music controls, shareable lyric cards, and a tiny subtitle mode when you want your screen back.

No Spotify login. No Spotify Web API. No external dependencies. Just Swift, Apple frameworks, LRCLIB, and the Spotify desktop app.

## Why It Exists

Spotify's built-in lyrics are locked inside the player. SpotifyLyrics makes lyrics part of the operating system experience:

- keep lyrics visible while coding, writing, designing, gaming, or presenting
- learn songs in Japanese, Korean, Chinese, Arabic, Russian, Hindi, and more with romanization and translation
- jump through a track by clicking lyric lines instead of scrubbing blindly
- turn a single lyric into a social-ready card with album art in one click
- run everything as a quiet menu bar utility instead of another big window

## Feature Highlights

### Karaoke Overlay

- **Full lyrics overlay** with frosted glass styling, smooth auto-scroll, and current-line focus
- **Mini subtitle mode** for a compact one-line lyric bar
- **Word-level karaoke fill** when enhanced LRC word timestamps are available
- **Four animation modes**: Karaoke, Smooth, Spring, and Glow
- **Instrumental break view** with countdown and next-line preview
- **Click-to-seek lyrics**: click any line to jump Spotify to that timestamp
- **Manual scrolling** with a one-click return to the current lyric
- **Resizable layouts**: Mini, Small, Medium, and Large
- **Opacity control** and **Always on Top** toggle
- **Hover controls** for play, pause, next, previous, shuffle, repeat, and seek

### Lyrics Sources

- **LRCLIB integration** for free synced and plain lyrics
- **Multiple candidate picker** when LRCLIB has several matches for a track
- **Duration-aware ranking** so the best synced match usually wins first
- **Per-track source memory** so your selected lyric version stays selected
- **Three-level cache**: in-memory, disk, then network
- **Cache clearing** from the menu bar
- **Speech recognition fallback** path for last-resort lyrics generation through Apple's Speech framework

### Translation, Romanization, and AI

- **Automatic language detection** with Apple's NaturalLanguage framework
- **Romanization** for non-Latin scripts using ICU and CFStringTokenizer
- **On-device translation** via Apple's Translation framework where available
- **14 target languages**: Indonesian, English, Japanese, Korean, Chinese, Spanish, French, German, Portuguese, Thai, Vietnamese, Arabic, Russian, and Hindi
- **Mixed-language handling** for lyrics that switch languages inside the same song
- **Apple Intelligence modes** on supported macOS versions:
  - Primary: AI translates directly for quality
  - Refine: fast translation first, AI improves in the background
  - Off: standard translation only
- **AI song summary**: a short one-line theme shown in the overlay when Foundation Models are available

### Menu Bar Player

- **300 x 300 album-art mini player** in the menu bar popover
- **Blurred artwork hover state** with playback controls
- **Dominant-color accenting** extracted from album art
- **Seek bar with timestamps**
- **Current mood indicator** when SoundAnalysis detects a known mood
- **Version display**, settings, cache controls, and quit action in one compact popover

### Sharing

- **Lyrics card generator** for quote-style lyric images
- **Album-art background blur** with the lyric, title, artist, romanization, and translation
- **1080 x 1080 square cards** by default, with landscape support in the generator
- **Clipboard export** from the in-app preview

### System Integration

- **macOS menu bar app** with no Dock icon
- **App Shortcuts support**:
  - Show, hide, or toggle the lyrics overlay
  - Ask what song is playing
  - Toggle translation and choose a target language
  - Set overlay size and animation mode from App Intents
- **AppleScript control** for Spotify playback and seeking
- **Accessibility polling** for faster play/pause, progress, shuffle, repeat, and liked-state reads
- **Predictive line switching**: the app schedules exact timers for upcoming lyric timestamps instead of relying only on polling

### Analysis and Native Intelligence

- **SoundAnalysis** for lightweight mood and audio-state classification
- **Vision** for album-art color extraction, OCR, and saliency analysis
- **Vocal activity detection** infrastructure for vocal vs instrumental sections
- **Drift correction** using Spotify-reported position and Accessibility progress
- **Render-friendly SwiftUI behavior** that avoids unnecessary published-state churn and per-frame work in idle states

## Requirements

- macOS 13 Ventura or later
- Spotify desktop app
- Swift 6.0 toolchain / Xcode Command Line Tools for building from source
- macOS 26+ and supported Apple Intelligence hardware for Foundation Models features
- Translation availability depends on Apple's Translation framework support on the machine

Permissions you may be asked for:

- **Automation**: required to control Spotify through AppleScript
- **Accessibility**: recommended for faster state/progress detection
- **Speech Recognition / Microphone**: only needed if using speech-recognition fallback workflows

## Installation

### Download

Grab the latest build from [Releases](https://github.com/denyherianto/SpotifyLyrics/releases), open it, and drag SpotifyLyrics to Applications.

If macOS blocks the unsigned app, remove quarantine:

```bash
xattr -cr /Applications/SpotifyLyrics.app
```

Then open SpotifyLyrics normally and allow the requested Spotify Automation permission.

### Build From Source

```bash
git clone https://github.com/denyherianto/SpotifyLyrics.git
cd SpotifyLyrics
swift build -c release --product SpotifyLyrics
```

### Run

```bash
./run.sh
```

Or manually:

```bash
swift build -c release --product SpotifyLyrics
.build/release/SpotifyLyrics
```

## Usage

1. Open Spotify and play a song.
2. Launch SpotifyLyrics.
3. The lyrics overlay appears at the bottom of the screen.
4. Use the menu bar music icon to control visibility, lyrics source, translation, romanization, overlay size, animation, opacity, and cache.

In the overlay:

- hover to reveal controls
- click a lyric line to seek
- scroll manually to browse the song
- click **Current** to return to the active line
- switch to **Mini** when you only want a subtitle bar
- right-click a lyric line to copy it or share it as a card

## Architecture

```text
Spotify desktop app
  -> AppleScriptBridge
       track metadata, playback state, controls, seek
  -> AccessibilityBridge
       fast UI state, progress cross-check, shuffle/repeat/liked reads
  -> SpotifyPlayerManager
       polling, interpolation, drift correction, predictive line timers

LRCLIB / cache / speech fallback
  -> LyricsManager
       candidate ranking, per-track source selection, memory + disk cache
  -> LRCParser
       line timestamps and inline word timestamps
  -> EnrichmentCoordinator
       language detection, romanization, translation, AI refinement, summaries

SwiftUI + AppKit
  -> LyricsOverlayWindow
       transparent non-activating NSPanel
  -> LyricsOverlayView / MiniOverlayView
       karaoke rendering, controls, seek bar, instrumental breaks, share cards
  -> MenuBarView
       album-art mini player, settings, source picker, cache, mood indicator
```

## Project Layout

```text
Sources/SpotifyLyricsCore/
  Analysis/      SoundAnalysis, Vision, vocal activity helpers
  Controls/      playback controls and seek bar
  Lyrics/        LRCLIB provider, LRC parser, cache, enrichment pipeline
  Models/        track, lyric, language, animation, and overlay models
  Overlay/       full and mini overlay views, lyric line rendering, break view
  Sharing/       lyrics card rendering and clipboard export
  Spotify/       AppleScript and Accessibility bridges

Sources/App/
  Intents/       App Shortcuts and App Intents
  MenuBarView    menu bar popover mini player and settings
  SpotifyLyricsApp
                 app lifecycle, overlay controller, state wiring

Tests/
  Custom executable test harness, not XCTest
```

## Build and Test

```bash
# Debug build
swift build

# Release build
swift build -c release --product SpotifyLyrics

# Run the custom test harness
swift run SpotifyLyricsTests
```

## Apple Frameworks Used

| Framework | Purpose |
| --- | --- |
| AppKit | menu bar app, NSPanel overlay, image handling |
| SwiftUI | overlay, menu bar popover, controls, card rendering |
| AppIntents | Shortcuts support |
| Accessibility | fast Spotify UI state and progress reads |
| NaturalLanguage | language detection and text classification |
| Translation | on-device lyrics translation where available |
| FoundationModels | Apple Intelligence summaries and AI translation refinement where available |
| Speech | fallback lyric recognition workflow |
| SoundAnalysis | audio and mood classification |
| Vision | album-art palette extraction, OCR, saliency |
| CreateML | vocal activity infrastructure |
| CoreFoundation | ICU-backed romanization |

## Privacy and Constraints

SpotifyLyrics is intentionally local-first:

- It does **not** use the Spotify Web API.
- It does **not** ask for your Spotify account or OAuth token.
- It reads the Spotify desktop app through AppleScript and Accessibility.
- Lyrics searches go to LRCLIB.
- Translation, romanization, analysis, and AI features use Apple frameworks where available.
- Cached lyrics are stored locally in the user's caches directory.

Known constraints:

- Spotify desktop app is required.
- Queue, playlist, and library management are out of scope because there is no Spotify Web API integration.
- Lyrics quality depends on available LRCLIB matches unless a fallback workflow is used.
- AI features require supported macOS, hardware, and Apple Intelligence settings.

## Contributing

The project is deliberately dependency-free and split into a reusable core target plus a small app target. Keep changes native, testable, and focused.

Before opening a PR:

```bash
swift build
swift run SpotifyLyricsTests
```

New tests live in `Tests/` and should be registered in `Tests/TestRunner.swift`.

## License

[MIT](LICENSE)
