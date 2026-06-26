import SwiftUI

/// A SwiftUI marquee/scrolling text view for long text that overflows its container.
/// Text scrolls continuously when it's wider than the available space, with seamless looping.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 14, weight: .semibold)
    var spacing: CGFloat = 30
    var speed: Double = 30 // points per second
    var initialDelay: TimeInterval = 2.0

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var startTime: Date? = nil
    @State private var delayTask: DispatchWorkItem? = nil

    private var needsScroll: Bool { textWidth > containerWidth && containerWidth > 0 }
    private var totalCycleWidth: CGFloat { textWidth + spacing }

    var body: some View {
        GeometryReader { geo in
            let containerW = geo.size.width

            Group {
                if needsScroll, startTime != nil {
                    TimelineView(.animation) { timeline in
                        let elapsed = timeline.date.timeIntervalSince(startTime ?? timeline.date)
                        let rawOffset = elapsed * speed
                        let cycleOffset = rawOffset.truncatingRemainder(dividingBy: totalCycleWidth)

                        Canvas { context, size in
                            let resolved = context.resolve(resolvedText)

                            // First copy
                            let x1 = -cycleOffset
                            context.draw(resolved, at: CGPoint(x: x1, y: size.height / 2), anchor: .leading)

                            // Second copy for seamless loop
                            let x2 = x1 + totalCycleWidth
                            if x2 < size.width + textWidth {
                                context.draw(resolved, at: CGPoint(x: x2, y: size.height / 2), anchor: .leading)
                            }
                        }
                        .frame(width: containerW)
                    }
                } else {
                    textContent
                        .frame(width: containerW, alignment: .center)
                }
            }
            .clipped()
            .onAppear {
                containerWidth = containerW
                scheduleStart()
            }
            .onChange(of: containerW) { newW in
                containerWidth = newW
                resetAndSchedule()
            }
            .onChange(of: text) { _ in
                resetAndSchedule()
            }
            .onChange(of: textWidth) { _ in
                resetAndSchedule()
            }
        }
        .frame(height: textHeight)
        .background(
            textContent
                .fixedSize()
                .background(GeometryReader { geo in
                    Color.clear
                        .onAppear { textWidth = geo.size.width }
                        .onChange(of: text) { _ in
                            DispatchQueue.main.async { textWidth = geo.size.width }
                        }
                })
                .hidden()
        )
    }

    private var textContent: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
    }

    private var resolvedText: Text {
        Text(text)
            .font(font)
            .foregroundColor(.white)
    }

    private var textHeight: CGFloat { 22 }

    private func resetAndSchedule() {
        delayTask?.cancel()
        startTime = nil
        scheduleStart()
    }

    private func scheduleStart() {
        guard needsScroll, startTime == nil else { return }
        let task = DispatchWorkItem { [self] in
            if self.needsScroll {
                self.startTime = Date()
            }
        }
        delayTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay, execute: task)
    }
}
