import SwiftUI
import AppKit

public struct LyricsOverlayView: View {
    @ObservedObject var lyricsManager: LyricsManager
    @ObservedObject var playerManager: SpotifyPlayerManager
    @Binding var backgroundOpacity: Double
    @Binding var animationMode: AnimationMode
    var onClose: (() -> Void)?

    public init(lyricsManager: LyricsManager, playerManager: SpotifyPlayerManager, backgroundOpacity: Binding<Double> = .constant(0.85), animationMode: Binding<AnimationMode> = .constant(.karaoke), onClose: (() -> Void)? = nil) {
        self.lyricsManager = lyricsManager
        self.playerManager = playerManager
        self._backgroundOpacity = backgroundOpacity
        self._animationMode = animationMode
        self.onClose = onClose
    }

    @State private var isManualScrolling = false
    @State private var isAutoScrolling = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var isOverlayHovered = false
    @State private var displayedLineIndex: Int = 0
    @State private var cardPreviewImage: NSImage?
    @State private var showCardPreview = false
    private let cardGenerator = LyricsCardGenerator()

    public var body: some View {
        ZStack {
            if !playerManager.isSpotifyRunning {
                statusView("Waiting for Spotify...")
            } else if lyricsManager.isLoading {
                statusView("Loading lyrics...")
            } else if !lyricsManager.hasLyrics {
                statusView("No lyrics available")
            } else {
                ZStack {
                    lyricsScrollView
                        .opacity(lyricsManager.isInstrumentalBreak ? 0 : 1)

                    if lyricsManager.isInstrumentalBreak {
                        InstrumentalBreakView(
                            lyricsManager: lyricsManager,
                            playerManager: playerManager
                        )
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.5), value: lyricsManager.isInstrumentalBreak)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .opacity(backgroundOpacity)
        )
        .overlay(alignment: .topLeading) {
            if let track = playerManager.currentTrack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(track.artist)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    if let summary = lyricsManager.songSummary {
                        Text(summary)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                            .italic()
                    }
                }
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .opacity(isOverlayHovered ? 1 : 0)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: { onClose?() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(.white.opacity(0.15)))
            }
            .buttonStyle(ControlButtonStyle(size: 24))
            .padding(10)
            .opacity(isOverlayHovered ? 1 : 0)
            .allowsHitTesting(isOverlayHovered)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 6) {
                ZStack {
                    MusicControlsView(playerManager: playerManager, style: .compact)

                    if isManualScrolling {
                        Button {
                            scrollBackToCurrent()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Current")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.white.opacity(0.15)))
                        }
                        .buttonStyle(PillButtonStyle())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .transition(.opacity)
                    }
                }
                SeekBarView(playerManager: playerManager)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            )
            .opacity(isOverlayHovered && playerManager.isSpotifyRunning ? 1 : 0)
            .allowsHitTesting(isOverlayHovered && playerManager.isSpotifyRunning)
        }
        .animation(.easeInOut(duration: 0.2), value: isOverlayHovered)
        .onWindowHover { isOverlayHovered = $0 }
        .overlay {
            if showCardPreview, let image = cardPreviewImage {
                cardPreviewOverlay(image: image)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showCardPreview)
    }

    @ViewBuilder
    private func cardPreviewOverlay(image: NSImage) -> some View {
        ZStack {
            Color.black.opacity(0.7)
                .onTapGesture { showCardPreview = false }

            VStack(spacing: 12) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 280, maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 10)

                HStack(spacing: 10) {
                    Button("Copy to Clipboard") {
                        cardGenerator.copyToClipboard(image)
                        showCardPreview = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Cancel") {
                        showCardPreview = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func scrollBackToCurrent() {
        isManualScrolling = false
        if let proxy = scrollProxy {
            isAutoScrolling = true
            withAnimation(animationMode.transition) {
                displayedLineIndex = lyricsManager.currentLineIndex
                proxy.scrollTo(lyricsManager.currentLineIndex, anchor: .center)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isAutoScrolling = false
            }
        }
    }

    private var lyricsScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    Spacer().frame(height: 60)

                    ForEach(Array(lyricsManager.currentLines.enumerated()), id: \.element.id) { index, line in
                        lineView(index: index, line: line)
                            .id(index)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                playerManager.seekTo(line.timestamp)
                                lyricsManager.updateCurrentLine(at: line.timestamp)
                                withAnimation(animationMode.transition) {
                                    displayedLineIndex = lyricsManager.currentLineIndex
                                }
                                isManualScrolling = false
                            }
                    }

                    Spacer().frame(height: 60)
                }
                .padding(.horizontal, 24)
            }
            .onAppear {
                scrollProxy = proxy
                displayedLineIndex = lyricsManager.currentLineIndex
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isAutoScrolling = true
                    proxy.scrollTo(lyricsManager.currentLineIndex, anchor: .center)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isAutoScrolling = false
                    }
                }
            }
            .onChange(of: lyricsManager.currentLineIndex) { newIndex in
                guard !isManualScrolling else { return }
                isAutoScrolling = true
                withAnimation(animationMode.transition) {
                    displayedLineIndex = newIndex
                    proxy.scrollTo(newIndex, anchor: .center)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    isAutoScrolling = false
                }
            }
            .onUserScroll {
                guard !isAutoScrolling else { return }
                isManualScrolling = true
            }
            .onChange(of: lyricsManager.enrichment.count) { _ in
                // When enrichment changes (translation/romanization toggled),
                // re-scroll to the current line so it stays centered.
                isManualScrolling = false
                isAutoScrolling = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(animationMode.transition) {
                        proxy.scrollTo(lyricsManager.currentLineIndex, anchor: .center)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isAutoScrolling = false
                    }
                }
            }
        }
    }

    /// Builds a line view. The active line is wrapped in a per-frame TimelineView
    /// for the karaoke fill and glow pulse; other lines render statically.
    @ViewBuilder
    private func lineView(index: Int, line: LyricLine) -> some View {
        let activeIndex = displayedLineIndex
        let isActive = index == activeIndex
        let lineEnrichment = lyricsManager.enrichment[index]
        let shareHandler: (LyricLine, LineEnrichment?) -> Void = { line, enrichment in
            generateCardPreview(line: line, enrichment: enrichment)
        }
        if isActive && (animationMode == .karaoke || animationMode == .glow) {
            TimelineView(.animation) { _ in
                LyricLineView(
                    line: line,
                    isActive: true,
                    offset: 0,
                    mode: animationMode,
                    position: playerManager.playbackPosition,
                    lineEnd: lineEnd(at: index),
                    enrichment: lineEnrichment,
                    onShareAsCard: shareHandler
                )
            }
        } else {
            LyricLineView(
                line: line,
                isActive: isActive,
                offset: index - activeIndex,
                mode: animationMode,
                position: playerManager.playbackPosition,
                lineEnd: lineEnd(at: index),
                enrichment: lineEnrichment,
                onShareAsCard: shareHandler
            )
        }
    }

    /// Effective end time for a line: its own end, else the next line's start.
    private func lineEnd(at index: Int) -> TimeInterval {
        let lines = lyricsManager.currentLines
        guard index < lines.count else { return 0 }
        if let end = lines[index].endTime { return end }
        if index + 1 < lines.count { return lines[index + 1].timestamp }
        return lines[index].timestamp + 5
    }

    private func generateCardPreview(line: LyricLine, enrichment: LineEnrichment?) {
        guard let track = playerManager.currentTrack else { return }
        let artworkURL = playerManager.artworkURL

        Task {
            // Download album artwork for the card background
            var artwork: NSImage?
            if let url = artworkURL {
                if let (data, _) = try? await URLSession.shared.data(from: url) {
                    artwork = NSImage(data: data)
                }
            }

            let image = cardGenerator.generateCard(
                line: line,
                enrichment: enrichment,
                title: track.title,
                artist: track.artist,
                artworkImage: artwork
            )
            cardPreviewImage = image
            showCardPreview = true
        }
    }

    private func statusView(_ message: String) -> some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            let breathe = (sin(phase * 1.8) + 1) / 2 // 0…1

            VStack(spacing: 10) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white.opacity(0.3 + 0.25 * breathe))
                    .scaleEffect(1.0 + 0.06 * breathe)

                Text(message)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4 + 0.2 * breathe))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

// MARK: - Window-level hover tracking

/// Uses NSEvent mouseMoved monitoring to track whether the cursor is inside
/// the hosting window. Much more reliable than SwiftUI's .onHover in NSPanel.
struct WindowHoverModifier: ViewModifier {
    let onHoverChanged: (Bool) -> Void
    @State private var monitor: Any?
    @State private var isInside = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseEntered, .mouseExited]) { event in
                    guard let window = event.window ?? NSApp.windows.first(where: {
                        $0 is NSPanel && $0.isVisible && $0.styleMask.contains(.nonactivatingPanel)
                    }) else {
                        if isInside {
                            isInside = false
                            onHoverChanged(false)
                        }
                        return event
                    }

                    let mouseLocation = NSEvent.mouseLocation
                    let inside = window.frame.contains(mouseLocation)

                    if inside != isInside {
                        isInside = inside
                        onHoverChanged(inside)
                    }
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
            }
    }
}

// MARK: - Scroll wheel detection

struct UserScrollModifier: ViewModifier {
    let onUserScroll: () -> Void
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    let isUserTrackpad = event.phase == .began || event.phase == .changed
                    let isMouseWheel = event.phase == []
                        && event.momentumPhase == []
                        && abs(event.deltaY) > 0.5

                    if isUserTrackpad || isMouseWheel {
                        onUserScroll()
                    }
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
            }
    }
}

extension View {
    func onUserScroll(_ action: @escaping () -> Void) -> some View {
        modifier(UserScrollModifier(onUserScroll: action))
    }

    func onWindowHover(_ action: @escaping (Bool) -> Void) -> some View {
        modifier(WindowHoverModifier(onHoverChanged: action))
    }
}
