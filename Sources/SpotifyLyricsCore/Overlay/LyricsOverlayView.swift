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
    @State private var scrollGeneration = 0
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
                        SummaryMarqueeText(summary)
                    }
                }
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .padding(.trailing, 34)
                .frame(maxWidth: .infinity, alignment: .leading)
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
            animateToLine(lyricsManager.currentLineIndex, proxy: proxy)
        }
    }

    /// Single entry point for moving the active line. Centers `index` and updates the active
    /// state inside *one* spring transaction, so the scroll offset and the per-line
    /// scale/opacity ride the exact same curve (mismatched curves read as jank). A generation
    /// token guards `isAutoScrolling`: during a rapid run of line changes, only the latest
    /// transition's timer clears the flag, so an early timer can't release it mid-flight and
    /// misread the tail of an auto-scroll as a user scroll.
    private func animateToLine(_ index: Int, proxy: ScrollViewProxy, animated: Bool = true) {
        isAutoScrolling = true
        scrollGeneration += 1
        let generation = scrollGeneration
        let move = {
            displayedLineIndex = index
            proxy.scrollTo(index, anchor: .center)
        }
        if animated {
            withAnimation(animationMode.transition, move)
        } else {
            move()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if generation == scrollGeneration { isAutoScrolling = false }
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
                                isManualScrolling = false
                                animateToLine(lyricsManager.currentLineIndex, proxy: proxy)
                            }
                    }

                    Spacer().frame(height: 60)
                }
                .padding(.horizontal, 24)
            }
            .mask(lyricPanelFadeMask)
            .onAppear {
                scrollProxy = proxy
                displayedLineIndex = lyricsManager.currentLineIndex
                // Jump (no animation) to the current line on first layout.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    animateToLine(lyricsManager.currentLineIndex, proxy: proxy, animated: false)
                }
            }
            .onChange(of: lyricsManager.currentLineIndex) { newIndex in
                guard !isManualScrolling else { return }
                animateToLine(newIndex, proxy: proxy)
            }
            .onUserScroll {
                guard !isAutoScrolling else { return }
                isManualScrolling = true
            }
            .onChange(of: lyricsManager.enrichment.count) { _ in
                // Enrichment toggled (translation/romanization) changes line heights, so
                // re-center the current line once the new layout settles.
                isManualScrolling = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    animateToLine(lyricsManager.currentLineIndex, proxy: proxy)
                }
            }
        }
    }

    private var lyricPanelFadeMask: some View {
        let stops = LyricPanelFadeStops()
        return LinearGradient(
            stops: [
                .init(color: .clear, location: stops.topClear),
                .init(color: .black, location: stops.topOpaque),
                .init(color: .black, location: stops.bottomOpaque),
                .init(color: .clear, location: stops.bottomClear)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Builds a line view. Every line uses the same `TimelineView` structure to keep
    /// SwiftUI view identity stable across active-state changes. Only the active
    /// karaoke/glow line actually runs per-frame; others are paused (zero cost).
    @ViewBuilder
    private func lineView(index: Int, line: LyricLine) -> some View {
        let activeIndex = displayedLineIndex
        let isActive = index == activeIndex
        let lineEnrichment = lyricsManager.enrichment[index]
        let shareHandler: (LyricLine, LineEnrichment?) -> Void = { line, enrichment in
            generateCardPreview(line: line, enrichment: enrichment)
        }
        let needsPerFrame = isActive && (animationMode == .karaoke || animationMode == .glow)

        TimelineView(.animation(minimumInterval: nil, paused: !needsPerFrame)) { _ in
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
        VStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.45))

            Text(message)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        // Render-server breathing — no per-frame main-thread re-evaluation. These idle states
        // (waiting / loading / no lyrics) can persist for a whole track, so a TimelineView here
        // would burn the main thread at the display refresh rate for purely decorative motion.
        .breathing()
    }
}

// MARK: - Lyric panel fade

public struct LyricPanelFadeStops: Equatable {
    public let topClear: CGFloat
    public let topOpaque: CGFloat
    public let bottomOpaque: CGFloat
    public let bottomClear: CGFloat

    public init(
        topClear: CGFloat = 0,
        topOpaque: CGFloat = 0.16,
        bottomOpaque: CGFloat = 0.84,
        bottomClear: CGFloat = 1
    ) {
        self.topClear = topClear
        self.topOpaque = topOpaque
        self.bottomOpaque = bottomOpaque
        self.bottomClear = bottomClear
    }
}

// MARK: - AI summary marquee

public struct SummaryMarqueeMetrics: Equatable {
    public static let minimumDuration: Double = 5
    public static let pointsPerSecond: CGFloat = 22
    private static let measurementTolerance: CGFloat = 1

    public let containerWidth: CGFloat
    public let contentWidth: CGFloat

    public init(containerWidth: CGFloat, contentWidth: CGFloat) {
        self.containerWidth = max(0, containerWidth)
        self.contentWidth = max(0, contentWidth)
    }

    public var shouldScroll: Bool {
        contentWidth > containerWidth + Self.measurementTolerance
    }

    public var scrollDistance: CGFloat {
        shouldScroll ? contentWidth - containerWidth : 0
    }

    public var duration: Double {
        guard shouldScroll else { return 0 }
        return max(Self.minimumDuration, Double(scrollDistance / Self.pointsPerSecond))
    }
}

private struct SummaryMarqueeText: View {
    let text: String

    @State private var containerWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var isShiftedLeft = false
    @State private var animationGeneration = 0

    init(_ text: String) {
        self.text = text
    }

    private var metrics: SummaryMarqueeMetrics {
        SummaryMarqueeMetrics(containerWidth: containerWidth, contentWidth: contentWidth)
    }

    var body: some View {
        GeometryReader { proxy in
            let currentMetrics = SummaryMarqueeMetrics(
                containerWidth: proxy.size.width,
                contentWidth: contentWidth
            )

            Text(text)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .italic()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: isShiftedLeft && currentMetrics.shouldScroll ? -currentMetrics.scrollDistance : 0)
                .background(
                    GeometryReader { textProxy in
                        Color.clear.preference(key: SummaryTextWidthPreferenceKey.self, value: textProxy.size.width)
                    }
                )
                .animation(
                    currentMetrics.shouldScroll
                        ? .easeInOut(duration: currentMetrics.duration).repeatForever(autoreverses: true)
                        : .default,
                    value: isShiftedLeft
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .onAppear {
                    containerWidth = proxy.size.width
                    restartAnimation()
                }
                .onChange(of: proxy.size.width) { width in
                    containerWidth = width
                    restartAnimation()
                }
        }
        .frame(height: 14)
        .clipped()
        .onPreferenceChange(SummaryTextWidthPreferenceKey.self) { width in
            contentWidth = width
            restartAnimation()
        }
        .onChange(of: text) { _ in
            restartAnimation()
        }
    }

    private func restartAnimation() {
        animationGeneration += 1
        let generation = animationGeneration
        isShiftedLeft = false

        guard metrics.shouldScroll else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard generation == animationGeneration else { return }
            isShiftedLeft = true
        }
    }
}

private struct SummaryTextWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Render-server breathing pulse

/// A gentle scale+opacity "breathing" loop driven entirely by Core Animation (the render
/// server), so it costs nothing on the main thread — unlike `TimelineView(.animation)`, which
/// re-evaluates the SwiftUI body every frame. Use for purely decorative, always-on motion.
struct BreathingModifier: ViewModifier {
    var duration: Double = 1.7
    var minScale: CGFloat = 1.0
    var maxScale: CGFloat = 1.05
    var minOpacity: Double = 0.7
    var maxOpacity: Double = 1.0

    @State private var on = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? maxScale : minScale)
            .opacity(on ? maxOpacity : minOpacity)
            .onAppear {
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

extension View {
    func breathing(duration: Double = 1.7, minScale: CGFloat = 1.0, maxScale: CGFloat = 1.05,
                   minOpacity: Double = 0.7, maxOpacity: Double = 1.0) -> some View {
        modifier(BreathingModifier(duration: duration, minScale: minScale, maxScale: maxScale,
                                   minOpacity: minOpacity, maxOpacity: maxOpacity))
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
