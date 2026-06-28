<p align="center">
  <img src="Assets/mascot.svg" width="200" alt="Spotify Lyrics Mascot"/>
</p>

<h1 align="center">Spotify Lyrics</h1>

<p align="center">
  <strong>Karaoke-style lyrics overlay for Spotify on macOS</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue" alt="Platform"/>
  <img src="https://img.shields.io/badge/swift-5.9%2B-orange" alt="Swift"/>
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License"/>
</p>

---

A lightweight macOS menu bar app that displays synced lyrics at the bottom of your screen while you listen to Spotify. Lyrics scroll in real-time, karaoke-style, with a frosted glass overlay.

## Features

### Lyrics & Playback
- **Karaoke-style synced lyrics** — current line highlighted with word-by-word fill animation
- **Word-level timing** — per-word karaoke fill via enhanced LRC word tags or Musixmatch richsync
- **Auto-scroll** — lyrics follow the music in real-time
- **Manual scroll** — scroll through lyrics freely, click "Back to Current" to resume
- **Click-to-seek** — click any lyric line to jump Spotify playback to that timestamp
- **Multiple lyrics sources** — LRCLIB (free, no API key) with Musixmatch fallback
- **Speech recognition fallback** — generates lyrics from audio via Apple Speech framework when no online provider has results
- **Playback interpolation** — wall-clock interpolation between 500ms polls for smooth tracking

### Language & Enrichment
- **Multi-language translation** — on-device translation via Apple Translation framework (macOS 26+), supporting 14+ languages (Indonesian, English, Japanese, Korean, Chinese, Spanish, French, German, Portuguese, Thai, Vietnamese, Arabic, Russian, Hindi)
- **Romanization** — phonetic readings for non-Latin scripts (Japanese with correct kanji readings, CJK, Cyrillic, Arabic) via ICU/CFStringTokenizer
- **Automatic language detection** — NaturalLanguage framework detects source language per line
- **Mixed-language handling** — segments and translates foreign portions of mixed-language lines independently

### Analysis & Intelligence
- **Sound classification** — real-time mood detection (vocal, instrumental, energetic, calm) via SoundAnalysis framework
- **Vision-powered palette** — multi-color extraction (dominant, accent, background) from album art using Vision framework
- **Album art text recognition** — OCR on album artwork via VNRecognizeTextRequest
- **Vocal activity detection** — identifies singing vs instrumental sections for smarter processing
- **Lyrics language classification** — NaturalLanguage-based classifier tuned for song lyrics with mixed-language support
- **Accessibility integration** — reads Spotify UI state via AX APIs for faster response

### Overlay & UI
- **Frosted glass overlay** — transparent `.ultraThinMaterial` background at screen bottom
- **Resizable overlay** — Small (500x200), Medium (700x260), Large (900x360)
- **Album art theming** — Vision-powered multi-color palette for dynamic overlay styling
- **Music controls** — play/pause/skip directly from the overlay
- **Track info header** — current track display in overlay
- **Menu bar app** — no dock icon, lives quietly in your menu bar
- **Always-on-top toggle** — float above all windows or stay behind them
- **Opacity control** — adjust overlay transparency from the menu bar
- **Locale-safe** — handles comma decimal separators (e.g. Indonesian locale)

## Requirements

- macOS 13 (Ventura) or later (macOS 26+ for translation features)
- Spotify desktop app installed
- Swift 5.9+ / Xcode Command Line Tools

## Installation

### Download (recommended)

Grab the latest `.dmg` from the [Releases](https://github.com/denyherianto/SpotifyLyrics/releases) page, open it, and drag SpotifyLyrics to Applications.

> **Note:** The app is unsigned. On first launch, right-click the app and select **Open**, or go to **System Settings > Privacy & Security > Open Anyway**.

### Build from source

```bash
git clone https://github.com/denyherianto/SpotifyLyrics.git
cd SpotifyLyrics
swift build -c release
```

### Run

```bash
./run.sh
# or manually:
swift build -c release && .build/release/SpotifyLyrics
```

On first launch, macOS will ask for **Automation permission** to control Spotify — allow it.

## Usage

1. **Start Spotify** and play a song
2. **Run Spotify Lyrics** — lyrics appear at the bottom of your screen
3. **Menu bar icon** (♪) gives you controls:
   - Show/Hide lyrics overlay
   - Always on Top toggle
   - Opacity slider
   - Current track info

### Scrolling

- **Auto-scroll**: lyrics follow the song automatically
- **Manual scroll**: use trackpad/mouse wheel to browse lyrics freely
- **Back to Current**: click the button to snap back to the playing line
- **Click a line**: seeks Spotify playback to that lyric's timestamp

## Architecture

```
SpotifyLyricsCore/                  # Library target
├── Models/
│   ├── TrackInfo.swift              # Track metadata + cache key
│   ├── LyricLine.swift              # Timestamp + text + word timings + fill calculation
│   ├── LyricWord.swift              # Word-level start/end timestamps
│   ├── LineEnrichment.swift         # Romanization + translation per line
│   ├── TranslationLanguage.swift    # 14+ supported languages enum
│   ├── AnimationMode.swift          # Karaoke / scroll modes
│   └── OverlaySize.swift            # Small / Medium / Large presets
├── Spotify/
│   ├── AppleScriptBridge.swift      # Spotify communication via AppleScript
│   ├── AccessibilityBridge.swift    # Spotify UI state via AX APIs
│   └── SpotifyPlayerManager.swift   # Polling + position interpolation
├── Lyrics/
│   ├── LRCParser.swift              # .lrc format parser (line + word tags)
│   ├── LRCLibProvider.swift         # Free synced lyrics API
│   ├── MusixmatchProvider.swift     # Fallback lyrics API (richsync support)
│   ├── SpeechRecognitionProvider.swift  # Fallback lyrics via Apple Speech
│   ├── LyricsManager.swift          # Provider orchestration + caching
│   └── Enrichment/
│       ├── EnrichmentCoordinator.swift      # Romanization + translation pipeline
│       ├── LyricsEnrichmentProvider.swift   # Provider protocol
│       ├── ICURomanizationProvider.swift    # CFStringTokenizer-based romanization
│       └── AppleTranslationProvider.swift   # Apple Translation framework (macOS 26+)
├── Analysis/
│   ├── SoundClassifier.swift        # SoundAnalysis mood/genre detection
│   ├── VisionAnalyzer.swift         # Vision palette + OCR + saliency
│   └── VocalActivityDetector.swift  # Vocal vs instrumental detection
└── Overlay/
    ├── LyricsOverlayWindow.swift    # NSPanel (transparent, floating)
    ├── LyricsOverlayView.swift      # Karaoke scroll view + controls
    └── LyricLineView.swift          # Per-word fill animation

App/                                # Executable target
├── SpotifyLyricsApp.swift           # @main, MenuBarExtra, Settings
├── StatusBarController.swift        # Menu bar integration
├── MenuBarView.swift                # Menu bar dropdown UI
└── DominantColorExtractor.swift     # Vision-backed color extraction

Tests/                              # Test runner
├── TestRunner.swift
├── LRCParserTests.swift
├── ParseNumberTests.swift
├── LyricsManagerTests.swift
└── ModelTests.swift
```

## Testing

```bash
swift run SpotifyLyricsTests
```

## How It Works

1. **AppleScript** polls Spotify every 500ms for track info and playback position, supplemented by **Accessibility APIs** for faster state detection
2. **Position interpolation** fills the gaps between polls using wall-clock time for smooth tracking
3. **LRCLIB API** fetches synced lyrics (`.lrc` format with timestamps), with Musixmatch as fallback
4. **Speech recognition** (Apple Speech framework) generates lyrics from audio when no online provider has results
5. **LRC parser** extracts `[mm:ss.xx] text` into timed lyric lines, including inline `<mm:ss.xx>word` tags for word-level timing
6. **Enrichment pipeline** detects language, adds romanization (phonetic readings), and translates lyrics on-device
7. **SoundAnalysis** classifies audio mood in real-time; **Vision** extracts multi-color palettes from album art
8. **SwiftUI overlay** scrolls to the current line with per-word karaoke fill animation
9. **NSPanel** renders the overlay as a floating, transparent, non-activating window

## Apple Frameworks Used

| Framework | Purpose |
|-----------|---------|
| **Speech** | Fallback lyrics generation via speech recognition |
| **SoundAnalysis** | Real-time audio mood/genre classification |
| **Vision** | Album art palette extraction, OCR, saliency detection |
| **CreateML** | Vocal activity detection infrastructure |
| **NaturalLanguage** | Language detection, tagging, and lyrics classification |
| **Translation** | On-device multi-language translation (macOS 26+) |
| **Accessibility** | Fast Spotify UI state reading via AX APIs |
| **AppKit** | Menu bar, window management, image processing |
| **SwiftUI** | UI rendering |
| **Core Foundation** | CFStringTokenizer for romanization |

## Musixmatch Setup (Optional)

LRCLIB works out of the box with no API key. For broader lyrics coverage, you can add a Musixmatch API key:

```bash
defaults write com.denyherianto.SpotifyLyrics musixmatchApiKey "YOUR_API_KEY"
```

## License

[MIT](LICENSE) — do whatever you want.
