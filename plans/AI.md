# Local Forced-Alignment for Word-Accurate Karaoke

## Context

We shipped multi-mode lyric animation with a **Karaoke** mode that fills the active line.
Today the fill uses real word timings only when the source provides them (enhanced-LRC or
commercial Musixmatch richsync); otherwise it interpolates across the line. Most lyrics are
**line-level only**, so karaoke usually falls back to interpolation.

This change adds an **optional, on-device** path to derive true per-word timings by aligning
the *known* lyrics to the song's audio — no commercial API, fully local. The user chose:
- **Engine:** wav2vec2/MMS **CTC forced alignment** (aligns known text to audio; multilingual incl. Japanese). Not ASR.
- **Distribution:** a **self-signed `.app` bundle** with a stable local cert so the Screen Recording grant persists across rebuilds.

**Key de-risking insight:** we already have **line-level timestamps**. So this is *not*
full-song alignment — it's "place N known words inside a known ~3–5s line window." Errors are
bounded per line, and even modest models do well in short, anchored windows.

**The feature is fully decoupled and off by default.** The overlay already consumes
`LyricLine.words` via `fillFraction`; if alignment is disabled, unavailable, denied, or fails,
karaoke uses the existing interpolation fallback with zero regression.

## How it works (runtime flow)

1. Track changes (`SpotifyPlayerManager.onTrackChanged`) → lyrics load (existing path).
2. If a **word-timing cache hit** exists on disk for `track.cacheKey` → enrich `currentLines`, done.
3. Else, if **Local word-sync is enabled** and Screen Recording is granted → start capturing
   **Spotify-only** audio while the song plays (first listen).
4. On track end / change, run the alignment pass **off-main**:
   for each LRC line, take the audio window `[line.timestamp, nextLine.timestamp]` (mapped from
   capture start), romanize the line text, run the CTC model → emissions, run a forced-align
   Viterbi constrained to the line's tokens → per-word absolute start/end → `[LyricWord]`.
5. Persist enriched `[LyricLine]` to disk (keyed by `cacheKey`) and update `LyricsManager`.
   The next play (or the current one, if still playing) shows word-accurate karaoke.

## Components (new `Sources/SpotifyLyricsCore/Alignment/`)

- **`AudioCaptureService.swift`** — ScreenCaptureKit `SCStream` with `SCContentFilter` targeting
  the Spotify app, `capturesAudio = true`, 2×2 video. Downmix to **mono 16 kHz Float** (model
  rate), buffer the full song (~15 MB for 4 min), and record the capture-start offset vs
  `playerManager.playbackPosition` so sample index ↔ song time. Permission via
  `SCShareableContent` (request/check). Start/stop tied to play state + track changes.
- **`ForcedAligner.swift`** — loads the Core ML acoustic model, produces CTC emissions for an
  audio window, and runs a forced-alignment Viterbi against a token sequence (torchaudio-style
  `forced_align`), returning word time spans. (Or wraps the dependency chosen in Phase 1.)
- **`Romanizer.swift`** — lyric text → model token sequence. Latin path = lowercase/strip;
  Japanese = kana→romaji table; kanji-heavy lines are best-effort and fall back to interpolation
  when unromanizable (documented limitation).
- **`LyricsAlignmentCoordinator.swift`** — orchestrates capture lifecycle, runs per-line
  alignment in the background, writes the cache, and pushes results into `LyricsManager`.
- **`WordTimingCache.swift`** — on-disk JSON cache under Application Support keyed by `cacheKey`.

## Edits to existing code

- **Models** (`LyricLine.swift`, `LyricWord.swift`): add `Codable` for the disk cache (keep the
  existing `Equatable`/`fillFraction`). `LyricsManager.words` consumption is already done.
- **`LyricsManager.swift`**: check `WordTimingCache` during `fetchLyrics(for:)`; add a method to
  merge aligned word timings into `currentLines` and the in-memory `cache`.
- **`OverlayController`** (`SpotifyLyricsApp.swift`): add `@Published var localAlignmentEnabled = false`
  (persisted via UserDefaults, mirroring `animationMode`); wire the coordinator on launch.
- **`MenuBarView.swift`**: add a "Word-level sync (local)" toggle + a small status line
  (Off / Listening… / Aligning… / Ready), following the existing `settingsRow` pattern.

## Phasing (de-risk before plumbing)

- **Phase 0 — Packaging (prerequisite).** Add `bundle.sh` (+ README update) that assembles
  `SpotifyLyrics.app/Contents/{MacOS,Resources,Info.plist}`, embeds `Info.plist`, copies the
  model resource, and codesigns with a **stable self-signed identity** (documented one-time
  `security`/cert-creation step). Verify the app appears in System Settings → Privacy →
  **Screen Recording** and that the grant **persists across rebuilds**.
- **Phase 1 — Alignment spike (GATE).** Before building plumbing, prove the model + runtime can
  align one known English line window to a captured audio clip on Apple Silicon and emit
  plausible, monotonic word times. Decide the concrete vehicle: **torchaudio `MMS_FA` → Core ML**
  (+ Swift Viterbi) vs. an existing Swift/MLX aligner package (e.g. `soniqo/speech-swift`).
  Settle model **bundling vs first-run download** (hundreds of MB). If accuracy/feasibility is
  poor, fall back to **line-constrained whisper.cpp**.
- **Phase 2 — Audio capture.** ScreenCaptureKit Spotify-only capture, permission flow, buffer +
  sample→time mapping; validate captured duration and line-boundary alignment via logs.
- **Phase 3 — Pipeline + cache + settings.** Per-line alignment, romanization, `WordTimingCache`,
  `LyricsManager` integration, the menu toggle + status, end-to-end on a real track.
- **Phase 4 — Polish.** Japanese romanization quality, failure fallbacks, perf, cache eviction.

## Risks (explicit)

- **Japanese kanji** romanization on-device is hard (needs a reading dictionary); v1 handles
  kana/romaji well, kanji-heavy lines fall back to interpolation.
- **Music vs. speech:** sung vocals over a full mix reduce accuracy; line-constraining mitigates.
  Optional future: on-device vocal separation.
- **Model size** (hundreds of MB) → bundle vs download decision in Phase 1.
- **Apple-Silicon-leaning** (Core ML / ANE / MLX).
- **First listen has no word timing** (capture+align happen during/after the first play); cached
  thereafter. This is inherent to having no audio-file access (Spotify exposes none).

## Verification

- **Phase 0:** build `SpotifyLyrics.app`, confirm it's listed under Screen Recording; grant,
  rebuild, confirm the grant persists (stable cert).
- **Phase 1:** CLI/unit test aligning a known line over a sample wav; assert word times are
  monotonic and within the window. Viterbi on synthetic emissions is deterministic → unit-testable.
- **Capture:** log captured-vs-song duration; assert sample→time mapping matches known line bounds.
- **End-to-end:** play a vocal-forward English track with synced LRC, enable the setting, let it
  play through; on replay confirm the karaoke fill lands on words; relaunch and confirm a disk
  cache hit (no re-capture). Disable/deny → graceful interpolation fallback, no crash.
- **Tests** (extend the custom runner in `Tests/`): `WordTimingCache` Codable round-trip,
  `Romanizer` (Latin + kana), aligner Viterbi on synthetic emissions, toggle persistence.
- **Build/test toolchain:** `export PATH="$HOME/.swiftly/bin:$PATH"` then `swift build` /
  `swift run SpotifyLyricsTests` (system CLI is Swift 5.10 and cannot build this package).
