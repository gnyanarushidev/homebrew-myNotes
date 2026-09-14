#if false // Disabled: duplicate of existing EditorCamera-based system
import Foundation
import CoreGraphics

/// A platform-agnostic camera model for navigating a 2D document space.
public struct NotebookCamera {
    /// The current zoom scale.
    public var scale: CGFloat
    /// The translation offset from document to screen coordinates.
    public var offset: CGSize
    /// The size of the viewport (screen).
    public var viewportSize: CGSize
    /// The minimum allowable zoom scale.
    public var minScale: CGFloat
    /// The maximum allowable zoom scale.
    public var maxScale: CGFloat

    /// Creates a new NotebookCamera with default values.
    public init(
        scale: CGFloat = 1,
        offset: CGSize = .zero,
        viewportSize: CGSize = .zero,
        minScale: CGFloat = 0.25,
        maxScale: CGFloat = 6.0
    ) {
        self.scale = scale
        self.offset = offset
        self.viewportSize = viewportSize
        self.minScale = minScale
        self.maxScale = maxScale
    }

    /// Sets the viewport size.
    /// - Parameter size: The new viewport size.
    public mutating func setViewportSize(_ size: CGSize) {
        viewportSize = size
        clampOffset()
    }

    /// Converts a point from screen coordinates to document coordinates.
    /// - Parameter p: The point in screen coordinates.
    /// - Returns: The corresponding point in document coordinates.
    public func screenToDocument(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: (p.x - offset.width) / scale,
            y: (p.y - offset.height) / scale
        )
    }

    /// Converts a point from document coordinates to screen coordinates.
    /// - Parameter p: The point in document coordinates.
    /// - Returns: The corresponding point in screen coordinates.
    public func documentToScreen(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: p.x * scale + offset.width,
            y: p.y * scale + offset.height
        )
    }

    /// Converts a rect from document coordinates to screen coordinates.
    /// - Parameter r: The rect in document coordinates.
    /// - Returns: The corresponding rect in screen coordinates.
    public func documentToScreen(_ r: CGRect) -> CGRect {
        CGRect(
            origin: documentToScreen(r.origin),
            size: CGSize(width: r.size.width * scale, height: r.size.height * scale)
        )
    }

    /// Converts a rect from screen coordinates to document coordinates.
    /// - Parameter r: The rect in screen coordinates.
    /// - Returns: The corresponding rect in document coordinates.
    public func screenToDocument(_ r: CGRect) -> CGRect {
        CGRect(
            origin: screenToDocument(r.origin),
            size: CGSize(width: r.size.width / scale, height: r.size.height / scale)
        )
    }

    /// Pans the camera by a delta offset in screen coordinates.
    /// - Parameter delta: The delta offset to pan by.
    public mutating func pan(by delta: CGSize) {
        offset.width += delta.width
        offset.height += delta.height
        clampOffset()
    }

    /// Sets the scale (zoom level) around a given screen anchor point.
    /// The document point under the screenAnchor remains stationary.
    /// - Parameters:
    ///   - newScale: The new scale to set.
    ///   - screenAnchor: The screen point around which to zoom.
    public mutating func setScale(_ newScale: CGFloat, around screenAnchor: CGPoint) {
        let clampedScale = clampScale(newScale)
        guard clampedScale != scale else { return }

        // Document point under screenAnchor before zoom change
        let docAnchor = screenToDocument(screenAnchor)

        scale = clampedScale

        // Adjust offset so docAnchor maps back to screenAnchor
        offset.width = screenAnchor.x - docAnchor.x * scale
        offset.height = screenAnchor.y - docAnchor.y * scale

        clampOffset()
    }

    /// Zooms in by a factor around a given screen anchor point.
    /// - Parameters:
    ///   - factor: Zoom factor, default is 1.2 (20% zoom in).
    ///   - screenAnchor: The screen point around which to zoom.
    public mutating func zoomIn(factor: CGFloat = 1.2, around screenAnchor: CGPoint) {
        setScale(scale * factor, around: screenAnchor)
    }

    /// Zooms out by a factor around a given screen anchor point.
    /// - Parameters:
    ///   - factor: Zoom factor, default is 1.2 (20% zoom out).
    ///   - screenAnchor: The screen point around which to zoom.
    public mutating func zoomOut(factor: CGFloat = 1.2, around screenAnchor: CGPoint) {
        setScale(scale / factor, around: screenAnchor)
    }

    /// Fits a document rectangle into the viewport with padding.
    /// Adds a margin of 24 points around the fitted rectangle.
    /// - Parameter documentRect: The document rect to fit.
    public mutating func fit(rect documentRect: CGRect) {
        guard !viewportSize.equalTo(.zero),
              !documentRect.isEmpty else { return }

        let margin: CGFloat = 24

        let availableWidth = max(viewportSize.width - 2 * margin, 1)
        let availableHeight = max(viewportSize.height - 2 * margin, 1)

        let scaleX = availableWidth / documentRect.width
        let scaleY = availableHeight / documentRect.height
        let targetScale = clampScale(min(scaleX, scaleY))

        scale = targetScale

        let fittedScreenRect = documentToScreen(documentRect)
        // Center documentRect in viewport
        offset.width += (viewportSize.width - fittedScreenRect.width) / 2 - fittedScreenRect.minX
        offset.height += (viewportSize.height - fittedScreenRect.height) / 2 - fittedScreenRect.minY

        clampOffset()
    }

    /// Sets the camera to actual size (scale = 1) and optionally centers on a document point.
    /// - Parameter documentPoint: Optional document point to center on.
    public mutating func actualSize(centerOn documentPoint: CGPoint? = nil) {
        scale = clampScale(1)
        if let center = documentPoint {
            centerDocumentPointInViewport(center)
        } else {
            clampOffset()
        }
    }

    // MARK: - Private Helpers

    /// Clamps the offset so that the visible document area does not show empty space beyond content.
    private mutating func clampOffset() {
        guard viewportSize.width > 0 && viewportSize.height > 0 else { return }

        // The size of the document visible on screen at current scale
        let visibleDocWidth = viewportSize.width / scale
        let visibleDocHeight = viewportSize.height / scale

        // The max offsets in screen coordinates
        // We clamp offset so that document top-left is not too far right/down,
        // and bottom-right is not too far left/up, assuming document starts at 0,0.
        // Since we don't know document bounds here, allow panning freely (no clamping).
        // However, to avoid jumping offset to large positive values, clamp offset to reasonable range:
        // We only clamp offset so that it doesn't shift viewport off positive coordinates of document.

        // Minimum offset in screen coordinates corresponds to document origin at top-left of viewport
        let minOffsetX = viewportSize.width - CGFloat.greatestFiniteMagnitude // effectively no limit
        let minOffsetY = viewportSize.height - CGFloat.greatestFiniteMagnitude

        // Maximum offset where the document origin is at top-left of viewport (offset can be positive)
        let maxOffsetX = CGFloat.greatestFiniteMagnitude
        let maxOffsetY = CGFloat.greatestFiniteMagnitude

        // For a generic camera, no clamping is possible without document bounds info,
        // so we skip clamping offset here.

        // This function is a placeholder to be expanded if document bounds are ever provided.

        // If desired, could clamp offsets to avoid extreme values to prevent floating point precision issues:
        offset.width = clamp(value: offset.width, lower: -1_000_000_000, upper: 1_000_000_000)
        offset.height = clamp(value: offset.height, lower: -1_000_000_000, upper: 1_000_000_000)
    }

    /// Clamps a scale value between minScale and maxScale.
    /// - Parameter s: The scale value to clamp.
    /// - Returns: The clamped scale value.
    private func clampScale(_ s: CGFloat) -> CGFloat {
        min(max(s, minScale), maxScale)
    }

    /// Centers the viewport on a given document point.
    /// - Parameter documentPoint: The point in document coordinates to center on.
    private mutating func centerDocumentPointInViewport(_ documentPoint: CGPoint) {
        offset.width = viewportSize.width / 2 - documentPoint.x * scale
        offset.height = viewportSize.height / 2 - documentPoint.y * scale
        clampOffset()
    }

    /// Clamps a value between lower and upper bounds.
    /// - Parameters:
    ///   - value: The value to clamp.
    ///   - lower: The lower bound.
    ///   - upper: The upper bound.
    /// - Returns: The clamped value.
    private func clamp(value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
#endif
