#if os(macOS)
import AppKit
import SwiftUI
import SwiftData

/// Keeps toolbar actions attached to the selection even when a button takes focus.
final class MacSelectionController: ObservableObject {
    @Published private(set) var hasSelection = false
    private weak var selectedCanvas: MacCanvasNSView?

    func selectionDidChange(in canvas: MacCanvasNSView) {
        if canvas.selection.isActive {
            let previousCanvas = selectedCanvas
            selectedCanvas = canvas
            if previousCanvas !== canvas {
                previousCanvas?.clearSelection()
            }
        } else if selectedCanvas === canvas {
            selectedCanvas = nil
        }
        updateAvailability()
    }

    func deleteSelection() {
        selectedCanvas?.deleteSelection()
    }

    func detach(_ canvas: MacCanvasNSView) {
        guard selectedCanvas === canvas else { return }
        selectedCanvas = nil
        // Page removal can happen during an NSViewRepresentable update.
        DispatchQueue.main.async { [weak self] in self?.updateAvailability() }
    }

    private func updateAvailability() {
        let isActive = selectedCanvas?.selection.isActive == true
        if hasSelection != isActive { hasSelection = isActive }
    }
}

struct MacNotebookCanvasView: NSViewRepresentable {
    let pages: [Page]
    @ObservedObject var camera: EditorCamera
    @Binding var selectedTool: MacDrawingTool
    @Binding var toolSettings: EditorToolSettings
    let selectionController: MacSelectionController
    var modelContext: ModelContext
    var layout: NotebookLayout

    func makeNSView(context: Context) -> MacNotebookCanvasNSView {
        let view = MacNotebookCanvasNSView(frame: .zero)
        view.camera = camera
        view.modelContext = modelContext
        view.selectionController = selectionController
        view.notebookLayout = layout
        view.updateToolState(selectedTool: selectedTool, toolSettings: toolSettings)
        camera.onViewportChanged = { [weak view] in view?.invalidatePageViews() }
        view.updatePages(pages)
        camera.surface = nil
        return view
    }

    func updateNSView(_ nsView: MacNotebookCanvasNSView, context: Context) {
        nsView.camera = camera
        nsView.modelContext = modelContext
        nsView.selectionController = selectionController
        nsView.notebookLayout = layout
        nsView.updateToolState(selectedTool: selectedTool, toolSettings: toolSettings)
        camera.onViewportChanged = { [weak nsView] in nsView?.invalidatePageViews() }
        nsView.updatePages(pages)
    }

    static func dismantleNSView(_ nsView: MacNotebookCanvasNSView, coordinator: ()) {
        nsView.detachSelectionController()
    }
}

final class MacNotebookCanvasNSView: NSView {
    private struct PageConfiguration: Equatable {
        let id: UUID
        let size: CGSize
        let template: PageTemplate
        let color: PageColor
    }

    weak var camera: EditorCamera?
    var modelContext: ModelContext?
    var notebookLayout = NotebookLayout(pageGap: 32)
    var selectedTool: MacDrawingTool = .pen
    var toolSettings = EditorToolSettings()
    var selectionController: MacSelectionController?

    private var pageViews: [UUID: MacCanvasNSView] = [:]
    private var pageFrames: [UUID: CGRect] = [:]
    private var pagesByID: [UUID: Page] = [:]
    private var pageConfigurations: [PageConfiguration] = []
    private var loadedPageIDs = Set<UUID>()
    private var exportObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        observeExports()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        observeExports()
    }

    deinit {
        if let exportObserver { NotificationCenter.default.removeObserver(exportObserver) }
    }

    private func observeExports() {
        exportObserver = NotificationCenter.default.addObserver(forName: .captureMacNotebookExport, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, self.window?.isKeyWindow == true, let request = notification.object as? MacNotebookExportRequest else { return }
                for (id, page) in self.pagesByID where page.notebook?.id == request.notebookID && self.loadedPageIDs.contains(id) {
                    if let view = self.pageViews[id] { request.strokes[id] = view.strokes }
                }
            }
        }
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }

    func updateToolState(selectedTool: MacDrawingTool, toolSettings: EditorToolSettings) {
        guard self.selectedTool != selectedTool || self.toolSettings != toolSettings else { return }
        self.selectedTool = selectedTool
        self.toolSettings = toolSettings
        for pageView in pageViews.values {
            pageView.selectedTool = selectedTool
            pageView.toolSettings = toolSettings
            pageView.syncCursorState()
        }
    }

    func updatePages(_ pages: [Page]) {
        guard let camera else { return }
        pagesByID = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, $0) })
        let configurations = pages.map {
            PageConfiguration(
                id: $0.id,
                size: $0.pageSize.dimensions,
                template: $0.effectiveTemplate,
                color: $0.effectivePageColor
            )
        }
        guard configurations != pageConfigurations else { return }

        let sizes = pages.map { $0.pageSize.dimensions }
        let documentHeight = notebookLayout.totalDocumentHeight(pageSizes: sizes)
        let documentWidth = sizes.map(\.width).max() ?? 1
        let isExtension = !pageConfigurations.isEmpty
            && configurations.count > pageConfigurations.count
            && configurations.prefix(pageConfigurations.count).map(\.id) == pageConfigurations.map(\.id)
        camera.setDocumentSize(
            CGSize(width: documentWidth, height: documentHeight),
            preservingViewport: isExtension
        )

        let validIDs = Set(pages.map(\.id))
        for (id, pageView) in pageViews where !validIDs.contains(id) {
            selectionController?.detach(pageView)
            pageView.onSelectionChanged = nil
            pageView.removeFromSuperview()
            pageViews.removeValue(forKey: id)
            pageFrames.removeValue(forKey: id)
            loadedPageIDs.remove(id)
        }

        for (index, page) in pages.enumerated() {
            let originY = notebookLayout.documentY(forPageAt: index, pageSizes: sizes)
            let frame = CGRect(origin: CGPoint(x: 0, y: originY), size: page.pageSize.dimensions)
            pageFrames[page.id] = frame

            let pageView: MacCanvasNSView
            if let existing = pageViews[page.id] {
                pageView = existing
            } else {
                pageView = makePageView(page: page)
                pageViews[page.id] = pageView
                addSubview(pageView)
            }
            pageView.camera = camera
            pageView.camera?.surface = nil
            pageView.documentOrigin = frame.origin
            pageView.pageSize = frame.size
            pageView.template = page.effectiveTemplate
            pageView.pageColor = page.effectivePageColor
            pageView.selectedTool = selectedTool
            pageView.toolSettings = toolSettings
            pageView.frame = bounds
            if pageConfigurations.first(where: { $0.id == page.id }) != configurations[index] {
                pageView.needsDisplay = true
            }
        }
        pageConfigurations = configurations
        updatePageVisibility()
    }

    func invalidatePageViews() {
        updatePageVisibility()
    }

    func detachSelectionController() {
        for pageView in pageViews.values {
            selectionController?.detach(pageView)
        }
        selectionController = nil
    }

    private func makePageView(page: Page) -> MacCanvasNSView {
        let pageView = MacCanvasNSView(frame: bounds)
        pageView.selectedTool = selectedTool
        pageView.toolSettings = toolSettings
        pageView.template = page.effectiveTemplate
        pageView.pageColor = page.effectivePageColor
        pageView.pageSize = page.pageSize.dimensions
        pageView.onSelectionChanged = { [weak self, weak pageView] _ in
            guard let pageView else { return }
            self?.selectionController?.selectionDidChange(in: pageView)
        }
        pageView.onContinueInk = { [weak self, weak page] point in
            guard let self, let page,
                  let index = self.pageConfigurations.firstIndex(where: { $0.id == page.id }),
                  self.pageConfigurations.indices.contains(index + 1),
                  point.y >= page.pageSize.dimensions.height else { return nil }
            let nextID = self.pageConfigurations[index + 1].id
            guard let next = self.pagesByID[nextID], let view = self.pageViews[nextID] else { return nil }
            if !self.loadedPageIDs.contains(nextID) { view.strokes = self.loadStrokes(for: next) }
            return view
        }
        pageView.onStrokesChanged = { [weak self, weak page] strokes in
            guard let self, let page else { return }
            page.hasDrawingContent = !strokes.isEmpty
            page.updatedAt = .now
            page.notebook?.updatedAt = .now
            if page.drawingFileName == nil {
                page.drawingFileName = "\(page.id.uuidString).drawing.json"
            }
            MacDrawingStorage.save(strokes, to: page.drawingFileName!)
            try? self.modelContext?.save()
        }
        return pageView
    }

    private func loadStrokes(for page: Page) -> [MacStroke] {
        loadedPageIDs.insert(page.id)
        let strokes = page.drawingFileName.map(MacDrawingStorage.load) ?? []
        if page.hasDrawingContent != !strokes.isEmpty {
            page.hasDrawingContent = !strokes.isEmpty
        }
        return strokes
    }

    private func updatePageVisibility() {
        guard let camera, camera.viewportSize.width > 0, camera.viewportSize.height > 0 else { return }
        let topLeft = camera.pagePoint(fromCanvasPoint: .zero)
        let bottomRight = camera.pagePoint(fromCanvasPoint: CGPoint(
            x: camera.viewportSize.width,
            y: camera.viewportSize.height
        ))
        let visibleDocumentRect = CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        ).insetBy(dx: -160, dy: -160)

        for (id, pageView) in pageViews {
            let shouldRender = pageView.isHandlingInkGesture || pageFrames[id]?.intersects(visibleDocumentRect) == true
            pageView.isHidden = !shouldRender
            guard shouldRender else { continue }
            if !loadedPageIDs.contains(id), let page = pagesByID[id] {
                pageView.strokes = loadStrokes(for: page)
            }
            pageView.needsDisplay = true
        }
    }

    override func layout() {
        super.layout()
        for pageView in pageViews.values {
            pageView.frame = bounds
        }
        camera?.setViewportSize(bounds.size)
        updatePageVisibility()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // NSView receives this point in its superview's coordinates, which may
        // have a different origin and flippedness than the notebook viewport.
        let canvasPoint = convert(point, from: superview)
        guard !isHidden, bounds.contains(canvasPoint) else { return nil }
        guard let camera else { return self }
        let documentPoint = camera.pagePoint(fromCanvasPoint: canvasPoint)
        for (id, frame) in pageFrames where frame.contains(documentPoint) {
            if let pageView = pageViews[id], !pageView.isHidden {
                return pageView
            }
        }
        return self
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
        dirtyRect.fill()
    }

    override func scrollWheel(with event: NSEvent) {
        guard let camera else { return }
        if event.modifierFlags.contains(.command) {
            let point = convert(event.locationInWindow, from: nil)
            camera.zoomByFactor(exp(-event.scrollingDeltaY * 0.02), around: point)
        } else {
            let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
            let translation = CGSize(width: event.scrollingDeltaX * multiplier, height: event.scrollingDeltaY * multiplier)
            if translation.height < 0, abs(translation.height) > abs(translation.width),
               bounds.height > 0,
               let id = pageConfigurations.last?.id, let frame = pageFrames[id],
               camera.pagePoint(fromCanvasPoint: CGPoint(x: bounds.midX, y: bounds.maxY - translation.height)).y >= frame.maxY,
               let page = pagesByID[id], let view = pageViews[id], let notebook = page.notebook {
                if !loadedPageIDs.contains(id) { view.strokes = loadStrokes(for: page) }
                // Read the current adapter, not a stale persisted flag after
                // an erase/undo. Loading is at most once per mounted page.
                let hasInk = !view.strokes.isEmpty
                if page.hasDrawingContent != hasInk { page.hasDrawingContent = hasInk }
                if notebook.appendContinuationPage(after: page) != nil {
                    updatePages(notebook.pages.sorted { $0.createdAt < $1.createdAt })
                    try? modelContext?.save()
                }
            }
            camera.pan(by: translation)
        }
    }

    override func magnify(with event: NSEvent) {
        camera?.applyMagnification(event.magnification, at: convert(event.locationInWindow, from: nil))
    }

    override func keyDown(with event: NSEvent) {
        guard let camera else { super.keyDown(with: event); return }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "0": camera.actualSize(); return
            case "9": camera.fitPage(); return
            case "+", "=": camera.zoomIn(); return
            case "-", "_": camera.zoomOut(); return
            default: break
            }
        }
        switch event.keyCode {
        case 123: camera.pan(by: CGSize(width: 24, height: 0))
        case 124: camera.pan(by: CGSize(width: -24, height: 0))
        case 125: camera.pan(by: CGSize(width: 0, height: -24))
        case 126: camera.pan(by: CGSize(width: 0, height: 24))
        default: super.keyDown(with: event)
        }
    }
}
#endif
