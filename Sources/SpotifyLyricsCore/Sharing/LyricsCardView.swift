import SwiftUI

/// SwiftUI template for a shareable lyrics card image.
/// Renders a single lyric line over a blurred album art background
/// with optional enrichment text and artist credit.
public struct LyricsCardView: View {
    public let lineText: String
    public let romanization: String?
    public let translation: String?
    public let title: String
    public let artist: String
    public let artworkImage: NSImage?
    public let accentColor: Color
    public let size: CGSize

    public init(
        lineText: String,
        romanization: String? = nil,
        translation: String? = nil,
        title: String,
        artist: String,
        artworkImage: NSImage? = nil,
        accentColor: Color = .white,
        size: CGSize = CGSize(width: 1080, height: 1080)
    ) {
        self.lineText = lineText
        self.romanization = romanization
        self.translation = translation
        self.title = title
        self.artist = artist
        self.artworkImage = artworkImage
        self.accentColor = accentColor
        self.size = size
    }

    public var body: some View {
        ZStack {
            // Background
            if let artworkImage {
                Image(nsImage: artworkImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 30)
                    .scaleEffect(1.3)
            } else {
                LinearGradient(
                    colors: [Color(white: 0.15), Color(white: 0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            // Dark overlay
            Color.black.opacity(0.45)

            // Content
            VStack(spacing: 0) {
                Spacer()

                // Accent quote mark
                Text("\u{201C}")
                    .font(.system(size: 72, weight: .bold, design: .serif))
                    .foregroundStyle(accentColor.opacity(0.5))
                    .padding(.bottom, -20)

                // Romanization (above main text)
                if let romanization {
                    Text(romanization)
                        .font(.system(size: fontSize * 0.55, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.bottom, 8)
                }

                // Main lyric text
                Text(lineText)
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.6), radius: 8, y: 3)
                    .padding(.horizontal, horizontalPadding)

                // Translation (below main text)
                if let translation {
                    Text(translation)
                        .font(.system(size: fontSize * 0.5, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .italic()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 12)
                }

                Spacer()

                // Credit line
                HStack(spacing: 4) {
                    Text("\(title)")
                        .fontWeight(.semibold)
                    Text("—")
                    Text(artist)
                }
                .font(.system(size: creditFontSize, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .padding(.bottom, bottomPadding)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var fontSize: CGFloat { size.width * 0.045 }
    private var creditFontSize: CGFloat { size.width * 0.018 }
    private var horizontalPadding: CGFloat { size.width * 0.1 }
    private var bottomPadding: CGFloat { size.height * 0.06 }
}
