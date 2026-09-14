import SwiftUI

/// How the camera behaves when the viewport is resized.
/// `.fit` keeps the page centered and refits; `.free` preserves the
/// current scale/offset and only clamps the pan so the page stays reachable.
enum ViewportMode: Equatable {
    case fit
    case free
}

struct ViewportState: Equatable {
    var scale: CGFloat = 1
    var offset: CGSize = .zero
    var mode: ViewportMode = .fit

    static let minimumScale: CGFloat = 0.25
    static let maximumScale: CGFloat = 5.0
    static let pagePadding: CGFloat = 40
    static let maximumOverscroll: CGFloat = 24

    /// Maps a page-space point into canvas-space using the camera transform.
    func pagePointToCanvas(_ pagePoint: CGPoint) -> CGPoint {
        CGPoint(
            x: pagePoint.x * scale + offset.width,
            y: pagePoint.y * scale + offset.height
        )
    }

    /// Maps a canvas-space point back into the page coordinate system.
    func canvasPointToPage(_ canvasPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (canvasPoint.x - offset.width) / scale,
            y: (canvasPoint.y - offset.height) / scale
        )
    }

    /// Change scale while keeping the given screen anchor point visually stable.
    mutating func setScale(_ newScale: CGFloat, around anchor: CGPoint) {
        let clampedScale = min(max(newScale, Self.minimumScale), Self.maximumScale)
        guard self.scale > 0 else {
            self.scale = clampedScale
            return
        }
        let pagePoint = canvasPointToPage(anchor)
        self.scale = clampedScale
        offset = CGSize(
            width: anchor.x - pagePoint.x * clampedScale,
            height: anchor.y - pagePoint.y * clampedScale
        )
    }

    mutating func zoomIn(center: CGPoint? = nil, in viewportSize: CGSize) {
        let anchor = center ?? CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        setScale(scale * 1.25, around: anchor)
    }

    mutating func zoomOut(center: CGPoint? = nil, in viewportSize: CGSize) {
        let anchor = center ?? CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        setScale(scale / 1.25, around: anchor)
    }

    /// Set scale to 1x (actual size), keeping the page centered in the viewport.
    mutating func actualSize(pageSize: CGSize, in viewportSize: CGSize) {
        scale = 1
        center(on: pageSize, in: viewportSize)
    }

    /// Fit the page within the viewport with padding, centered.
    mutating func fitPage(pageSize: CGSize, in viewportSize: CGSize) {
        let availableWidth = max(1, viewportSize.width - Self.pagePadding * 2)
        let availableHeight = max(1, viewportSize.height - Self.pagePadding * 2)
        let fitScale = min(availableWidth / pageSize.width, availableHeight / pageSize.height)
        scale = min(max(fitScale, Self.minimumScale), Self.maximumScale)
        center(on: pageSize, in: viewportSize)
    }

    /// Center the page in the viewport at the current scale.
    mutating func center(on pageSize: CGSize, in viewportSize: CGSize) {
        offset = CGSize(
            width: (viewportSize.width - pageSize.width * scale) / 2,
            height: (viewportSize.height - pageSize.height * scale) / 2
        )
    }

    mutating func pan(by translation: CGSize) {
        offset.width += translation.width
        offset.height += translation.height
    }

    /// Clamp offset so the page can't drift entirely outside the viewport.
    func clampedOffset(pageSize: CGSize, viewportSize: CGSize) -> CGSize {
        let scaledW = pageSize.width * scale
        let scaledH = pageSize.height * scale

        let centeredX = (viewportSize.width - scaledW) / 2
        let centeredY = (viewportSize.height - scaledH) / 2
        let minX = scaledW >= viewportSize.width
            ? viewportSize.width - scaledW - Self.maximumOverscroll
            : centeredX - Self.maximumOverscroll
        let maxX = scaledW >= viewportSize.width
            ? Self.maximumOverscroll
            : centeredX + Self.maximumOverscroll
        let minY = scaledH >= viewportSize.height
            ? viewportSize.height - scaledH - Self.maximumOverscroll
            : centeredY - Self.maximumOverscroll
        let maxY = scaledH >= viewportSize.height
            ? Self.maximumOverscroll
            : centeredY + Self.maximumOverscroll

        return CGSize(
            width: min(max(offset.width, minX), maxX),
            height: min(max(offset.height, minY), maxY)
        )
    }
}

struct SelectionFilter: Equatable {
    var handwriting = true
    var highlighter = true
    var images = true
    var text = true
    var shapes = true
    var stickyNotes = true
}

struct PageSelection: Equatable {
    var selectedStrokeIDs: Set<UUID> = []
    var lassoPoints: [CGPoint] = []
    var filter = SelectionFilter()

    var isSelecting: Bool { !lassoPoints.isEmpty }

    mutating func clear() {
        selectedStrokeIDs.removeAll()
        lassoPoints.removeAll()
    }
}

func pagePoint(from screenPoint: CGPoint, viewport: ViewportState) -> CGPoint {
    viewport.canvasPointToPage(screenPoint)
}

func pageBounds(for points: [CGPoint]) -> CGRect {
    guard let first = points.first else { return .null }
    return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { bounds, point in
        bounds.union(CGRect(origin: point, size: .zero))
    }
}
