import SwiftUI

enum EditorTool: Equatable, Hashable, Sendable {
    case pen
    case pencil
    case highlighter
    case eraser
    case lasso
    case rectangularSelection
    case text
    case image
    case shape(ShapeKind)
    case ruler
    case pan
    case select

    static var allKnownTools: [EditorTool] {
        var tools: [EditorTool] = [
            .pen,
            .pencil,
            .highlighter,
            .eraser,
            .lasso,
            .rectangularSelection,
            .text,
            .image,
            .ruler,
            .pan,
            .select,
        ]
        tools.append(contentsOf: ShapeKind.allCases.map { .shape($0) })
        return tools
    }

    var displayName: String {
        switch self {
        case .pen: return "Pen"
        case .pencil: return "Pencil"
        case .highlighter: return "Highlighter"
        case .eraser: return "Eraser"
        case .lasso: return "Lasso"
        case .rectangularSelection: return "Rect. Selection"
        case .text: return "Text"
        case .image: return "Image"
        case .shape(let kind): return kind.rawValue.capitalized
        case .ruler: return "Ruler"
        case .pan: return "Pan"
        case .select: return "Select"
        }
    }

    var systemImage: String {
        switch self {
        case .pen: return "pencil"
        case .pencil: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        case .lasso: return "lasso"
        case .rectangularSelection: return "rectangle.dashed"
        case .text: return "text.cursor"
        case .image: return "photo.badge.plus"
        case .shape(let kind): return kind.systemImage
        case .ruler: return "ruler"
        case .pan: return "hand.draw"
        case .select: return "cursorarrow"
        }
    }

    var isDrawingTool: Bool {
        switch self {
        case .pen, .pencil, .highlighter: return true
        default: return false
        }
    }

    var isSelectionTool: Bool {
        switch self {
        case .lasso, .rectangularSelection, .select: return true
        default: return false
        }
    }
}

enum ShapeKind: String, CaseIterable, Identifiable, Sendable {
    case rectangle
    case circle
    case line
    case arrow

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        }
    }
}

enum CornerDirection: Equatable, Sendable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    var debugName: String {
        switch self {
        case .topLeft: return "topLeft"
        case .top: return "top"
        case .topRight: return "topRight"
        case .right: return "right"
        case .bottomRight: return "bottomRight"
        case .bottom: return "bottom"
        case .bottomLeft: return "bottomLeft"
        case .left: return "left"
        }
    }

    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return true
        default: return false
        }
    }
}

enum HandleRegion: Equatable, Sendable {
    case resize(CornerDirection)
    case rotate
}

enum EditorInteractionState: Equatable, Sendable {
    case idle
    case drawing
    case dragging
    case resizing
    case rotating
    case selecting
    case panning

    var debugName: String {
        switch self {
        case .idle: return "idle"
        case .drawing: return "drawing"
        case .dragging: return "dragging"
        case .resizing: return "resizing"
        case .rotating: return "rotating"
        case .selecting: return "selecting"
        case .panning: return "panning"
        }
    }
}

enum EditorCursor: Equatable, Sendable {
    case arrow
    case pen
    case pencil
    case highlighter
    case eraser
    case lasso
    case rectangularSelection
    case text
    case image
    case shape(ShapeKind)
    case ruler
    case panOpen
    case panClosed
    case move
    case resize(CornerDirection)
    case rotate
    case pointingHand
    case notAllowed
    case custom(String)

    var debugName: String {
        switch self {
        case .arrow: return "Arrow"
        case .pen: return "PenCursor"
        case .pencil: return "PencilCursor"
        case .highlighter: return "HighlighterCursor"
        case .eraser: return "EraserCursor"
        case .lasso: return "LassoCursor"
        case .rectangularSelection: return "RectSelectionCursor"
        case .text: return "TextCursor"
        case .image: return "ImageCursor"
        case .shape(let kind): return "ShapeCursor(\(kind.rawValue))"
        case .ruler: return "RulerCursor"
        case .panOpen: return "OpenHandCursor"
        case .panClosed: return "ClosedHandCursor"
        case .move: return "MoveCursor"
        case .resize(let direction): return "ResizeCursor(\(direction.debugName))"
        case .rotate: return "RotateCursor"
        case .pointingHand: return "PointingHandCursor"
        case .notAllowed: return "NotAllowedCursor"
        case .custom(let name): return name
        }
    }

    var systemImage: String {
        switch self {
        case .arrow: return "cursorarrow"
        case .pen: return "pencil"
        case .pencil: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        case .lasso: return "lasso"
        case .rectangularSelection: return "rectangle.dashed"
        case .text: return "text.cursor"
        case .image: return "photo.badge.plus"
        case .shape(let kind): return kind.systemImage
        case .ruler: return "ruler"
        case .panOpen, .panClosed: return "hand.draw"
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .resize(let direction):
            switch direction {
            case .topLeft, .bottomRight: return "arrow.up.left.and.arrow.down.right"
            case .topRight, .bottomLeft: return "arrow.up.right.and.arrow.down.left"
            case .left, .right: return "arrow.left.and.right"
            case .top, .bottom: return "arrow.up.and.down"
            }
        case .rotate: return "arrow.triangle.2.circlepath"
        case .pointingHand: return "hand.point.up"
        case .notAllowed: return "nosign"
        case .custom: return "cursorarrow"
        }
    }
}

struct EditorCursorState: Equatable {
    var activeTool: EditorTool = .pen
    var interaction: EditorInteractionState = .idle
    var temporaryToolOverride: EditorTool?
    var debugToolOverride: EditorTool?

    var overMovableContent = false
    var overLockedContent = false
    var overHandle: HandleRegion?
    var resizingDirection: CornerDirection = .bottomRight
    var isSelecting = false
    var isPanning = false
    var isOutsidePage = false
    var isBusy = false

    var viewportScale: CGFloat = 1
    var eraserRadius: CGFloat = 18
    var highlighterWidth: CGFloat = 12
    var pencilWidth: CGFloat = 4
    var penWidth: CGFloat = 3

    var effectiveTool: EditorTool {
        debugToolOverride ?? temporaryToolOverride ?? activeTool
    }

    mutating func resetTransientFlags() {
        overMovableContent = false
        overLockedContent = false
        overHandle = nil
        isSelecting = false
        isPanning = false
        isOutsidePage = false
        isBusy = false
        interaction = .idle
    }
}

struct CursorDebugSnapshot: Equatable {
    var cursor: EditorCursor
    var effectiveTool: EditorTool
    var interaction: EditorInteractionState
    var pagePoint: CGPoint?
    var canvasPoint: CGPoint?
    var overMovableContent: Bool
    var overLockedContent: Bool
    var isOutsidePage: Bool
    var isBusy: Bool
    var viewportScale: CGFloat
    var eraserRadius: CGFloat
    var highlighterWidth: CGFloat
}

enum CursorController {

    static func cursor(for state: EditorCursorState) -> EditorCursor {
        let tool = state.effectiveTool

        if state.isBusy {
            return .arrow
        }

        if state.overLockedContent {
            return .notAllowed
        }

        if let handle = state.overHandle {
            switch handle {
            case .resize(let direction): return .resize(direction)
            case .rotate: return .rotate
            }
        }

        switch state.interaction {
        case .dragging: return .move
        case .resizing: return .resize(state.resizingDirection)
        case .rotating: return .rotate
        case .panning: return .panClosed
        case .idle, .drawing, .selecting: break
        }

        if tool == .pan {
            return .panOpen
        }

        if state.isSelecting {
            return .lasso
        }

        if tool.isSelectionTool && state.overMovableContent {
            return .move
        }

        return toolCursor(for: tool, state: state)
    }

    static func toolCursor(for tool: EditorTool, state: EditorCursorState) -> EditorCursor {
        if state.isOutsidePage {
            return .arrow
        }
        switch tool {
        case .pen: return .pen
        case .pencil: return .pencil
        case .highlighter: return .highlighter
        case .eraser: return .eraser
        case .lasso: return .lasso
        case .rectangularSelection: return .rectangularSelection
        case .text: return .text
        case .image: return .image
        case .shape(let kind): return .shape(kind)
        case .ruler: return .ruler
        case .pan: return .panOpen
        case .select: return state.overMovableContent ? .move : .arrow
        }
    }

    static func snapshot(for state: EditorCursorState, pagePoint: CGPoint?, canvasPoint: CGPoint? = nil) -> CursorDebugSnapshot {
        CursorDebugSnapshot(
            cursor: cursor(for: state),
            effectiveTool: state.effectiveTool,
            interaction: state.interaction,
            pagePoint: pagePoint,
            canvasPoint: canvasPoint,
            overMovableContent: state.overMovableContent,
            overLockedContent: state.overLockedContent,
            isOutsidePage: state.isOutsidePage,
            isBusy: state.isBusy,
            viewportScale: state.viewportScale,
            eraserRadius: state.eraserRadius,
            highlighterWidth: state.highlighterWidth
        )
    }
}

#if os(macOS)
extension EditorTool {
    init(macTool: MacDrawingTool) {
        switch macTool {
        case .pen: self = .pen
        case .pencil: self = .pencil
        case .highlighter: self = .highlighter
        case .eraser: self = .eraser
        case .lasso: self = .lasso
        case .rectangle: self = .shape(.rectangle)
        case .circle: self = .shape(.circle)
        case .line: self = .shape(.line)
        case .arrow: self = .shape(.arrow)
        }
    }
}
#endif

// MARK: - Tool settings

/// Style for an inking tool (pen / pencil / highlighter).
struct InkToolSettings: Equatable {
    var color: Color = .black
    var width: CGFloat = 3
}

/// Per-tool drawing settings, remembered while switching tools.
struct EditorToolSettings: Equatable {
    var pen = InkToolSettings(color: Color(red: 0.0, green: 0.0, blue: 0.0), width: 3)
    var pencil = InkToolSettings(color: Color(red: 0.38, green: 0.38, blue: 0.42), width: 1.5)
    var highlighter = InkToolSettings(color: Color.yellow, width: 14)
    var highlighterOpacity: CGFloat = 0.35
    var eraserRadius: CGFloat = 12

    #if os(macOS)
    func inkSettings(for tool: MacDrawingTool) -> InkToolSettings {
        switch tool {
        case .pen, .rectangle, .circle, .line, .arrow: return pen
        case .pencil: return pencil
        case .highlighter: return highlighter
        default: return InkToolSettings(color: .black, width: 3)
        }
    }
    #endif
}

// MARK: - Selection

/// A lasso selection in page (logical) coordinates.
struct EditorSelection: Equatable {
    var strokeIDs: Set<UUID> = []
    var bounds: CGRect = .zero
    var isActive: Bool { !strokeIDs.isEmpty }

    mutating func removeAll() {
        strokeIDs.removeAll()
        bounds = .zero
    }
}

enum SelectionGeometry {
    /// On-screen handle size, converted into page units for the given viewport scale.
    static func handleSize(for scale: CGFloat) -> CGFloat {
        10 / Swift.max(scale, 0.05)
    }

    static func hitPadding(for scale: CGFloat) -> CGFloat {
        8 / Swift.max(scale, 0.05)
    }

    static func rotateHandleSize(for scale: CGFloat) -> CGFloat {
        7 / Swift.max(scale, 0.05)
    }

    static func rect(halfSize: CGFloat, center: CGPoint) -> CGRect {
        CGRect(x: center.x - halfSize, y: center.y - halfSize, width: halfSize * 2, height: halfSize * 2)
    }

    /// Returns handle rects (page space) for the 8 resize grips plus the rotation grip.
    static func handles(bounds: CGRect, scale: CGFloat) -> [CornerDirection: CGRect] {
        let h = handleSize(for: scale) / 2
        let minX = bounds.minX, maxX = bounds.maxX
        let minY = bounds.minY, maxY = bounds.maxY
        let midX = bounds.midX, midY = bounds.midY

        return [
            .topLeft: rect(halfSize: h, center: CGPoint(x: minX, y: minY)),
            .topRight: rect(halfSize: h, center: CGPoint(x: maxX, y: minY)),
            .bottomLeft: rect(halfSize: h, center: CGPoint(x: minX, y: maxY)),
            .bottomRight: rect(halfSize: h, center: CGPoint(x: maxX, y: maxY)),
            .top: rect(halfSize: h, center: CGPoint(x: midX, y: minY)),
            .bottom: rect(halfSize: h, center: CGPoint(x: midX, y: maxY)),
            .left: rect(halfSize: h, center: CGPoint(x: minX, y: midY)),
            .right: rect(halfSize: h, center: CGPoint(x: maxX, y: midY))
        ]
    }

    static func rotateHandle(bounds: CGRect, scale: CGFloat) -> CGRect {
        rect(
            halfSize: rotateHandleSize(for: scale) / 2,
            center: CGPoint(x: bounds.midX, y: bounds.minY - handleSize(for: scale) * 1.6)
        )
    }

    /// Which set of expandable directions a point is over, if any.
    static func resizeDirection(at point: CGPoint, bounds: CGRect, scale: CGFloat) -> CornerDirection? {
        for (direction, handleRect) in handles(bounds: bounds, scale: scale) {
            if handleRect.insetBy(dx: -hitPadding(for: scale), dy: -hitPadding(for: scale)).contains(point) {
                return direction
            }
        }
        return nil
    }

    static func isOverRotateHandle(_ point: CGPoint, bounds: CGRect, scale: CGFloat) -> Bool {
        rotateHandle(bounds: bounds, scale: scale)
            .insetBy(dx: -hitPadding(for: scale), dy: -hitPadding(for: scale))
            .contains(point)
    }

    static func isInside(_ point: CGPoint, bounds: CGRect, scale: CGFloat) -> Bool {
        let pad = hitPadding(for: scale)
        return bounds.insetBy(dx: -pad, dy: -pad).contains(point)
    }
}