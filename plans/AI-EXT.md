# AI Enrichment: Translation & Romanization — Development Plan

A tiered, swappable enrichment layer that adds per-line **translation** and
**romanization** beside `LyricsManager`, without blocking lyric display.

## Guiding decisions (made upfront)

- **Keep macOS 13 floor.** Gate newer backends with `if #available` rather than
  bumping the target. ICU romanization works on 13 and ships value immediately.
- **Enrichment is layered, not baked into `LyricLine`.** `LyricLine.id` is a
  fresh UUID per parse and `==` ignores enrichment, so attaching fields there is
  fragile. Instead publish a parallel `[Int: LineEnrichment]` keyed by line
  index — stable per song, reactive, keeps the parse model pure.
- **Enrichment is async and additive.** Lyrics render instantly;
  translation/romanization fade in as they resolve. A track change cancels
  in-flight work.

Two genuine open decisions (not assumed):

- Whether to ship the **paid Claude fallback** at all (Phase 7).
- The **default target language** (system locale vs. fixed).

## New types

```swift
// Models/LineEnrichment.swift
public struct LineEnrichment: Equatable {
    public var romanization: String?
    public var translation: String?
}

// Lyrics/Enrichment/LyricsEnrichmentProvider.swift
public protocol LyricsEnrichmentProvider: Sendable {
    var capabilities: EnrichmentCapabilities { get }   // .romanization, .translation
    func romanize(_ lines: [String], from: Locale.Language?) async throws -> [String?]
    func translate(_ lines: [String], to: Locale.Language, from: Locale.Language?) async throws -> [String?]
}
```

Backends, each declaring what it can do and gated by availability:

| Backend | File | Does | Min macOS | Key? |
|---|---|---|---|---|
| `ICURomanizationProvider` | `Enrichment/ICURomanizationProvider.swift` | romanize (`StringTransform.toLatin`) | 13 | no |
| `AppleTranslationProvider` | `Enrichment/AppleTranslationProvider.swift` | translate (`Translation` framework) | 15 | no |
| `FoundationModelsProvider` | `Enrichment/FoundationModelsProvider.swift` | romanize (JA), maybe translate (`LanguageModelSession`) | 26 + Apple Silicon | no |
| `ClaudeEnrichmentProvider` | `Enrichment/ClaudeEnrichmentProvider.swift` | both, any language (`URLSession`, Haiku) | 13 | yes |

An `EnrichmentCoordinator` picks the best available provider per capability from
user prefs, runs language detection (`NLLanguageRecognizer`) to skip no-op work
(already-Latin script → no romanization; already-target language → no
translation), and merges results.

## Phases

**Phase 0 — De-risk (½ day).** Spike two unknowns before committing:

- The `Translation` framework's `TranslationSession` is
  **SwiftUI-lifecycle-bound** (surfaced via `.translationTask`), not a
  free-standing async API. Confirm you can drive it from a hidden view host or
  accept the constraint. This is the biggest architectural wrinkle.
- Confirm `FoundationModels` (`LanguageModelSession`) availability/quality for
  JA romanization on your hardware. If weak, drop Phase 6.

**Phase 1 — Model + ICU romanization (macOS 13, no OS bump).** Add
`LineEnrichment`, the protocol, `EnrichmentCapabilities`,
`ICURomanizationProvider`, and `NLLanguageRecognizer`-based detection. Ships real
value on the lowest floor. Fully unit-testable.

**Phase 2 — `LyricsManager` integration.**
`Sources/SpotifyLyricsCore/Lyrics/LyricsManager.swift`

- Add `@Published public var enrichment: [Int: LineEnrichment] = [:]`.
- Add an `enrichmentCache: [String: [Int: LineEnrichment]]` keyed by
  `cacheKey + targetLang + flags`.
- After lyrics resolve, kick off a stored `Task` that fills enrichment; cancel it
  at the top of `fetchLyrics` so a track change abandons stale work. Clear
  `enrichment` alongside `currentLines`.

**Phase 3 — View.** `Overlay/LyricLineView.swift` — wrap `content` in a `VStack`
and render a secondary `Text` (romanization above or translation below,
dimmer/smaller) when `enrichment` for that line exists. Keep it **outside** the
karaoke mask so the fill geometry in `karaokeText` is unaffected.
`LyricsOverlayView.lineView` passes `lyricsManager.enrichment[index]` down.

**Phase 4 — Settings + menu bar.** Toggles for translation / romanization,
target-language picker, persisted in `UserDefaults` (already have
`SettingsPersistenceTests`). Surface in `MenuBarView`.

**Phase 5 — Apple Translation backend (macOS 15+, gated).** Wire
`AppleTranslationProvider` per the Phase 0 finding, including language-pack
download handling (`LanguageAvailability`).

**Phase 6 — Foundation Models backend (macOS 26+, gated).** JA romanization where
ICU is weak. Skip if Phase 0 showed poor quality.

**Phase 7 — Claude fallback (optional).** `URLSession` →
`https://api.anthropic.com/v1/messages` with `claude-haiku-4-5`, batching all
lines of a song into one structured-output call, cached per song. Needs Keychain
key storage + a settings UI. Only build if you want quality coverage on 13–14 or
unsupported languages.

**Phase 8 — Polish.** Verify `TimelineView`-per-frame active line doesn't
re-trigger enrichment reads, dedup concurrent requests, finalize caching.

## Testing (custom runner)

Register an `EnrichmentTests` in `Tests/TestRunner.swift`. Deterministic,
CI-safe targets: ICU transforms (known input→output), `NLLanguageRecognizer`
detection, and the coordinator's provider-selection/merge logic via **fake
providers**. On-device translation and Foundation Models aren't reproducible in
CI — keep them behind the protocol and test only the router. Build/test via
swiftly Swift 6.3.2 per the project toolchain.

## Sequencing

Phases 1→4 deliver a complete, shippable feature (romanization + the full
UI/settings pipeline) on macOS 13 with zero paid dependencies. Phases 5–7 are
independent backend add-ons that can land in any order behind the same protocol.
