import AppKit

/// The logo glyph (crotchet whose stem becomes a tuning fork) for the menu bar, in the logo's gold
/// gradient. Coordinates match design/logo.svg (1024-unit canvas, y down). The vibration arcs show
/// while active. Drawn at display time, so the shades follow the menu bar's light/dark appearance.
enum MenuBarIcon {
    private static let cache = [false: make(active: false), true: make(active: true)]

    static func image(active: Bool) -> NSImage { cache[active]! }

    private static func make(active: Bool) -> NSImage {
        let height: CGFloat = 18
        let width: CGFloat = active ? 22 : 12
        let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // Glyph spans y 196...870 in logo units (with arcs: x 270...810).
            let scale = height / 690
            let transform = CGAffineTransform(translationX: width / 2, y: 0)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -540, y: -190)

            // The logo's gold reads well on a dark menu bar; a light one needs deeper shades.
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let colors = dark ? [rgb(0xFFE08A), rgb(0xFF9B3D)] : [rgb(0xF2A51F), rgb(0xC9560E)]
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                      colors: colors as CFArray, locations: [0, 1])!

            // Each piece is clipped and filled separately so overlapping outlines can't cancel out.
            func fill(_ path: CGPath, alpha: CGFloat = 1) {
                ctx.saveGState()
                ctx.setAlpha(alpha)
                ctx.addPath(path)
                ctx.clip()
                ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
                ctx.restoreGState()
            }
            func stroked(_ path: CGPath, units: CGFloat) -> CGPath {
                path.copy(strokingWithWidth: units, lineCap: .round, lineJoin: .round, miterLimit: 10,
                          transform: transform)
            }

            // Fork prongs: down, around a half circle, back up.
            let fork = CGMutablePath()
            fork.move(to: CGPoint(x: 450, y: 236))
            fork.addLine(to: CGPoint(x: 450, y: 414))
            fork.addArc(center: CGPoint(x: 540, y: 414), radius: 90, startAngle: .pi, endAngle: 0, clockwise: true)
            fork.addLine(to: CGPoint(x: 630, y: 236))
            fill(stroked(fork, units: 64))

            let stem = CGMutablePath()
            stem.move(to: CGPoint(x: 540, y: 504))
            stem.addLine(to: CGPoint(x: 540, y: 770))
            fill(stroked(stem, units: 64))

            let headTransform = CGAffineTransform(translationX: 478, y: 782)
                .rotated(by: -24 * .pi / 180)
                .translatedBy(x: -478, y: -782)
                .concatenating(transform)
            fill(CGPath(ellipseIn: CGRect(x: 478 - 112, y: 782 - 84, width: 224, height: 168),
                        transform: [headTransform]))

            if active {
                for (x, bulge) in [(CGFloat(352), CGFloat(-40)), (728, 40)] {
                    let arc = CGMutablePath()
                    arc.move(to: CGPoint(x: x, y: 262))
                    arc.addCurve(to: CGPoint(x: x, y: 418), control1: CGPoint(x: x + bulge, y: 300),
                                 control2: CGPoint(x: x + bulge, y: 380))
                    fill(stroked(arc, units: 48), alpha: 0.85)
                }
            }
            return true
        }
        image.accessibilityDescription = active ? "PitchTap (on)" : "PitchTap"
        return image
    }

    private static func rgb(_ hex: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
