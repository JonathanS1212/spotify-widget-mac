import AppKit
import CoreImage

/// Shows the current album art behind the desktop icons, like the iPhone lock screen: the cover
/// sits in the middle of a blurred, colour-rich version of itself and cross-fades when the track changes.
/// It draws in its own desktop-level window, so the real wallpaper is never touched.
final class AlbumWallpaper {
    static let shared = AlbumWallpaper()

    private var windows: [NSWindow] = []
    private var source: String?       // artwork URL on screen (or loading)
    private var current: (cover: CGImage, background: CGImage)?
    private let ciContext = CIContext()
    private let fade: CFTimeInterval = 0.7

    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.rebuildWindows() }
    }

    /// Call with the current artwork URL, or nil when nothing is playing.
    func show(_ artworkURL: String?) {
        guard let artworkURL, !artworkURL.isEmpty else { return hide() }
        guard artworkURL != source, let url = URL(string: artworkURL) else { return }
        source = artworkURL
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let cover = data.flatMap(NSImage.init(data:))?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            let background = cover.flatMap(self.blurred)
            DispatchQueue.main.async {
                guard self.source == artworkURL else { return }   // a newer track won
                guard let cover, let background else { self.source = nil; return }
                self.current = (cover, background)
                if self.windows.isEmpty { self.rebuildWindows() } else { self.windows.forEach(self.update) }
            }
        }.resume()
    }

    func hide() {
        source = nil
        current = nil
        let old = windows
        windows = []
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fade
            old.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { old.forEach { $0.orderOut(nil) } })
    }

    // MARK: Windows

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        guard current != nil else { return }
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.hasShadow = false
            window.backgroundColor = .black
            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            window.contentView = view
            window.setFrame(screen.frame, display: false)
            window.alphaValue = 0
            update(window)
            window.orderFront(nil)
            window.animator().alphaValue = 1
            windows.append(window)
        }
    }

    /// Swaps in the current artwork, cross-fading from whatever was there.
    private func update(_ window: NSWindow) {
        guard let current, let root = window.contentView?.layer else { return }
        let size = root.bounds.size
        let scale = window.backingScaleFactor

        let content = CALayer()
        content.frame = root.bounds
        content.contentsScale = scale

        let background = CALayer()
        background.frame = content.bounds
        background.contents = current.background
        background.contentsGravity = .resizeAspectFill
        background.magnificationFilter = .linear
        content.addSublayer(background)

        let dim = CALayer()
        dim.frame = content.bounds
        dim.backgroundColor = CGColor(gray: 0, alpha: 0.18)
        content.addSublayer(dim)

        let side = min(size.width, size.height) * 0.46
        let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
        let radius = side * 0.035
        let shadow = CALayer()
        shadow.frame = rect
        shadow.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: rect.size),
                                   cornerWidth: radius, cornerHeight: radius, transform: nil)
        shadow.shadowColor = .black
        shadow.shadowOpacity = 0.5
        shadow.shadowRadius = side * 0.06
        shadow.shadowOffset = CGSize(width: 0, height: -side * 0.03)
        let cover = CALayer()
        cover.frame = shadow.bounds
        cover.contents = current.cover
        cover.contentsGravity = .resizeAspectFill
        cover.cornerRadius = radius
        cover.masksToBounds = true
        cover.contentsScale = scale
        shadow.addSublayer(cover)
        content.addSublayer(shadow)

        let transition = CATransition()
        transition.type = .fade
        transition.duration = fade
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        root.add(transition, forKey: "fade")
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        root.addSublayer(content)
    }

    /// The artwork heavily blurred and saturated. Kept small (it has no detail left) and scaled up on screen.
    private func blurred(_ art: CGImage) -> CGImage? {
        let side: CGFloat = 160
        let input = CIImage(cgImage: art)
        let small = input.transformed(by: CGAffineTransform(scaleX: side / input.extent.width, y: side / input.extent.height))
        let output = small.clampedToExtent()
            .applyingGaussianBlur(sigma: side * 0.06)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.5, kCIInputBrightnessKey: -0.05])
            .cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
        return ciContext.createCGImage(output, from: output.extent)
    }
}
