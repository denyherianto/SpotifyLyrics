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

- **Karaoke-style synced lyrics** — current line highlighted, surrounding lines faded
- **Frosted glass overlay** — transparent `.ultraThinMaterial` background at screen bottom
- **Auto-scroll** — lyrics follow the music in real-time
- **Manual scroll** — scroll through lyrics freely, click "Back to Current" to resume
- **Click-to-seek** — click any lyric line to jump Spotify playback to that timestamp
- **Menu bar app** — no dock icon, lives quietly in your menu bar
- **Always-on-top toggle** — float above all windows or stay behind them
- **Opacity control** — adjust overlay transparency from the menu bar
- **Multiple lyrics sources** — LRCLIB (free, no API key) with Musixmatch fallback
- **Locale-safe** — handles comma decimal separators (e.g. Indonesian locale)

## Requirements

- macOS 13 (Ventura) or later
- Spotify desktop app installed
- Swift 5.9+ / Xcode Command Line Tools

## Installation

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
SpotifyLyricsCore/              # Library target
├── Models/
│   ├── TrackInfo.swift          # Track metadata
│   └── LyricLine.swift         # Timestamp + text
├── Spotify/
│   ├── AppleScriptBridge.swift  # Spotify communication via AppleScript
│   └── SpotifyPlayerManager.swift # Polling + position interpolation
├── Lyrics/
│   ├── LRCParser.swift          # .lrc format parser
│   ├── LRCLibProvider.swift     # Free synced lyrics API
│   ├── MusixmatchProvider.swift # Fallback lyrics API
│   └── LyricsManager.swift     # Provider orchestration + caching
└── Overlay/
    ├── LyricsOverlayWindow.swift # NSPanel (transparent, floating)
    ├── LyricsOverlayView.swift   # Karaoke scroll view
    └── LyricLineView.swift       # Individual line styling

App/                            # Executable target
├── SpotifyLyricsApp.swift       # @main, MenuBarExtra, AppDelegate
└── MenuBarView.swift            # Menu bar dropdown UI

Tests/                          # Test runner
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

1. **AppleScript** polls Spotify every 500ms for track info and playback position
2. **Position interpolation** fills the gaps between polls using wall-clock time for smooth tracking
3. **LRCLIB API** fetches synced lyrics (`.lrc` format with timestamps)
4. **LRC parser** extracts `[mm:ss.xx] text` into timed lyric lines
5. **SwiftUI overlay** scrolls to the current line with smooth animation
6. **NSPanel** renders the overlay as a floating, transparent, non-activating window

## Musixmatch Setup (Optional)

LRCLIB works out of the box with no API key. For broader lyrics coverage, you can add a Musixmatch API key:

```bash
defaults write com.denyherianto.SpotifyLyrics musixmatchApiKey "YOUR_API_KEY"
```

## License

[MIT](LICENSE) — do whatever you want.
