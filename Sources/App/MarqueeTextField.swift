import AppKit

final class MarqueeTextField: NSView {
    var text: NSString? {
        didSet {
            guard text != oldValue else { return }
            stringSize = text?.size(withAttributes: textFontAttributes) ?? NSSize(width: 0, height: 0)
            point.x = 0
            setNeedsDisplay(bounds)
            updateTraits()
        }
    }

    var font: NSFont = .systemFont(ofSize: 13.5) {
        didSet {
            textFontAttributes[.font] = font
            if let text {
                stringSize = text.size(withAttributes: textFontAttributes)
            }
            setNeedsDisplay(bounds)
            updateTraits()
        }
    }

    var textColor: NSColor = .headerTextColor {
        didSet { setNeedsDisplay(bounds) }
    }

    var spacing: CGFloat = 20
    var delay: TimeInterval = 2
    var speed: Double = 4 {
        didSet { updateTraits() }
    }

    private var timer: Timer?
    private var point = NSPoint(x: 0, y: 0)
    private(set) var stringSize = NSSize(width: 0, height: 0)

    private var timerSpeed: Double { speed / 100 }

    private lazy var textFontAttributes: [NSAttributedString.Key: Any] = [
        .font: font
    ]

    var textWidth: CGFloat { stringSize.width }

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let text else { return }

        // Clip drawing to view bounds
        NSBezierPath(rect: bounds).addClip()

        // Wrap around: when the first copy scrolls fully off-screen, reset
        if point.x + stringSize.width < 0 {
            point.x += stringSize.width + spacing
        }

        textFontAttributes[.foregroundColor] = textColor
        text.draw(at: point, withAttributes: textFontAttributes)

        // Draw a second copy for seamless looping
        if point.x < 0 {
            var otherPoint = point
            otherPoint.x += stringSize.width + spacing
            text.draw(at: otherPoint, withAttributes: textFontAttributes)
        }
    }

    override func layout() {
        super.layout()
        point.y = (frame.height - stringSize.height) / 2
        updateTraits()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            textColor = .white
        } else {
            textColor = .headerTextColor
        }
    }

    // MARK: - Scrolling

    func stopScrolling() {
        clearTimer()
        point.x = 0
        setNeedsDisplay(bounds)
    }

    private func updateTraits() {
        clearTimer()

        if stringSize.width > frame.width && text != nil {
            // Delay before starting scroll
            timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.startScrollTimer()
            }
        }
    }

    private func startScrollTimer() {
        clearTimer()
        let interval = timerSpeed
        guard interval > 0, text != nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func tick() {
        point.x -= 1
        setNeedsDisplay(bounds)
    }

    private func clearTimer() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}
