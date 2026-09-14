import SwiftUI
import SwiftData
import PencilKit
import UniformTypeIdentifiers
import PhotosUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct EditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.notebookSidebarVisible) private var notebookSidebarVisible
    let page: Page
    let showsToolbar: Bool
    @State private var showingTextEditor = false
    @State private var selectedPhoto: PhotosPickerItem?

#if os(macOS)
    @StateObject private var camera: EditorCamera
#endif

    init(page: Page, showsToolbar: Bool = true) {
        self.page = page
        self.showsToolbar = showsToolbar
#if os(macOS)
        _camera = StateObject(wrappedValue: EditorCamera(pageSize: page.pageSize.dimensions))
#endif
    }

    private var pageSize: CGSize { page.pageSize.dimensions }

    @ViewBuilder
    private var textEditorOverlay: some View {
        if showingTextEditor {
            TextEditor(text: Binding(
                get: { page.text },
                set: { page.text = $0 }
            ))
            .padding(12)
            .frame(maxWidth: 760, maxHeight: 180)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                Button {
                    showingTextEditor = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(24)
        }
    }

    @ViewBuilder
    private var imageOverlay: some View {
        if let data = page.imageData {
#if os(iOS)
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 360, maxHeight: 260)
                    .shadow(radius: 5)
            }
#else
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 360, maxHeight: 260)
                    .shadow(radius: 5)
            }
#endif
        }
    }

    @State private var editorViewportSize: CGSize = .zero
    @State private var isClampingViewport = false

#if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.notebookMagnificationChanged) private var notebookMagnificationChanged
    @State private var drawing = PKDrawing()
    @State private var drawingLoaded = false
    @State private var drawingLoadFailed = false
    @State private var savedDrawing = PKDrawing()
    @State private var saveTask: Task<Void, Never>?
    @State private var showingExporter = false
    @State private var exportDocument = PDFExportDocument()
    @State private var viewport = ViewportState()
    @State private var gestureStartScale: CGFloat = 1
    @GestureState private var isMagnifying = false
    @State private var didInitialFit = false
    @State private var activeDrawingTool: EditorTool = .pen
    @State private var pointerHover: CGPoint?
    @State private var isSelecting = false
    @State private var selectionStart: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let viewportSize = geometry.size
            ZStack(alignment: .topLeading) {
                pageContent
                    .frame(width: pageSize.width, height: pageSize.height)
                    .scaleEffect(viewport.scale, anchor: .topLeading)
                    .offset(x: viewport.offset.width, y: viewport.offset.height)
            }
            .frame(width: viewportSize.width, height: viewportSize.height)
            .clipped()
            .background(workspaceBackground)
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($isMagnifying) { _, state, _ in state = true }
                    .onChanged { value in
                        notebookMagnificationChanged?(true)
                        let anchor = CGPoint(
                            x: value.startAnchor.x * viewportSize.width,
                            y: value.startAnchor.y * viewportSize.height
                        )
                        viewport.setScale(gestureStartScale * value.magnification, around: anchor)
                    }
                    .onEnded { _ in
                        notebookMagnificationChanged?(false)
                        gestureStartScale = viewport.scale
                    }
            )
            .onAppear {
                loadDrawing()
                performInitialFit(viewportSize: viewportSize)
            }
            .onChange(of: viewportSize) { oldSize, newSize in
                handleViewportSizeChange(oldSize: oldSize, newSize: newSize)
            }
        }
        .onChange(of: isMagnifying) { _, active in
            if !active { notebookMagnificationChanged?(false) }
        }
        .overlay(alignment: .topTrailing) { imageOverlay.padding(24) }
        .navigationTitle(page.notebook?.title ?? "Page")
        .toolbar { if showsToolbar { editorToolbar } }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .pdf,
            defaultFilename: "Note-\(page.id.uuidString.prefix(8))"
        ) { _ in }
        .onDisappear {
            if isMagnifying { notebookMagnificationChanged?(false) }
            flushDrawing()
        }
        .onChange(of: drawing) {
            if drawingLoaded, !page.isDeleted {
                page.hasDrawingContent = !drawing.strokes.isEmpty
            }
            scheduleSave()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { flushDrawing() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .flushNotebookDrawings)) { notification in
            guard let request = notification.object as? NotebookDrawingExportRequest,
                  request.notebookID == page.notebook?.id, drawingLoaded else { return }
            flushDrawing()
            request.drawings[page.id] = drawing
        }
        .alert("Drawing Could Not Be Loaded", isPresented: $drawingLoadFailed) {
            Button("Retry", action: loadDrawing)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The saved drawing is unavailable. Editing is disabled to avoid overwriting it.")
        }
        .onChange(of: page.text) {
            page.updatedAt = .now
            try? modelContext.save()
        }
        .onChange(of: selectedPhoto) {
            loadSelectedPhoto()
        }
        .onChange(of: viewport) {
            applyPanClampIfNeeded()
        }
    }

#else
    @Environment(\.undoManager) private var undoManager
    @State private var strokes: [MacStroke] = []
    @State private var savedStrokes: [MacStroke] = []
    @State private var drawingLoaded = false
    @State private var showingExporter = false
    @State private var exportDocument = PDFExportDocument()
    @State private var selectedTool: MacDrawingTool = .pen
    @State private var showingCursorDebug = false
    @State private var debugCursorTool: EditorTool?
    @State private var debugBusy = false
    @State private var debugLocked = false
    @State private var debugOutside = false
    @State private var toolSettings = EditorToolSettings()
    @State private var selection = EditorSelection()
    @State private var settingsTool: MacDrawingTool?
    @State private var isSelecting = false
    @State private var selectionStart: CGPoint?

    private var fileName: String {
        if let existing = page.drawingFileName { return existing }
        let newName = "\(page.id.uuidString).drawing.json"
        page.drawingFileName = newName
        try? modelContext.save()
        return newName
    }

    @ViewBuilder
    private var cursorDebugOverlay: some View {
        EmptyView()
    }

    var body: some View {
        GeometryReader { geometry in
            canvasWithViewport(viewportSize: geometry.size)
        }
        .background(workspaceBackground.ignoresSafeArea())
        .overlay(alignment: .topTrailing) { imageOverlay.padding(24) }
        .navigationTitle("Page")
        .toolbar { editorToolbar }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .pdf,
            defaultFilename: "Note-\(page.id.uuidString.prefix(8))"
        ) { _ in }
        .onChange(of: page.text) {
            page.updatedAt = .now
            try? modelContext.save()
        }
        .onChange(of: strokes) {
            page.hasDrawingContent = !strokes.isEmpty
            try? modelContext.save()
        }
        .onChange(of: selectedPhoto) {
            loadSelectedPhoto()
        }
        .onChange(of: selectedTool) {
            page.updatedAt = .now
            try? modelContext.save()
        }
        .onAppear(perform: loadDrawing)
        .onDisappear {
            if drawingLoaded, strokes != savedStrokes {
                MacDrawingStorage.save(strokes, to: fileName)
            }
        }
    }

    private func canvasWithViewport(viewportSize: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            MacCanvasView(
                strokes: $strokes,
                selectedTool: $selectedTool,
                camera: camera,
                template: Binding(
                    get: { page.effectiveTemplate },
                    set: { page.customizeStyle(); page.template = $0 }
                ),
                pageColor: Binding(
                    get: { page.effectivePageColor },
                    set: { page.customizeStyle(); page.pageColor = $0 }
                ),
                toolSettings: $toolSettings,
                selection: $selection,
                debugTool: debugCursorTool,
                debugBusy: debugBusy,
                debugLocked: debugLocked,
                debugOutside: debugOutside
            )
            cursorDebugOverlay
            if isSelecting {
                SelectionOverlay(selection: selection, viewportScale: camera.viewport.scale)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let location = value.location
                                selection.bounds = CGRect(
                                    x: min(selectionStart!.x, location.x),
                                    y: min(selectionStart!.y, location.y),
                                    width: abs(location.x - selectionStart!.x),
                                    height: abs(location.y - selectionStart!.y)
                                )
                            }
                            .onEnded { _ in
                                isSelecting = false
                                // Find strokes within selection bounds
                                selection.strokeIDs = Set(strokes.filter { stroke in
                                        selection.bounds.contains(stroke.points.first?.cgPoint ?? .zero) ||
                                        selection.bounds.intersects(CGRect(
                                            x: stroke.points.first?.cgPoint.x ?? 0,
                                            y: stroke.points.first?.cgPoint.y ?? 0,
                                            width: 1,
                                            height: 1
                                        ))
                                    }.map { $0.id })
                            }
                    )
            }
        }
        .frame(width: viewportSize.width, height: viewportSize.height)
        .clipped()
        .background(workspaceBackground)
        .onAppear {
            loadDrawing()
            camera.setViewportSize(viewportSize)
        }
        .onChange(of: viewportSize) { _, newSize in
            camera.setViewportSize(newSize)
        }
    }
#endif

    private var workspaceBackground: some View {
        Color(red: 0.11, green: 0.11, blue: 0.12)
            .ignoresSafeArea()
    }

#if os(iOS)
    private func applyPanClampIfNeeded() {
        guard !isClampingViewport else { return }
        let clamped = viewport.clampedOffset(pageSize: pageSize, viewportSize: viewportForZoom)
        guard clamped != viewport.offset else { return }
        isClampingViewport = true
        viewport.offset = clamped
        isClampingViewport = false
    }

    private func performInitialFit(viewportSize: CGSize) {
        guard !didInitialFit, viewportSize.width > 0, viewportSize.height > 0 else { return }
        didInitialFit = true
        editorViewportSize = viewportSize
        viewport.fitPage(pageSize: pageSize, in: viewportSize)
    }

    private func handleViewportSizeChange(oldSize: CGSize, newSize: CGSize) {
        guard newSize.width > 0, newSize.height > 0 else { return }
        editorViewportSize = newSize
        if !didInitialFit {
            performInitialFit(viewportSize: newSize)
        } else {
            viewport.center(on: pageSize, in: newSize)
        }
    }
#endif

    @ViewBuilder
    private var pageContent: some View {
        ZStack {
            PaperBackground(template: page.effectiveTemplate, color: page.effectivePageColor, size: pageSize)
            canvasLayer
            #if os(macOS)
            if selection.isActive {
                SelectionOverlay(selection: selection, viewportScale: camera.viewport.scale)
            }
            #endif
        }
        .clipShape(Rectangle())
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
    }

    @ViewBuilder
    private var canvasLayer: some View {
#if os(iOS)
        PencilCanvasView(
            drawing: Binding(
                get: { drawing },
                set: {
                    drawing = $0
                    // Native scrolling can arrive before SwiftUI's onChange.
                    if drawingLoaded, !page.isDeleted {
                        page.hasDrawingContent = !$0.strokes.isEmpty
                    }
                }
            ),
            onToolChanged: { activeDrawingTool = $0 },
            onPointerHover: { pointerHover = $0 },
            onDrawingInteractionEnded: flushDrawing
        )
        .allowsHitTesting(drawingLoaded)
        .overlay { PointerToolIndicator(tool: activeDrawingTool, location: pointerHover) }
#else
        MacCanvasView(
            strokes: $strokes,
            selectedTool: $selectedTool,
            camera: camera,
            template: Binding(
                get: { page.effectiveTemplate },
                set: { page.customizeStyle(); page.template = $0 }
            ),
            pageColor: Binding(
                get: { page.effectivePageColor },
                set: { page.customizeStyle(); page.pageColor = $0 }
            ),
            toolSettings: $toolSettings,
            selection: $selection,
            debugTool: debugCursorTool,
            debugBusy: debugBusy,
            debugLocked: debugLocked,
            debugOutside: debugOutside
        )
#endif
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
#if os(iOS)
        ToolbarItem(placement: .secondaryAction) {
            pageStyleControl
        }
        ToolbarItem(placement: .secondaryAction) {
            Button {
                isSelecting = true
                let start = pointerHover ?? CGPoint(x: editorViewportSize.width / 2, y: editorViewportSize.height / 2)
                selectionStart = start
            } label: {
                Label("Lasso", systemImage: "lasso.and.magnifyingglass")
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Image", systemImage: "photo")
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Button {
                showingTextEditor.toggle()
            } label: {
                Label("Text", systemImage: "text.cursor")
            }
        }
        zoomControls
        if page.notebook == nil {
            ToolbarItem(placement: .secondaryAction) {
                Button("Export Current Page as PDF", systemImage: "square.and.arrow.up", action: exportCurrentPage)
                    .disabled(!drawingLoaded)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                drawing = PKDrawing()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(!drawingLoaded)
        }
#else
        ToolbarItemGroup(placement: .secondaryAction) {
            drawingToolButtons
        }
        ToolbarItem(placement: .secondaryAction) {
            pageStyleControl
        }
        ToolbarItem(placement: .secondaryAction) {
            Button {
                isSelecting = true
                selectionStart = CGPoint(x: 200, y: 200)
            } label: {
                Label("Lasso", systemImage: "lasso.and.magnifyingglass")
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Image", systemImage: "photo")
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Button {
                showingTextEditor.toggle()
            } label: {
                Label("Text", systemImage: "text.cursor")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Export Current Page as PDF") {
                    exportCurrentPage()
                }
            } label: {
                Label("Export", systemImage: "doc.on.doc")
            }
        }
        ToolbarItemGroup(placement: .secondaryAction) {
            Button {
                undoManager?.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)

            Button {
                undoManager?.redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        zoomControls
        ToolbarItem(placement: .primaryAction) {
            Button {
                if let canvas = NSApp.keyWindow?.firstResponder as? MacCanvasNSView {
                    selection = EditorSelection()
                    canvas.replaceStrokes([])
                } else {
                    selection = EditorSelection()
                    strokes.removeAll()
                    MacDrawingStorage.save(strokes, to: fileName)
                }
            } label: {
                Label("Clear Page", systemImage: "trash")
            }
        }
#endif
    }

    private var pageStyleControl: some View {
        PageStyleControl(
            inheritsNotebookStyle: page.inheritsNotebookStyle,
            template: page.effectiveTemplate,
            color: page.effectivePageColor,
            isEnabled: true,
            onCustomize: { page.customizeStyle(); savePageStyle() },
            onUseNotebookDefault: { page.useNotebookStyle(); savePageStyle() },
            onSelectTemplate: { page.customizeStyle(); page.template = $0; savePageStyle() },
            onSelectColor: { page.customizeStyle(); page.pageColor = $0; savePageStyle() }
        )
    }

    private func savePageStyle() {
        page.updatedAt = .now
        page.notebook?.updatedAt = .now
        try? modelContext.save()
    }

#if os(macOS)
    @ViewBuilder
    private var drawingToolButtons: some View {
        HStack(spacing: 2) {
            ForEach(MacDrawingTool.allCases, id: \.self) { tool in
                Button {
                    toggleTool(tool)
                } label: {
                    Image(systemName: icon(for: tool))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(selectedTool == tool ? Color.accentColor : .primary)
                }
                .buttonStyle(.plain)
                .help(tool == .line ? "Straight Line" : tool.rawValue.capitalized)
                .keyboardShortcut(shortcut(for: tool), modifiers: [])
            }
        }
        .popover(isPresented: settingsPopoverBinding) {
            ToolSettingsPanel(macTool: settingsTool ?? selectedTool, toolSettings: $toolSettings)
        }
    }

    private func toggleTool(_ tool: MacDrawingTool) {
        if selectedTool == tool {
            settingsTool = (settingsTool == tool) ? nil : tool
        } else {
            settingsTool = nil
            selectedTool = tool
        }
    }

    private var settingsPopoverBinding: Binding<Bool> {
        Binding(
            get: { settingsTool != nil },
            set: { if !$0 { settingsTool = nil } }
        )
    }

    private func icon(for tool: MacDrawingTool) -> String {
        switch tool {
        case .pen: return "pencil"
        case .pencil: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .lasso: return "lasso"
        case .eraser: return "eraser"
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        }
    }

    private func shortcut(for tool: MacDrawingTool) -> KeyEquivalent {
        switch tool {
        case .pen: return "p"
        case .pencil: return "2"
        case .highlighter: return "h"
        case .lasso: return "v"
        case .eraser: return "e"
        case .circle: return "c"
        case .line: return "l"
        case .rectangle, .arrow: return "d"
        }
    }
#endif

    private var zoomControls: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                zoomOut()
            } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            .keyboardShortcut("-", modifiers: .command)

            Button {
                fitPage()
            } label: {
                Label("Fit Page", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .keyboardShortcut("9", modifiers: .command)

            Button {
                actualSize()
            } label: {
                Label("Actual Size", systemImage: "1.magnifyingglass")
            }
            .keyboardShortcut("0", modifiers: .command)

            Button {
                zoomIn()
            } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            .keyboardShortcut("+", modifiers: .command)
        }
    }

    private func zoomIn() {
#if os(macOS)
        camera.zoomIn()
#else
        viewport.zoomIn(in: viewportForZoom)
#endif
    }

    private func zoomOut() {
#if os(macOS)
        camera.zoomOut()
#else
        viewport.zoomOut(in: viewportForZoom)
#endif
    }

    private func fitPage() {
#if os(macOS)
        camera.fitPage()
#else
        viewport.fitPage(pageSize: pageSize, in: viewportForZoom)
#endif
    }

    private func actualSize() {
#if os(macOS)
        camera.actualSize()
#else
        viewport.actualSize(pageSize: pageSize, in: viewportForZoom)
#endif
    }

    private var viewportForZoom: CGSize {
        editorViewportSize.width > 0 ? editorViewportSize : CGSize(width: 800, height: 600)
    }

    private func loadDrawing() {
#if os(iOS)
        guard !drawingLoaded else { return }
        if let name = page.drawingFileName {
            guard let loaded = DrawingStorage.loadDrawing(from: name) else {
                drawingLoadFailed = true
                return
            }
            drawing = loaded
        }
        page.hasDrawingContent = !drawing.strokes.isEmpty
        savedDrawing = drawing
        drawingLoaded = true
#else
        guard !drawingLoaded else { return }
        if let name = page.drawingFileName {
            strokes = MacDrawingStorage.load(from: name)
        }
        savedStrokes = strokes
        drawingLoaded = true
#endif
    }

    private func scheduleSave() {
#if os(iOS)
        saveTask?.cancel()
        saveTask = nil
        guard drawingLoaded, drawing != savedDrawing else { return }
        saveTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            saveTask = nil
            flushDrawing()
        }
#endif
    }

#if os(iOS)
    private func flushDrawing() {
        saveTask?.cancel()
        saveTask = nil
        guard drawingLoaded, drawing != savedDrawing, !page.isDeleted else { return }
        let name = page.drawingFileName ?? "\(page.id.uuidString).pkdrawing"
        guard DrawingStorage.saveDrawing(drawing, to: name) else { return }
        page.drawingFileName = name
        page.hasDrawingContent = !drawing.strokes.isEmpty
        page.updatedAt = .now
        page.notebook?.updatedAt = .now
        do {
            try modelContext.save()
            savedDrawing = drawing
        } catch {
            // Leave the drawing dirty so the next flush can retry the model save.
        }
    }
#endif
    
    private func exportCurrentPage() {
#if os(iOS)
        loadDrawing()
        guard drawingLoaded else { return }
        flushDrawing()
        let pdfData = PDFExporter.makePDF(
            from: drawing,
            pageSize: pageSize,
            color: page.effectivePageColor,
            template: page.effectiveTemplate
        )
        showingExporter = true
        exportDocument.data = pdfData
#elseif os(macOS)
        let pdfData = PDFExporter.makePDF(pages: [PDFExportPage(
            size: pageSize,
            color: page.effectivePageColor,
            template: page.effectiveTemplate,
            strokes: strokes
        )])
        showingExporter = true
        exportDocument.data = pdfData
#endif
    }
    
    @State private var sharingService: Any?
    @State private var showingShareSheet = false

    private func loadSelectedPhoto() {
        guard let selectedPhoto else { return }
        Task {
            guard let data = try? await selectedPhoto.loadTransferable(type: Data.self) else { return }
            page.imageData = data
            page.updatedAt = .now
            try? modelContext.save()
            self.selectedPhoto = nil
        }
    }
}

struct PaperBackground: View {
    let template: PageTemplate
    let color: PageColor
    let size: CGSize

    var body: some View {
        Canvas { context, _ in
            guard template != .blank else { return }
            var path = Path()
            switch template {
            case .ruled:
                stride(from: CGFloat(36), through: size.height, by: CGFloat(32)).forEach { y in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
            case .grid:
                stride(from: CGFloat(0), through: size.width, by: CGFloat(32)).forEach { x in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                stride(from: CGFloat(0), through: size.height, by: CGFloat(32)).forEach { y in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
            case .dots:
                stride(from: CGFloat(16), through: size.width, by: CGFloat(24)).forEach { x in
                    stride(from: CGFloat(16), through: size.height, by: CGFloat(24)).forEach { y in
                        path.addEllipse(in: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5))
                    }
                }
            case .blank:
                break
            }
            let templateColor = color == .dark
                ? Color(red: 0.45, green: 0.65, blue: 1).opacity(0.32)
                : Color.blue.opacity(0.16)
            if template == .dots {
                context.fill(path, with: .color(templateColor))
            } else {
                context.stroke(path, with: .color(templateColor), lineWidth: 0.7)
            }
        }
        .background(pageColor)
    }

    private var pageColor: Color {
        switch color {
        case .white: return .white
        case .cream: return Color(red: 0.98, green: 0.96, blue: 0.88)
        case .dark: return Color(red: 0.12, green: 0.12, blue: 0.13)
        }
    }
}

#if os(iOS)
private struct PointerToolIndicator: View {
    let tool: EditorTool
    let location: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            if let location, geometry.frame(in: .local).contains(location) {
                HStack(spacing: 5) {
                    Image(systemName: tool.systemImage)
                    Text(tool.displayName)
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 2, y: 1)
                .position(x: location.x + 16, y: location.y + 18)
            }
        }
        .allowsHitTesting(false)
    }
}
#endif

#if os(macOS)
private struct CursorDebugPanel: View {
    let snapshot: CursorDebugSnapshot?
    let activeTool: EditorTool
    let viewport: ViewportState
    let selectedDebugTool: EditorTool?
    @Binding var busy: Bool
    @Binding var locked: Bool
    @Binding var outside: Bool
    let onSelectDebugTool: (EditorTool?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Cursor Debug", systemImage: "cursorarrow")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                row("Active Tool", value: activeTool.displayName)
                row("Effective Tool", value: snapshot?.effectiveTool.displayName ?? "—")
                row("Cursor", value: snapshot?.cursor.debugName ?? "—")
                row("Interaction", value: snapshot?.interaction.debugName ?? "—")
                row("Zoom", value: String(format: "%.2fx", viewport.scale))
                row(
                    "Page Point",
                    value: snapshot?.pagePoint.map {
                        String(format: "X: %.1f  Y: %.1f", $0.x, $0.y)
                    } ?? "—"
                )
                row(
                    "Viewport",
                    value: String(
                        format: "Scale: %.2f  Offset: %.1f, %.1f",
                        viewport.scale, viewport.offset.width, viewport.offset.height
                    )
                )
            }
            .font(.system(.caption, design: .monospaced))

            HStack(spacing: 8) {
                Toggle("Busy", isOn: $busy)
                Toggle("Locked", isOn: $locked)
                Toggle("Outside", isOn: $outside)
            }
            .font(.caption)
            .toggleStyle(.checkbox)

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button {
                        onSelectDebugTool(nil)
                    } label: {
                        Text("⟲").font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help("Reset debug tool override")
                    ForEach(EditorTool.allKnownTools, id: \.self) { tool in
                        Button {
                            onSelectDebugTool(tool)
                        } label: {
                            Label(tool.displayName, systemImage: tool.systemImage)
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(selectedDebugTool == tool ? Color.accentColor : .primary)
                    }
                }
            }
            .font(.caption)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 8, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(16)
    }

    private func row(_ label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(.primary)
        }
    }
}

private struct SelectionOverlay: View {
    let selection: EditorSelection
    let viewportScale: CGFloat

    var body: some View {
        ZStack {
            Rectangle()
                .stroke(
                    Color.accentColor.opacity(0.8),
                    style: StrokeStyle(lineWidth: 1.5 / max(viewportScale, 0.05), dash: [6 / max(viewportScale, 0.05), 4 / max(viewportScale, 0.05)])
                )
                .frame(width: selection.bounds.width, height: selection.bounds.height)
                .position(x: selection.bounds.midX, y: selection.bounds.midY)

            let handles = SelectionGeometry.handles(bounds: selection.bounds, scale: viewportScale)
            ForEach(Array(handles.keys), id: \.self) { direction in
                let rect = handles[direction]!
                RoundedRectangle(cornerRadius: 2 / max(viewportScale, 0.05))
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2 / max(viewportScale, 0.05))
                            .stroke(Color.accentColor, lineWidth: 1.5 / max(viewportScale, 0.05))
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }

            let rotateRect = SelectionGeometry.rotateHandle(bounds: selection.bounds, scale: viewportScale)
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 1.5 / max(viewportScale, 0.05), height: max(rotateRect.midY - selection.bounds.minY, 1))
                .position(x: selection.bounds.midX, y: (selection.bounds.minY + rotateRect.midY) / 2)
            Circle()
                .fill(Color.accentColor)
                .frame(width: rotateRect.width, height: rotateRect.height)
                .position(x: rotateRect.midX, y: rotateRect.midY)
        }
        .allowsHitTesting(false)
    }
}

struct ToolSettingsPanel: View {
    let macTool: MacDrawingTool
    @Binding var toolSettings: EditorToolSettings

    var body: some View {
        switch macTool {
        case .pen, .rectangle, .circle, .line, .arrow:
            InkSettingsView(title: "Pen", settings: $toolSettings.pen)
        case .pencil:
            InkSettingsView(title: "Pencil", settings: $toolSettings.pencil)
        case .highlighter:
            HighlighterSettingsView(
                settings: $toolSettings.highlighter,
                opacity: $toolSettings.highlighterOpacity
            )
        case .eraser:
            EraserSettingsView(radius: $toolSettings.eraserRadius)
        case .lasso:
            VStack(alignment: .leading, spacing: 6) {
                Label("Lasso", systemImage: "lasso")
                    .font(.headline)
                Text("Drag around content to select it.\nClick the selection to move, use the handles to resize or rotate, or click empty space to deselect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(width: 260)
        }
    }
}

private struct InkSettingsView: View {
    let title: String
    @Binding var settings: InkToolSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            InkColorSwatches(selectedColor: $settings.color)
            VStack(alignment: .leading, spacing: 4) {
                Slider(value: $settings.width, in: 1...12)
                Text("Width: \(Int(settings.width.rounded()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 260)
    }
}

private struct HighlighterSettingsView: View {
    @Binding var settings: InkToolSettings
    @Binding var opacity: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Highlighter")
                .font(.headline)
            InkColorSwatches(selectedColor: $settings.color)
            VStack(alignment: .leading, spacing: 4) {
                Slider(value: $opacity, in: 0.1...0.7)
                Text("Transparency: \(Int(opacity * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Slider(value: $settings.width, in: 6...24)
                Text("Width: \(Int(settings.width.rounded()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 260)
    }
}

private struct EraserSettingsView: View {
    @Binding var radius: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Eraser")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Slider(value: $radius, in: 6...40)
                Text("Size: \(Int(radius.rounded()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Circle()
                    .stroke(Color.secondary, lineWidth: 1)
                    .frame(width: 2 * radius, height: 2 * radius)
                    .frame(height: 40, alignment: .leading)
                Text("Circle size = eraser radius")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 260)
    }
}
#endif

#Preview {
    NavigationStack {
        EditorView(page: Page())
    }
}
