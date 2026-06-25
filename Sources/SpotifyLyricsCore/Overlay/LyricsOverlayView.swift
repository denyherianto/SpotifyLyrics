import SwiftUI
import AppKit

public struct LyricsOverlayView: View {
    @ObservedObject var lyricsManager: LyricsManager
    @ObservedObject var playerManager: SpotifyPlayerManager

    public init(lyricsManager: LyricsManager, playerManager: SpotifyPlayerManager) {
        self.lyricsManager = lyricsManager
        self.playerManager = playerManager
    }

    @State private var isManualScrolling = false
    @State private var isAutoScrolling = false
    @State private var scrollProxy: ScrollViewProxy?

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
                .opacity(0.85)
        )
    }

    private var lyricsScrollView: some View {
        ZStack(alignment: .bottomTrailing) {
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
                    // Initial scroll to current line when lyrics view first appears
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

            // "Back to current" button
            if isManualScrolling {
                Button {
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
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Current")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    )
                }
                .buttonStyle(.plain)
                .padding(12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeInOut(duration: 0.2), value: isManualScrolling)
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

// MARK: - Scroll wheel detection

/// Detects user-initiated scroll wheel events using NSEvent phase tracking.
/// Programmatic scrolls (from scrollTo) are filtered out via a callback guard.
struct UserScrollModifier: ViewModifier {
    let onUserScroll: () -> Void
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    // User-initiated trackpad scrolls have a began/changed phase.
                    // Mouse scroll wheels have phase == .none but momentumPhase == .none too,
                    // AND they are direct user input — so we accept those.
                    // Programmatic scrolls from scrollTo typically have no user phase.
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
}
