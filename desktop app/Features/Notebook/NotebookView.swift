import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(iOS)
import PencilKit
import UIKit
#else
import AppKit
#endif

struct NotebookView: View {
    @Environment(\.modelContext) private var modelContext
    let notebook: Notebook
    @State private var isRenaming = false
    @State private var editedTitle = ""
    @State private var showingPDFExporter = false
    @State private var exportDocument = PDFExportDocument()
    @State private var exportFilename = "Notebook"
    private let layout = NotebookLayout(pageGap: 32)

#if os(iOS)
    @State private var isMagnifying = false
    @State private var scrollPositionID: UUID?
    @State private var scrollInteractionRevision = 0

    private var visiblePageID: UUID? {
        get { scrollPositionID }
        nonmutating set {
            // Only explicit navigation invalidates a drag; native position updates do not.
            scrollInteractionRevision += 1
            scrollPositionID = newValue
        }
    }
#endif

#if os(macOS)
    @StateObject private var camera: EditorCamera
    @StateObject private var selectionController = MacSelectionController()
    @State private var selectedTool: MacDrawingTool = .pen
    @State private var toolSettings = EditorToolSettings()
    @State private var settingsTool: MacDrawingTool?
    @State private var showingDeleteConfirmation = false
    @State private var didInitialPerPageFit = false
    @State private var showingWebExporter = false
    @State private var webExportDocument = NotebookJSONDocument()
    @State private var webExportError: String?
#endif

    init(notebook: Notebook) {
        self.notebook = notebook
#if os(macOS)
        let sortedPages = notebook.pages.sorted { $0.createdAt < $1.createdAt }
        let sizes = sortedPages.map { $0.pageSize.dimensions }
        let documentHeight = NotebookLayout(pageGap: 32).totalDocumentHeight(pageSizes: sizes)
        let documentWidth = sizes.map(\.width).max() ?? 1
        _camera = StateObject(wrappedValue: EditorCamera(pageSize: CGSize(width: documentWidth, height: documentHeight)))
#endif
    }

    private var pages: [Page] {
        notebook.pages.sorted { $0.createdAt < $1.createdAt }
    }

    private var pageSizes: [CGSize] { pages.map { $0.pageSize.dimensions } }

#if os(macOS)
    private var visiblePageIndex: Int {
        let center = CGPoint(
            x: camera.viewportSize.width / 2,
            y: camera.viewportSize.height / 2
        )
        let point = camera.pagePoint(fromCanvasPoint: center)
        return layout.nearestPageIndex(to: point, pageSizes: pageSizes) ?? 0
    }
#else
    private var visiblePageIndex: Int {
        visiblePageID.flatMap { id in pages.firstIndex { $0.id == id } } ?? 0
    }
#endif

    private var visiblePage: Page? {
        pages.indices.contains(visiblePageIndex) ? pages[visiblePageIndex] : nil
    }

#if os(macOS)
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                MacNotebookCanvasView(
                    pages: pages,
                    camera: camera,
                    selectedTool: $selectedTool,
                    toolSettings: $toolSettings,
                    selectionController: selectionController,
                    modelContext: modelContext,
                    layout: layout
                )

                FloatingWritingToolbar(
                    selectedTool: $selectedTool,
                    toolSettings: $toolSettings,
                    settingsTool: $settingsTool,
                    canDeleteSelection: selectionController.hasSelection,
                    onDeleteSelection: selectionController.deleteSelection,
                    viewportSize: geometry.size
                )
            }
            .coordinateSpace(name: "notebookViewport")
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .onAppear {
                // Perform an initial per-page fit so the first page is reasonably sized
                if !didInitialPerPageFit, camera.viewportSize.width > 0, !pages.isEmpty {
                    fitPage(visiblePageIndex)
                    didInitialPerPageFit = true
                }
            }
            .onChange(of: camera.viewportSize) { _, newSize in
                if !didInitialPerPageFit, newSize.width > 0, !pages.isEmpty {
                    fitPage(visiblePageIndex)
                    didInitialPerPageFit = true
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(notebook.title.isEmpty ? "Untitled Notebook" : notebook.title)
        .navigationSubtitle("Page \(visiblePageIndex + 1) of \(pages.count)")
        .toolbar { macNotebookToolbar }
        .confirmationDialog(
            "Delete this page?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Page", role: .destructive) { deleteCurrentPage() }
        } message: {
            Text("Its drawing will be removed from this device. This cannot be undone.")
        }
        .alert("Rename Notebook", isPresented: $isRenaming) {
            TextField("Notebook name", text: $editedTitle)
            Button("Cancel", role: .cancel) { }
            Button("Save", action: renameNotebook)
        } message: {
            Text("Choose a name for this notebook.")
        }
        .fileExporter(
            isPresented: $showingPDFExporter,
            document: exportDocument,
            contentType: .pdf,
            defaultFilename: exportFilename
        ) { _ in }
        .fileExporter(isPresented: $showingWebExporter, document: webExportDocument, contentType: .json, defaultFilename: "\(safeExportName).mynotes") { result in
            if case .failure(let error) = result { webExportError = error.localizedDescription }
        }
        .alert("Notebook export failed", isPresented: Binding(get: { webExportError != nil }, set: { if !$0 { webExportError = nil } })) {
            Button("OK", role: .cancel) { webExportError = nil }
        } message: { Text(webExportError ?? "") }
    }

    private var pageNavigationMenu: some View {
        Menu {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, _ in
                Button("Page \(index + 1)") { focusPage(index) }
            }
        } label: {
            Label("Page \(visiblePageIndex + 1) of \(pages.count)", systemImage: "doc.text")
        }
    }

    @ToolbarContentBuilder
    private var macNotebookToolbar: some ToolbarContent {
        navigationToolbar
        toolSelectionToolbar
        pageConfigurationToolbar
        viewportToolbar
        notebookActionsToolbar
    }

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { focusPage(max(visiblePageIndex - 1, 0)) } label: {
                Label("Previous Page", systemImage: "chevron.left")
            }
            .disabled(visiblePageIndex == 0)
        }
        ToolbarItem(placement: .navigation) {
            Button { focusPage(min(visiblePageIndex + 1, max(pages.count - 1, 0))) } label: {
                Label("Next Page", systemImage: "chevron.right")
            }
            .disabled(pages.isEmpty)
        }
    }

    @ToolbarContentBuilder
    private var toolSelectionToolbar: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            MacEditorToolPalette(
                selectedTool: $selectedTool,
                settingsTool: $settingsTool,
                toolSettings: $toolSettings
            )
        }
    }

    @ToolbarContentBuilder
    private var pageConfigurationToolbar: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            pageNavigationMenu
        }
        ToolbarItem(placement: .secondaryAction) {
            NotebookStyleControl(
                template: notebook.template,
                color: notebook.pageColor,
                onSelectTemplate: setNotebookTemplate,
                onSelectColor: setNotebookPageColor
            )
        }
        ToolbarItem(placement: .secondaryAction) {
            PageStyleControl(
                inheritsNotebookStyle: visiblePage?.inheritsNotebookStyle ?? true,
                template: visiblePage?.effectiveTemplate ?? notebook.template,
                color: visiblePage?.effectivePageColor ?? notebook.pageColor,
                isEnabled: visiblePage != nil,
                onCustomize: customizeCurrentPageStyle,
                onUseNotebookDefault: useNotebookStyleForCurrentPage,
                onSelectTemplate: setCurrentPageTemplate,
                onSelectColor: setCurrentPageColor
            )
        }
        ToolbarItem(placement: .secondaryAction) {
            exportMenu
        }
    }

    @ToolbarContentBuilder
    private var viewportToolbar: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Button("Fit Page", systemImage: "arrow.up.left.and.arrow.down.right") {
                fitPage(visiblePageIndex)
            }
            .keyboardShortcut("9", modifiers: .command)
        }
        ToolbarItem(placement: .secondaryAction) {
            Button("Actual Size", systemImage: "1.magnifyingglass") {
                actualSize(visiblePageIndex)
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }

    @ToolbarContentBuilder
    private var notebookActionsToolbar: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Button("Rename Notebook", systemImage: "pencil") {
                editedTitle = notebook.title
                isRenaming = true
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Add Page", systemImage: "plus", action: addPage)
        }
        ToolbarItem(placement: .secondaryAction) {
            Button("Delete Current Page", systemImage: "trash", role: .destructive) {
                showingDeleteConfirmation = true
            }
            .disabled(pages.count <= 1)
        }
    }

    private func focusPage(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        let frame = layout.pageFrame(for: pages[index], at: index, precedingPageSizes: pageSizes)
        camera.focus(documentFrame: frame)
    }

    private func fitPage(_ index: Int) {
        guard pages.indices.contains(index), camera.viewportSize.width > 0 else { return }
        let frame = layout.pageFrame(for: pages[index], at: index, precedingPageSizes: pageSizes)
        camera.fit(documentFrame: frame)
    }

    private func actualSize(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        let frame = layout.pageFrame(for: pages[index], at: index, precedingPageSizes: pageSizes)
        camera.actualSize(centeredOn: frame)
    }

    private func setCurrentPageColor(_ color: PageColor) {
        guard let visiblePage else { return }
        visiblePage.customizeStyle()
        visiblePage.pageColor = color
        visiblePage.updatedAt = .now
        notebook.updatedAt = .now
        try? modelContext.save()
    }

    private func setCurrentPageTemplate(_ template: PageTemplate) {
        guard let visiblePage else { return }
        visiblePage.customizeStyle()
        visiblePage.template = template
        visiblePage.updatedAt = .now
        notebook.updatedAt = .now
        try? modelContext.save()
    }

    private func customizeCurrentPageStyle() {
        guard let visiblePage else { return }
        visiblePage.customizeStyle()
        visiblePage.updatedAt = .now
        try? modelContext.save()
    }

    private func useNotebookStyleForCurrentPage() {
        guard let visiblePage else { return }
        visiblePage.useNotebookStyle()
        visiblePage.updatedAt = .now
        try? modelContext.save()
    }

#else
    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: layout.pageGap) {
                ForEach(pages) { page in
                    EditorView(page: page, showsToolbar: visiblePage?.id == page.id)
                        .frame(width: page.pageSize.dimensions.width, height: page.pageSize.dimensions.height)
                        .frame(maxWidth: .infinity)
                        .id(page.id)
                }
            }
            .scrollTargetLayout()
            .frame(maxWidth: .infinity)
            .background {
                NotebookEndScrollObserver(
                    isMagnifying: { isMagnifying },
                    interactionRevision: { scrollInteractionRevision }
                ) { [lastPage = pages.last] in
                    guard let lastPage, !lastPage.isDeleted, lastPage.hasDrawingContent,
                          notebook.appendContinuationPage(after: lastPage) != nil else { return }
                    try? modelContext.save()
                }
            }
            .padding(.vertical, layout.pageGap)
        }
        .environment(\.notebookMagnificationChanged) { active in
            guard isMagnifying != active else { return }
            isMagnifying = active
            if active { scrollInteractionRevision += 1 }
        }
        .scrollPosition(id: $scrollPositionID, anchor: .top)
        .scrollBounceBehavior(.always, axes: .vertical)
        .background(Color.black)
        .navigationTitle(notebook.title.isEmpty ? "Untitled Notebook" : notebook.title)
        .toolbar {
            ToolbarItem(placement: .secondaryAction) { pageNavigationMenu }
            ToolbarItem(placement: .secondaryAction) {
                NotebookStyleControl(
                    template: notebook.template,
                    color: notebook.pageColor,
                    onSelectTemplate: setNotebookTemplate,
                    onSelectColor: setNotebookPageColor
                )
            }
            ToolbarItem(placement: .secondaryAction) { exportMenu }
            ToolbarItem(placement: .secondaryAction) {
                Button("Rename Notebook", systemImage: "pencil") { editedTitle = notebook.title; isRenaming = true }
            }
            ToolbarItem(placement: .primaryAction) { Button("Add Page", systemImage: "plus", action: addPage) }
        }
        .alert("Rename Notebook", isPresented: $isRenaming) {
            TextField("Notebook name", text: $editedTitle)
            Button("Cancel", role: .cancel) { }
            Button("Save", action: renameNotebook)
        } message: { Text("Choose a name for this notebook.") }
        .fileExporter(
            isPresented: $showingPDFExporter,
            document: exportDocument,
            contentType: .pdf,
            defaultFilename: exportFilename
        ) { _ in }
    }

    private var pageNavigationMenu: some View {
        Menu {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                Button("Page \(index + 1)") { visiblePageID = page.id }
            }
        } label: { Label("Page \(visiblePageIndex + 1) of \(pages.count)", systemImage: "doc.text") }
    }
#endif

    private var exportMenu: some View {
        Menu {
            Button("Current Page as PDF") {
                guard let visiblePage else { return }
                preparePDFExport(
                    pages: [visiblePage],
                    filename: "\(safeExportName)-Page-\(visiblePageIndex + 1)"
                )
            }
            Button("Entire Notebook as PDF") {
                preparePDFExport(pages: pages, filename: safeExportName)
            }
#if os(macOS)
            Divider()
            Button("Export for web (.json)") {
                do {
                    let request = MacNotebookExportRequest(notebookID: notebook.id)
                    NotificationCenter.default.post(name: .captureMacNotebookExport, object: request)
                    try modelContext.save()
                    webExportDocument = NotebookJSONDocument(data: try NotebookWebExporter.data(for: notebook, snapshots: request.strokes))
                    showingWebExporter = true
                } catch { webExportError = error.localizedDescription }
            }
#endif
        } label: {
            Label("Export PDF", systemImage: "square.and.arrow.up")
        }
        .disabled(pages.isEmpty)
    }

    private func setNotebookTemplate(_ template: PageTemplate) {
        notebook.template = template
        notebook.updatedAt = .now
        try? modelContext.save()
    }

    private func setNotebookPageColor(_ color: PageColor) {
        notebook.pageColor = color
        notebook.updatedAt = .now
        try? modelContext.save()
    }

    private var safeExportName: String {
        let name = notebook.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Notebook" : name
    }

    private func preparePDFExport(pages: [Page], filename: String) {
#if os(iOS)
        let request = NotebookDrawingExportRequest(notebookID: notebook.id)
        NotificationCenter.default.post(name: .flushNotebookDrawings, object: request)
#endif
        let exportPages = pages.map { page in
#if os(iOS)
            PDFExportPage(
                size: page.pageSize.dimensions,
                color: page.effectivePageColor,
                template: page.effectiveTemplate,
                drawing: request.drawings[page.id]
                    ?? page.drawingFileName.flatMap { DrawingStorage.loadDrawing(from: $0) }
                    ?? PKDrawing()
            )
#else
            PDFExportPage(
                size: page.pageSize.dimensions,
                color: page.effectivePageColor,
                template: page.effectiveTemplate,
                strokes: page.drawingFileName.map(MacDrawingStorage.load) ?? []
            )
#endif
        }
        exportDocument = PDFExportDocument(data: PDFExporter.makePDF(pages: exportPages), pageCount: pages.count)
        exportFilename = filename
        showingPDFExporter = true
    }

    private func addPage() {
        let page = Page()
        page.notebook = notebook
        notebook.pages.append(page)
        notebook.updatedAt = .now
        try? modelContext.save()
#if os(iOS)
        visiblePageID = page.id
#endif
    }

    private func deleteCurrentPage() {
        guard pages.count > 1 else { return }
#if os(macOS)
        let index = visiblePageIndex
#else
        let index = visiblePageID.flatMap { id in pages.firstIndex { $0.id == id } } ?? 0
#endif
        guard pages.indices.contains(index) else { return }
        let page = pages[index]
        if let name = page.drawingFileName {
            DrawingStorage.deleteDrawing(named: name)
        }
        modelContext.delete(page)
        notebook.updatedAt = .now
        try? modelContext.save()
#if os(macOS)
        focusPage(min(index, pages.count - 2))
#else
        visiblePageID = pages.indices.contains(min(index, pages.count - 2)) ? pages[min(index, pages.count - 2)].id : nil
#endif
    }

    private func renameNotebook() {
        let text = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        notebook.title = text
        notebook.updatedAt = .now
        try? modelContext.save()
    }
}

#if os(iOS)
private struct NotebookMagnificationHandlerKey: EnvironmentKey {
    static let defaultValue: ((Bool) -> Void)? = nil
}

extension EnvironmentValues {
    var notebookMagnificationChanged: ((Bool) -> Void)? {
        get { self[NotebookMagnificationHandlerKey.self] }
        set { self[NotebookMagnificationHandlerKey.self] = newValue }
    }
}

private struct NotebookEndScrollObserver: UIViewRepresentable {
    let isMagnifying: () -> Bool
    let interactionRevision: () -> Int
    let onReachedBottom: () -> Void

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.isUserInteractionEnabled = false
        view.isMagnifying = isMagnifying
        view.interactionRevision = interactionRevision
        view.onReachedBottom = onReachedBottom
        return view
    }

    func updateUIView(_ uiView: ObserverView, context: Context) {
        uiView.isMagnifying = isMagnifying
        uiView.interactionRevision = interactionRevision
        uiView.onReachedBottom = onReachedBottom
    }

    static func dismantleUIView(_ uiView: ObserverView, coordinator: ()) {
        uiView.detach()
    }

    final class ObserverView: UIView {
        var onReachedBottom: (() -> Void)?
        var interactionRevision: (() -> Int)?
        var isMagnifying: (() -> Bool)?

        private weak var scrollView: UIScrollView?
        private var offsetObservation: NSKeyValueObservation?
        private var isUserScroll = false
        private var allowsDeceleration = false
        private var didRequestPage = false
        private var pendingForwardDrag = false
        private var gestureInteractionRevision = 0
        private var previousOffsetY: CGFloat = 0
        private var previousTranslationY: CGFloat = 0
        private var contentSize: CGSize = .zero
        private var viewportSize: CGSize = .zero
        private var contentInset: UIEdgeInsets = .zero
        private var zoomScale: CGFloat = 1

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            attach()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { detach() } else { attach() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if scrollView == nil { attach() }
        }

        private func attach() {
            guard window != nil else { detach(); return }
            var ancestor = superview
            while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
            let next = ancestor as? UIScrollView
            guard next !== scrollView else { return }
            detach()
            guard let next else { return }
            scrollView = next
            next.panGestureRecognizer.addTarget(self, action: #selector(panChanged(_:)))
            offsetObservation = next.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                self?.checkScroll()
            }
        }

        func detach() {
            offsetObservation?.invalidate()
            offsetObservation = nil
            scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(panChanged(_:)))
            scrollView = nil
            isUserScroll = false
        }

        @objc private func panChanged(_ pan: UIPanGestureRecognizer) {
            guard let scrollView else { return }
            switch pan.state {
            case .began:
                isUserScroll = isMagnifying?() != true
                allowsDeceleration = false
                didRequestPage = false
                pendingForwardDrag = false
                gestureInteractionRevision = interactionRevision?() ?? 0
                previousOffsetY = scrollView.contentOffset.y
                previousTranslationY = pan.translation(in: scrollView).y
                contentSize = scrollView.contentSize
                viewportSize = scrollView.bounds.size
                contentInset = scrollView.adjustedContentInset
                zoomScale = scrollView.zoomScale
            case .changed:
                checkScroll()
            case .ended:
                allowsDeceleration = isUserScroll && pan.velocity(in: scrollView).y < 0
            case .cancelled, .failed:
                isUserScroll = false
                allowsDeceleration = false
            default:
                break
            }
        }

        private func checkScroll() {
            guard let scrollView else { return }
            let pan = scrollView.panGestureRecognizer
            let offsetY = scrollView.contentOffset.y
            let translationY = pan.translation(in: scrollView).y
            let offsetDelta = offsetY - previousOffsetY
            let translationDelta = translationY - previousTranslationY
            defer {
                previousOffsetY = offsetY
                previousTranslationY = translationY
            }

            // A resize, inset adjustment, or zoom is not a continuation gesture.
            guard isMagnifying?() != true, !scrollView.isZooming, !scrollView.isZoomBouncing,
                  interactionRevision?() == gestureInteractionRevision,
                  scrollView.contentSize == contentSize,
                  scrollView.bounds.size == viewportSize,
                  scrollView.adjustedContentInset == contentInset,
                  scrollView.zoomScale == zoomScale else {
                isUserScroll = false
                return
            }
            guard isUserScroll, !didRequestPage else { return }

            if scrollView.isDragging {
                // KVO and pan targets may run in either order for the same input sample.
                if translationDelta != 0 { pendingForwardDrag = translationDelta < 0 }
                guard pan.state == .changed, pendingForwardDrag,
                      pan.velocity(in: scrollView).y < 0, offsetDelta >= 0 else { return }
                if offsetDelta > 0 { pendingForwardDrag = false }
            } else if scrollView.isDecelerating {
                // Once momentum reverses, subsequent spring/bounce motion is ineligible.
                if offsetDelta < 0 { allowsDeceleration = false }
                guard allowsDeceleration, offsetDelta > 0 else { return }
            } else {
                isUserScroll = false
                return
            }

            // The unpadded stack ends at the final paper edge, not the trailing gap.
            let pageBottom = convert(bounds, to: scrollView).maxY
            let viewportBottom = offsetY + scrollView.bounds.height - contentInset.bottom
            guard bounds.height > 0, viewportSize.height > 0,
                  viewportBottom >= pageBottom else { return }
            didRequestPage = true
            onReachedBottom?()
        }
    }
}
#endif

#if os(macOS)
private struct MacEditorToolPalette: View {
    @Binding var selectedTool: MacDrawingTool
    @Binding var settingsTool: MacDrawingTool?
    @Binding var toolSettings: EditorToolSettings
    @State private var lastSelectedShape: MacDrawingTool = .rectangle

    private let primaryTools: [MacDrawingTool] = [.pen, .pencil, .highlighter, .eraser, .lasso, .circle, .line]
    private let shapeTools: [MacDrawingTool] = [.rectangle, .circle, .line, .arrow]

    private var activeShape: MacDrawingTool {
        selectedTool.isShape ? selectedTool : lastSelectedShape
    }

    private var settingsPopoverBinding: Binding<Bool> {
        Binding(
            get: { settingsTool != nil },
            set: { if !$0 { settingsTool = nil } }
        )
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(primaryTools, id: \.self) { tool in
                MacEditorToolButton(
                    tool: tool,
                    isSelected: selectedTool == tool
                ) {
                    select(tool)
                }
                .keyboardShortcut(tool.keyboardShortcut, modifiers: [])
            }

            shapesMenu

            Divider()
                .frame(height: 18)
                .padding(.horizontal, 2)

            Button {
                settingsTool = selectedTool
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .help("\(selectedTool.displayName) Settings")
            .accessibilityLabel("Tool Settings")
        }
        .popover(isPresented: settingsPopoverBinding, arrowEdge: .bottom) {
            ToolSettingsPanel(
                macTool: settingsTool ?? selectedTool,
                toolSettings: $toolSettings
            )
        }
        .onChange(of: selectedTool) { _, tool in
            if tool.isShape {
                lastSelectedShape = tool
            }
        }
    }

    private var shapesMenu: some View {
        Menu {
            Button("Draw \(activeShape.displayName)") {
                select(activeShape)
            }
            .keyboardShortcut("d", modifiers: [])

            Divider()

            ForEach(shapeTools, id: \.self) { shape in
                Button {
                    select(shape)
                } label: {
                    Label(shape.displayName, systemImage: shape.systemImage)
                }
            }
        } label: {
            Image(systemName: "square.on.circle")
                .foregroundStyle(selectedTool.isShape ? Color.accentColor : .primary)
                .frame(width: 30, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selectedTool.isShape ? Color.accentColor.opacity(0.18) : .clear)
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .keyboardShortcut("s", modifiers: [])
        .help("Shapes")
        .accessibilityLabel("Shapes")
    }

    private func select(_ tool: MacDrawingTool) {
        selectedTool = tool
        settingsTool = nil
    }
}

private struct MacEditorToolButton: View {
    let tool: MacDrawingTool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.systemImage)
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .frame(width: 30, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
                }
        }
        .buttonStyle(.plain)
        .help(tool.displayName)
        .accessibilityLabel(tool.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#endif

struct NotebookStyleControl: View {
    let template: PageTemplate
    let color: PageColor
    let onSelectTemplate: (PageTemplate) -> Void
    let onSelectColor: (PageColor) -> Void
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("Notebook Style", systemImage: "paintbrush")
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            PageStyleEditor(
                title: "Notebook Default Style",
                description: "Applies to new pages and pages using the notebook default. Custom pages keep their style.",
                template: template,
                color: color,
                onSelectTemplate: onSelectTemplate,
                onSelectColor: onSelectColor
            )
            .padding(14)
        }
    }
}

struct PageStyleControl: View {
    let inheritsNotebookStyle: Bool
    let template: PageTemplate
    let color: PageColor
    let isEnabled: Bool
    let onCustomize: () -> Void
    let onUseNotebookDefault: () -> Void
    let onSelectTemplate: (PageTemplate) -> Void
    let onSelectColor: (PageColor) -> Void
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label(
                inheritsNotebookStyle ? "Page Uses Notebook Style" : "Custom Page Style",
                systemImage: inheritsNotebookStyle ? "link" : "slider.horizontal.3"
            )
        }
        .disabled(!isEnabled)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                if inheritsNotebookStyle {
                    Label("Using Notebook Default", systemImage: "link")
                        .font(.headline)
                    PageStyleSummary(template: template, color: color)
                    Button("Customize This Page", action: onCustomize)
                        .buttonStyle(.borderedProminent)
                } else {
                    PageStyleEditor(
                        title: "Custom Page Style",
                        description: "This page is independent from notebook defaults.",
                        template: template,
                        color: color,
                        onSelectTemplate: onSelectTemplate,
                        onSelectColor: onSelectColor
                    )
                    Button("Use Notebook Default", action: onUseNotebookDefault)
                        .buttonStyle(.bordered)
                }
            }
            .padding(14)
            .frame(width: 310)
        }
    }
}

private struct PageStyleEditor: View {
    let title: String
    let description: String
    let template: PageTemplate
    let color: PageColor
    let onSelectTemplate: (PageTemplate) -> Void
    let onSelectColor: (PageColor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Template")
                .font(.caption.weight(.semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(PageTemplate.allCases) { option in
                    Button {
                        onSelectTemplate(option)
                    } label: {
                        VStack(spacing: 5) {
                            PaperBackground(template: option, color: color, size: CGSize(width: 280, height: 160))
                                .frame(width: 280, height: 160)
                                .scaleEffect(0.4)
                                .frame(width: 112, height: 64)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .allowsHitTesting(false)
                            Text(option.displayName)
                                .font(.caption)
                        }
                        .padding(6)
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(
                                    option == template ? Color.accentColor : Color.secondary.opacity(0.4),
                                    lineWidth: option == template ? 2 : 0.75
                                )
                        }
                        .overlay(alignment: .topTrailing) {
                            if option == template {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.white, Color.accentColor)
                                    .padding(3)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(option.displayName)
                    .accessibilityLabel(option.displayName)
                    .accessibilityAddTraits(option == template ? .isSelected : [])
                }
            }
            Text("Page Color")
                .font(.caption.weight(.semibold))
            PageColorSwatches(selectedColor: color, onSelect: onSelectColor)
        }
        .frame(width: 280)
    }
}

private struct PageStyleSummary: View {
    let template: PageTemplate
    let color: PageColor

    var body: some View {
        HStack(spacing: 8) {
            Label(template.displayName, systemImage: template.systemImage)
            Circle()
                .fill(color.swatchColor)
                .frame(width: 16, height: 16)
                .overlay { Circle().stroke(.secondary, lineWidth: 0.75) }
            Text(color.displayName)
        }
        .font(.callout)
    }
}

private struct PageColorSwatches: View {
    let selectedColor: PageColor
    let onSelect: (PageColor) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(PageColor.allCases) { color in
                Button {
                    onSelect(color)
                } label: {
                    VStack(spacing: 5) {
                        Circle()
                            .fill(color.swatchColor)
                            .frame(width: 28, height: 28)
                            .overlay {
                                Circle().stroke(
                                    color == selectedColor ? Color.accentColor : Color.secondary.opacity(0.5),
                                    lineWidth: color == selectedColor ? 3 : 1
                                )
                            }
                        Text(color.displayName)
                            .font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.displayName)
                .accessibilityAddTraits(color == selectedColor ? .isSelected : [])
            }
        }
    }
}

#if os(macOS)
struct InkColorSwatches: View {
    @Binding var selectedColor: Color

    private let colors: [(name: String, color: Color)] = [
        ("Black", .black),
        ("Dark Gray", Color(white: 0.3)),
        ("Gray", .gray),
        ("Red", .red),
        ("Orange", .orange),
        ("Yellow", .yellow),
        ("Green", .green),
        ("Blue", .blue),
        ("Purple", .purple),
        ("Pink", .pink),
        ("Brown", .brown),
        ("White", .white)
    ]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(colors, id: \.name) { option in
                let isSelected = matches(option.color)
                Button {
                    selectedColor = option.color
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: 15, height: 15)
                        .overlay {
                            Circle().stroke(
                                isSelected ? Color.accentColor : Color.secondary.opacity(0.55),
                                lineWidth: isSelected ? 2.5 : 0.75
                            )
                        }
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(option.name == "White" || option.name == "Yellow" ? .black : .white)
                                    .shadow(color: .black.opacity(0.4), radius: 1)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(option.name)
                .accessibilityLabel(option.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func matches(_ color: Color) -> Bool {
        guard let selected = NSColor(selectedColor).usingColorSpace(.sRGB),
              let swatch = NSColor(color).usingColorSpace(.sRGB) else { return false }
        return abs(selected.redComponent - swatch.redComponent) < 0.01
            && abs(selected.greenComponent - swatch.greenComponent) < 0.01
            && abs(selected.blueComponent - swatch.blueComponent) < 0.01
            && abs(selected.alphaComponent - swatch.alphaComponent) < 0.01
    }
}

private struct InkColorPalette: View {
    let selectedTool: MacDrawingTool
    @Binding var toolSettings: EditorToolSettings

    private var supportsInk: Bool {
        selectedTool == .pen || selectedTool == .pencil || selectedTool == .highlighter || selectedTool.isShape
    }

    private var selectedColor: Color {
        switch selectedTool {
        case .pen, .rectangle, .circle, .line, .arrow: return toolSettings.pen.color
        case .pencil: return toolSettings.pencil.color
        case .highlighter: return toolSettings.highlighter.color
        default: return .clear
        }
    }

    var body: some View {
        InkColorSwatches(selectedColor: Binding(get: { selectedColor }, set: select))
            .disabled(!supportsInk)
            .opacity(supportsInk ? 1 : 0.45)
    }

    private func select(_ color: Color) {
        switch selectedTool {
        case .pen, .rectangle, .circle, .line, .arrow: toolSettings.pen.color = color
        case .pencil: toolSettings.pencil.color = color
        case .highlighter: toolSettings.highlighter.color = color
        default: break
        }
    }
}

private struct FloatingWritingToolbar: View {
    @Binding var selectedTool: MacDrawingTool
    @Binding var toolSettings: EditorToolSettings
    @Binding var settingsTool: MacDrawingTool?
    let canDeleteSelection: Bool
    let onDeleteSelection: () -> Void
    let viewportSize: CGSize

    @State private var savedPosition: CGPoint?
    @State private var paletteSize: CGSize = .zero
    @GestureState private var dragTranslation: CGSize = .zero

    private let tools: [MacDrawingTool] = [.pen, .pencil, .highlighter, .eraser, .lasso, .circle, .line]
    private let margin: CGFloat = 12

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 28)
                    .contentShape(Rectangle())
                    .gesture(moveGesture)
                    .help("Move Writing Toolbar")
                    .accessibilityLabel("Move Writing Toolbar")

                Divider()
                    .frame(height: 18)

                ForEach(tools, id: \.self) { tool in
                    MacEditorToolButton(
                        tool: tool,
                        isSelected: selectedTool == tool
                    ) {
                        settingsTool = nil
                        selectedTool = tool
                    }
                }

                Divider()
                    .frame(height: 18)

                Button(action: onDeleteSelection) {
                    Image(systemName: "trash")
                        .frame(width: 30, height: 26)
                }
                .buttonStyle(.plain)
                .disabled(!canDeleteSelection)
                .help("Delete Selection (Delete)")
                .accessibilityLabel("Delete Selection")
            }
            InkColorPalette(
                selectedTool: selectedTool,
                toolSettings: $toolSettings
            )
        }
        .padding(6)
        .fixedSize()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 7, y: 3)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            paletteSize = newSize
        }
        // Offset the intrinsic-sized palette instead of creating a viewport-sized hit region.
        .offset(x: displayPosition.x - paletteSize.width / 2, y: displayPosition.y - paletteSize.height / 2)
    }

    private var settledPosition: CGPoint {
        if let savedPosition {
            return clamped(savedPosition)
        }
        return clamped(CGPoint(x: viewportSize.width / 2, y: paletteSize.height / 2 + margin))
    }

    private var displayPosition: CGPoint {
        clamped(CGPoint(
            x: settledPosition.x + dragTranslation.width,
            y: settledPosition.y + dragTranslation.height
        ))
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("notebookViewport"))
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let finalPosition = clamped(CGPoint(
                    x: settledPosition.x + value.translation.width,
                    y: settledPosition.y + value.translation.height
                ))
                savedPosition = finalPosition
            }
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: clampedAxis(point.x, content: paletteSize.width, viewport: viewportSize.width),
            y: clampedAxis(point.y, content: paletteSize.height, viewport: viewportSize.height)
        )
    }

    private func clampedAxis(_ value: CGFloat, content: CGFloat, viewport: CGFloat) -> CGFloat {
        guard viewport > content + margin * 2 else { return viewport / 2 }
        return min(max(value, content / 2 + margin), viewport - content / 2 - margin)
    }
}

private extension MacDrawingTool {
    var isShape: Bool {
        switch self {
        case .rectangle, .circle, .line, .arrow: return true
        default: return false
        }
    }

    var displayName: String {
        self == .line ? "Straight Line" : rawValue.capitalized
    }

    var systemImage: String {
        switch self {
        case .pen: return "pencil"
        case .pencil: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        case .lasso: return "lasso"
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        }
    }

    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .pen: return "p"
        case .pencil: return "2"
        case .highlighter: return "h"
        case .eraser: return "e"
        case .lasso: return "v"
        case .circle: return "c"
        case .line: return "l"
        case .rectangle, .arrow: return "d"
        }
    }
}

#endif

private extension PageColor {
    var displayName: String { rawValue.capitalized }

    var swatchColor: Color {
        switch self {
        case .white: return .white
        case .cream: return Color(red: 0.98, green: 0.96, blue: 0.88)
        case .dark: return Color(red: 0.12, green: 0.12, blue: 0.13)
        }
    }
}

private extension PageTemplate {
    var displayName: String {
        switch self {
        case .blank: return "Blank"
        case .ruled: return "Ruled Lines"
        case .grid: return "Square Grid"
        case .dots: return "Dot Grid"
        }
    }

    var systemImage: String {
        switch self {
        case .blank: return "doc"
        case .ruled: return "line.3.horizontal"
        case .grid: return "square.grid.3x3"
        case .dots: return "circle.grid.3x3"
        }
    }
}

#Preview {
    NavigationStack { NotebookView(notebook: Notebook(title: "Preview")) }
}
