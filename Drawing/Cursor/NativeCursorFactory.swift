#if os(macOS)
import AppKit

enum NativeCursorFactory {

    static func cursor(for editor: EditorCursor, state: EditorCursorState) -> NSCursor {
        switch editor {
        case .arrow: return .arrow
        case .text: return .iBeam
        case .panOpen: return .openHand
        case .panClosed: return .closedHand
        case .pointingHand: return .pointingHand
        case .notAllowed, .custom: return .operationNotAllowed
        case .move, .ruler: return CursorArt.move
        case .rotate: return CursorArt.rotate
        case .pen: return CursorArt.pen
        case .pencil: return CursorArt.pencil
        case .lasso: return CursorArt.lasso
        case .rectangularSelection: return CursorArt.rectangularSelection
        case .image: return CursorArt.image
        case .shape(let kind): return CursorArt.shape(kind)
        case .highlighter: return sizedHighlighter(width: state.highlighterWidth, scale: state.viewportScale)
        case .eraser: return sizedEraser(radius: state.eraserRadius, scale: state.viewportScale)
        case .resize(let direction): return resize(direction)
        }
    }

static func resize(_ direction: CornerDirection) -> NSCursor {
        CursorArt.directional(direction)
    }

    private static var highlighterCache: [Int: NSCursor] = [:]

    static func sizedHighlighter(width: CGFloat, scale: CGFloat) -> NSCursor {
        let screenWidth = max(width * scale, 12)
        let key = Int(screenWidth * 4)
        if let cached = highlighterCache[key] { return cached }
        let cursor = CursorArt.highlighter(width: screenWidth)
        highlighterCache[key] = cursor
        return cursor
    }

    private static var eraserCache: [Int: NSCursor] = [:]

    static func sizedEraser(radius: CGFloat, scale: CGFloat) -> NSCursor {
        let screenRadius = max(radius * scale, 5)
        let key = Int(screenRadius * 4)
        if let cached = eraserCache[key] { return cached }
        let cursor = CursorArt.eraser(radius: screenRadius)
        eraserCache[key] = cursor
        return cursor
    }

    private enum CursorArt {

        static let pen: NSCursor = makeCursor(size: CGSize(width: 18, height: 28), hotSpot: CGPoint(x: 9, y: 26)) { ctx, _ in
            let path = CGMutablePath()
            path.move(to: p(9, 26))
            path.addLine(to: p(6, 17))
            path.addLine(to: p(12, 17))
            path.closeSubpath()
            fillGlyph(ctx, path: path)

            let barrel = CGMutablePath()
            barrel.move(to: p(6, 16))
            barrel.addLine(to: p(12, 16))
            barrel.addLine(to: p(10, 7))
            barrel.addLine(to: p(8, 7))
            barrel.closeSubpath()
            fillGlyph(ctx, path: barrel)
        }

        static let pencil: NSCursor = makeCursor(size: CGSize(width: 20, height: 30), hotSpot: CGPoint(x: 10, y: 28)) { ctx, _ in
            let tip = CGMutablePath()
            tip.move(to: p(10, 28))
            tip.addLine(to: p(7, 18))
            tip.addLine(to: p(13, 18))
            tip.closeSubpath()
            fillGlyph(ctx, path: tip)

            let body = CGMutablePath()
            body.move(to: p(7, 17))
            body.addLine(to: p(13, 17))
            body.addLine(to: p(11, 6))
            body.addLine(to: p(8, 6))
            body.closeSubpath()
            fillGlyph(ctx, path: body)

            let eraser = CGMutablePath()
            eraser.addRoundedRect(in: CGRect(x: 7, y: 1, width: 6, height: 6), cornerWidth: 1.5, cornerHeight: 1.5)
            fillGlyph(ctx, path: eraser, fill: NSColor(calibratedWhite: 0.45, alpha: 1).cgColor)
        }

        static func highlighter(width: CGFloat) -> NSCursor {
            let height: CGFloat = 16
            let size = CGSize(width: width, height: height)
            return makeCursor(size: size, hotSpot: CGPoint(x: size.width / 2, y: size.height / 2)) { ctx, _ in
                let rect = CGRect(x: 0.5, y: 0.5, width: size.width - 1, height: size.height - 1)
                let path = CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil)
                ctx.saveGState()
                ctx.setFillColor(NSColor(calibratedWhite: 0, alpha: 0.32).cgColor)
                ctx.addPath(path)
                ctx.fillPath()
                ctx.setLineWidth(2)
                ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.95).cgColor)
                ctx.addPath(path)
                ctx.strokePath()
                ctx.restoreGState()

                let centerLine = CGMutablePath()
                centerLine.move(to: CGPoint(x: 5, y: size.height / 2))
                centerLine.addLine(to: CGPoint(x: size.width - 5, y: size.height / 2))
                strokeGlyph(ctx, path: centerLine, color: NSColor(calibratedWhite: 0.15, alpha: 0.85).cgColor, width: 1.2)
            }
        }

        static func eraser(radius: CGFloat) -> NSCursor {
            let diameter = radius * 2
            let pad: CGFloat = 9
            let size = CGSize(width: diameter + pad, height: diameter + pad)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let side = diameter
            return makeCursor(size: size, hotSpot: center) { ctx, _ in
                let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
                let path = CGPath(roundedRect: rect, cornerWidth: radius * 0.3, cornerHeight: radius * 0.3, transform: nil)
                ctx.saveGState()
                ctx.setFillColor(NSColor(calibratedWhite: 0, alpha: 0.16).cgColor)
                ctx.addPath(path)
                ctx.fillPath()
                ctx.setLineWidth(1.6)
                ctx.setStrokeColor(NSColor(calibratedWhite: 0, alpha: 0.65).cgColor)
                ctx.addPath(path)
                ctx.strokePath()
                ctx.setLineWidth(3)
                ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.9).cgColor)
                ctx.addPath(path)
                ctx.strokePath()
                ctx.restoreGState()

                drawPlus(ctx, at: center, length: max(min(side * 0.4, 14), 6))

                let handle = CGMutablePath()
                handle.addRoundedRect(in: CGRect(x: size.width - 12, y: 1, width: 8, height: 6), cornerWidth: 1.5, cornerHeight: 1.5)
                fillGlyph(ctx, path: handle, fill: NSColor(calibratedRed: 0.9, green: 0.55, blue: 0.6, alpha: 1).cgColor)
            }
        }

        static let lasso: NSCursor = makeCursor(size: CGSize(width: 22, height: 22), hotSpot: CGPoint(x: 11, y: 10)) { ctx, _ in
            let center = CGPoint(x: 11, y: 11)
            let radius: CGFloat = 6
            let ring = CGMutablePath()
            ring.addArc(center: center, radius: radius, startAngle: .pi * 1.5, endAngle: .pi * 1.5 + .pi * 1.85, clockwise: false)
            strokeGlyph(ctx, path: ring, color: NSColor.black.cgColor, width: 2)

            let tail = CGMutablePath()
            tail.move(to: CGPoint(x: center.x - radius, y: center.y + 1))
            tail.addCurve(to: CGPoint(x: center.x - radius - 6, y: center.y + 6), control1: CGPoint(x: center.x - radius - 2, y: center.y + 3), control2: CGPoint(x: center.x - radius - 3, y: center.y + 5))
            strokeGlyph(ctx, path: tail, color: NSColor.black.cgColor, width: 1.6)
        }

        static let rectangularSelection: NSCursor = makeCursor(size: CGSize(width: 20, height: 20), hotSpot: CGPoint(x: 10, y: 10)) { ctx, _ in
            let path = CGPath(roundedRect: CGRect(x: 3.5, y: 3.5, width: 13, height: 13), cornerWidth: 2, cornerHeight: 2, transform: nil)
            ctx.saveGState()
            ctx.setLineWidth(3.2)
            ctx.setLineDash(phase: 0, lengths: [3.5, 2.5])
            ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.95).cgColor)
            ctx.addPath(path)
            ctx.strokePath()
            ctx.setLineWidth(1.8)
            ctx.setLineDash(phase: 0, lengths: [3.5, 2.5])
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.addPath(path)
            ctx.strokePath()
            ctx.restoreGState()
        }

        static let move: NSCursor = makeCursor(size: CGSize(width: 22, height: 22), hotSpot: CGPoint(x: 11, y: 11)) { ctx, _ in
            arrowGlyph(ctx, from: CGPoint(x: 7, y: 9), to: CGPoint(x: 15, y: 9))
            arrowGlyph(ctx, from: CGPoint(x: 7, y: 13), to: CGPoint(x: 15, y: 13))
            arrowGlyph(ctx, from: CGPoint(x: 9, y: 7), to: CGPoint(x: 9, y: 15))
            arrowGlyph(ctx, from: CGPoint(x: 13, y: 7), to: CGPoint(x: 13, y: 15))

            let center = CGMutablePath()
            center.addRoundedRect(in: CGRect(x: 9.4, y: 9.4, width: 3.2, height: 3.2), cornerWidth: 0.8, cornerHeight: 0.8)
            fillGlyph(ctx, path: center)
        }

        static let resizeNorthWestSouthEast: NSCursor = makeCursor(size: CGSize(width: 20, height: 20), hotSpot: CGPoint(x: 10, y: 10)) { ctx, _ in
            let bar = CGMutablePath()
            bar.move(to: CGPoint(x: 7, y: 7))
            bar.addLine(to: CGPoint(x: 13, y: 13))
            strokeGlyph(ctx, path: bar, color: NSColor.black.cgColor, width: 2.5)

            let upper = CGMutablePath()
            upper.move(to: CGPoint(x: 3, y: 3))
            upper.addLine(to: CGPoint(x: 8, y: 3.5))
            upper.addLine(to: CGPoint(x: 3.5, y: 8))
            upper.closeSubpath()
            fillGlyph(ctx, path: upper)

            let lower = CGMutablePath()
            lower.move(to: CGPoint(x: 17, y: 17))
            lower.addLine(to: CGPoint(x: 12, y: 16.5))
            lower.addLine(to: CGPoint(x: 16.5, y: 12))
            lower.closeSubpath()
            fillGlyph(ctx, path: lower)
        }

        static let resizeNorthEastSouthWest: NSCursor = makeCursor(size: CGSize(width: 20, height: 20), hotSpot: CGPoint(x: 10, y: 10)) { ctx, _ in
            let bar = CGMutablePath()
            bar.move(to: CGPoint(x: 13, y: 7))
            bar.addLine(to: CGPoint(x: 7, y: 13))
            strokeGlyph(ctx, path: bar, color: NSColor.black.cgColor, width: 2.5)

            let upper = CGMutablePath()
            upper.move(to: CGPoint(x: 17, y: 3))
            upper.addLine(to: CGPoint(x: 12, y: 3.5))
            upper.addLine(to: CGPoint(x: 16.5, y: 8))
            upper.closeSubpath()
            fillGlyph(ctx, path: upper)

            let lower = CGMutablePath()
            lower.move(to: CGPoint(x: 3, y: 17))
            lower.addLine(to: CGPoint(x: 8, y: 16.5))
            lower.addLine(to: CGPoint(x: 3.5, y: 12))
            lower.closeSubpath()
            fillGlyph(ctx, path: lower)
        }

        static let rotate: NSCursor = makeCursor(size: CGSize(width: 24, height: 24), hotSpot: CGPoint(x: 12, y: 12)) { ctx, _ in
            let ring = CGMutablePath()
            ring.addArc(center: CGPoint(x: 12, y: 12), radius: 7, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            strokeGlyph(ctx, path: ring, color: NSColor.black.cgColor, width: 1.8)

            let head = CGMutablePath()
            head.move(to: CGPoint(x: 17.5, y: 5))
            head.addLine(to: CGPoint(x: 21, y: 8.5))
            head.addLine(to: CGPoint(x: 16.5, y: 9))
            head.closeSubpath()
            fillGlyph(ctx, path: head)
        }

        static func shape(_ kind: ShapeKind) -> NSCursor {
            makeCursor(size: CGSize(width: 18, height: 18), hotSpot: CGPoint(x: 9, y: 9)) { ctx, _ in
                switch kind {
                case .rectangle:
                    let path = CGPath(roundedRect: CGRect(x: 3, y: 3, width: 12, height: 12), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
                    strokeGlyph(ctx, path: path, color: NSColor.black.cgColor, width: 2)
                case .circle:
                    let path = CGMutablePath()
                    path.addEllipse(in: CGRect(x: 3, y: 3, width: 12, height: 12))
                    strokeGlyph(ctx, path: path, color: NSColor.black.cgColor, width: 2)
                case .line:
                    let path = CGMutablePath()
                    path.move(to: CGPoint(x: 4, y: 14))
                    path.addLine(to: CGPoint(x: 14, y: 4))
                    strokeGlyph(ctx, path: path, color: NSColor.black.cgColor, width: 2.2)
                    tipDot(ctx, at: CGPoint(x: 4, y: 14))
                    tipDot(ctx, at: CGPoint(x: 14, y: 4))
                case .arrow:
                    let path = CGMutablePath()
                    path.move(to: CGPoint(x: 3, y: 15))
                    path.addLine(to: CGPoint(x: 13, y: 5))
                    strokeGlyph(ctx, path: path, color: NSColor.black.cgColor, width: 2)
                    let head = CGMutablePath()
                    head.move(to: CGPoint(x: 14, y: 3.5))
                    head.addLine(to: CGPoint(x: 15, y: 10))
                    head.addLine(to: CGPoint(x: 9, y: 7))
                    head.closeSubpath()
                    fillGlyph(ctx, path: head)
                }
            }
        }

        static func directional(_ direction: CornerDirection) -> NSCursor {
            let start: CGPoint
            let end: CGPoint
            switch direction {
            case .left, .right:
                start = CGPoint(x: 4, y: 11)
                end = CGPoint(x: 18, y: 11)
            case .top, .bottom:
                start = CGPoint(x: 11, y: 4)
                end = CGPoint(x: 11, y: 18)
            case .topLeft, .bottomRight:
                start = CGPoint(x: 4, y: 18)
                end = CGPoint(x: 18, y: 4)
            case .topRight, .bottomLeft:
                start = CGPoint(x: 4, y: 4)
                end = CGPoint(x: 18, y: 18)
            }

            return makeCursor(size: CGSize(width: 22, height: 22), hotSpot: CGPoint(x: 11, y: 11)) { ctx, _ in
                arrowGlyph(ctx, from: start, to: end, doubleHeaded: true)
            }
        }

        static let image: NSCursor = makeCursor(size: CGSize(width: 20, height: 20), hotSpot: CGPoint(x: 8, y: 6)) { ctx, _ in
            let frame = CGMutablePath()
            frame.addRoundedRect(in: CGRect(x: 2, y: 2, width: 13, height: 11), cornerWidth: 2, cornerHeight: 2)
            fillGlyph(ctx, path: frame)

            let sun = CGMutablePath()
            sun.addEllipse(in: CGRect(x: 9, y: 9, width: 2.4, height: 2.4))
            fillGlyph(ctx, path: sun)

            let mountain = CGMutablePath()
            mountain.move(to: CGPoint(x: 3.5, y: 10.5))
            mountain.addLine(to: CGPoint(x: 7, y: 5.5))
            mountain.addLine(to: CGPoint(x: 9.5, y: 9))
            mountain.addLine(to: CGPoint(x: 12, y: 7))
            mountain.addLine(to: CGPoint(x: 14, y: 10.5))
            strokeGlyph(ctx, path: mountain, color: NSColor.white.cgColor, width: 1.4)

            drawPlus(ctx, at: CGPoint(x: 15, y: 14), length: 5)
        }

        private static func makeCursor(size: NSSize, hotSpot: NSPoint, painter: @escaping (CGContext, CGRect) -> Void) -> NSCursor {
            let image = NSImage(size: size, flipped: true) { rect in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.clear(rect)
                context.setShouldAntialias(true)
                context.setAllowsAntialiasing(true)
                painter(context, rect)
                return true
            }
            return NSCursor(image: image, hotSpot: hotSpot)
        }

        private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x, y: y)
        }

        private static func fillGlyph(_ ctx: CGContext, path: CGPath, fill: CGColor = NSColor.black.cgColor, outlineWidth: CGFloat = 2.2) {
            ctx.saveGState()
            ctx.setLineWidth(outlineWidth)
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.98).cgColor)
            ctx.addPath(path)
            ctx.strokePath()
            ctx.setFillColor(fill)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.restoreGState()
        }

        private static func strokeGlyph(_ ctx: CGContext, path: CGPath, color: CGColor, width: CGFloat) {
            ctx.saveGState()
            ctx.setLineWidth(width + 3)
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.95).cgColor)
            ctx.addPath(path)
            ctx.strokePath()
            ctx.setLineWidth(width)
            ctx.setStrokeColor(color)
            ctx.addPath(path)
            ctx.strokePath()
            ctx.restoreGState()
        }

        private static func drawPlus(_ ctx: CGContext, at center: CGPoint, length: CGFloat) {
            let bar = NSColor(calibratedWhite: 0.1, alpha: 0.9).cgColor
            let half = length / 2
            let horizontal = CGRect(x: center.x - half, y: center.y - 0.65, width: length, height: 1.3)
            let vertical = CGRect(x: center.x - 0.65, y: center.y - half, width: 1.3, height: length)
            ctx.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.95).cgColor)
            ctx.fill([horizontal, vertical])
            ctx.setFillColor(bar)
            ctx.fill([horizontal.insetBy(dx: 0.9, dy: 0.9), vertical.insetBy(dx: 0.9, dy: 0.9)])
        }

        private static func arrowGlyph(_ ctx: CGContext, from start: CGPoint, to end: CGPoint, doubleHeaded: Bool = false) {
            let body = CGMutablePath()
            body.move(to: start)
            body.addLine(to: end)
            strokeGlyph(ctx, path: body, color: NSColor.black.cgColor, width: 1.8)
            let angle = atan2(end.y - start.y, end.x - start.x)
            arrowhead(ctx, at: end, angle: angle)
            if doubleHeaded {
                arrowhead(ctx, at: start, angle: angle + .pi)
            }
        }

        private static func arrowhead(_ ctx: CGContext, at point: CGPoint, angle: CGFloat) {
            let length: CGFloat = 5.5
            let spread: CGFloat = 0.55
            let left = CGPoint(
                x: point.x - length * cos(angle - spread),
                y: point.y - length * sin(angle - spread)
            )
            let right = CGPoint(
                x: point.x - length * cos(angle + spread),
                y: point.y - length * sin(angle + spread)
            )
            let head = CGMutablePath()
            head.move(to: point)
            head.addLine(to: left)
            head.addLine(to: right)
            head.closeSubpath()
            fillGlyph(ctx, path: head)
        }

        private static func tipDot(_ ctx: CGContext, at point: CGPoint) {
            let path = CGMutablePath()
            path.addEllipse(in: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3))
            fillGlyph(ctx, path: path)
        }
    }
}
#endif