# SpotifyLyrics Improvement Plan — Phase 2

## Context

All Phase 1 features are complete: mini overlay, instrumental breaks, Foundation Model summaries, App Intents, and lyrics card sharing. This plan adds 10 new features across 4 milestones, continuing the zero-external-dependency, Apple-frameworks-only approach.

**Key architectural constraints:**
- No Spotify Web API — all data via AppleScript + Accessibility bridge (no queue, playlist, or library access)
- Custom test harness (`check()`/`checkEqual()`/`checkApprox()`), not XCTest
- `OverlayController` owns all persisted settings (UserDefaults via `didSet`)
- `AppState.shared` singleton for App Intents access
- `LyricsEnrichmentProvider` protocol for enrichment pipeline
- `#if canImport(FoundationModels)` / `@available(macOS 26, *)` gating for Apple AI features

**Existing infrastructure to reuse:**
- `VisionAnalyzer.ColorPalette` (dominant/accent/background) — computed but not wired to overlay theming
- `SoundClassifier.MusicMood` (with `themeHue`, `animationSpeed`) — computed but only displayed as label in MenuBarView
- `DominantColorExtractor` — used only for MenuBarView controls tint
- `EnrichmentCoordinator` — picks first provider per capability, detects source language
- `FoundationModelProvider` — established pattern: macOS 26+ guard, async + 10s timeout, in-memory cache
- `LyricsManager` lyrics cache keyed by `TrackInfo.cacheKey` (`"{artist}|{title}"` lowercased)

---

## Milestone 1: Sync & Polish (No AI, immediate value)

### 1.1 Sync Offset Adjustment

**Goal:** Manual ±ms slider to correct lyrics timing per track. Solves the #1 user complaint with third-party lyrics sources.

**Files to modify:**
- `Sources/SpotifyLyricsCore/Lyrics/LyricsManager.swift` — Apply offset to line matching
- `Sources/App/SpotifyLyricsApp.swift` — Add `syncOffset` to `OverlayController`, per-track persistence
- `Sources/App/MenuBarView.swift` — Offset slider + reset button in settings

**Implementation:**

1. **Add offset property to `OverlayController`:**
   ```swift
   @Published var syncOffset: Double = 0.0  // milliseconds, range -2000...+2000
   ```
   - Unlike other settings, this is per-track, not global
   - Persist to `UserDefaults` with key `"syncOffset_\(trackCacheKey)"` — read on track change
   - Add `func loadSyncOffset(for track: TrackInfo)` and `func resetSyncOffset()`

2. **Apply offset in `LyricsManager.updateCurrentLine(at:)`:**
   - Accept offset parameter: `public func updateCurrentLine(at position: TimeInterval, offset: TimeInterval = 0)`
   - Adjusted position: `let adjusted = position + (offset / 1000.0)` (offset is in ms, position in seconds)
   - Same adjustment in `updateInstrumentalBreak(at:offset:)`
   - This shifts which line is "current" without modifying the underlying `LyricLine` timestamps

3. **Wire in `AppDelegate`'s 100ms timer:**
   - Pass `overlayController.syncOffset` to both `updateCurrentLine` and `updateInstrumentalBreak`

4. **MenuBarView UI:**
   ```swift
   // Inside settings section, below Animation picker
   VStack(alignment: .leading, spacing: 4) {
       HStack {
           Text("Sync Offset")
           Spacer()
           Text("\(Int(overlayController.syncOffset))ms")
               .monospacedDigit()
           Button("Reset") { overlayController.resetSyncOffset() }
               .buttonStyle(.plain)
               .opacity(overlayController.syncOffset != 0 ? 1 : 0.3)
       }
       Slider(value: $overlayController.syncOffset, in: -2000...2000, step: 50)
   }
   ```
   - Keyboard shortcuts: `Cmd+[` = -50ms, `Cmd+]` = +50ms for quick adjustment during playback

5. **Per-track persistence strategy:**
   - On track change (`onTrackChanged`), save current offset for old track, load offset for new track
   - Default to 0.0 if no saved offset for a track
   - `resetSyncOffset()` sets to 0 and removes the UserDefaults key

**Tests (`SyncOffsetTests.swift`):**
- Verify `updateCurrentLine` with positive offset selects later line
- Verify negative offset selects earlier line
- Verify zero offset matches baseline behavior
- Verify per-track key format

---

### 1.2 Multi-Display Awareness

**Goal:** Remember overlay position per display configuration. Auto-relocate overlay when displays connect/disconnect.

**Files to modify:**
- `Sources/SpotifyLyricsCore/Overlay/LyricsOverlayWindow.swift` — Display-aware positioning
- `Sources/App/SpotifyLyricsApp.swift` — Monitor display changes, persist positions

**Files to create:**
- `Sources/SpotifyLyricsCore/Overlay/DisplayPositionManager.swift` — Display config tracking + position persistence

**Implementation:**

1. **Create `DisplayPositionManager`:**
   ```swift
   @MainActor public final class DisplayPositionManager {
       /// Key: display configuration hash (sorted display IDs + resolutions)
       /// Value: saved window origin (CGPoint)
       private var positions: [String: CGPoint] = [:]

       public var currentConfigKey: String  // computed from NSScreen.screens

       public func savePosition(_ origin: CGPoint)
       public func loadPosition() -> CGPoint?
       public func configurationKey(for screens: [NSScreen]) -> String
   }
   ```
   - Configuration key: sort screens by `NSScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]`, hash as `"{id}_{w}x{h}"` joined by `+`
   - Example: `"1_2560x1440+2_1920x1080"` for a dual-monitor setup
   - Persist entire positions dictionary to UserDefaults key `"overlayPositions"`

2. **Monitor display changes in `AppDelegate`:**
   ```swift
   NotificationCenter.default.addObserver(
       forName: NSApplication.didChangeScreenParametersNotification,
       object: nil, queue: .main
   ) { [weak self] _ in
       self?.handleDisplayChange()
   }
   ```
   - `handleDisplayChange()`:
     1. Save current position under old config key
     2. Recompute config key
     3. If saved position exists for new config → move window there
     4. If no saved position → center on primary screen (current default behavior)
     5. Validate that restored position is within visible screen bounds (display may have been removed)

3. **Save on window move:**
   - `LyricsOverlayWindow` already supports `isMovableByWindowBackground`
   - Add `NSWindow.didMoveNotification` observer → `displayPositionManager.savePosition(frame.origin)`
   - Debounce saves (300ms) to avoid excessive writes during drag

4. **Bounds validation:**
   ```swift
   func clampToVisibleScreens(_ origin: CGPoint, windowSize: CGSize) -> CGPoint
   ```
   - Ensure at least 50px of the window is visible on some screen
   - If fully offscreen, reset to center of primary screen

**Tests (`DisplayPositionTests.swift`):**
- Verify configuration key generation with mock screen data
- Verify position save/load round-trip
- Verify bounds clamping when position is offscreen
- Verify different configs produce different keys

---

## Milestone 2: Apple Intelligence (macOS 26+)

### 2.1 Mood-Adaptive Overlay Theming

**Goal:** Analyze lyrics sentiment per section and shift overlay colors/animation intensity in real-time. Foundation Models classifies mood → maps to color temperature and animation speed.

**Files to create:**
- `Sources/SpotifyLyricsCore/Lyrics/Enrichment/MoodAnalyzer.swift` — Per-section mood classification

**Files to modify:**
- `Sources/SpotifyLyricsCore/Lyrics/LyricsManager.swift` — Expose `currentMood` based on active section
- `Sources/SpotifyLyricsCore/Overlay/LyricsOverlayView.swift` — Apply mood-driven color/animation
- `Sources/SpotifyLyricsCore/Overlay/MiniOverlayView.swift` — Apply mood tint in mini mode
- `Sources/App/SpotifyLyricsApp.swift` — Add `moodTheming` toggle to `OverlayController`
- `Sources/App/MenuBarView.swift` — Toggle for mood theming

**Implementation:**

1. **Create `MoodAnalyzer`:**
   ```swift
   #if canImport(FoundationModels)
   import FoundationModels

   public enum LyricsMood: String, Sendable, CaseIterable {
       case joyful, melancholic, energetic, romantic, aggressive, reflective, neutral
       
       public var colorTemperature: Double    // 0.0 (cool/blue) to 1.0 (warm/orange)
       public var animationIntensity: Double  // 0.3 (slow/gentle) to 1.0 (fast/dynamic)
       public var accentHue: Double           // hue angle 0-360 for accent overlay
   }

   @available(macOS 26, *)
   @MainActor public final class MoodAnalyzer {
       /// Analyzes lyrics in chunks of ~8 lines, returns mood per chunk
       public func analyzeSections(_ lines: [String], title: String, artist: String) async throws -> [Range<Int>: LyricsMood]
   }
   ```
   - Prompt strategy: send all lyrics with line numbers, ask model to classify sections:
     ```
     Classify the mood of each section of these lyrics. Output JSON array of {startLine, endLine, mood}.
     Valid moods: joyful, melancholic, energetic, romantic, aggressive, reflective, neutral.
     ```
   - Use `@Generable` struct for structured output if available, otherwise parse JSON response
   - Cache result per `TrackInfo.cacheKey` (mood doesn't change per song)
   - Timeout: 15s (more complex than summary), fallback to `.neutral` for all sections
   - Chunk lyrics into ~8-line sections by gaps/repetition for prompt efficiency

2. **Expose in `LyricsManager`:**
   ```swift
   @Published public var sectionMoods: [Range<Int>: LyricsMood] = [:]
   @Published public var currentMood: LyricsMood = .neutral
   ```
   - After lyrics fetch, if mood theming enabled:
     ```swift
     if #available(macOS 26, *) {
         Task { sectionMoods = try? await moodAnalyzer.analyzeSections(...) }
     }
     ```
   - In `updateCurrentLine`, look up `currentLineIndex` in `sectionMoods` ranges → update `currentMood`

3. **Apply mood to overlay theming:**
   - `LyricsOverlayView` and `MiniOverlayView` read `lyricsManager.currentMood`
   - Color blending: interpolate between `DominantColorExtractor.dominantColor` and `mood.accentHue` (70/30 mix — album art still dominates)
   - Animation speed: multiply `AnimationMode.transition` duration by `1.0 / mood.animationIntensity`
   - Background material: shift warm/cool by adjusting overlay gradient hue
   - Transitions between moods: 2s ease-in-out animation to avoid jarring shifts

4. **Settings:**
   - `OverlayController.moodTheming: Bool` (UserDefaults `"moodTheming"`, default: true on macOS 26+)
   - MenuBarView: "Mood Theming" toggle (below AI Summary toggle, same section)

5. **Fallback on macOS < 26:** Feature hidden entirely. `LyricsMood.neutral` is the default, producing no visual change.

**Tests (`MoodAnalyzerTests.swift`):**
- Verify `LyricsMood` color/animation properties are in valid ranges
- Verify section lookup returns correct mood for given line index
- Verify cache hit on second call with same cacheKey
- Verify fallback to `.neutral` on timeout/error

---

### 2.2 Sing-Along Pronunciation Guide

**Goal:** For non-native language songs, generate phonetic pronunciation hints beyond romanization — actual pronunciation coaching with stress markers.

**Files to create:**
- `Sources/SpotifyLyricsCore/Lyrics/Enrichment/PronunciationProvider.swift` — Foundation Models pronunciation generator

**Files to modify:**
- `Sources/SpotifyLyricsCore/Models/LineEnrichment.swift` — Add `pronunciation` field
- `Sources/SpotifyLyricsCore/Lyrics/Enrichment/EnrichmentCoordinator.swift` — Add pronunciation capability
- `Sources/SpotifyLyricsCore/Lyrics/Enrichment/LyricsEnrichmentProvider.swift` — Add `.pronunciation` capability
- `Sources/SpotifyLyricsCore/Overlay/LyricLineView.swift` — Display pronunciation line
- `Sources/SpotifyLyricsCore/Overlay/MiniOverlayView.swift` — Show pronunciation in mini mode
- `Sources/App/SpotifyLyricsApp.swift` — Add `showPronunciation` toggle
- `Sources/App/MenuBarView.swift` — Pronunciation toggle

**Implementation:**

1. **Extend `LineEnrichment`:**
   ```swift
   public struct LineEnrichment: Equatable {
       public var romanization: String?
       public var translation: String?
       public var pronunciation: String?   // NEW: phonetic guide with stress markers
       public var isEmpty: Bool { romanization == nil && translation == nil && pronunciation == nil }
   }
   ```

2. **Extend `EnrichmentCapabilities`:**
   ```swift
   public struct EnrichmentCapabilities: OptionSet, Sendable {
       public static let romanization  = EnrichmentCapabilities(rawValue: 1 << 0)
       public static let translation   = EnrichmentCapabilities(rawValue: 1 << 1)
       public static let pronunciation = EnrichmentCapabilities(rawValue: 1 << 2)  // NEW
   }
   ```

3. **Add protocol method with default implementation:**
   ```swift
   protocol LyricsEnrichmentProvider: Sendable {
       // ... existing ...
       func pronounce(_ lines: [String], from sourceLanguage: String?) async throws -> [String?]
   }
   // Default: return Array(repeating: nil, count: lines.count)
   ```

4. **Create `PronunciationProvider`:**
   ```swift
   #if canImport(FoundationModels)
   @available(macOS 26, *)
   public struct PronunciationProvider: LyricsEnrichmentProvider {
       public var capabilities: EnrichmentCapabilities { .pronunciation }
       
       public func pronounce(_ lines: [String], from sourceLanguage: String?) async throws -> [String?] {
           // Use LanguageModelSession with prompt:
           // "For each line of {language} lyrics, provide an English phonetic pronunciation guide.
           //  Use syllable breaks with hyphens, CAPS for stressed syllables.
           //  Example: 'こんにちは' → 'kon-ni-chi-WAH'
           //  Return one pronunciation per line, same order."
       }
   }
   #endif
   ```
   - Process in batches of 20 lines to stay within model context
   - Skip lines that are already in the user's native script (detect via `NLLanguageRecognizer`)
   - Cache alongside other enrichments using the same compound key pattern

5. **Wire into `EnrichmentCoordinator`:**
   - Add `pronunciationProvider` alongside existing providers
   - In enrichment flow, after romanization and translation, run pronunciation if capability available and `showPronunciation` is true
   - Store results in `enrichment[index].pronunciation`

6. **Display in `LyricLineView`:**
   ```swift
   // Below romanization, above translation (reading order: original → how to say it → what it means)
   if let pronunciation = enrichment?.pronunciation {
       Text(pronunciation)
           .font(.system(size: fontSize * 0.7, weight: .medium, design: .monospaced))
           .foregroundStyle(.white.opacity(0.6))
   }
   ```

7. **Settings:**
   - `OverlayController.showPronunciation: Bool` (UserDefaults `"showPronunciation"`, default: false)
   - Combine sink in `AppDelegate` → sets `lyricsManager.showPronunciation` → triggers `scheduleEnrichmentRefresh()`
   - MenuBarView: "Pronunciation" toggle (between Romanization and Translation)

**Tests (`PronunciationTests.swift`):**
- Verify `.pronunciation` capability bit is distinct from others
- Verify `LineEnrichment.isEmpty` accounts for pronunciation field
- Verify provider skips Latin-script lines
- Verify enrichment cache key includes pronunciation flag

---

### 2.3 Smart Lyrics Search (Foundation Models)

**Goal:** "What was that song about driving at night?" — search cached lyrics by theme/content using semantic understanding.

**Files to create:**
- `Sources/SpotifyLyricsCore/Lyrics/LyricsSearchEngine.swift` — Search index + Foundation Models semantic matching

**Files to modify:**
- `Sources/SpotifyLyricsCore/Lyrics/LyricsManager.swift` — Persist lyrics to searchable cache
- `Sources/App/MenuBarView.swift` — Search UI in menu bar popover
- `Sources/App/SpotifyLyricsApp.swift` — Wire search engine, add search intent

**Files to create (intent):**
- `Sources/App/Intents/SearchLyricsIntent.swift` — Siri "Find that song about..."

**Implementation:**

1. **Create `LyricsSearchEngine`:**
   ```swift
   @MainActor public final class LyricsSearchEngine: ObservableObject {
       /// In-memory index: cacheKey → (track: TrackInfo, lyrics: String, summary: String?)
       @Published public var searchResults: [(track: TrackInfo, matchLine: String, score: Double)] = []
       @Published public var isSearching = false
       
       private var index: [String: SearchEntry] = [:]
       
       struct SearchEntry: Codable {
           let title: String
           let artist: String
           let lyricsText: String       // all lines joined
           let summary: String?         // from FoundationModelProvider if available
           let lastPlayed: Date
       }
       
       public func indexTrack(_ track: TrackInfo, lines: [LyricLine], summary: String?)
       public func search(query: String) async -> [(track: TrackInfo, matchLine: String, score: Double)]
       
       // Persistence
       private func saveToDisk()
       private func loadFromDisk()
   }
   ```

2. **Two-tier search strategy:**
   - **Tier 1 — Keyword search (instant, no AI):** `String.localizedCaseInsensitiveContains` on lyrics text and track metadata. Always runs first for immediate results.
   - **Tier 2 — Semantic search (macOS 26+, async):**
     ```swift
     #if canImport(FoundationModels)
     @available(macOS 26, *)
     func semanticSearch(query: String, candidates: [SearchEntry]) async throws -> [ScoredResult] {
         // Prompt: "Given the search query '{query}', rank these songs by relevance.
         //  Return indices of matching songs with confidence 0-1.
         //  Songs: {numbered list of title - artist: first 4 lines}"
     }
     #endif
     ```
   - Merge results: keyword matches get score boost (+0.3), semantic matches scored by model confidence
   - Limit semantic search to 50 most recent entries to stay within prompt limits

3. **Index persistence:**
   - Store in `~/Library/Application Support/SpotifyLyrics/lyrics_index.json`
   - Updated each time `LyricsManager.fetchLyrics` succeeds: `searchEngine.indexTrack(track, lines, summary)`
   - Capped at 500 entries (LRU eviction by `lastPlayed`)
   - Load on app launch

4. **Search UI in `MenuBarView`:**
   ```swift
   // Above the mini player section
   if isSearchExpanded {
       VStack(spacing: 8) {
           TextField("Search lyrics...", text: $searchQuery)
               .textFieldStyle(.roundedBorder)
               .onSubmit { Task { await searchEngine.search(query: searchQuery) } }
           
           ForEach(searchEngine.searchResults.prefix(5), id: \.track.cacheKey) { result in
               VStack(alignment: .leading) {
                   Text(result.track.title).font(.caption.bold())
                   Text("\"\(result.matchLine)\"").font(.caption2).foregroundStyle(.secondary)
               }
               .onTapGesture { /* open Spotify to this track via AppleScript */ }
           }
       }
   }
   ```
   - Toggle search with magnifying glass icon button
   - Keyboard shortcut: `Cmd+F` when menu bar popover is open

5. **`SearchLyricsIntent`:**
   ```swift
   struct SearchLyricsIntent: AppIntent {
       static var title: LocalizedStringResource = "Find Song by Lyrics"
       @Parameter(title: "Query") var query: String
       
       func perform() async throws -> some IntentResult & ReturnsValue<String> {
           let results = await AppState.shared.searchEngine?.search(query: query) ?? []
           guard let top = results.first else { return .result(value: "No matching songs found.") }
           return .result(value: "\(top.track.title) by \(top.track.artist)")
       }
   }
   ```
   - Add to `SpotifyLyricsShortcuts`: `AppShortcut(intent: SearchLyricsIntent(), phrases: ["Find song about \(\.$query) in \(.applicationName)"])`

**Tests (`LyricsSearchTests.swift`):**
- Verify keyword search finds exact text matches
- Verify indexing and retrieval round-trip
- Verify LRU eviction at 500 entries
- Verify empty query returns empty results
- Verify search result scoring (keyword match > no match)

---

### 2.4 Writing Kit Integration (macOS 26+)

**Goal:** When sharing lyrics cards or exporting lyrics, use Writing Kit to offer tone adjustments for captions.

**Files to modify:**
- `Sources/SpotifyLyricsCore/Sharing/LyricsCardView.swift` — Add caption field with Writing Kit
- `Sources/SpotifyLyricsCore/Sharing/LyricsCardGenerator.swift` — Include user caption in card
- `Sources/SpotifyLyricsCore/Overlay/LyricsOverlayView.swift` — Caption editing in card preview

**Implementation:**

1. **Add caption to card generation:**
   ```swift
   // LyricsCardGenerator
   public func generateCard(
       line: LyricLine,
       enrichment: LineEnrichment?,
       track: TrackInfo,
       artworkURL: URL?,
       palette: (dominant: Color, accent: Color)?,
       caption: String? = nil   // NEW
   ) async -> NSImage
   ```

2. **Update `LyricsCardView`:**
   ```swift
   // Below the credit line, if caption is provided
   if let caption {
       Text(caption)
           .font(.system(size: 14, weight: .regular, design: .rounded))
           .foregroundStyle(.white.opacity(0.7))
           .multilineTextAlignment(.center)
           .padding(.horizontal, 40)
   }
   ```

3. **Caption editor with Writing Kit in card preview:**
   ```swift
   #if canImport(WritingTools)
   // In the card preview popover (LyricsOverlayView)
   @available(macOS 26, *)
   TextField("Add a caption...", text: $caption)
       .writingToolsBehavior(.complete)  // enables Writing Kit suggestions
       // Writing Kit will offer: "Make Professional", "Make Friendly", "Make Concise"
   #endif
   ```
   - On macOS < 26: plain `TextField` without Writing Kit
   - Pre-fill caption with `"\(track.title) — \(track.artist)"`

4. **Export with caption:**
   - "Copy to Clipboard" and "Save as PNG" include the caption in the rendered card
   - "Copy Text" option: copies just the lyric text + caption as plain text

**Tests (`WritingKitTests.swift`):**
- Verify card generator includes caption text when provided
- Verify card generator omits caption area when nil
- Verify card dimensions unchanged when caption is nil

---

## Milestone 3: Engagement & Personalization

### 3.1 Lyric Line Bookmarks

**Goal:** Tap a heart on any line to save it to a personal collection with song context. View favorites in menu bar.

**Files to create:**
- `Sources/SpotifyLyricsCore/Sharing/BookmarkManager.swift` — Bookmark storage + management
- `Sources/SpotifyLyricsCore/Sharing/BookmarksListView.swift` — Favorites list SwiftUI view

**Files to modify:**
- `Sources/SpotifyLyricsCore/Overlay/LyricLineView.swift` — Add bookmark button on hover/right-click
- `Sources/App/MenuBarView.swift` — Bookmarks section with list
- `Sources/App/SpotifyLyricsApp.swift` — Instantiate `BookmarkManager`, expose via `AppState`

**Implementation:**

1. **Create `BookmarkManager`:**
   ```swift
   @MainActor public final class BookmarkManager: ObservableObject {
       public struct Bookmark: Identifiable, Codable, Equatable {
           public let id: UUID
           public let lineText: String
           public let romanization: String?
           public let translation: String?
           public let trackTitle: String
           public let trackArtist: String
           public let trackCacheKey: String
           public let timestamp: TimeInterval    // position in song
           public let createdAt: Date
       }
       
       @Published public var bookmarks: [Bookmark] = []
       
       public func toggle(line: LyricLine, enrichment: LineEnrichment?, track: TrackInfo) -> Bool
       public func isBookmarked(lineText: String, trackCacheKey: String) -> Bool
       public func remove(id: UUID)
       public func removeAll(for trackCacheKey: String)
       
       // Persistence
       private let fileURL: URL  // ~/Library/Application Support/SpotifyLyrics/bookmarks.json
       private func save()
       private func load()
   }
   ```
   - `toggle()` returns `true` if bookmark was added, `false` if removed
   - Bookmarks sorted by `createdAt` descending (newest first)
   - Capped at 1000 bookmarks (no eviction — manual removal only, warn at limit)

2. **Bookmark button on `LyricLineView`:**
   ```swift
   // Shown on hover, right side of line
   .overlay(alignment: .trailing) {
       if isHovering {
           Button(action: { toggleBookmark() }) {
               Image(systemName: isBookmarked ? "heart.fill" : "heart")
                   .foregroundStyle(isBookmarked ? .red : .white.opacity(0.5))
                   .font(.system(size: 12))
           }
           .buttonStyle(.plain)
           .transition(.opacity)
       }
   }
   ```
   - Also add to existing right-click context menu: "Bookmark Line" / "Remove Bookmark"

3. **Bookmarks in `MenuBarView`:**
   ```swift
   // New collapsible section below settings
   DisclosureGroup("Favorites (\(bookmarkManager.bookmarks.count))", isExpanded: $isBookmarksExpanded) {
       if bookmarkManager.bookmarks.isEmpty {
           Text("No bookmarked lyrics yet")
               .font(.caption)
               .foregroundStyle(.secondary)
       } else {
           ForEach(bookmarkManager.bookmarks.prefix(20)) { bookmark in
               VStack(alignment: .leading, spacing: 2) {
                   Text("\"\(bookmark.lineText)\"")
                       .font(.caption)
                       .lineLimit(2)
                   Text("\(bookmark.trackTitle) — \(bookmark.trackArtist)")
                       .font(.caption2)
                       .foregroundStyle(.secondary)
               }
               .contextMenu {
                   Button("Copy Line") { /* copy to pasteboard */ }
                   Button("Share as Card") { /* trigger card generator */ }
                   Button("Remove") { bookmarkManager.remove(id: bookmark.id) }
               }
           }
       }
   }
   ```

4. **App Intent — `GetBookmarksIntent`:**
   ```swift
   struct GetBookmarksIntent: AppIntent {
       static var title: LocalizedStringResource = "My Favorite Lyrics"
       @Parameter(title: "Count") var count: Int?
       
       func perform() async throws -> some IntentResult & ReturnsValue<String> {
           let bookmarks = AppState.shared.bookmarkManager?.bookmarks.prefix(count ?? 5) ?? []
           let text = bookmarks.map { "\"\($0.lineText)\" — \($0.trackTitle)" }.joined(separator: "\n")
           return .result(value: text.isEmpty ? "No bookmarks yet." : text)
       }
   }
   ```

5. **Mini mode:** No bookmark button (no line list), but add "Bookmark Current Line" to right-click context menu and as menu bar action.

**Tests (`BookmarkTests.swift`):**
- Verify add/remove toggle behavior
- Verify `isBookmarked` lookup
- Verify persistence save/load round-trip
- Verify cap at 1000 bookmarks
- Verify `removeAll(for:)` only removes matching track

---

### 3.2 Listening Stats Dashboard

**Goal:** Track which songs had lyrics viewed, languages translated, time with overlay active. Fun data for the user.

**Files to create:**
- `Sources/SpotifyLyricsCore/Models/ListeningStats.swift` — Stats model + persistence
- `Sources/App/StatsView.swift` — Stats dashboard view (popover or sheet)

**Files to modify:**
- `Sources/App/SpotifyLyricsApp.swift` — Track events, instantiate stats manager
- `Sources/App/MenuBarView.swift` — "My Stats" button to show dashboard

**Implementation:**

1. **Create `ListeningStats`:**
   ```swift
   @MainActor public final class ListeningStats: ObservableObject {
       public struct Stats: Codable {
           var totalOverlayTime: TimeInterval = 0          // seconds with overlay visible
           var songsWithLyrics: Int = 0                     // unique tracks with lyrics loaded
           var totalLinesViewed: Int = 0                    // lines scrolled through
           var translationsUsed: [String: Int] = [:]        // language code → count
           var topTracks: [TrackStat] = []                  // tracks with most overlay time
           var firstUsed: Date = Date()
           var lastUsed: Date = Date()
           var cardsGenerated: Int = 0
           var bookmarksCreated: Int = 0
       }
       
       public struct TrackStat: Codable, Identifiable {
           public var id: String { cacheKey }
           let cacheKey: String
           let title: String
           let artist: String
           var overlaySeconds: TimeInterval
           var timesPlayed: Int
       }
       
       @Published public var stats = Stats()
       
       // Event tracking
       public func recordOverlayTick()              // called every second when overlay is visible
       public func recordTrackWithLyrics(_ track: TrackInfo)
       public func recordLineViewed()
       public func recordTranslation(language: String)
       public func recordCardGenerated()
       public func recordBookmarkCreated()
       
       // Persistence
       private let fileURL: URL  // ~/Library/Application Support/SpotifyLyrics/stats.json
       private func save()       // debounced, every 30 seconds
   }
   ```

2. **Event tracking in `AppDelegate`:**
   - In the 100ms position timer: every ~1 second (every 10th tick), if overlay is visible → `stats.recordOverlayTick()`
   - On `onTrackChanged` when lyrics load successfully → `stats.recordTrackWithLyrics(track)`
   - On `currentLineIndex` change → `stats.recordLineViewed()`
   - On translation toggle → `stats.recordTranslation(language:)`
   - Wire card generation and bookmark creation events

3. **`StatsView`:**
   ```swift
   struct StatsView: View {
       @ObservedObject var stats: ListeningStats
       
       var body: some View {
           VStack(alignment: .leading, spacing: 12) {
               // Header
               Text("Your Lyrics Stats")
                   .font(.headline)
               
               // Key metrics (grid)
               LazyVGrid(columns: [.init(), .init()], spacing: 8) {
                   StatCard(label: "Time with Lyrics", value: formatDuration(stats.stats.totalOverlayTime))
                   StatCard(label: "Songs", value: "\(stats.stats.songsWithLyrics)")
                   StatCard(label: "Lines Viewed", value: "\(stats.stats.totalLinesViewed)")
                   StatCard(label: "Cards Created", value: "\(stats.stats.cardsGenerated)")
               }
               
               // Top translated languages
               if !stats.stats.translationsUsed.isEmpty {
                   Text("Top Languages")
                       .font(.subheadline.bold())
                   ForEach(sortedLanguages.prefix(3), id: \.key) { lang, count in
                       HStack {
                           Text(Locale.current.localizedString(forLanguageCode: lang) ?? lang)
                           Spacer()
                           Text("\(count) songs")
                               .foregroundStyle(.secondary)
                       }
                       .font(.caption)
                   }
               }
               
               // Top tracks
               if !stats.stats.topTracks.isEmpty {
                   Text("Most Viewed")
                       .font(.subheadline.bold())
                   ForEach(stats.stats.topTracks.prefix(5)) { track in
                       HStack {
                           VStack(alignment: .leading) {
                               Text(track.title).font(.caption.bold())
                               Text(track.artist).font(.caption2).foregroundStyle(.secondary)
                           }
                           Spacer()
                           Text(formatDuration(track.overlaySeconds))
                               .font(.caption2)
                               .foregroundStyle(.secondary)
                       }
                   }
               }
               
               // Member since
               Text("Using SpotifyLyrics since \(stats.stats.firstUsed, style: .date)")
                   .font(.caption2)
                   .foregroundStyle(.tertiary)
           }
           .padding()
           .frame(width: 280)
       }
   }
   ```

4. **Menu bar access:**
   ```swift
   // In MenuBarView, below settings section
   Button(action: { showStats.toggle() }) {
       Label("My Stats", systemImage: "chart.bar")
   }
   .popover(isPresented: $showStats) {
       StatsView(stats: listeningStats)
   }
   ```

**Tests (`ListeningStatsTests.swift`):**
- Verify counter increments
- Verify top tracks sorting by overlay time
- Verify persistence round-trip
- Verify debounced save doesn't lose data

---

## Milestone 4: Playback Intelligence

### 4.1 Spotify Queue-Aware Prefetch

**Goal:** Prefetch lyrics + enrichment for upcoming songs to eliminate loading delay on track change.

**Architectural note:** Spotify's AppleScript/Accessibility APIs expose no queue data. We use a predictive approach instead.

**Files to create:**
- `Sources/SpotifyLyricsCore/Lyrics/LyricsPrefetcher.swift` — Predictive prefetch engine

**Files to modify:**
- `Sources/SpotifyLyricsCore/Lyrics/LyricsManager.swift` — Expose prefetch cache, accept prefetched results
- `Sources/SpotifyLyricsCore/Spotify/AppleScriptBridge.swift` — Attempt queue read (best-effort)
- `Sources/App/SpotifyLyricsApp.swift` — Wire prefetcher into track change flow

**Implementation:**

1. **Attempt Spotify queue access (best-effort):**
   ```swift
   // AppleScriptBridge — add method
   public func getNextTrack() -> (title: String, artist: String)? {
       // Try: tell application "Spotify" to get name of next track
       // This is undocumented and may not work — return nil if it fails
       // Fallback: no queue data available
   }
   ```
   - Spotify's AppleScript dictionary doesn't officially expose queue
   - This is a best-effort attempt — the prefetcher works without it

2. **Create `LyricsPrefetcher`:**
   ```swift
   @MainActor public final class LyricsPrefetcher {
       /// Cache of prefetched lyrics: cacheKey → [LyricLine]
       private var cache: [String: [LyricLine]] = [:]
       private var enrichmentCache: [String: [Int: LineEnrichment]] = [:]
       private var inFlight: Set<String> = []
       
       /// Strategy 1: Queue-based (if Spotify provides next track)
       public func prefetchFromQueue(nextTrack: TrackInfo) async
       
       /// Strategy 2: Album-based (fetch lyrics for next track number on same album)
       public func prefetchAlbumNext(currentTrack: TrackInfo, trackNumber: Int?) async
       
       /// Strategy 3: History-based (if user often plays A then B, prefetch B)
       public func prefetchFromHistory(currentTrack: TrackInfo) async
       
       /// Check cache before hitting network
       public func getCached(for track: TrackInfo) -> [LyricLine]?
       public func getCachedEnrichment(for track: TrackInfo) -> [Int: LineEnrichment]?
       
       /// Evict old entries (keep max 5 prefetched tracks)
       private func evictIfNeeded()
   }
   ```

3. **Prefetch trigger points:**
   - When current track reaches 75% played duration → trigger prefetch
   - On track change → check prefetch cache before network fetch
   - Background priority: `Task(priority: .utility)` to avoid impacting UI

4. **History-based prediction:**
   ```swift
   /// Track transition history: "played A, then B" pattern
   private var transitionHistory: [String: [String: Int]] = [:]  // fromCacheKey → [toCacheKey: count]
   ```
   - Record each track transition in `onTrackChanged`
   - Predict next track = most frequent successor of current track
   - Persist to `~/Library/Application Support/SpotifyLyrics/transitions.json`
   - Only predict with confidence ≥ 3 occurrences

5. **Wire into `LyricsManager`:**
   ```swift
   public func fetchLyrics(for track: TrackInfo, prefetcher: LyricsPrefetcher? = nil) async {
       // Check prefetch cache first
       if let cached = prefetcher?.getCached(for: track) {
           self.currentLines = cached
           self.hasLyrics = true
           // Also load cached enrichment if available
           if let enrichment = prefetcher?.getCachedEnrichment(for: track) {
               self.enrichment = enrichment
           }
           return
       }
       // ... existing fetch logic ...
   }
   ```

6. **No UI toggle needed** — prefetch is transparent, always on. Zero user-facing change except faster lyrics on track switch.

**Tests (`PrefetchTests.swift`):**
- Verify cache hit returns lyrics without network call
- Verify cache miss falls through to normal fetch
- Verify eviction keeps max 5 entries
- Verify history-based prediction with mock transition data
- Verify 75% trigger point calculation

---

### 4.2 Control Center Widget (macOS 26+)

**Goal:** Show current lyric line in macOS Control Center as a widget.

**Files to create:**
- `Sources/App/Widgets/LyricsControlWidget.swift` — ControlCenter widget definition

**Files to modify:**
- `Sources/App/SpotifyLyricsApp.swift` — Register widget extension
- `Package.swift` — May need widget extension target (if separate process)

**Implementation:**

1. **Evaluate architecture:**
   - macOS 26 introduces `ControlCenterWidget` (similar to iOS Control Center controls)
   - If available as in-process widget (like `AppIntentsExtension`), implement directly
   - If requires extension target, add to `Package.swift`:
     ```swift
     .executableTarget(
         name: "SpotifyLyricsWidget",
         dependencies: ["SpotifyLyricsCore"],
         path: "Sources/Widget"
     )
     ```

2. **Create `LyricsControlWidget`:**
   ```swift
   #if canImport(WidgetKit)
   import WidgetKit
   import SwiftUI

   @available(macOS 26, *)
   struct LyricsControlWidget: ControlWidget {
       var body: some ControlWidgetConfiguration {
           StaticControlConfiguration(kind: "com.spotifylyrics.currentLine") {
               ControlWidgetLabel {
                   // Current lyric line text (truncated)
                   // Tapping opens/toggles the overlay
               }
           }
           .displayName("Current Lyric")
           .description("Shows the current lyric line")
       }
   }
   #endif
   ```

3. **Data sharing between app and widget:**
   - Use `UserDefaults(suiteName: "group.spotifylyrics")` (App Group) to share current line text
   - In `AppDelegate`'s 100ms timer, when line changes:
     ```swift
     sharedDefaults?.set(currentLine.text, forKey: "currentLyricLine")
     sharedDefaults?.set("\(track.title) — \(track.artist)", forKey: "currentTrack")
     ControlCenter.shared.reloadControls(ofKind: "com.spotifylyrics.currentLine")
     ```
   - Throttle `reloadControls` to once per line change (not every 100ms)

4. **Widget interactions:**
   - Tap: toggle overlay visibility (via `ShowLyricsIntent` — reuse existing intent)
   - Long press: open app / show menu bar popover

5. **Fallback:** Feature only available on macOS 26+. No widget on earlier versions.

**Tests (`ControlWidgetTests.swift`):**
- Verify shared UserDefaults write/read for current line
- Verify throttle logic (only updates on line change)
- Verify nil handling when no track is playing

---

## Milestone 5: Overlay Customization & Visual Polish

### 5.1 Overlay Themes / Skins

**Goal:** Predefined visual themes that bundle background style, font, color treatment, and animation together. One-tap personality for the overlay.

**Files to create:**
- `Sources/SpotifyLyricsCore/Models/OverlayTheme.swift` — Theme model with presets
- `Sources/SpotifyLyricsCore/Overlay/ThemedOverlayModifier.swift` — ViewModifier applying theme

**Files to modify:**
- `Sources/SpotifyLyricsCore/Overlay/LyricsOverlayView.swift` — Apply active theme
- `Sources/SpotifyLyricsCore/Overlay/MiniOverlayView.swift` — Apply active theme
- `Sources/App/SpotifyLyricsApp.swift` — Add `overlayTheme` to `OverlayController`
- `Sources/App/MenuBarView.swift` — Theme picker in settings

**Implementation:**

1. **Define `OverlayTheme`:**
   ```swift
   public enum OverlayTheme: String, CaseIterable, Codable {
       case classic         // current default: dark material + white text
       case glassmorphism   // frosted glass, blurred background, translucent borders
       case neon            // dark background, glowing text with color-matched neon outline
       case minimal         // no background, just floating text with subtle shadow
       case paper           // warm off-white background, dark serif text, print aesthetic
       case vinyl           // dark with grooved circular texture, retro feel
       
       public var backgroundStyle: ThemeBackground    // material, color, gradient, or none
       public var fontDesign: Font.Design              // .default, .serif, .rounded, .monospaced
       public var fontWeight: Font.Weight
       public var textColor: Color                     // primary text color (overridden by mood if enabled)
       public var usesAlbumArtTint: Bool               // whether album colors bleed into background
       public var cornerRadius: CGFloat
       public var displayName: String
   }
   
   public enum ThemeBackground {
       case material(NSVisualEffectView.Material)
       case solidColor(Color)
       case gradient(Color, Color)
       case none
   }
   ```

2. **`ThemedOverlayModifier`:**
   ```swift
   struct ThemedOverlayModifier: ViewModifier {
       let theme: OverlayTheme
       let palette: (dominant: Color, accent: Color)?
       
       func body(content: Content) -> some View {
           content
               .font(.system(size: fontSize, weight: theme.fontWeight, design: theme.fontDesign))
               .foregroundStyle(theme.textColor)
               // Apply background based on theme.backgroundStyle
       }
   }
   ```

3. **Settings:**
   - `OverlayController.overlayTheme: OverlayTheme` (UserDefaults `"overlayTheme"`, default: `.classic`)
   - MenuBarView: horizontal scroll of theme thumbnails (small preview cards)

4. **Interaction with mood theming:**
   - If mood theming is on, mood colors override theme's text/accent colors but keep the theme's background style
   - Theme provides the "shape", mood provides the "color"

**Tests (`OverlayThemeTests.swift`):**
- Verify all theme cases have valid properties
- Verify `displayName` is non-empty for all cases
- Verify `CaseIterable` includes all cases

---

### 5.2 Custom Font Picker

**Goal:** Let users choose overlay font family, weight, and size beyond the theme defaults. Personal typography.

**Files to create:**
- `Sources/SpotifyLyricsCore/Models/OverlayFont.swift` — Font configuration model

**Files to modify:**
- `Sources/SpotifyLyricsCore/Overlay/LyricLineView.swift` — Apply custom font
- `Sources/SpotifyLyricsCore/Overlay/MiniOverlayView.swift` — Apply custom font
- `Sources/App/SpotifyLyricsApp.swift` — Add font settings to `OverlayController`
- `Sources/App/MenuBarView.swift` — Font picker UI

**Implementation:**

1. **Define `OverlayFont`:**
   ```swift
   public struct OverlayFont: Codable, Equatable {
       public var familyName: String?        // nil = use theme default
       public var sizeMultiplier: Double      // 0.5...2.0, default 1.0 (relative to OverlaySize base)
       public var weight: Font.Weight         // default .bold
       public var design: Font.Design         // default from theme
       
       public static let `default` = OverlayFont(familyName: nil, sizeMultiplier: 1.0, weight: .bold, design: .default)
       
       public func resolve(baseFontSize: CGFloat) -> Font
   }
   ```

2. **Font picker in `MenuBarView`:**
   ```swift
   // Collapsible "Font" section in settings
   DisclosureGroup("Font", isExpanded: $isFontExpanded) {
       // Font family: picker from NSFontManager.shared.availableFontFamilies
       Picker("Family", selection: $overlayController.overlayFont.familyName) {
           Text("Default").tag(String?.none)
           ForEach(popularFonts, id: \.self) { family in
               Text(family).tag(Optional(family))
           }
       }
       // Size multiplier: slider 50% - 200%
       HStack {
           Text("Size")
           Slider(value: $overlayController.overlayFont.sizeMultiplier, in: 0.5...2.0, step: 0.1)
           Text("\(Int(overlayController.overlayFont.sizeMultiplier * 100))%").monospacedDigit()
       }
       // Weight picker
       Picker("Weight", selection: $overlayController.overlayFont.weight) { ... }
   }
   ```
   - Show only popular/readable fonts (filter system fonts to ~20 curated families: SF Pro, Helvetica Neue, Avenir, Georgia, Menlo, etc.)

3. **Apply in `LyricLineView`:**
   - Replace hardcoded `.system(size:weight:design:)` with `overlayFont.resolve(baseFontSize:)`
   - `baseFontSize` comes from `OverlaySize.dimensions` as before

**Tests (`OverlayFontTests.swift`):**
- Verify default font resolves to system font
- Verify size multiplier scales correctly
- Verify custom family name produces non-system font
- Verify Codable round-trip

---

### 5.3 Album Art Parallax

**Goal:** Subtle parallax shift of the blurred album art background as lyrics scroll, adding visual depth.

**Files to modify:**
- `Sources/SpotifyLyricsCore/Overlay/LyricsOverlayView.swift` — Add parallax offset to background image

**Implementation:**

1. **Track scroll offset:**
   ```swift
   // In LyricsOverlayView, wrap the ScrollViewReader content
   GeometryReader { geo in
       ScrollView {
           // existing lyrics content
       }
       .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
           parallaxOffset = offset * 0.15  // 15% of scroll = subtle parallax
       }
   }
   ```

2. **Apply parallax to background:**
   ```swift
   // Album art background layer (existing blurred image)
   AsyncImage(url: artworkURL) { image in
       image.resizable()
           .aspectRatio(contentMode: .fill)
           .scaleEffect(1.2)  // slight oversize to allow movement
           .offset(y: parallaxOffset)
           .blur(radius: 30)
   }
   ```

3. **Performance:** Use `.drawingGroup()` on the background layer to rasterize the blur, avoiding per-frame recomputation. Parallax offset changes are driven by scroll, not a timer.

4. **Disable conditions:**
   - Mini mode: no parallax (no scroll)
   - Reduce Motion accessibility: disable parallax (`UIAccessibility.isReduceMotionEnabled`)

**Tests (`ParallaxTests.swift`):**
- Verify parallax factor (15% of scroll offset)
- Verify parallax is 0 when scroll is at top
- Verify parallax is disabled when reduce motion is on

---

## Milestone 6: Apple AI — Advanced (macOS 26+)

### 6.1 Lyrics Explanation on Demand

**Goal:** Long-press a lyric line → Foundation Models explains the metaphor, cultural reference, slang, or meaning in context.

**Files to create:**
- `Sources/SpotifyLyricsCore/Lyrics/Enrichment/LyricsExplainer.swift` — On-demand line explanation

**Files to modify:**
- `Sources/SpotifyLyricsCore/Overlay/LyricLineView.swift` — Long-press gesture + popover
- `Sources/SpotifyLyricsCore/Overlay/LyricsOverlayView.swift` — Explanation popover state

**Implementation:**

1. **Create `LyricsExplainer`:**
   ```swift
   #if canImport(FoundationModels)
   import FoundationModels

   @available(macOS 26, *)
   @MainActor public final class LyricsExplainer {
       private var cache: [String: String] = [:]  // lineText+trackKey → explanation
       
       public func explain(
           line: String,
           surroundingLines: [String],    // 2 lines before + 2 after for context
           title: String,
           artist: String
       ) async throws -> String {
           // Prompt: "Explain this lyric line in 2-3 sentences. Cover any metaphors,
           //  cultural references, wordplay, or slang. Context: Song '{title}' by {artist}.
           //  Surrounding lyrics: {context}. Line to explain: '{line}'"
       }
   }
   #endif
   ```
   - Timeout: 10s, fallback: "Explanation unavailable"
   - Cache per `"{line}|{trackCacheKey}"` to avoid re-explaining same line

2. **Long-press gesture on `LyricLineView`:**
   ```swift
   .onLongPressGesture(minimumDuration: 0.5) {
       Task {
           if #available(macOS 26, *) {
               explanation = try? await explainer.explain(
                   line: line.text,
                   surroundingLines: getSurroundingLines(index: lineIndex, count: 2),
                   title: track.title, artist: track.artist
               )
               showExplanation = true
           }
       }
   }
   .popover(isPresented: $showExplanation) {
       VStack(alignment: .leading, spacing: 8) {
           Text("\"\(line.text)\"").font(.caption.bold().italic())
           if let explanation {
               Text(explanation).font(.caption)
           } else {
               ProgressView().controlSize(.small)
           }
       }
       .padding()
       .frame(width: 280)
   }
   ```

3. **Also add to right-click context menu:** "Explain This Line" (alongside existing "Share as Card", "Copy Line")

**Tests (`LyricsExplainerTests.swift`):**
- Verify prompt includes surrounding context lines
- Verify cache hit on repeated explain call
- Verify nil/error handling returns fallback text

---

### 6.2 Vocabulary Builder

**Goal:** For foreign-language songs, extract key vocabulary words per line, building a personal word bank for language learners.

**Files to create:**
- `Sources/SpotifyLyricsCore/Lyrics/Enrichment/VocabularyExtractor.swift` — Word extraction + definitions
- `Sources/SpotifyLyricsCore/Models/VocabularyEntry.swift` — Word bank model
- `Sources/App/VocabularyView.swift` — Word bank browser

**Files to modify:**
- `Sources/SpotifyLyricsCore/Overlay/LyricLineView.swift` — Tappable words with definitions
- `Sources/App/MenuBarView.swift` — "Word Bank" section
- `Sources/App/SpotifyLyricsApp.swift` — Instantiate vocabulary manager

**Implementation:**

1. **`VocabularyEntry` model:**
   ```swift
   public struct VocabularyEntry: Identifiable, Codable, Equatable {
       public let id: UUID
       public let word: String                // original script
       public let romanization: String?       // how to read it
       public let pronunciation: String?      // how to say it
       public let definition: String           // meaning in target language
       public let partOfSpeech: String?        // noun, verb, adjective, etc.
       public let exampleLine: String          // the lyric line it came from
       public let trackTitle: String
       public let trackArtist: String
       public let sourceLanguage: String
       public let addedAt: Date
       public var mastered: Bool = false       // user marks as "known"
   }
   ```

2. **`VocabularyExtractor` (Foundation Models):**
   ```swift
   #if canImport(FoundationModels)
   @available(macOS 26, *)
   @MainActor public final class VocabularyExtractor {
       public func extractKeyWords(
           from lines: [String],
           sourceLanguage: String,
           targetLanguage: String
       ) async throws -> [Int: [WordDefinition]] {
           // Prompt: "Extract 2-3 key vocabulary words from each line of these {language} lyrics.
           //  For each word, provide: word, romanization, definition in {targetLanguage}, part of speech.
           //  Focus on useful, non-trivial vocabulary. Skip common particles and conjunctions.
           //  Return as JSON: [{lineIndex, words: [{word, romanization, definition, partOfSpeech}]}]"
       }
   }
   #endif
   ```
   - Process alongside enrichment (after lyrics fetch, if vocabulary is enabled)
   - Cache per `"{trackCacheKey}|{targetLanguage}"`

3. **Tappable words in `LyricLineView`:**
   ```swift
   // When vocabulary data is available, render line as tappable segments
   if let vocabWords = vocabularyWords {
       HStack(spacing: 0) {
           ForEach(segments) { segment in
               Text(segment.text)
                   .underline(segment.hasDefinition, color: .white.opacity(0.3))
                   .onTapGesture {
                       if let def = segment.definition {
                           selectedWord = def
                           showWordPopover = true
                       }
                   }
           }
       }
   }
   ```
   - Word tap shows a small popover: word, romanization, definition, "Save to Word Bank" button

4. **Word bank persistence:**
   - `~/Library/Application Support/SpotifyLyrics/vocabulary.json`
   - `VocabularyManager` with `@Published var entries: [VocabularyEntry]`
   - Mark words as "mastered" → they still appear but dimmed/de-emphasized

5. **`VocabularyView`:**
   ```swift
   struct VocabularyView: View {
       // Grouped by language, sorted by addedAt
       // Search/filter bar
       // Toggle: show all vs. unmastered only
       // Swipe to mark mastered, swipe to delete
       // Export as CSV for Anki import
   }
   ```
   - Accessible from MenuBarView: "Word Bank (42 words)" button

6. **Anki export:**
   ```swift
   func exportAsCSV() -> String {
       // "word\tromanization\tdefinition\texample\n" (tab-separated for Anki import)
   }
   ```
   - "Export for Anki" button in VocabularyView → saves .tsv file via NSSavePanel

**Tests (`VocabularyTests.swift`):**
- Verify entry creation and mastered toggle
- Verify persistence round-trip
- Verify CSV export format
- Verify deduplication (same word from different songs)

---

### 6.3 Lyrics Correction / Quality Fix

**Goal:** Foundation Models detects likely transcription errors in fetched lyrics (misheard words, broken encoding, duplicated lines) and suggests inline fixes.

**Files to create:**
- `Sources/SpotifyLyricsCore/Lyrics/Enrichment/LyricsCorrector.swift` — Error detection + correction

**Files to modify:**
- `Sources/SpotifyLyricsCore/Lyrics/LyricsManager.swift` — Apply corrections after fetch
- `Sources/SpotifyLyricsCore/Overlay/LyricLineView.swift` — Show correction indicator
- `Sources/App/SpotifyLyricsApp.swift` — Add `autoCorrectLyrics` toggle

**Implementation:**

1. **Create `LyricsCorrector`:**
   ```swift
   #if canImport(FoundationModels)
   @available(macOS 26, *)
   @MainActor public final class LyricsCorrector {
       public struct Correction: Equatable {
           let lineIndex: Int
           let original: String
           let corrected: String
           let reason: String         // "likely encoding error", "misheard word", "duplicate line"
           let confidence: Double      // 0-1
       }
       
       public func detectErrors(
           lines: [String],
           title: String,
           artist: String
       ) async throws -> [Correction] {
           // Prompt: "Review these song lyrics for errors. Look for:
           //  1. Encoding issues (mojibake, broken characters)
           //  2. Likely misheard words that don't fit context
           //  3. Obvious duplicated lines that shouldn't repeat
           //  4. Missing words or truncated lines
           //  Only flag lines you're confident (>80%) are wrong.
           //  Return JSON: [{lineIndex, original, corrected, reason, confidence}]"
       }
   }
   #endif
   ```
   - Only apply corrections with confidence ≥ 0.8
   - Cache corrections per `trackCacheKey`
   - Timeout: 15s (analyzes full lyrics)

2. **Apply in `LyricsManager`:**
   ```swift
   // After fetchLyrics succeeds, if autoCorrectLyrics is enabled:
   if #available(macOS 26, *), autoCorrectLyrics {
       Task {
           let corrections = try? await corrector.detectErrors(lines: ..., title: ..., artist: ...)
           for correction in corrections ?? [] where correction.confidence >= 0.8 {
               currentLines[correction.lineIndex] = LyricLine(
                   id: currentLines[correction.lineIndex].id,
                   timestamp: currentLines[correction.lineIndex].timestamp,
                   text: correction.corrected,
                   words: currentLines[correction.lineIndex].words,
                   endTime: currentLines[correction.lineIndex].endTime
               )
           }
           self.appliedCorrections = corrections?.filter { $0.confidence >= 0.8 } ?? []
       }
   }
   ```

3. **Visual indicator on corrected lines:**
   ```swift
   // In LyricLineView, if this line was corrected
   if isCorrected {
       Image(systemName: "wand.and.stars")
           .font(.system(size: 8))
           .foregroundStyle(.white.opacity(0.4))
   }
   ```
   - Tooltip on hover: "Corrected: {reason}. Original: {original text}"
   - Right-click: "Revert to Original" option

4. **Settings:**
   - `OverlayController.autoCorrectLyrics: Bool` (UserDefaults, default: true on macOS 26+)
   - Toggle in MenuBarView: "Auto-Correct Lyrics"

**Tests (`LyricsCorrectorTests.swift`):**
- Verify corrections only applied at ≥ 0.8 confidence
- Verify revert restores original text
- Verify cache prevents re-analysis on same track
- Verify line ID preserved after correction

---

### 6.4 Auto-Generate Session Summary

**Goal:** After a listening session, summarize the lyrical themes into a shareable paragraph — "tonight's vibe."

**Files to create:**
- `Sources/SpotifyLyricsCore/Lyrics/Enrichment/SessionSummarizer.swift` — Session theme analysis

**Files to modify:**
- `Sources/App/SpotifyLyricsApp.swift` — Track session history, trigger summary
- `Sources/App/MenuBarView.swift` — "Session Vibe" display + share

**Implementation:**

1. **Session tracking in `AppDelegate`:**
   ```swift
   struct SessionTrack {
       let title: String
       let artist: String
       let summary: String?         // from FoundationModelProvider
       let mood: LyricsMood?        // from MoodAnalyzer, if available
       let playedAt: Date
   }
   var sessionTracks: [SessionTrack] = []
   ```
   - Append on each `onTrackChanged` (only tracks where lyrics were loaded)
   - Session resets when app launches or after 4 hours of inactivity

2. **`SessionSummarizer`:**
   ```swift
   #if canImport(FoundationModels)
   @available(macOS 26, *)
   @MainActor public final class SessionSummarizer {
       public func summarize(tracks: [SessionTrack]) async throws -> String {
           // Prompt: "Summarize the mood and themes of this listening session in 2-3 sentences.
           //  Make it personal and evocative, like a journal entry about tonight's music.
           //  Tracks played: {title - artist (summary/mood) for each track}"
       }
   }
   #endif
   ```
   - Minimum 3 tracks before summary is available
   - Re-generate on each new track (debounced 30s)

3. **Display in `MenuBarView`:**
   ```swift
   // Below mini player, above settings
   if let sessionVibe = sessionSummary, sessionTracks.count >= 3 {
       VStack(alignment: .leading, spacing: 4) {
           HStack {
               Text("Tonight's Vibe").font(.caption.bold())
               Spacer()
               Button(action: { copySessionVibe() }) {
                   Image(systemName: "doc.on.doc")
               }.buttonStyle(.plain)
           }
           Text(sessionVibe)
               .font(.caption)
               .foregroundStyle(.secondary)
               .lineLimit(4)
       }
       .padding(.horizontal, 12)
   }
   ```

4. **Share options:**
   - Copy to clipboard (plain text)
   - Include track list: "Tonight's Vibe: {summary}\n\nPlaylist: {track list}"

**Tests (`SessionSummarizerTests.swift`):**
- Verify minimum 3 tracks required
- Verify session reset after 4 hours
- Verify summary includes track context

---

## Milestone 7: Interaction & Sharing

### 7.1 Lyrics Export

**Goal:** Export full lyrics as .txt, .lrc (with timestamps), or .pdf with album art header.

**Files to create:**
- `Sources/SpotifyLyricsCore/Sharing/LyricsExporter.swift` — Multi-format export

**Files to modify:**
- `Sources/SpotifyLyricsCore/Overlay/LyricsOverlayView.swift` — Export button in controls
- `Sources/App/MenuBarView.swift` — Export action in menu

**Implementation:**

1. **`LyricsExporter`:**
   ```swift
   @MainActor public final class LyricsExporter {
       public enum ExportFormat: String, CaseIterable {
           case plainText  // .txt — lyrics only
           case lrc        // .lrc — with [mm:ss.xx] timestamps
           case pdf        // .pdf — formatted with album art header
       }
       
       public func export(
           lines: [LyricLine],
           enrichment: [Int: LineEnrichment]?,
           track: TrackInfo,
           format: ExportFormat,
           includeEnrichment: Bool = true
       ) -> Data {
           switch format {
           case .plainText: return exportPlainText(lines, enrichment, includeEnrichment)
           case .lrc:       return exportLRC(lines)
           case .pdf:       return exportPDF(lines, enrichment, track, includeEnrichment)
           }
       }
   }
   ```

2. **Plain text export:**
   ```
   Song Title — Artist Name
   
   [Line text]
   (romanization)  // if enrichment enabled
   [translation]   // if enrichment enabled
   
   [Next line...]
   ```

3. **LRC export:**
   ```
   [ti:Song Title]
   [ar:Artist Name]
   [al:Album Name]
   [00:12.34]First lyric line
   [00:16.78]Second lyric line
   ```
   - Include word-level tags if `LyricWord` data is available: `[00:12.34]<00:12.34>First <00:12.89>lyric <00:13.12>line`

4. **PDF export:**
   - Use `PDFKit` or `NSPrintOperation` to render a styled page
   - Header: album art (small) + title + artist
   - Body: lyrics with optional enrichment annotations
   - Footer: "Generated by SpotifyLyrics"

5. **UI trigger:**
   - Right-click overlay → "Export Lyrics..." → format picker → NSSavePanel
   - MenuBarView → "Export" button (below existing controls)

**Tests (`LyricsExporterTests.swift`):**
- Verify plain text format output
- Verify LRC timestamp formatting
- Verify LRC includes word-level tags when available
- Verify PDF data is non-empty
- Verify enrichment inclusion toggle

---

### 7.2 Quick Share to Messages / AirDrop

**Goal:** Direct share sheet integration for lyrics lines and cards — share via Messages, Notes, AirDrop, or any macOS share target.

**Files to modify:**
- `Sources/SpotifyLyricsCore/Overlay/LyricLineView.swift` — Add "Share..." to context menu
- `Sources/SpotifyLyricsCore/Sharing/LyricsCardGenerator.swift` — Provide `NSSharingServicePicker` items

**Implementation:**

1. **Share service for text:**
   ```swift
   // In LyricLineView context menu
   Button("Share...") {
       let text = "\"\(line.text)\" — \(track.title) by \(track.artist)"
       let picker = NSSharingServicePicker(items: [text])
       picker.show(relativeTo: .zero, of: NSApp.keyWindow!.contentView!, preferredEdge: .minY)
   }
   ```

2. **Share service for cards:**
   ```swift
   // After card generation in preview popover
   Button("Share...") {
       let image = generatedCardImage  // NSImage from LyricsCardGenerator
       let picker = NSSharingServicePicker(items: [image])
       picker.show(...)
   }
   ```
   - This automatically provides Messages, AirDrop, Notes, Mail, and any installed share extensions

3. **Share from menu bar:**
   - "Share Current Line" action in MenuBarView → shares currently active line as text
   - Works in both full and mini mode

**Tests (`ShareTests.swift`):**
- Verify share text format includes attribution
- Verify card image is valid `NSImage` for sharing

---

### 7.3 Sing-Along Scoring

**Goal:** Use `SFSpeechRecognizer` on microphone input to compare what the user sings vs. the lyric text. Show a match percentage per line.

**Files to create:**
- `Sources/SpotifyLyricsCore/Analysis/SingAlongScorer.swift` — Mic capture + speech-to-text comparison
- `Sources/SpotifyLyricsCore/Overlay/SingAlongScoreView.swift` — Score display overlay

**Files to modify:**
- `Sources/SpotifyLyricsCore/Overlay/LyricsOverlayView.swift` — Show score overlay when sing-along active
- `Sources/App/SpotifyLyricsApp.swift` — Add sing-along toggle, manage mic permissions
- `Sources/App/MenuBarView.swift` — Sing-along mode toggle

**Implementation:**

1. **`SingAlongScorer`:**
   ```swift
   @MainActor public final class SingAlongScorer: ObservableObject {
       @Published public var isActive = false
       @Published public var currentLineScore: Double = 0     // 0-100%
       @Published public var totalScore: Double = 0            // running average
       @Published public var recognizedText: String = ""
       
       private var audioEngine: AVAudioEngine?
       private var recognizer: SFSpeechRecognizer?
       private var recognitionTask: SFSpeechRecognitionTask?
       
       public func start()     // request mic permission, start audio engine + recognition
       public func stop()
       
       /// Compare recognized text against expected lyric line
       public func score(recognized: String, expected: String) -> Double {
           // Levenshtein distance-based scoring:
           // 1. Normalize both strings (lowercase, remove punctuation)
           // 2. Split into words
           // 3. Calculate word-level edit distance
           // 4. Score = 1.0 - (distance / max(expectedWords, recognizedWords))
           // 5. Clamp to 0...1, multiply by 100
       }
   }
   ```

2. **Mic capture with `AVAudioEngine`:**
   - `SpeechRecognitionProvider` already uses `SFSpeechRecognizer` — reuse the pattern
   - Continuous recognition: stream mic audio → on each partial result, score against current expected line
   - Reset recognition buffer on line change (new `SFSpeechAudioBufferRecognitionRequest`)

3. **Score display (`SingAlongScoreView`):**
   ```swift
   struct SingAlongScoreView: View {
       let lineScore: Double
       let totalScore: Double
       
       var body: some View {
           HStack(spacing: 12) {
               // Per-line score: colored circle
               ZStack {
                   Circle().stroke(lineWidth: 3).foregroundStyle(.white.opacity(0.2))
                   Circle().trim(from: 0, to: lineScore / 100)
                       .stroke(scoreColor, lineWidth: 3)
                   Text("\(Int(lineScore))").font(.system(size: 14, weight: .bold))
               }
               .frame(width: 44, height: 44)
               
               // Running total
               VStack(alignment: .leading) {
                   Text("Line Score").font(.caption2)
                   Text("Total: \(Int(totalScore))%").font(.caption.bold())
               }
           }
       }
       
       var scoreColor: Color {
           lineScore > 80 ? .green : lineScore > 50 ? .yellow : .red
       }
   }
   ```
   - Displayed as floating badge in top-right of overlay when sing-along mode is active

4. **Settings:**
   - `OverlayController.singAlongMode: Bool` (not persisted — resets to false on app launch, requires explicit activation)
   - MenuBarView: "Sing Along" toggle with microphone icon
   - First activation triggers mic permission dialog

5. **Privacy:**
   - Audio is processed locally via `SFSpeechRecognizer` — no data leaves the device
   - Clear microphone usage description in Info.plist: "SpotifyLyrics uses the microphone for sing-along scoring"
   - No audio is recorded or stored

**Tests (`SingAlongScorerTests.swift`):**
- Verify scoring: identical text → 100%
- Verify scoring: completely different → ~0%
- Verify scoring: partial match → proportional score
- Verify normalization (case, punctuation)
- Verify empty input handling

---

## Milestone 8: Audio Intelligence & Enrichment Backends

### 8.1 Local Forced Alignment for Word-Accurate Karaoke

**Goal:** Derive true per-word timings by aligning known lyrics to Spotify's audio via on-device CTC forced alignment. Replaces interpolation-based karaoke fill with accurate word-level sync.

**Source:** `plans/AI.md`

**Key insight:** We already have line-level timestamps, so this is "place N known words inside a known ~3–5s line window" — not full-song alignment. Errors are bounded per line. The feature is fully decoupled and off by default; if disabled/unavailable, karaoke uses existing interpolation fallback.

**Files to create (new `Sources/SpotifyLyricsCore/Alignment/`):**
- `AudioCaptureService.swift` — ScreenCaptureKit `SCStream` targeting Spotify app, captures audio-only, downmixes to mono 16kHz Float, records capture-start offset vs playback position
- `ForcedAligner.swift` — Core ML acoustic model → CTC emissions → forced-alignment Viterbi (torchaudio-style), returns per-word time spans
- `Romanizer.swift` — Lyric text → model token sequence (Latin: lowercase/strip; Japanese: kana→romaji; kanji falls back to interpolation)
- `LyricsAlignmentCoordinator.swift` — Orchestrates capture lifecycle, runs per-line alignment in background, writes cache, pushes results to `LyricsManager`
- `WordTimingCache.swift` — On-disk JSON cache under Application Support keyed by `TrackInfo.cacheKey`

**Files to modify:**
- `Sources/SpotifyLyricsCore/Models/LyricLine.swift` / `LyricWord.swift` — Add `Codable` for disk cache
- `Sources/SpotifyLyricsCore/Lyrics/LyricsManager.swift` — Check `WordTimingCache` during `fetchLyrics`, method to merge aligned word timings
- `Sources/App/SpotifyLyricsApp.swift` — Add `localAlignmentEnabled` to `OverlayController`, wire coordinator
- `Sources/App/MenuBarView.swift` — "Word-level sync (local)" toggle + status line (Off / Listening… / Aligning… / Ready)

**Phasing:**
- **Phase 0 — Packaging:** Self-signed `.app` bundle with stable cert so Screen Recording grant persists across rebuilds
- **Phase 1 — Alignment spike (GATE):** Prove model + runtime can align one English line on Apple Silicon. Decide vehicle: torchaudio `MMS_FA` → Core ML (+ Swift Viterbi) vs. existing Swift/MLX aligner. Settle model bundling vs first-run download
- **Phase 2 — Audio capture:** ScreenCaptureKit Spotify-only capture, permission flow, buffer + sample→time mapping
- **Phase 3 — Pipeline + cache + settings:** Per-line alignment, romanization, cache, `LyricsManager` integration, menu toggle + status
- **Phase 4 — Polish:** Japanese romanization quality, failure fallbacks, perf, cache eviction

**Risks:**
- Japanese kanji romanization hard on-device; v1 handles kana/romaji, kanji-heavy lines fall back to interpolation
- Sung vocals over full mix reduce accuracy; line-constraining mitigates
- Model size (hundreds of MB) → bundle vs download decision in Phase 1
- Apple-Silicon-leaning (Core ML / ANE / MLX)
- First listen has no word timing (capture+align happen during/after first play); cached thereafter

**Tests:**
- `WordTimingCache` Codable round-trip
- `Romanizer` (Latin + kana)
- Aligner Viterbi on synthetic emissions (deterministic)
- Toggle persistence

---

### 8.2 Claude Enrichment Fallback (Optional Paid Backend)

**Goal:** `URLSession` → Anthropic API with `claude-haiku-4-5` for romanization + translation on macOS 13–14 or unsupported languages where ICU/Apple Translation/Foundation Models aren't available.

**Source:** `plans/AI-EXT.md` (Phase 7)

**Files to create:**
- `Sources/SpotifyLyricsCore/Lyrics/Enrichment/ClaudeEnrichmentProvider.swift` — Implements `LyricsEnrichmentProvider`, batches all lines into one structured-output call, cached per song

**Files to modify:**
- `Sources/SpotifyLyricsCore/Lyrics/Enrichment/EnrichmentCoordinator.swift` — Register Claude as lowest-priority fallback provider
- `Sources/App/SpotifyLyricsApp.swift` — Keychain-based API key storage
- `Sources/App/MenuBarView.swift` — API key settings UI + provider status

**Implementation:**
- `capabilities: [.romanization, .translation]` — both, any language
- Minimum macOS 13 (no OS bump needed)
- Batch all lines of a song into one API call for efficiency
- Cache per `TrackInfo.cacheKey` — songs don't change lyrics
- Needs Keychain key storage + settings UI for API key entry
- Only used when no free provider covers the needed capability

**Tests:**
- Verify provider declares both capabilities
- Verify coordinator selects Claude only when free providers unavailable
- Verify API key storage/retrieval round-trip

---

## Milestone 9: System Integration & Accessibility

### 9.1 Global Hotkey Customization

**Goal:** Let users rebind all keyboard shortcuts via a preferences pane.

**Files to create:**
- `Sources/SpotifyLyricsCore/Models/HotkeyBinding.swift` — Keybinding model
- `Sources/App/HotkeyManager.swift` — Global hotkey registration + customization
- `Sources/App/HotkeySettingsView.swift` — Keybinding editor UI

**Files to modify:**
- `Sources/App/SpotifyLyricsApp.swift` — Replace hardcoded shortcuts with configurable bindings
- `Sources/App/MenuBarView.swift` — "Keyboard Shortcuts" settings section

**Implementation:**

1. **`HotkeyBinding` model:**
   ```swift
   public struct HotkeyBinding: Codable, Equatable, Identifiable {
       public var id: String { action.rawValue }
       public let action: HotkeyAction
       public var keyCode: UInt16
       public var modifiers: NSEvent.ModifierFlags
       
       public var displayString: String  // e.g., "⌘⇧M"
   }
   
   public enum HotkeyAction: String, CaseIterable, Codable {
       case toggleOverlay          // default: Cmd+Shift+L
       case toggleMiniMode         // default: Cmd+Shift+M
       case syncOffsetEarlier      // default: Cmd+[
       case syncOffsetLater        // default: Cmd+]
       case nextLine               // default: Cmd+Down
       case previousLine           // default: Cmd+Up
       case bookmarkCurrentLine    // default: Cmd+Shift+B
       case toggleSingAlong        // default: Cmd+Shift+S
       
       public var defaultBinding: HotkeyBinding
       public var displayName: String
   }
   ```

2. **`HotkeyManager`:**
   ```swift
   @MainActor final class HotkeyManager {
       private var bindings: [HotkeyAction: HotkeyBinding] = [:]
       private var monitors: [Any] = []
       
       func registerAll()
       func updateBinding(_ action: HotkeyAction, keyCode: UInt16, modifiers: NSEvent.ModifierFlags)
       func resetToDefaults()
       
       // Uses NSEvent.addGlobalMonitorForEvents for global hotkeys
       // Uses NSEvent.addLocalMonitorForEvents for in-app hotkeys
   }
   ```
   - Persist to UserDefaults key `"hotkeyBindings"`
   - Validate no conflicts (same key combo for different actions)

3. **`HotkeySettingsView`:**
   ```swift
   struct HotkeySettingsView: View {
       @ObservedObject var hotkeyManager: HotkeyManager
       
       var body: some View {
           VStack(spacing: 8) {
               ForEach(HotkeyAction.allCases, id: \.self) { action in
                   HStack {
                       Text(action.displayName).font(.caption)
                       Spacer()
                       KeyRecorderView(binding: hotkeyManager.binding(for: action)) { newKey, newMods in
                           hotkeyManager.updateBinding(action, keyCode: newKey, modifiers: newMods)
                       }
                   }
               }
               Button("Reset to Defaults") { hotkeyManager.resetToDefaults() }
                   .font(.caption)
           }
       }
   }
   ```
   - `KeyRecorderView`: click to start recording → next key press sets the binding → Escape to cancel

**Tests (`HotkeyTests.swift`):**
- Verify default bindings for all actions
- Verify conflict detection
- Verify persistence round-trip
- Verify reset to defaults

---

### 9.2 Focus Mode Awareness

**Goal:** Respect macOS Focus filters — auto-hide overlay during "Work" focus, auto-show during "Personal." Configurable per Focus mode.

**Files to create:**
- `Sources/App/Intents/SpotifyLyricsFocusFilter.swift` — FocusFilter intent

**Files to modify:**
- `Sources/App/SpotifyLyricsApp.swift` — Respond to Focus changes

**Implementation:**

1. **`SpotifyLyricsFocusFilter`:**
   ```swift
   import AppIntents

   struct SpotifyLyricsFocusFilter: SetFocusFilterIntent {
       static var title: LocalizedStringResource = "SpotifyLyrics Behavior"
       static var description: IntentDescription = "Configure how SpotifyLyrics behaves during this Focus"
       
       @Parameter(title: "Show Overlay") var showOverlay: Bool
       @Parameter(title: "Overlay Mode") var overlayMode: OverlaySizeEnum?
       
       func perform() async throws -> some IntentResult {
           let controller = await AppState.shared.overlayController
           if showOverlay {
               await controller?.show(...)
               if let mode = overlayMode {
                   await MainActor.run { controller?.overlaySize = mode.toOverlaySize }
               }
           } else {
               await controller?.hide()
           }
           return .result()
       }
   }
   ```

2. **User configuration:**
   - In System Settings → Focus → (any Focus mode) → Focus Filters → SpotifyLyrics
   - Options: "Show Overlay" (bool), "Overlay Mode" (mini/small/medium/large)
   - "Work" focus: user sets showOverlay = false → overlay auto-hides when Work focus activates
   - "Personal" focus: user sets showOverlay = true, mode = large → overlay auto-shows in large mode

3. **No custom UI needed** — `SetFocusFilterIntent` integrates directly with System Settings Focus Filters pane.

**Tests (`FocusFilterTests.swift`):**
- Verify intent parameter types
- Verify show/hide logic
- Verify overlay mode change

---

### 9.3 Accessibility VoiceOver Mode

**Goal:** Announce current lyric line via VoiceOver for visually impaired users. Speak the line, romanization, and translation at each line change.

**Files to modify:**
- `Sources/SpotifyLyricsCore/Overlay/LyricsOverlayView.swift` — VoiceOver annotations
- `Sources/SpotifyLyricsCore/Overlay/LyricLineView.swift` — Accessibility labels
- `Sources/SpotifyLyricsCore/Overlay/MiniOverlayView.swift` — Accessibility announcement
- `Sources/SpotifyLyricsCore/Lyrics/LyricsManager.swift` — Post accessibility notifications on line change

**Implementation:**

1. **Accessibility labels on `LyricLineView`:**
   ```swift
   .accessibilityLabel(buildAccessibilityLabel())
   .accessibilityAddTraits(isActive ? .isSelected : [])
   
   func buildAccessibilityLabel() -> String {
       var parts = [line.text]
       if let romanization = enrichment?.romanization {
           parts.append("Pronounced: \(romanization)")
       }
       if let translation = enrichment?.translation {
           parts.append("Meaning: \(translation)")
       }
       return parts.joined(separator: ". ")
   }
   ```

2. **Announce line changes:**
   ```swift
   // In LyricsManager.updateCurrentLine, when line changes:
   if NSWorkspace.shared.isVoiceOverEnabled {
       let announcement = buildAnnouncementText(line: currentLine, enrichment: currentEnrichment)
       NSAccessibility.post(
           element: NSApp.mainWindow as Any,
           notification: .announcementRequested,
           userInfo: [.announcement: announcement, .priority: NSAccessibilityPriorityLevel.high]
       )
   }
   ```

3. **Overlay-level accessibility:**
   ```swift
   // LyricsOverlayView
   .accessibilityElement(children: .contain)
   .accessibilityLabel("Lyrics Overlay")
   .accessibilityValue("\(track.title) by \(track.artist)")
   .accessibilityHint("Showing synchronized lyrics")
   ```

4. **MiniOverlayView:**
   ```swift
   .accessibilityLabel("Current lyric: \(currentLine.text)")
   .accessibilityAddTraits(.updatesFrequently)
   ```

5. **Respect announcement frequency:**
   - Only announce when VoiceOver is actually running (`NSWorkspace.shared.isVoiceOverEnabled`)
   - Don't announce during instrumental breaks (silent period)
   - Don't interrupt VoiceOver if user is navigating other UI

**Tests (`AccessibilityTests.swift`):**
- Verify accessibility label includes all enrichment parts
- Verify announcement text format
- Verify instrumental break suppresses announcement
- Verify `.updatesFrequently` trait on mini mode

---

### 9.4 Menu Bar Scrolling Lyric

**Goal:** Show the current lyric line as scrolling marquee text in the menu bar itself — for users who don't want the overlay at all.

**Files to modify:**
- `Sources/App/StatusBarController.swift` — Dynamic menu bar title with current line
- `Sources/App/SpotifyLyricsApp.swift` — Add `showMenuBarLyric` toggle, wire line updates
- `Sources/App/MenuBarView.swift` — Toggle for menu bar lyric display

**Implementation:**

1. **Dynamic status bar title:**
   ```swift
   // In StatusBarController
   func updateMenuBarTitle(_ text: String?) {
       if let text, !text.isEmpty {
           // Truncate to ~40 chars for menu bar space
           let truncated = text.count > 40 ? String(text.prefix(37)) + "..." : text
           statusItem.button?.title = " \(truncated)"  // space after icon
       } else {
           statusItem.button?.title = ""  // icon only
       }
   }
   ```

2. **Marquee animation (optional):**
   ```swift
   // For lines longer than 40 chars, scroll text left
   // Use a Timer to shift the visible substring window
   private var marqueeTimer: Timer?
   private var marqueeOffset = 0
   
   func startMarquee(text: String) {
       guard text.count > 40 else {
           statusItem.button?.title = " \(text)"
           return
       }
       marqueeOffset = 0
       marqueeTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
           // Shift visible window by 1 character
           let padded = text + "    \(text)"  // seamless loop
           let start = padded.index(padded.startIndex, offsetBy: self?.marqueeOffset ?? 0)
           let end = padded.index(start, offsetBy: min(40, padded.distance(from: start, to: padded.endIndex)))
           self?.statusItem.button?.title = " " + String(padded[start..<end])
           self?.marqueeOffset = ((self?.marqueeOffset ?? 0) + 1) % (text.count + 4)
       }
   }
   ```

3. **Wire in `AppDelegate`:**
   - On `currentLineIndex` change → `statusBarController.updateMenuBarTitle(currentLine.text)`
   - On track change with no lyrics → clear title
   - On overlay hidden (if `showMenuBarLyric` enabled) → show in menu bar as fallback

4. **Settings:**
   - `OverlayController.showMenuBarLyric: Bool` (UserDefaults `"showMenuBarLyric"`, default: false)
   - MenuBarView: "Show Lyric in Menu Bar" toggle
   - Option: "Only when overlay is hidden" vs. "Always"

**Tests (`MenuBarLyricTests.swift`):**
- Verify truncation at 40 chars
- Verify empty string when no lyrics
- Verify marquee offset wrapping

---

## Priority & Dependency Order

```
Milestone 1 (No AI, immediate value)
  1.1 Sync Offset .............. standalone, no dependencies
  1.2 Multi-Display ............ standalone, no dependencies

Milestone 2 (Apple Intelligence, macOS 26+ gated)
  2.1 Mood Theming ............. depends on FoundationModels, extends existing palette
  2.2 Pronunciation Guide ...... extends enrichment pipeline
  2.3 Lyrics Search ............ depends on lyrics cache, optional FoundationModels
  2.4 Writing Kit .............. extends card generator

Milestone 3 (Engagement)
  3.1 Bookmarks ................ standalone
  3.2 Listening Stats .......... standalone, wires into existing events

Milestone 4 (Playback Intelligence)
  4.1 Queue Prefetch ........... modifies LyricsManager fetch flow
  4.2 Control Center Widget .... macOS 26+, depends on App Group setup

Milestone 5 (Overlay Customization)
  5.1 Overlay Themes ........... standalone, enhances visual layer
  5.2 Custom Font Picker ....... standalone, pairs with themes
  5.3 Album Art Parallax ....... standalone, small scope

Milestone 6 (Apple AI — Advanced, macOS 26+)
  6.1 Lyrics Explanation ....... depends on FoundationModels
  6.2 Vocabulary Builder ....... depends on FoundationModels + enrichment pipeline
  6.3 Lyrics Correction ........ depends on FoundationModels, modifies LyricsManager
  6.4 Session Summary .......... depends on FoundationModels + mood/summary data

Milestone 7 (Interaction & Sharing)
  7.1 Lyrics Export ............ standalone
  7.2 Quick Share .............. extends card generator + context menu
  7.3 Sing-Along Scoring ....... standalone, uses SFSpeechRecognizer

Milestone 8 (Audio Intelligence & Enrichment Backends)
  8.1 Local Forced Alignment ...... requires Screen Recording, Core ML model, Apple Silicon
  8.2 Claude Enrichment Fallback ... optional, paid API, extends enrichment pipeline

Milestone 9 (System Integration & Accessibility)
  9.1 Global Hotkey Customization .. standalone, replaces hardcoded shortcuts
  9.2 Focus Mode Awareness ......... depends on App Intents infrastructure
  9.3 Accessibility VoiceOver ...... standalone, modifies overlay views
  9.4 Menu Bar Scrolling Lyric ..... standalone, modifies StatusBarController
```

**Recommended build order (all 32 features):**

**Phase A — Foundation (high impact, no AI):**
1.1 → 1.2 → 3.1 → 4.1 → 5.1 → 5.2 → 9.1

**Phase B — Engagement & Sharing:**
3.2 → 7.1 → 7.2 → 9.4 → 9.3

**Phase C — Apple Intelligence:**
2.2 → 2.1 → 6.1 → 6.3 → 2.3 → 6.2 → 6.4 → 2.4

**Phase D — Audio Intelligence & Platform:**
8.1 → 8.2 → 5.3 → 7.3 → 9.2 → 4.2

**Rationale:**
- Phase A tackles the biggest pain points and most-requested features first, all without AI dependencies
- Phase B adds personality and sharing — features that drive engagement and word-of-mouth
- Phase C layers on Apple Intelligence features in dependency order (pronunciation extends pipeline first, then mood uses same pattern, then explanation, correction, search, vocabulary build on each other)
- Phase D includes local forced alignment (complex, requires spike), Claude fallback (optional paid), and platform polish — smaller scope or higher risk, can ship independently

---

## Completion Checklist

### Milestone 1: Sync & Polish
- [ ] **1.1 Sync Offset Adjustment**
  - [ ] Add `syncOffset` to `OverlayController` with per-track UserDefaults persistence
  - [ ] Apply offset in `LyricsManager.updateCurrentLine(at:offset:)` and `updateInstrumentalBreak`
  - [ ] Wire offset in `AppDelegate` 100ms timer
  - [ ] Add slider + reset button to `MenuBarView`
  - [ ] Save/load offset on track change
  - [ ] Create `SyncOffsetTests.swift`
- [ ] **1.2 Multi-Display Awareness**
  - [ ] Create `DisplayPositionManager.swift` (config key, position save/load)
  - [ ] Monitor `didChangeScreenParametersNotification` in `AppDelegate`
  - [ ] Save position on `NSWindow.didMoveNotification` (debounced)
  - [ ] Validate restored position within visible bounds
  - [ ] Create `DisplayPositionTests.swift`

### Milestone 2: Apple Intelligence
- [ ] **2.1 Mood-Adaptive Overlay Theming**
  - [ ] Create `MoodAnalyzer.swift` with `LyricsMood` enum
  - [ ] Add `sectionMoods` / `currentMood` to `LyricsManager`
  - [ ] Apply mood-driven color blending in overlay views
  - [ ] Add `moodTheming` toggle to `OverlayController` + `MenuBarView`
  - [ ] Create `MoodAnalyzerTests.swift`
- [ ] **2.2 Pronunciation Guide**
  - [ ] Add `pronunciation` to `LineEnrichment`
  - [ ] Add `.pronunciation` to `EnrichmentCapabilities`
  - [ ] Create `PronunciationProvider.swift`
  - [ ] Wire into `EnrichmentCoordinator`
  - [ ] Display in `LyricLineView` and `MiniOverlayView`
  - [ ] Add `showPronunciation` toggle
  - [ ] Create `PronunciationTests.swift`
- [ ] **2.3 Smart Lyrics Search**
  - [ ] Create `LyricsSearchEngine.swift` (keyword + semantic search)
  - [ ] Index tracks in `LyricsManager` on successful fetch
  - [ ] Add search UI in `MenuBarView`
  - [ ] Create `SearchLyricsIntent.swift`
  - [ ] Create `LyricsSearchTests.swift`
- [ ] **2.4 Writing Kit Integration**
  - [ ] Add caption parameter to `LyricsCardGenerator`
  - [ ] Update `LyricsCardView` with caption area
  - [ ] Add caption editor with `.writingToolsBehavior(.complete)` in card preview
  - [ ] Create `WritingKitTests.swift`

### Milestone 3: Engagement
- [ ] **3.1 Lyric Bookmarks**
  - [ ] Create `BookmarkManager.swift` (toggle, persistence, 1000 cap)
  - [ ] Add bookmark button on `LyricLineView` hover
  - [ ] Create `BookmarksListView.swift`
  - [ ] Add bookmarks section to `MenuBarView`
  - [ ] Create `GetBookmarksIntent.swift`
  - [ ] Create `BookmarkTests.swift`
- [ ] **3.2 Listening Stats Dashboard**
  - [ ] Create `ListeningStats.swift` (event counters, top tracks, persistence)
  - [ ] Create `StatsView.swift` (dashboard with metrics grid)
  - [ ] Wire event tracking in `AppDelegate`
  - [ ] Add "My Stats" button to `MenuBarView`
  - [ ] Create `ListeningStatsTests.swift`

### Milestone 4: Playback Intelligence
- [ ] **4.1 Queue-Aware Prefetch**
  - [ ] Create `LyricsPrefetcher.swift` (cache, history-based prediction, eviction)
  - [ ] Attempt queue read in `AppleScriptBridge` (best-effort)
  - [ ] Integrate prefetch cache into `LyricsManager.fetchLyrics`
  - [ ] Trigger prefetch at 75% track progress
  - [ ] Persist transition history
  - [ ] Create `PrefetchTests.swift`
- [ ] **4.2 Control Center Widget**
  - [ ] Create `LyricsControlWidget.swift` (macOS 26+)
  - [ ] Set up App Group shared UserDefaults
  - [ ] Throttle widget updates to line changes
  - [ ] Wire tap interaction to `ShowLyricsIntent`
  - [ ] Create `ControlWidgetTests.swift`

### Milestone 5: Overlay Customization
- [ ] **5.1 Overlay Themes / Skins**
  - [ ] Create `OverlayTheme.swift` with 6 preset themes
  - [ ] Create `ThemedOverlayModifier.swift`
  - [ ] Apply themes in `LyricsOverlayView` and `MiniOverlayView`
  - [ ] Add `overlayTheme` to `OverlayController` + theme picker in `MenuBarView`
  - [ ] Create `OverlayThemeTests.swift`
- [ ] **5.2 Custom Font Picker**
  - [ ] Create `OverlayFont.swift` model
  - [ ] Apply custom font in `LyricLineView` and `MiniOverlayView`
  - [ ] Add font picker UI in `MenuBarView` (family, size multiplier, weight)
  - [ ] Create `OverlayFontTests.swift`
- [ ] **5.3 Album Art Parallax**
  - [ ] Add scroll offset tracking to `LyricsOverlayView`
  - [ ] Apply parallax offset to background image layer
  - [ ] Respect Reduce Motion accessibility setting
  - [ ] Create `ParallaxTests.swift`

### Milestone 6: Apple AI — Advanced
- [ ] **6.1 Lyrics Explanation on Demand**
  - [ ] Create `LyricsExplainer.swift` (Foundation Models, context-aware)
  - [ ] Add long-press gesture + popover to `LyricLineView`
  - [ ] Add "Explain This Line" to right-click context menu
  - [ ] Create `LyricsExplainerTests.swift`
- [ ] **6.2 Vocabulary Builder**
  - [ ] Create `VocabularyExtractor.swift` and `VocabularyEntry.swift`
  - [ ] Add tappable words in `LyricLineView`
  - [ ] Create `VocabularyView.swift` (word bank browser + Anki export)
  - [ ] Wire vocabulary manager into `AppDelegate` and `MenuBarView`
  - [ ] Create `VocabularyTests.swift`
- [ ] **6.3 Lyrics Correction / Quality Fix**
  - [ ] Create `LyricsCorrector.swift` (error detection, confidence threshold)
  - [ ] Apply corrections in `LyricsManager` after fetch
  - [ ] Show correction indicator + revert option in `LyricLineView`
  - [ ] Add `autoCorrectLyrics` toggle
  - [ ] Create `LyricsCorrectorTests.swift`
- [ ] **6.4 Auto-Generate Session Summary**
  - [ ] Create `SessionSummarizer.swift`
  - [ ] Track session history in `AppDelegate`
  - [ ] Display "Tonight's Vibe" in `MenuBarView` with share option
  - [ ] Create `SessionSummarizerTests.swift`

### Milestone 7: Interaction & Sharing
- [ ] **7.1 Lyrics Export**
  - [ ] Create `LyricsExporter.swift` (plain text, LRC, PDF formats)
  - [ ] Add export button in overlay controls and `MenuBarView`
  - [ ] Create `LyricsExporterTests.swift`
- [ ] **7.2 Quick Share to Messages / AirDrop**
  - [ ] Add `NSSharingServicePicker` to `LyricLineView` context menu
  - [ ] Add share option for generated cards
  - [ ] Add "Share Current Line" in `MenuBarView`
  - [ ] Create `ShareTests.swift`
- [ ] **7.3 Sing-Along Scoring**
  - [ ] Create `SingAlongScorer.swift` (mic capture, speech recognition, Levenshtein scoring)
  - [ ] Create `SingAlongScoreView.swift` (score circle + running total)
  - [ ] Integrate into `LyricsOverlayView` as floating badge
  - [ ] Add sing-along toggle in `MenuBarView` with mic permission
  - [ ] Create `SingAlongScorerTests.swift`

### Milestone 8: Audio Intelligence & Enrichment Backends
- [ ] **8.1 Local Forced Alignment for Word-Accurate Karaoke**
  - [ ] Phase 0: Self-signed `.app` bundle, stable cert, Screen Recording grant persists
  - [ ] Phase 1 (GATE): Spike alignment model on Apple Silicon, decide Core ML vs MLX vs whisper.cpp
  - [ ] Phase 2: ScreenCaptureKit Spotify-only audio capture, permission flow, sample→time mapping
  - [ ] Phase 3: Per-line alignment, `Romanizer`, `WordTimingCache`, `LyricsManager` integration, menu toggle
  - [ ] Phase 4: Japanese romanization polish, failure fallbacks, perf, cache eviction
  - [ ] Create alignment tests (Viterbi on synthetic emissions, cache round-trip, romanizer)
- [ ] **8.2 Claude Enrichment Fallback**
  - [ ] Create `ClaudeEnrichmentProvider.swift` (romanization + translation via Haiku API)
  - [ ] Add Keychain-based API key storage + settings UI
  - [ ] Register as lowest-priority fallback in `EnrichmentCoordinator`
  - [ ] Create `ClaudeEnrichmentTests.swift`

### Milestone 9: System Integration & Accessibility
- [ ] **9.1 Global Hotkey Customization**
  - [ ] Create `HotkeyBinding.swift` model and `HotkeyManager.swift`
  - [ ] Create `HotkeySettingsView.swift` with key recorder
  - [ ] Replace hardcoded shortcuts with configurable bindings
  - [ ] Add "Keyboard Shortcuts" section in `MenuBarView`
  - [ ] Create `HotkeyTests.swift`
- [ ] **9.2 Focus Mode Awareness**
  - [ ] Create `SpotifyLyricsFocusFilter.swift` (`SetFocusFilterIntent`)
  - [ ] Wire into existing App Intents infrastructure
  - [ ] Create `FocusFilterTests.swift`
- [ ] **9.3 Accessibility VoiceOver Mode**
  - [ ] Add accessibility labels to `LyricLineView` (line + enrichment)
  - [ ] Post `announcementRequested` on line change when VoiceOver active
  - [ ] Add `.updatesFrequently` trait to `MiniOverlayView`
  - [ ] Suppress announcements during instrumental breaks
  - [ ] Create `AccessibilityTests.swift`
- [ ] **9.4 Menu Bar Scrolling Lyric**
  - [ ] Add dynamic title to `StatusBarController` with truncation
  - [ ] Implement marquee animation for long lines
  - [ ] Add `showMenuBarLyric` toggle to `OverlayController` + `MenuBarView`
  - [ ] Create `MenuBarLyricTests.swift`

---

## Verification Plan

After each feature, verify:

1. **Build:** `swift build` passes with no errors
2. **Tests:** `swift run SpotifyLyricsTests` — all existing + new tests pass
3. **Manual testing per feature:**
   - **Sync Offset:** Play a song, adjust slider, verify lyrics shift earlier/later, switch tracks and verify offset persists independently
   - **Multi-Display:** Move overlay, unplug external monitor, verify overlay returns to valid position, re-plug and verify it remembers the dual-monitor position
   - **Mood Theming:** Play songs with different moods (upbeat pop vs. slow ballad), verify overlay colors shift gradually
   - **Pronunciation:** Enable pronunciation for a Japanese/Korean song, verify phonetic guide appears below romanization
   - **Lyrics Search:** Play several songs, open search, type a lyric fragment, verify matching song appears
   - **Writing Kit:** Open card preview, focus caption field, verify Writing Kit suggestions appear (macOS 26+)
   - **Bookmarks:** Hover a lyric line, click heart, verify it appears in Favorites section, remove it
   - **Listening Stats:** Use app for a few songs, open stats, verify counters are reasonable
   - **Prefetch:** Play a track, wait for 75% mark, switch to next track, verify lyrics appear instantly (check console for "prefetch hit" log)
   - **Control Center Widget:** Open Control Center, verify current lyric line appears, tap to toggle overlay
   - **Overlay Themes:** Cycle through all 6 themes, verify each applies distinct background/font/color
   - **Custom Font:** Pick a serif font at 150% size, verify overlay text changes, switch back to default
   - **Album Art Parallax:** Scroll lyrics, verify background image shifts subtly. Enable Reduce Motion, verify parallax stops
   - **Lyrics Explanation:** Long-press a metaphorical lyric line, verify explanation popover appears with cultural context
   - **Vocabulary Builder:** Play a Japanese song with translation on, tap an underlined word, verify definition popover, save to word bank, check word bank list
   - **Lyrics Correction:** Play a song with known bad lyrics, verify correction icon appears on fixed lines, right-click to revert
   - **Session Summary:** Play 3+ songs, verify "Tonight's Vibe" appears in menu bar with thematic summary
   - **Lyrics Export:** Export as .lrc, open in text editor, verify timestamps match. Export as PDF, verify album art header
   - **Quick Share:** Right-click a line → Share... → verify Messages/AirDrop options appear
   - **Sing-Along:** Enable sing-along, sing a line, verify score circle updates in real-time
   - **Local Forced Alignment:** Enable word-level sync, play a vocal-forward English track, let it play through; on replay confirm karaoke fill lands on words; relaunch and confirm disk cache hit (no re-capture). Disable/deny → graceful interpolation fallback
   - **Claude Enrichment:** Enter API key, play a song in unsupported language, verify romanization/translation via Claude. Remove key, verify fallback to ICU/Apple providers
   - **Hotkey Customization:** Open shortcuts settings, rebind toggle overlay to Cmd+Shift+K, verify old binding stops working and new one works
   - **Focus Mode:** Set up Work focus filter to hide overlay, activate Work focus, verify overlay hides, deactivate, verify overlay returns
   - **VoiceOver:** Enable VoiceOver, play a song, verify each line is announced with enrichment. Verify instrumental break suppresses announcement
   - **Menu Bar Lyric:** Enable menu bar lyric, verify current line appears next to icon, play a song with long lines, verify marquee scrolling
4. **Regression:** All Phase 1 features (mini mode, instrumental breaks, AI summary, App Intents, lyrics cards) unchanged
