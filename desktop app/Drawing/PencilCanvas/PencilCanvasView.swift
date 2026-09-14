import SwiftUI
import PencilKit

#if os(iOS)
import UIKit

struct PencilCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var onToolChanged: ((EditorTool) -> Void)?
    var onPointerHover: ((CGPoint?) -> Void)?
    var onDrawingInteractionEnded: (() -> Void)?

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.delegate = context.coordinator
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        let hover = UIHoverGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleHover(_:)))
        canvas.addGestureRecognizer(hover)
        let toolPicker = PKToolPicker()
        context.coordinator.toolPicker = toolPicker
        toolPicker.addObserver(canvas)
        toolPicker.setVisible(true, forFirstResponder: canvas)
        canvas.becomeFirstResponder()
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        if uiView.drawing != drawing { uiView.drawing = drawing }
        let tool = uiView.tool.editorTool
        if context.coordinator.lastReportedTool != tool {
            context.coordinator.lastReportedTool = tool
            onToolChanged?(tool)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvasView
        var toolPicker: PKToolPicker?
        var lastReportedTool: EditorTool?
        private var isUsingInk = false
        private var awaitingFinalInk = false
        private var initialStrokeCount = 0
        init(_ parent: PencilCanvasView) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
            if !isUsingInk, awaitingFinalInk,
               canvasView.drawing.strokes.count > initialStrokeCount {
                awaitingFinalInk = false
                parent.onDrawingInteractionEnded?()
            }
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            isUsingInk = canvasView.tool is PKInkingTool
            awaitingFinalInk = false
            initialStrokeCount = canvasView.drawing.strokes.count
            reportTool(canvasView)
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
            // PencilKit may publish the committed drawing after tool-up.
            awaitingFinalInk = isUsingInk && canvasView.drawing.strokes.count <= initialStrokeCount
            isUsingInk = false
            reportTool(canvasView)
            parent.onDrawingInteractionEnded?()
        }

        @objc func handleHover(_ recognizer: UIHoverGestureRecognizer) {
            guard let view = recognizer.view else {
                parent.onPointerHover?(nil)
                return
            }
            switch recognizer.state {
            case .began, .changed:
                parent.onPointerHover?(recognizer.location(in: view))
            default:
                parent.onPointerHover?(nil)
            }
        }

        private func reportTool(_ canvasView: PKCanvasView) {
            let tool = canvasView.tool.editorTool
            if lastReportedTool != tool {
                lastReportedTool = tool
                parent.onToolChanged?(tool)
            }
        }
    }
}

extension PKTool {
    var editorTool: EditorTool {
        switch self {
        case let ink as PKInkingTool:
            switch ink.inkType {
            case .marker: return .highlighter
            case .pencil: return .pencil
            default: return .pen
            }
        case is PKEraserTool: return .eraser
        case is PKLassoTool: return .lasso
        default: return .pen
        }
    }
}
#endif

#if os(macOS)
import AppKit

enum MacDrawingTool: String, Codable, CaseIterable {
    case pen = "pen"
    case pencil = "pencil"
    case highlighter = "highlighter"
    case lasso = "lasso"
    case eraser = "eraser"
    case rectangle = "rectangle"
    case circle = "circle"
    case line = "line"
    case arrow = "arrow"
}

struct MacPoint: Codable, Equatable {
    let x: Double
    let y: Double
    init(_ point: CGPoint) { x = point.x; y = point.y }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

/// Immutable appearance captured with each stroke. This prevents later
/// toolbar changes from changing the appearance of ink already on the page.
struct MacStrokeStyle: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
    let width: Double
    let opacity: Double

    init(color: Color, width: CGFloat, opacity: CGFloat = 1) {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .black
        red = Double(nsColor.redComponent)
        green = Double(nsColor.greenComponent)
        blue = Double(nsColor.blueComponent)
        alpha = Double(nsColor.alphaComponent)
        self.width = Double(width)
        self.opacity = Double(opacity)
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1, width: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
        self.width = width
        self.opacity = opacity
    }

    var nsColor: NSColor {
        NSColor(
            calibratedRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha * opacity)
        )
    }

    static func legacyDefault(for tool: MacDrawingTool) -> MacStrokeStyle {
        switch tool {
        case .pencil:
            return MacStrokeStyle(red: 0.38, green: 0.38, blue: 0.42, width: 1.5, opacity: 0.9)
        case .highlighter:
            return MacStrokeStyle(red: 1, green: 1, blue: 0, width: 14, opacity: 0.35)
        default:
            return MacStrokeStyle(red: 0, green: 0, blue: 0, width: 3)
        }
    }
}

struct MacStroke: Codable, Identifiable, Equatable {
    let id: UUID
    let points: [MacPoint]
    let tool: MacDrawingTool
    let style: MacStrokeStyle
    init(points: [MacPoint], tool: MacDrawingTool = .pen, style: MacStrokeStyle? = nil) {
        id = UUID()
        self.points = points
        self.tool = tool
        self.style = style ?? MacStrokeStyle.legacyDefault(for: tool)
    }
    init(id: UUID, points: [MacPoint], tool: MacDrawingTool, style: MacStrokeStyle? = nil) {
        self.id = id
        self.points = points
        self.tool = tool
        self.style = style ?? MacStrokeStyle.legacyDefault(for: tool)
    }
    private enum CodingKeys: String, CodingKey { case id, points, tool, style }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        points = try container.decode([MacPoint].self, forKey: .points)
        tool = try container.decodeIfPresent(MacDrawingTool.self, forKey: .tool) ?? .pen
        style = try container.decodeIfPresent(MacStrokeStyle.self, forKey: .style) ?? MacStrokeStyle.legacyDefault(for: tool)
    }
}

/// macOS canvas. The NSView fills the entire editor viewport and owns all
/// rendering and input; the viewport state lives in `EditorCamera` (single
/// source of truth), so SwiftUI applies no transforms or viewport gestures.
struct MacCanvasView: NSViewRepresentable {
    @Binding var strokes: [MacStroke]
    @Binding var selectedTool: MacDrawingTool
    @ObservedObject var camera: EditorCamera
    @Binding var template: PageTemplate
    @Binding var pageColor: PageColor
    var pageSize: CGSize? = nil
    var documentOrigin: CGPoint = .zero
    @Binding var toolSettings: EditorToolSettings
    @Binding var selection: EditorSelection
    var debugTool: EditorTool? = nil
    var debugBusy: Bool = false
    var debugLocked: Bool = false
    var debugOutside: Bool = false
    var onCursorDebug: ((CursorDebugSnapshot?) -> Void)?

    func makeNSView(context: Context) -> MacCanvasNSView {
        let view = MacCanvasNSView(frame: .zero)
        view.strokes = strokes
        view.selectedTool = selectedTool
        view.camera = camera
        view.camera?.surface = view
        view.template = template
        view.pageColor = pageColor
        view.pageSize = pageSize ?? camera.pageSize
        view.documentOrigin = documentOrigin
        view.toolSettings = toolSettings
        view.selection = selection
        view.debugTool = debugTool
        view.debugBusy = debugBusy
        view.debugLocked = debugLocked
        view.debugOutside = debugOutside
        view.onStrokesChanged = { strokes = $0 }
        view.onSelectionChanged = { selection = $0 }
        view.onCursorDebug = onCursorDebug
        return view
    }

    func updateNSView(_ nsView: MacCanvasNSView, context: Context) {
        let strokesChanged = nsView.strokes != strokes
        let settingsChanged = nsView.toolSettings != toolSettings
        let selectionChanged = nsView.selection != selection
        let toolChanged = nsView.selectedTool != selectedTool
        let appearanceChanged = nsView.template != template
            || nsView.pageColor != pageColor
            || nsView.pageSize != (pageSize ?? camera.pageSize)
            || nsView.documentOrigin != documentOrigin
        let debugChanged = nsView.debugTool != debugTool
            || nsView.debugBusy != debugBusy
            || nsView.debugLocked != debugLocked
            || nsView.debugOutside != debugOutside
        let cameraChanged = nsView.camera !== camera
        nsView.strokes = strokes
        nsView.selectedTool = selectedTool
        nsView.camera = camera
        nsView.camera?.surface = nsView
        nsView.template = template
        nsView.pageColor = pageColor
        nsView.pageSize = pageSize ?? camera.pageSize
        nsView.documentOrigin = documentOrigin
        nsView.toolSettings = toolSettings
        nsView.selection = selection
        nsView.debugTool = debugTool
        nsView.debugBusy = debugBusy
        nsView.debugLocked = debugLocked
        nsView.debugOutside = debugOutside
        nsView.onCursorDebug = onCursorDebug
        if strokesChanged || selectionChanged || appearanceChanged || cameraChanged {
            nsView.needsDisplay = true
        }
        if cameraChanged || toolChanged || debugChanged || settingsChanged || selectionChanged || strokesChanged {
            nsView.syncCursorState()
        }
    }
}

final class MacCanvasNSView: NSView {
    var strokes: [MacStroke] = []
    var selectedTool: MacDrawingTool = .pen
    weak var camera: EditorCamera?
    var template: PageTemplate = .blank
    var pageColor: PageColor = .white
    var pageSize: CGSize = .zero
    var documentOrigin: CGPoint = .zero
    var toolSettings = EditorToolSettings()
    var selection = EditorSelection()
    var debugTool: EditorTool?
    var debugBusy = false
    var debugLocked = false
    var debugOutside = false
    var onStrokesChanged: (([MacStroke]) -> Void)?
    var onSelectionChanged: ((EditorSelection) -> Void)?
    var onCursorDebug: ((CursorDebugSnapshot?) -> Void)?

    var cursorState = EditorCursorState()
    var onContinueInk: ((CGPoint) -> MacCanvasNSView?)?
    var isHandlingInkGesture: Bool { mouseIsDown || forwardedInkView != nil }
    private weak var forwardedInkView: MacCanvasNSView?
    private var activeInkTool: MacDrawingTool = .pen
    private var activeInkStyle: MacStrokeStyle?
    private var activePoints: [MacPoint] = []
    private var lassoPoints: [CGPoint] = []
    private var trackingArea: NSTrackingArea?
    private var lastHoverPoint: CGPoint = .zero
    private var hoverActive = false
    private var mouseIsDown = false
    private var lastCursor: NSCursor = .arrow
    private var temporaryEraserHeld = false

    /// Space bar held while drawing temporarily switches pen/pencil/highlighter to the eraser.
    static let temporaryEraserKeyCode: UInt16 = 49

    private enum DragMode { case none, draw, erase, lasso, move, resize, rotate }
    private var dragMode: DragMode = .none
    private var dragStartPoint: CGPoint = .zero
    private var strokesBeforeDrag: [MacStroke] = []
    private var selectionBeforeDrag = EditorSelection()
    private var resizeDirection: CornerDirection = .topLeft
    private var rotateStartAngle: CGFloat = 0

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func becomeFirstResponder() -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let camera else { return }
        let viewport = camera.viewport
        let localPageSize = pageSize == .zero ? camera.pageSize : pageSize
        let pageRect = CGRect(origin: .zero, size: localPageSize)
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        let cg = ctx.cgContext
        cg.translateBy(
            x: viewport.offset.width + documentOrigin.x * viewport.scale,
            y: viewport.offset.height + documentOrigin.y * viewport.scale
        )
        cg.scaleBy(x: viewport.scale, y: viewport.scale)

        cg.saveGState()
        cg.setShadow(
            offset: CGSize(width: 0, height: 3 / max(viewport.scale, 0.05)),
            blur: 16 / max(viewport.scale, 0.05),
            color: NSColor.black.withAlphaComponent(0.35).cgColor
        )
        drawPageBackground(in: pageRect)
        cg.restoreGState()

        drawTemplate(in: pageRect)

        cg.saveGState()
        cg.clip(to: pageRect)
        for stroke in strokes {
            draw(stroke.points, tool: stroke.tool, style: stroke.style)
        }
        if dragMode == .draw {
            draw(shapePoints(for: activeInkTool), tool: activeInkTool, style: activeInkStyle)
        }
        if dragMode == .erase {
            draw(activePoints, tool: .eraser)
        }
        cg.restoreGState()

        if dragMode == .lasso {
            drawLasso(lassoPoints)
        }
        if selection.isActive {
            drawSelectionOverlay()
        }
        ctx.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let pagePoint = pagePoint(for: convert(event.locationInWindow, from: nil))
        guard CGRect(origin: .zero, size: pageSize).contains(pagePoint) else { return }
        mouseIsDown = true
        forwardedInkView = nil
        activeInkTool = selectedTool
        activeInkStyle = currentStrokeStyle(for: selectedTool)
        activePoints = [MacPoint(pagePoint)]
        dragStartPoint = pagePoint
        strokesBeforeDrag = strokes
        selectionBeforeDrag = selection

        if selectedTool == .lasso {
            if selection.isActive, SelectionGeometry.isOverRotateHandle(pagePoint, bounds: selection.bounds, scale: currentScale) {
                dragMode = .rotate
                rotateStartAngle = atan2(pagePoint.y - selection.bounds.midY, pagePoint.x - selection.bounds.midX)
            } else if selection.isActive, let direction = SelectionGeometry.resizeDirection(at: pagePoint, bounds: selection.bounds, scale: currentScale) {
                dragMode = .resize
                resizeDirection = direction
            } else if selection.isActive, SelectionGeometry.isInside(pagePoint, bounds: selection.bounds, scale: currentScale) {
                dragMode = .move
            } else {
                dragMode = .lasso
                lassoPoints = [pagePoint]
            }
        } else if isErasing {
            dragMode = .erase
        } else {
            dragMode = .draw
        }
        syncCursorState()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if let forwardedInkView {
            forwardedInkView.mouseDragged(with: event)
            return
        }
        let pagePoint = pagePoint(for: convert(event.locationInWindow, from: nil))
        switch dragMode {
        case .draw:
            if continueInkIfNeeded(at: pagePoint, event: event, ending: false) { return }
            activePoints.append(MacPoint(pagePoint))
        case .erase:
            activePoints.append(MacPoint(pagePoint))
            eraseUnder([MacPoint(pagePoint)])
        case .lasso:
            if lassoPoints.last != pagePoint {
                lassoPoints.append(pagePoint)
            }
        case .move:
            let delta = CGSize(width: pagePoint.x - dragStartPoint.x, height: pagePoint.y - dragStartPoint.y)
            moveSelection(by: delta)
        case .resize:
            resizeSelection(handlePoint: pagePoint)
        case .rotate:
            rotateSelection(handlePoint: pagePoint)
        case .none:
            break
        }
        syncCursorState()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let forwardedInkView {
            forwardedInkView.mouseUp(with: event)
            self.forwardedInkView = nil
            mouseIsDown = false
            syncCursorState()
            return
        }
        if mouseIsDown {
            let pagePoint = pagePoint(for: convert(event.locationInWindow, from: nil))
            switch dragMode {
            case .draw:
                if continueInkIfNeeded(at: pagePoint, event: event, ending: true) { return }
                activePoints.append(MacPoint(pagePoint))
                if activePoints.count > 1 {
                    strokes.append(MacStroke(
                        points: shapePoints(for: activeInkTool),
                        tool: activeInkTool,
                        style: activeInkStyle
                    ))
                    if strokes != strokesBeforeDrag {
                        registerUndo(for: strokesBeforeDrag)
                    }
                    onStrokesChanged?(strokes)
                }
            case .erase:
                activePoints.append(MacPoint(pagePoint))
                eraseUnder([MacPoint(pagePoint)])
                if strokes != strokesBeforeDrag {
                    registerUndo(for: strokesBeforeDrag)
                    onStrokesChanged?(strokes)
                }
                pruneSelection()
                onSelectionChanged?(selection)
            case .lasso:
                lassoPoints.append(pagePoint)
                commitLassoSelection()
            case .move, .resize, .rotate:
                if strokes != strokesBeforeDrag {
                    registerUndo(for: strokesBeforeDrag)
                    onStrokesChanged?(strokes)
                }
                onSelectionChanged?(selection)
            case .none:
                break
            }
        }
        activePoints.removeAll()
        lassoPoints.removeAll()
        mouseIsDown = false
        dragMode = .none
        syncCursorState()
        needsDisplay = true
    }

    private func continueInkIfNeeded(at point: CGPoint, event: NSEvent, ending: Bool) -> Bool {
        guard activeInkTool == .pen || activeInkTool == .pencil || activeInkTool == .highlighter,
              point.y >= pageSize.height,
              let crossingIndex = activePoints.lastIndex(where: { $0.y < pageSize.height }),
              let next = onContinueInk?(point), next !== self else { return false }
        let last = activePoints[crossingIndex].cgPoint
        let fraction = (pageSize.height - last.y) / (point.y - last.y)
        let boundary = CGPoint(x: last.x + (point.x - last.x) * fraction, y: pageSize.height)
        let overflow = activePoints.suffix(from: crossingIndex + 1)
        activePoints = Array(activePoints.prefix(through: crossingIndex))
        activePoints.append(MacPoint(boundary))
        strokes.append(MacStroke(points: activePoints, tool: activeInkTool, style: activeInkStyle))
        registerUndo(for: strokesBeforeDrag)
        onStrokesChanged?(strokes)

        // Finish only this page's segment. The same AppKit gesture continues on
        // the next adapter using the unchanged document-to-page conversion.
        next.beginContinuedInk(
            at: CGPoint(x: boundary.x + documentOrigin.x, y: boundary.y + documentOrigin.y),
            tool: activeInkTool,
            style: activeInkStyle
        )
        next.activePoints.append(contentsOf: overflow.map {
            MacPoint(CGPoint(
                x: $0.x + documentOrigin.x - next.documentOrigin.x,
                y: $0.y + documentOrigin.y - next.documentOrigin.y
            ))
        })
        activePoints.removeAll()
        dragMode = .none
        forwardedInkView = next
        needsDisplay = true
        if ending {
            next.mouseUp(with: event)
            forwardedInkView = nil
            mouseIsDown = false
        } else {
            next.mouseDragged(with: event)
        }
        return true
    }

    private func beginContinuedInk(at documentPoint: CGPoint, tool: MacDrawingTool, style: MacStrokeStyle?) {
        let local = CGPoint(x: documentPoint.x - documentOrigin.x, y: documentPoint.y - documentOrigin.y)
        activePoints = [MacPoint(local)]
        strokesBeforeDrag = strokes
        activeInkTool = tool
        activeInkStyle = style
        forwardedInkView = nil
        mouseIsDown = true
        dragMode = .draw
        isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        guard !activePoints.isEmpty else { return }
        activePoints.append(MacPoint(pagePoint(for: convert(event.locationInWindow, from: nil))))
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        hoverActive = true
        lastHoverPoint = convert(event.locationInWindow, from: nil)
        syncCursorState()
    }

    override func mouseMoved(with event: NSEvent) {
        hoverActive = true
        lastHoverPoint = convert(event.locationInWindow, from: nil)
        syncCursorState()
    }

    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 51 || event.keyCode == 117), selection.isActive,
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            deleteSelection()
            return
        }
        if let camera, event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "0": camera.actualSize(centeredOn: documentFrame); return
            case "9": camera.fit(documentFrame: documentFrame); return
            case "+", "=": camera.zoomIn(); return
            case "-", "_": camera.zoomOut(); return
            default: break
            }
        }
        if let camera {
            switch event.keyCode {
            case 123: camera.pan(by: CGSize(width: 24, height: 0)); return
            case 124: camera.pan(by: CGSize(width: -24, height: 0)); return
            case 125: camera.pan(by: CGSize(width: 0, height: -24)); return
            case 126: camera.pan(by: CGSize(width: 0, height: 24)); return
            default: break
            }
        }
        if event.keyCode == Self.temporaryEraserKeyCode {
            temporaryEraserHeld = true
            syncCursorState()
            return
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == Self.temporaryEraserKeyCode {
            temporaryEraserHeld = false
            syncCursorState()
            return
        }
        super.keyUp(with: event)
    }

    private var isErasing: Bool {
        if selectedTool == .eraser { return true }
        if temporaryEraserHeld {
            let tool = EditorTool(macTool: selectedTool)
            if tool.isDrawingTool { return true }
        }
        return false
    }

    func syncCursorState() {
        let scale = currentScale
        let hoverPagePoint = pagePoint(for: lastHoverPoint)
        cursorState.activeTool = EditorTool(macTool: selectedTool)
        cursorState.viewportScale = scale
        cursorState.debugToolOverride = debugTool
        cursorState.isBusy = debugBusy
        cursorState.overLockedContent = debugLocked
        cursorState.isOutsidePage = debugOutside || !hoverActive || !isHoveringOverPage
        cursorState.temporaryToolOverride = temporaryEraserHeld ? .eraser : nil
        cursorState.eraserRadius = toolSettings.eraserRadius / Swift.max(scale, 0.05)
        cursorState.highlighterWidth = toolSettings.highlighter.width
        cursorState.pencilWidth = toolSettings.pencil.width
        cursorState.penWidth = toolSettings.pen.width

        switch dragMode {
        case .draw, .erase: cursorState.interaction = .drawing
        case .lasso: cursorState.interaction = .selecting
        case .move: cursorState.interaction = .dragging
        case .resize:
            cursorState.interaction = .resizing
            cursorState.resizingDirection = resizeDirection
        case .rotate: cursorState.interaction = .rotating
        case .none: cursorState.interaction = mouseIsDown ? .drawing : .idle
        }
        cursorState.isSelecting = (dragMode == .lasso)

        let tool = cursorState.effectiveTool
        let overSelection = selection.isActive && hoverTarget(at: hoverPagePoint) != nil
        if tool.isSelectionTool {
            cursorState.overMovableContent = overSelection || contentNearby(at: hoverPagePoint)
            cursorState.overHandle = hoverTarget(at: hoverPagePoint)
        } else {
            cursorState.overMovableContent = false
            cursorState.overHandle = nil
        }
        applyResolvedCursor(pagePoint: hoverPagePoint, canvasPoint: lastHoverPoint)
    }

    private func hoverTarget(at point: CGPoint) -> HandleRegion? {
        guard selection.isActive else { return nil }
        if SelectionGeometry.isOverRotateHandle(point, bounds: selection.bounds, scale: currentScale) {
            return .rotate
        }
        if let direction = SelectionGeometry.resizeDirection(at: point, bounds: selection.bounds, scale: currentScale) {
            return .resize(direction)
        }
        return nil
    }

    private func contentNearby(at point: CGPoint) -> Bool {
        for stroke in strokes {
            for mappedPoint in stroke.points {
                let strokePoint = mappedPoint.cgPoint
                if hypot(strokePoint.x - point.x, strokePoint.y - point.y) < 8 { return true }
            }
        }
        return false
    }

    private func applyResolvedCursor(pagePoint: CGPoint, canvasPoint: CGPoint) {
        guard window != nil else { return }
        let editorCursor = CursorController.cursor(for: cursorState)
        let native = NativeCursorFactory.cursor(for: editorCursor, state: cursorState)
        if native !== lastCursor {
            native.set()
            lastCursor = native
        }
        onCursorDebug?(CursorController.snapshot(for: cursorState, pagePoint: pagePoint, canvasPoint: canvasPoint))
    }

    /// Two-finger trackpad drag -> pan (offset only). Cmd+scroll zooms around the pointer.
    override func scrollWheel(with event: NSEvent) {
        if let notebookView = superview as? MacNotebookCanvasNSView {
            notebookView.scrollWheel(with: event)
            return
        }
        if event.modifierFlags.contains(.command) {
            let canvasPoint = convert(event.locationInWindow, from: nil)
            camera?.zoomByFactor(exp(-event.scrollingDeltaY * 0.02), around: canvasPoint)
            return
        }
        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        camera?.pan(by: CGSize(
            width: event.scrollingDeltaX * multiplier,
            height: event.scrollingDeltaY * multiplier
        ))
    }

    /// Trackpad pinch -> zoom around the pointer, keeping the page point under it stable.
    override func magnify(with event: NSEvent) {
        let canvasPoint = convert(event.locationInWindow, from: nil)
        camera?.applyMagnification(event.magnification, at: canvasPoint)
    }

    func clearSelection() {
        guard selection.isActive else { return }
        selection.removeAll()
        onSelectionChanged?(selection)
        syncCursorState()
        needsDisplay = true
    }

    func deleteSelection() {
        guard selection.isActive, !isHandlingInkGesture else { return }
        let remainingStrokes = strokes.filter { !selection.strokeIDs.contains($0.id) }
        guard remainingStrokes.count != strokes.count else {
            clearSelection()
            return
        }
        replaceStrokes(remainingStrokes)
        undoManager?.setActionName("Delete Selection")
    }

    func replaceStrokes(_ updatedStrokes: [MacStroke]) {
        let previousStrokes = strokes
        strokes = updatedStrokes
        selection.removeAll()
        onSelectionChanged?(selection)
        registerUndo(for: previousStrokes)
        onStrokesChanged?(strokes)
        syncCursorState()
        needsDisplay = true
    }

    private func registerUndo(for previousStrokes: [MacStroke]) {
        undoManager?.registerUndo(withTarget: self) { $0.replaceStrokes(previousStrokes) }
        undoManager?.setActionName("Drawing Change")
    }

    // MARK: - Drawing

    private func pagePoint(for canvasPoint: CGPoint) -> CGPoint {
        guard let camera else { return canvasPoint }
        let documentPoint = camera.pagePoint(fromCanvasPoint: canvasPoint)
        return CGPoint(x: documentPoint.x - documentOrigin.x, y: documentPoint.y - documentOrigin.y)
    }

    private var currentScale: CGFloat {
        camera?.viewport.scale ?? 1
    }

    private var documentFrame: CGRect {
        let localPageSize = pageSize == .zero ? camera?.pageSize ?? .zero : pageSize
        return CGRect(origin: documentOrigin, size: localPageSize)
    }

    private var isHoveringOverPage: Bool {
        guard let camera else { return false }
        let localPageSize = pageSize == .zero ? camera.pageSize : pageSize
        return CGRect(origin: .zero, size: localPageSize).contains(pagePoint(for: lastHoverPoint))
    }

    private func drawPageBackground(in pageRect: CGRect) {
        let color: NSColor
        switch pageColor {
        case .white: color = .white
        case .cream: color = NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.88, alpha: 1)
        case .dark: color = NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.13, alpha: 1)
        }
        color.setFill()
        NSBezierPath(rect: pageRect).fill()
    }

    private func drawTemplate(in pageRect: CGRect) {
        guard template != .blank, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let templateColor = pageColor == .dark
            ? NSColor(calibratedRed: 0.45, green: 0.65, blue: 1, alpha: 0.32)
            : NSColor(calibratedRed: 0, green: 0, blue: 1, alpha: 0.16)
        ctx.setStrokeColor(templateColor.cgColor)
        ctx.setFillColor(templateColor.cgColor)
        ctx.setLineWidth(0.7)
        switch template {
        case .ruled:
            var y: CGFloat = 36
            while y <= pageRect.height {
                ctx.beginPath()
                ctx.move(to: CGPoint(x: 0, y: y))
                ctx.addLine(to: CGPoint(x: pageRect.width, y: y))
                ctx.strokePath()
                y += 32
            }
        case .grid:
            var x: CGFloat = 0
            while x <= pageRect.width {
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x, y: pageRect.height))
                ctx.strokePath()
                x += 32
            }
            var y: CGFloat = 0
            while y <= pageRect.height {
                ctx.beginPath()
                ctx.move(to: CGPoint(x: 0, y: y))
                ctx.addLine(to: CGPoint(x: pageRect.width, y: y))
                ctx.strokePath()
                y += 32
            }
        case .dots:
            var x: CGFloat = 16
            while x <= pageRect.width {
                var y: CGFloat = 16
                while y <= pageRect.height {
                    ctx.fillEllipse(in: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5))
                    y += 24
                }
                x += 24
            }
        case .blank:
            break
        }
    }

    private func drawSelectionOverlay() {
        guard selection.isActive, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let scale = max(currentScale, 0.05)
        let bounds = selection.bounds

        ctx.saveGState()
        ctx.setLineWidth(1.5 / scale)
        ctx.setStrokeColor(NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor)
        ctx.setLineDash(phase: 0, lengths: [6 / scale, 4 / scale])
        ctx.stroke(bounds)
        ctx.restoreGState()

        for (_, rect) in SelectionGeometry.handles(bounds: bounds, scale: scale) {
            drawHandle(rect: rect, scale: scale)
        }

        let rotateRect = SelectionGeometry.rotateHandle(bounds: bounds, scale: scale)
        let stemTop = min(rotateRect.midY, bounds.minY)
        let stem = CGRect(
            x: bounds.midX - 0.75 / scale,
            y: stemTop,
            width: 1.5 / scale,
            height: max(bounds.minY - rotateRect.midY, 0.75 / scale)
        )
        ctx.setFillColor(NSColor.controlAccentColor.cgColor)
        ctx.fill(stem)
        ctx.fillEllipse(in: rotateRect)
    }

    private func drawHandle(rect: CGRect, scale: CGFloat) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let corner = 2 / scale
        let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
        ctx.saveGState()
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.setLineWidth(1.5 / scale)
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func currentStrokeStyle(for tool: MacDrawingTool) -> MacStrokeStyle {
        let settings = toolSettings.inkSettings(for: tool)
        let opacity: CGFloat
        switch tool {
        case .highlighter: opacity = toolSettings.highlighterOpacity
        case .pencil: opacity = 0.9
        default: opacity = 1
        }
        return MacStrokeStyle(color: settings.color, width: settings.width, opacity: opacity)
    }

    private func draw(_ points: [MacPoint], tool: MacDrawingTool, style: MacStrokeStyle? = nil) {
        guard points.count > 1 else { return }
        let path = NSBezierPath()
        path.move(to: points[0].cgPoint)
        for point in points.dropFirst() { path.line(to: point.cgPoint) }
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        let appearance = style ?? currentStrokeStyle(for: tool)
        path.lineWidth = CGFloat(appearance.width)
        appearance.nsColor.setStroke()
        path.stroke()
    }

    private func drawLasso(_ points: [CGPoint]) {
        guard points.count > 1 else { return }
        let path = NSBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() { path.line(to: point) }
        path.lineWidth = 1.2 / Swift.max(currentScale, 0.05)
        path.setLineDash([6 / Swift.max(currentScale, 0.05), 4 / Swift.max(currentScale, 0.05)], count: 2, phase: 0)
        NSColor.systemBlue.setStroke()
        path.stroke()
    }

    private func shapePoints(for tool: MacDrawingTool) -> [MacPoint] {
        guard let start = activePoints.first, let end = activePoints.last else { return activePoints }
        let a = start.cgPoint
        let b = end.cgPoint
        switch tool {
        case .pen, .pencil, .highlighter, .eraser, .lasso: return activePoints
        case .line: return [start, end]
        case .arrow:
            let angle = atan2(b.y - a.y, b.x - a.x)
            let length: CGFloat = 14
            let left = CGPoint(x: b.x - length * cos(angle - .pi / 6), y: b.y - length * sin(angle - .pi / 6))
            let right = CGPoint(x: b.x - length * cos(angle + .pi / 6), y: b.y - length * sin(angle + .pi / 6))
            return [start, end, MacPoint(left), end, MacPoint(right)]
        case .rectangle:
            return [MacPoint(a), MacPoint(CGPoint(x: b.x, y: a.y)), end, MacPoint(CGPoint(x: a.x, y: b.y)), MacPoint(a)]
        case .circle:
            // Keep the starting corner fixed and constrain the drag to a square.
            let radius = max(abs(b.x - a.x), abs(b.y - a.y)) / 2
            let center = CGPoint(
                x: a.x + (b.x < a.x ? -radius : radius),
                y: a.y + (b.y < a.y ? -radius : radius)
            )
            return (0...64).map { step in
                let angle = CGFloat(step) * 2 * .pi / 64
                return MacPoint(CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
            }
        }
    }

    // MARK: - Eraser

    private func eraseUnder(_ points: [MacPoint]) {
        guard !points.isEmpty else { return }
        let radius = toolSettings.eraserRadius / Swift.max(currentScale, 0.05)
        strokes.removeAll { stroke in
            let strokePoints = stroke.points.map(\.cgPoint)
            let hitRadius = radius + CGFloat(stroke.style.width) / 2
            return points.contains { erasePoint in
                if strokePoints.count == 1 {
                    return hypot(erasePoint.cgPoint.x - strokePoints[0].x, erasePoint.cgPoint.y - strokePoints[0].y) < hitRadius
                }
                return zip(strokePoints, strokePoints.dropFirst()).contains { start, end in
                    distance(from: erasePoint.cgPoint, toSegmentFrom: start, to: end) < hitRadius
                }
            }
        }
    }

    private func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let t = min(max(projection, 0), 1)
        return hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy))
    }

    private func pruneSelection() {
        let liveIDs = Set(strokes.map(\.id))
        let removed = selection.strokeIDs.subtracting(liveIDs)
        guard !removed.isEmpty else { return }
        selection.strokeIDs = selection.strokeIDs.intersection(liveIDs)
        if selection.strokeIDs.isEmpty {
            selection.bounds = .zero
        } else {
            selection.bounds = inflatedBounds(of: strokes.filter { selection.strokeIDs.contains($0.id) })
        }
    }

    // MARK: - Lasso selection

    private func commitLassoSelection() {
        guard lassoPoints.count >= 2 else {
            selection.removeAll()
            onSelectionChanged?(selection)
            return
        }
        let polygon = lassoPoints
        let polyBounds = pageBounds(for: polygon)
        var newIDs: Set<UUID> = []
        for stroke in strokes {
            let selectionBounds = pageBounds(for: stroke.points.map { $0.cgPoint })
            guard selectionBounds.intersects(polyBounds) else { continue }
            if stroke.points.contains(where: { pointInside($0.cgPoint, polygon: polygon) }) {
                newIDs.insert(stroke.id)
            }
        }
        if newIDs.isEmpty {
            selection.removeAll()
        } else {
            let selectedStrokes = strokes.filter { newIDs.contains($0.id) }
            selection = EditorSelection(
                strokeIDs: newIDs,
                bounds: inflatedBounds(of: selectedStrokes)
            )
        }
        onSelectionChanged?(selection)
    }

    private func pointInside(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let xi = polygon[i].x, yi = polygon[i].y
            let xj = polygon[j].x, yj = polygon[j].y
            let intersects = ((yi > point.y) != (yj > point.y))
                && (point.x < (xj - xi) * (point.y - yi) / (yj - yi) + xi)
            if intersects { inside.toggle() }
            j = i
        }
        return inside
    }

    // MARK: - Selection transforms (page coordinates)

    private func moveSelection(by delta: CGSize) {
        guard selectionBeforeDrag.isActive else { return }
        let ids = selectionBeforeDrag.strokeIDs
        strokes = strokes.map { stroke in
            guard ids.contains(stroke.id) else { return stroke }
            return MacStroke(
                id: stroke.id,
                points: stroke.points.map { point in
                    let p = point.cgPoint
                    return MacPoint(CGPoint(x: p.x + delta.width, y: p.y + delta.height))
                },
                tool: stroke.tool,
                style: stroke.style
            )
        }
        selection.bounds = selectionBeforeDrag.bounds.offsetBy(dx: delta.width, dy: delta.height)
    }

    private func resizeSelection(handlePoint point: CGPoint) {
        guard selectionBeforeDrag.isActive else { return }
        let bounds = selectionBeforeDrag.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
        var anchor = center

        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            hypot(a.x - b.x, a.y - b.y)
        }

        switch resizeDirection {
        case .topLeft:
            anchor = CGPoint(x: bounds.maxX, y: bounds.maxY)
            let original = CGPoint(x: bounds.minX, y: bounds.minY)
            let ratio = max(distance(point, anchor) / max(distance(original, anchor), 1e-3), 0.1)
            scaleX = ratio; scaleY = ratio
        case .topRight:
            anchor = CGPoint(x: bounds.minX, y: bounds.maxY)
            let original = CGPoint(x: bounds.maxX, y: bounds.minY)
            let ratio = max(distance(point, anchor) / max(distance(original, anchor), 1e-3), 0.1)
            scaleX = ratio; scaleY = ratio
        case .bottomLeft:
            anchor = CGPoint(x: bounds.maxX, y: bounds.minY)
            let original = CGPoint(x: bounds.minX, y: bounds.maxY)
            let ratio = max(distance(point, anchor) / max(distance(original, anchor), 1e-3), 0.1)
            scaleX = ratio; scaleY = ratio
        case .bottomRight:
            anchor = CGPoint(x: bounds.minX, y: bounds.minY)
            let original = CGPoint(x: bounds.maxX, y: bounds.maxY)
            let ratio = max(distance(point, anchor) / max(distance(original, anchor), 1e-3), 0.1)
            scaleX = ratio; scaleY = ratio
        case .top:
            scaleY = max((bounds.maxY - point.y) / max(bounds.height, 1e-3), 0.1)
            anchor = CGPoint(x: bounds.midX, y: bounds.maxY)
        case .bottom:
            scaleY = max((point.y - bounds.minY) / max(bounds.height, 1e-3), 0.1)
            anchor = CGPoint(x: bounds.midX, y: bounds.minY)
        case .left:
            scaleX = max((bounds.maxX - point.x) / max(bounds.width, 1e-3), 0.1)
            anchor = CGPoint(x: bounds.maxX, y: bounds.midY)
        case .right:
            scaleX = max((point.x - bounds.minX) / max(bounds.width, 1e-3), 0.1)
            anchor = CGPoint(x: bounds.minX, y: bounds.midY)
        }
        scaleX = Swift.min(scaleX, 12)
        scaleY = Swift.min(scaleY, 12)
        applySelectedTransform(scaleX: scaleX, scaleY: scaleY, anchor: anchor, rotationDelta: 0)
    }

    private func rotateSelection(handlePoint point: CGPoint) {
        guard selectionBeforeDrag.isActive else { return }
        let bounds = selectionBeforeDrag.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let currentAngle = atan2(point.y - center.y, point.x - center.x)
        let delta = currentAngle - rotateStartAngle
        applySelectedTransform(scaleX: 1, scaleY: 1, anchor: center, rotationDelta: delta)
    }

    private func applySelectedTransform(scaleX: CGFloat, scaleY: CGFloat, anchor: CGPoint, rotationDelta: CGFloat) {
        let ids = selectionBeforeDrag.strokeIDs
        let hasRotation = abs(rotationDelta) > 1e-6
        strokes = strokes.map { stroke in
            guard ids.contains(stroke.id) else { return stroke }
            return MacStroke(
                id: stroke.id,
                points: stroke.points.map { point in
                    var p = point.cgPoint
                    let dx = (p.x - anchor.x) * scaleX
                    let dy = (p.y - anchor.y) * scaleY
                    if hasRotation {
                        let cosT = cos(rotationDelta)
                        let sinT = sin(rotationDelta)
                        p = CGPoint(
                            x: anchor.x + dx * cosT - dy * sinT,
                            y: anchor.y + dx * sinT + dy * cosT
                        )
                    } else {
                        p = CGPoint(x: anchor.x + dx, y: anchor.y + dy)
                    }
                    return MacPoint(p)
                },
                tool: stroke.tool,
                style: stroke.style
            )
        }
        let selectedStrokes = strokes.filter { ids.contains($0.id) }
        if selectedStrokes.isEmpty {
            selection.bounds = .zero
        } else {
            selection.bounds = inflatedBounds(of: selectedStrokes)
        }
    }

    private func inflatedBounds(of strokes: [MacStroke]) -> CGRect {
        let points = strokes.flatMap { $0.points.map { $0.cgPoint } }
        guard let first = points.first else { return .zero }
        let raw = points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { bounds, point in
            bounds.union(CGRect(origin: point, size: .zero))
        }
        let pad = SelectionGeometry.handleSize(for: Swift.max(currentScale, 0.05)) * 0.8
        return raw.insetBy(dx: -pad, dy: -pad)
    }
}
#endif
