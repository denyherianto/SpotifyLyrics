import SwiftUI
import AppKit

public struct LyricsOverlayView: View {
    @ObservedObject var lyricsManager: LyricsManager
    @ObservedObject var playerManager: SpotifyPlayerManager
    @Binding var backgroundOpacity: Double
    var onClose: (() -> Void)?

    public init(lyricsManager: LyricsManager, playerManager: SpotifyPlayerManager, backgroundOpacity: Binding<Double> = .constant(0.85), onClose: (() -> Void)? = nil) {
        self.lyricsManager = lyricsManager
        self.playerManager = playerManager
        self._backgroundOpacity = backgroundOpacity
        self.onClose = onClose
    }

    @State private var isManualScrolling = false
    @State private var isAutoScrolling = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var isOverlayHovered = false

    public var body: some View {
        ZStack {
            if !playerManager.isSpotifyRunning {
                statusView("Waiting for Spotify...")
            } else if lyricsManager.isLoading {
                statusView("Loading lyrics...")
            } else if !lyricsManager.hasLyrics {
                statusView("No lyrics available")
            } else {
                lyricsScrollView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .opacity(backgroundOpacity)
        )
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
    }

    private func scrollBackToCurrent() {
        isManualScrolling = false
        if let proxy = scrollProxy {
            isAutoScrolling = true
            withAnimation(.easeInOut(duration: 0.35)) {
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
                        LyricLineView(
                            text: line.text,
                            isActive: index == lyricsManager.currentLineIndex,
                            offset: index - lyricsManager.currentLineIndex
                        )
                        .id(index)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            playerManager.seekTo(line.timestamp)
                            lyricsManager.updateCurrentLine(at: line.timestamp)
                            isManualScrolling = false
                        }
                    }

                    Spacer().frame(height: 60)
                }
                .padding(.horizontal, 24)
            }
            .onAppear {
                scrollProxy = proxy
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
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isAutoScrolling = false
                }
            }
            .onUserScroll {
                guard !isAutoScrolling else { return }
                isManualScrolling = true
            }
        }
    }

    private func statusView(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 18, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
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
