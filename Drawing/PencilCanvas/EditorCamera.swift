#if os(macOS)
import SwiftUI

/// Single source of truth for the macOS canvas viewport ("camera over a page").
/// The NSView owns all rendering and input; every zoom/pan mutation flows through
/// this camera so the page stays in stable page-space coordinates and scaling is
/// consistent between toolbar, pinch, scroll-wheel, and pointer math.
final class EditorCamera: ObservableObject {
    @Published var viewport = ViewportState() {
        didSet { surface?.needsDisplay = true }
    }

    weak var surface: MacCanvasNSView?
    var onViewportChanged: (() -> Void)?
    private(set) var pageSize: CGSize
    private(set) var viewportSize: CGSize = .zero

    init(pageSize: CGSize) {
        self.pageSize = pageSize
    }

    func setDocumentSize(_ size: CGSize, preservingViewport: Bool = false) {
        guard size.width > 0, size.height > 0 else { return }
        guard pageSize != size else { return }
        pageSize = size
        // Appending paper extends the pan range, not the user's current view.
        guard !preservingViewport else { return }
        if viewport.mode == .fit { fitPage() } else { clampPan() }
    }

    // MARK: - Coordinate conversions (canvas <-> page)

    func pagePoint(fromCanvasPoint point: CGPoint) -> CGPoint {
        viewport.canvasPointToPage(point)
    }

    func canvasPoint(fromPagePoint point: CGPoint) -> CGPoint {
        viewport.pagePointToCanvas(point)
    }

    // MARK: - Viewport lifecycle

    /// Update the mounted canvas size. Applies a first fit, refits while in
    /// `.fit` mode, or only clamps the offset while in `.free` mode.
    func setViewportSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        guard viewportSize != size else { return }
        let hadSize = viewportSize.width > 0 && viewportSize.height > 0
        viewportSize = size
        if !hadSize {
            fitPage()
        } else if viewport.mode == .fit {
            fitPage()
        } else {
            clampPan()
        }
    }

    // MARK: - Zoom

    func fitPage() {
        var nextViewport = viewport
        nextViewport.fitPage(pageSize: pageSize, in: viewportSize)
        viewport.mode = .fit
        guard viewport.scale != nextViewport.scale || viewport.offset != nextViewport.offset else {
            return
        }
        viewport.scale = nextViewport.scale
        viewport.offset = nextViewport.offset
        notifyViewportChanged()
    }

    func actualSize() {
        viewport.actualSize(pageSize: pageSize, in: viewportSize)
        viewport.mode = .free
        clampPan()
        notifyViewportChanged()
    }

    func actualSize(centeredOn documentFrame: CGRect) {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        viewport.scale = 1
        viewport.offset = CGSize(
            width: viewportSize.width / 2 - documentFrame.midX,
            height: viewportSize.height / 2 - documentFrame.midY
        )
        viewport.mode = .free
        notifyViewportChanged()
    }

    func fit(documentFrame: CGRect) {
        guard viewportSize.width > 0, viewportSize.height > 0, !documentFrame.isEmpty else { return }
        let availableWidth = max(viewportSize.width - ViewportState.pagePadding * 2, 1)
        let availableHeight = max(viewportSize.height - ViewportState.pagePadding * 2, 1)
        viewport.scale = min(
            max(min(availableWidth / documentFrame.width, availableHeight / documentFrame.height), ViewportState.minimumScale),
            ViewportState.maximumScale
        )
        viewport.offset = CGSize(
            width: viewportSize.width / 2 - documentFrame.midX * viewport.scale,
            height: viewportSize.height / 2 - documentFrame.midY * viewport.scale
        )
        viewport.mode = .free
        notifyViewportChanged()
    }

    func focus(documentFrame: CGRect) {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        viewport.offset = CGSize(
            width: viewportSize.width / 2 - documentFrame.midX * viewport.scale,
            height: viewportSize.height / 2 - documentFrame.midY * viewport.scale
        )
        viewport.mode = .free
        clampPan()
        notifyViewportChanged()
    }

    func zoomIn() { zoomByFactor(1.25) }
    func zoomOut() { zoomByFactor(1 / 1.25) }

    func zoomByFactor(_ factor: CGFloat, around anchor: CGPoint? = nil) {
        let fallback = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        setScale(viewport.scale * factor, around: anchor ?? fallback)
    }

    /// Change scale while keeping `anchor` (canvas/viewport coordinates) stable.
    func setScale(_ newScale: CGFloat, around anchor: CGPoint) {
        viewport.setScale(newScale, around: anchor)
        viewport.mode = .free
        clampPan()
        notifyViewportChanged()
    }

    /// Trackpad pinch magnification, anchored at the pointer in canvas coordinates.
    func applyMagnification(_ amount: CGFloat, at canvasPoint: CGPoint) {
        setScale(viewport.scale * (1 + amount), around: canvasPoint)
    }

    // MARK: - Pan

    func pan(by translation: CGSize) {
        guard abs(translation.width) > 0.01 || abs(translation.height) > 0.01 else { return }
        var next = viewport
        next.pan(by: translation)
        next.mode = .free
        if viewportSize.width > 0, viewportSize.height > 0 {
            let clamped = next.clampedOffset(pageSize: pageSize, viewportSize: viewportSize)
            // Appended paper can change the allowed range while the old page
            // is centered. Clamping must not move farther than the user's pan.
            next.offset = CGSize(
                width: min(max(clamped.width, min(viewport.offset.width, next.offset.width)), max(viewport.offset.width, next.offset.width)),
                height: min(max(clamped.height, min(viewport.offset.height, next.offset.height)), max(viewport.offset.height, next.offset.height))
            )
        }
        guard next != viewport else { return }
        viewport = next
        notifyViewportChanged()
    }

    private func clampPan() {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        viewport.offset = viewport.clampedOffset(pageSize: pageSize, viewportSize: viewportSize)
    }

    private func notifyViewportChanged() {
        surface?.needsDisplay = true
        onViewportChanged?()
    }
}
#endif
