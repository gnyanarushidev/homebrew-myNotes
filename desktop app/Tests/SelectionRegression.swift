import AppKit
import SwiftData
import SwiftUI

private struct Failure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw Failure(description: message) }
}

private final class SelectionWindow: NSWindow {
    let history = UndoManager()
    override var undoManager: UndoManager? { history }
}

@MainActor private final class SelectionFixture {
    let container: ModelContainer
    let notebook = Notebook(title: "Selection regression only")
    let controller = MacSelectionController()
    let camera = EditorCamera(pageSize: PageSize.letterPortrait.dimensions)
    let root = MacNotebookCanvasNSView(frame: CGRect(x: 0, y: 0, width: 900, height: 1800))
    let window: SelectionWindow
    var saves: [ObjectIdentifier: [[MacStroke]]] = [:]

    var canvases: [MacCanvasNSView] {
        root.subviews.compactMap { $0 as? MacCanvasNSView }
            .sorted { $0.documentOrigin.y < $1.documentOrigin.y }
    }

    init() throws {
        container = try ModelContainer(for: Notebook.self, Page.self, configurations:
            ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        container.mainContext.autosaveEnabled = false
        for index in 0..<2 {
            let page = Page(createdAt: Date(timeIntervalSince1970: Double(index)))
            page.notebook = notebook
            notebook.pages.append(page)
        }
        container.mainContext.insert(notebook)
        window = SelectionWindow(contentRect: root.frame, styleMask: .borderless,
                                 backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.history.groupsByEvent = false
        window.contentView = root
        root.camera = camera
        root.modelContext = container.mainContext
        root.selectionController = controller
        root.updatePages(notebook.pages.sorted { $0.createdAt < $1.createdAt })
        root.layout()
        camera.viewport = ViewportState(scale: 1, offset: .zero, mode: .free)
        root.invalidatePageViews()
        for canvas in canvases {
            // Intercept persistence so the harness never writes to the user's drawings.
            let id = ObjectIdentifier(canvas)
            canvas.onStrokesChanged = { [weak self] in self?.saves[id, default: []].append($0) }
            canvas.strokes = [
                MacStroke(points: [MacPoint(CGPoint(x: 100, y: 100)), MacPoint(CGPoint(x: 140, y: 130))],
                          tool: .pen, style: MacStrokeStyle(color: .blue, width: 4, opacity: 1)),
                MacStroke(points: [MacPoint(CGPoint(x: 300, y: 300)), MacPoint(CGPoint(x: 340, y: 330))],
                          tool: .highlighter, style: MacStrokeStyle(color: .yellow, width: 14, opacity: 0.35))
            ]
        }
    }

    func select(on canvas: MacCanvasNSView, rect: CGRect = CGRect(x: 80, y: 80, width: 90, height: 80)) throws {
        root.updateToolState(selectedTool: .lasso, toolSettings: EditorToolSettings())
        let points = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.minY)
        ]
        for (index, point) in points.enumerated() {
            let type: NSEvent.EventType = index == 0 ? .leftMouseDown
                : index == points.count - 1 ? .leftMouseUp : .leftMouseDragged
            let documentPoint = CGPoint(x: point.x + canvas.documentOrigin.x, y: point.y + canvas.documentOrigin.y)
            let location = canvas.convert(camera.canvasPoint(fromPagePoint: documentPoint), to: nil)
            guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: index, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1) else {
                throw Failure(description: "Could not create lasso event")
            }
            switch type {
            case .leftMouseDown: canvas.mouseDown(with: event)
            case .leftMouseDragged: canvas.mouseDragged(with: event)
            default: canvas.mouseUp(with: event)
            }
        }
    }

    func deleting(_ action: () -> Void) {
        window.history.beginUndoGrouping()
        action()
        window.history.endUndoGrouping()
    }

    func saved(_ canvas: MacCanvasNSView) -> [[MacStroke]] {
        saves[ObjectIdentifier(canvas), default: []]
    }
}

@MainActor @main private struct SelectionRegression {
    static var passed = 0
    static var failed = 0

    static func test(_ name: String, _ body: (SelectionFixture) throws -> Void) {
        if let filter = CommandLine.arguments.dropFirst().first,
           !name.localizedCaseInsensitiveContains(filter) { return }
        do {
            let fixture = try SelectionFixture()
            defer { fixture.window.close() }
            try body(fixture)
            passed += 1
            print("PASS \(name)")
        } catch {
            failed += 1
            print("FAIL \(name): \(error)")
        }
    }

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()

        test("delete selected ink after focus changes; save, undo, redo, and stroke styles") { f in
            let canvas = f.canvases[0], other = f.canvases[1]
            let original = canvas.strokes, otherOriginal = other.strokes
            try f.select(on: canvas)
            try expect(canvas.selection.strokeIDs == [original[0].id] && f.controller.hasSelection,
                       "Lasso did not activate exactly the intended stroke")
            f.window.makeFirstResponder(f.root)
            f.deleting { f.controller.deleteSelection() }
            try expect(canvas.strokes == [original[1]] && other.strokes == otherOriginal,
                       "Delete changed unselected ink or the other page")
            try expect(!canvas.selection.isActive && !f.controller.hasSelection, "Delete did not clear selection state")
            try expect(f.saved(canvas) == [[original[1]]] && f.saved(other).isEmpty, "Wrong drawing save notifications")
            let decoded = try JSONDecoder().decode([MacStroke].self, from: JSONEncoder().encode(f.saved(canvas)[0]))
            try expect(decoded == [original[1]], "Saved ink lost its identity or style")
            try expect(f.window.history.canUndo, "Deletion was not undoable")
            f.window.history.undo()
            try expect(canvas.strokes == original && f.saved(canvas).last == original, "Undo did not restore and save ink")
            f.window.history.redo()
            try expect(canvas.strokes == [original[1]] && f.saved(canvas).count == 3, "Redo did not delete and save again")
        }

        test("selection deletion is a no-op when nothing is selected") { f in
            let original = f.canvases.map(\.strokes)
            f.controller.deleteSelection()
            f.canvases[0].deleteSelection()
            try expect(!f.controller.hasSelection && f.canvases.map(\.strokes) == original,
                       "Empty selection changed ink or enabled deletion")
            try expect(f.saves.isEmpty && !f.window.history.canUndo, "Empty selection saved or registered undo")
        }

        test("selecting a different page clears the previous selection") { f in
            let first = f.canvases[0], second = f.canvases[1]
            let firstOriginal = first.strokes, secondOriginal = second.strokes
            try f.select(on: first)
            try f.select(on: second)
            try expect(!first.selection.isActive && second.selection.isActive && f.controller.hasSelection,
                       "Selections remained active on multiple pages")
            f.deleting { f.controller.deleteSelection() }
            try expect(first.strokes == firstOriginal && second.strokes == [secondOriginal[1]],
                       "Delete targeted the wrong page")
        }

        test("empty lasso disables deletion") { f in
            let canvas = f.canvases[0], original = canvas.strokes
            try f.select(on: canvas)
            try f.select(on: canvas, rect: CGRect(x: 400, y: 100, width: 80, height: 80))
            f.deleting { f.controller.deleteSelection() }
            try expect(!f.controller.hasSelection && canvas.strokes == original && f.saves.isEmpty,
                       "An empty lasso left a stale deletion target")
        }

        test("deleting all selected ink keeps the page and supports undo") { f in
            let canvas = f.canvases[0], original = canvas.strokes
            try f.select(on: canvas, rect: CGRect(x: 60, y: 60, width: 320, height: 320))
            f.deleting { f.controller.deleteSelection() }
            try expect(canvas.strokes.isEmpty && f.saved(canvas).last == [] && f.notebook.pages.count == 2,
                       "Deleting all ink failed or removed a page")
            f.window.history.undo()
            try expect(canvas.strokes == original, "Undo did not restore a fully erased selection")
        }

        for keyCode: UInt16 in [51, 117] {
            test("keyboard selection deletion: key code \(keyCode)") { f in
                let canvas = f.canvases[0], original = canvas.strokes
                try f.select(on: canvas)
                guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: f.window.windowNumber,
                    context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}",
                    isARepeat: false, keyCode: keyCode) else { throw Failure(description: "Could not create Delete event") }
                f.deleting { canvas.keyDown(with: event) }
                try expect(canvas.strokes == [original[1]] && !f.controller.hasSelection,
                           "Delete key did not remove just the selection")
            }
        }

        test("removing a selected page detaches its deletion target") { f in
            let removed = f.canvases[1], original = removed.strokes
            try f.select(on: removed)
            let remainingPage = f.notebook.pages.min { $0.createdAt < $1.createdAt }!
            f.root.updatePages([remainingPage])
            f.deleting { f.controller.deleteSelection() }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            try expect(removed.strokes == original && !f.controller.hasSelection && f.saves.isEmpty,
                       "Removed page remained a deletion target")
        }

        print("Selection regressions: \(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}
