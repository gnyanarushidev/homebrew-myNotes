import AppKit
import SwiftData
import SwiftUI

private struct Failure: Error, CustomStringConvertible { let description: String }
private func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw Failure(description: message) }
}
private func near(_ a: CGPoint?, _ b: CGPoint) -> Bool {
    guard let a else { return false }
    return hypot(a.x - b.x, a.y - b.y) < 0.001
}
private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
private func memoryContainer() throws -> ModelContainer {
    try ModelContainer(for: Notebook.self, Page.self, configurations:
        ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
}

private final class ParentView: NSView {
    var usesFlippedCoordinates = false
    override var isFlipped: Bool { usesFlippedCoordinates }
}

// AppStorage writes stay in RAM, including drags after persisted-position support is restored.
private final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    init() {
        super.init(suiteName: "NotebookRegression.\(UUID().uuidString)")!
        for key in ["floatingWritingToolbarX", "floatingWritingToolbarY"] {
            values[key] = UserDefaults.standard.object(forKey: key)
        }
    }
    override func object(forKey key: String) -> Any? { values[key] }
    override func double(forKey key: String) -> Double { (values[key] as? NSNumber)?.doubleValue ?? 0 }
    override func set(_ value: Any?, forKey key: String) {
        willChangeValue(forKey: key)
        values[key] = value
        didChangeValue(forKey: key)
    }
    override func set(_ value: Double, forKey key: String) { set(value as Any, forKey: key) }
    override func removeObject(forKey key: String) { set(nil, forKey: key) }
}

private final class HostedWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor private func nativeDescendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(nativeDescendants)
}

// SwiftUI's nodes implement the public selectors without formal protocol conformance.
@MainActor private struct AccessibleElement {
    let object: NSObject
    func accessibilityLabel() -> String? {
        (object as AnyObject).accessibilityLabel?()
    }
    func accessibilityFrame() -> CGRect {
        (object as AnyObject).accessibilityFrame?() ?? .zero
    }
    func accessibilityRole() -> NSAccessibility.Role? {
        (object as AnyObject).accessibilityRole?()
    }
    func isAccessibilityEnabled() -> Bool { (object as AnyObject).isAccessibilityEnabled?() ?? false }
}

@MainActor private func accessibilityDescendants(_ object: Any) -> [AccessibleElement] {
    var seen = Set<ObjectIdentifier>()
    func visit(_ object: Any) -> [AccessibleElement] {
        guard let element = object as? NSObject,
              seen.insert(ObjectIdentifier(element)).inserted else { return [] }
        let children = (element as AnyObject).accessibilityChildren?() ?? []
        return [AccessibleElement(object: element)] + children.flatMap(visit)
    }
    return visit(object)
}

@MainActor private func settle(_ window: NSWindow) {
    for _ in 0..<4 {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.025))
        // Process activation/layout events, not physical input aimed at the temporary window.
        while let event = NSApp.nextEvent(matching: [.appKitDefined, .applicationDefined, .systemDefined],
            until: .distantPast, inMode: .default, dequeue: true) {
            NSApp.sendEvent(event)
        }
    }
}

@MainActor private final class HostedFixture {
    let container: ModelContainer
    let notebook = Notebook(title: "Hosted regression only")
    let defaults = MemoryDefaults()
    let window: NSWindow
    let host: NSHostingView<AnyView>
    var root: MacNotebookCanvasNSView! {
        nativeDescendants(host).compactMap { $0 as? MacNotebookCanvasNSView }.first
    }
    var saves: [ObjectIdentifier: [[MacStroke]]] = [:]
    private var protected = Set<ObjectIdentifier>()
    private var eventNumber = 0
    private var previousMousePoint: CGPoint?
    var adapters: [MacCanvasNSView] {
        nativeDescendants(host).compactMap { $0 as? MacCanvasNSView }
            .sorted { $0.documentOrigin.y < $1.documentOrigin.y }
    }
    var elements: [AccessibleElement] { accessibilityDescendants(host) }

    init() throws {
        container = try memoryContainer()
        container.mainContext.autosaveEnabled = false
        let page = Page(pageSize: .letterPortrait)
        notebook.pages.append(page)
        page.notebook = notebook
        container.mainContext.insert(notebook)
        let notebook = self.notebook
        host = NSHostingView(rootView: AnyView(
            NavigationStack { NotebookView(notebook: notebook) }
                .modelContainer(container)
                .defaultAppStorage(defaults)
        ))
        window = HostedWindow(contentRect: CGRect(x: 40, y: 40, width: 1100, height: 900),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        var ready = false
        defer { if !ready { window.close() } }
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        settle(window)
        _ = window.accessibilityChildren()
        _ = host.accessibilityChildren()
        // NavigationStack installs/animates its native titlebar after the first layout.
        for _ in 0..<6 { settle(window) }
        try expect(window.isKeyWindow, "Hosted test window did not become key for SwiftUI gestures")
        let roots = nativeDescendants(host).compactMap { $0 as? MacNotebookCanvasNSView }
        try expect(roots.count == 1, "Expected one recursively discovered native notebook root, got \(roots.count)")
        protectSaves()
        try expect(notebook.pages.count == 1 && notebook.pages[0].effectiveTemplate == .blank
            && notebook.pages[0].drawingFileName == nil && !notebook.pages[0].hasDrawingContent
            && notebook.pages[0].text.isEmpty && notebook.pages[0].imageData == nil
            && adapters.count == 1 && adapters[0].strokes.isEmpty,
            "Hosted notebook must start with exactly one blank page and no drawing references/ink")
        ready = true
    }

    private func protectSaves() {
        for view in adapters where protected.insert(ObjectIdentifier(view)).inserted {
            let id = ObjectIdentifier(view)
            view.onStrokesChanged = { [weak self] in self?.saves[id, default: []].append($0) }
            let append = view.onWritingNearBottom
            view.onWritingNearBottom = { [weak self] in append?(); self?.protectSaves() }
        }
    }

    func element(_ label: String) throws -> AccessibleElement {
        let matches = elements.filter { $0.accessibilityLabel() == label && !$0.accessibilityFrame().isEmpty }
        guard let element = matches.first else {
            let labels = elements.compactMap { $0.accessibilityLabel() }
            throw Failure(description: "Missing hosted accessibility element '\(label)'; labels: \(labels)")
        }
        return element
    }

    func frame(_ label: String) throws -> CGRect {
        host.convert(window.convertFromScreen(try element(label).accessibilityFrame()), from: nil)
    }

    func hit(_ point: CGPoint) -> NSView? { host.hitTest(host.convert(point, to: host.superview)) }

    func send(_ type: NSEvent.EventType, _ point: CGPoint) throws {
        protectSaves()
        eventNumber += 1
        guard var event = NSEvent.mouseEvent(with: type, location: host.convert(point, to: nil),
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: eventNumber,
            clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1) else {
            throw Failure(description: "Could not construct hosted mouse event")
        }
        if type == .leftMouseDragged, let previousMousePoint, let cg = event.cgEvent {
            cg.setDoubleValueField(.mouseEventDeltaX, value: point.x - previousMousePoint.x)
            cg.setDoubleValueField(.mouseEventDeltaY, value: point.y - previousMousePoint.y)
            if let translated = NSEvent(cgEvent: cg) { event = translated }
        }
        previousMousePoint = point
        try expect(event.windowNumber == window.windowNumber, "Synthetic hosted drag lost its window association")
        NSApp.postEvent(event, atStart: true)
        guard let queued = NSApp.nextEvent(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp],
            until: Date(timeIntervalSinceNow: 1), inMode: .default, dequeue: true) else {
            throw Failure(description: "Hosted event did not reach AppKit's in-process queue")
        }
        NSApp.sendEvent(queued)
        settle(window)
        protectSaves()
    }

    func click(_ label: String) throws {
        let rect = try frame(label)
        let center = point(rect.midX, rect.midY)
        try expect(hit(center) != nil && !(hit(center) is MacCanvasNSView) && hit(center) !== root,
                   "\(label) center falls through actual floating toolbar hit region")
        try send(.leftMouseDown, center)
        try send(.leftMouseUp, center)
    }

    func documentPoint(_ point: CGPoint) -> CGPoint {
        root.convert(root.camera!.canvasPoint(fromPagePoint: point), to: host)
    }

    func screenshot(_ name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["NOTEBOOK_REGRESSION_ARTIFACTS"] else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name + ".png")
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw Failure(description: "Cannot allocate hosted screenshot")
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw Failure(description: "Cannot encode hosted screenshot")
        }
        try data.write(to: url)
        print("ARTIFACT \(url.path)")
    }
}

@MainActor private final class CanvasFixture {
    let container: ModelContainer
    let notebook = Notebook(title: "Regression only", template: .grid, pageColor: .cream)
    let camera = EditorCamera(pageSize: PageSize.letterPortrait.dimensions)
    let root = MacNotebookCanvasNSView(frame: CGRect(x: 73, y: 91, width: 900, height: 900))
    let window: NSWindow
    var saves: [CGFloat: [[MacStroke]]] = [:]
    private var protected = Set<ObjectIdentifier>()
    private var eventNumber = 0
    var adapters: [MacCanvasNSView] {
        root.subviews.compactMap { $0 as? MacCanvasNSView }.sorted { $0.documentOrigin.y < $1.documentOrigin.y }
    }

    init(flipped: Bool = true, scale: CGFloat = 1, secondPage: Bool = false) throws {
        container = try memoryContainer()
        container.mainContext.autosaveEnabled = false
        let first = Page(createdAt: Date(timeIntervalSince1970: 1))
        notebook.pages.append(first)
        first.notebook = notebook
        if secondPage { notebook.appendContinuationPage(after: first) }
        container.mainContext.insert(notebook)
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 1100),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let parent = ParentView(frame: CGRect(x: 0, y: 0, width: 1100, height: 1100))
        parent.usesFlippedCoordinates = flipped
        window.contentView = parent
        parent.addSubview(root)
        root.camera = camera
        root.modelContext = container.mainContext
        camera.onViewportChanged = { [weak root] in root?.invalidatePageViews() }
        root.updatePages(notebook.pages.sorted { $0.createdAt < $1.createdAt })
        root.layoutSubtreeIfNeeded()
        root.layout()
        camera.viewport = ViewportState(scale: scale, offset: CGSize(width: 37, height: 600 - 780 * scale), mode: .free)
        root.invalidatePageViews()
        protectSaves()
        window.orderFront(nil)
        window.displayIfNeeded()
    }

    // Newly appended adapters must be intercepted synchronously, before a same-event handoff commits.
    private func protectSaves() {
        for view in adapters where protected.insert(ObjectIdentifier(view)).inserted {
            let origin = view.documentOrigin.y
            view.onStrokesChanged = { [weak self] in self?.saves[origin, default: []].append($0) }
            let append = view.onWritingNearBottom
            view.onWritingNearBottom = { [weak self] in append?(); self?.protectSaves() }
        }
    }

    func hit(_ documentPoint: CGPoint) -> NSView? {
        root.hitTest(root.convert(camera.canvasPoint(fromPagePoint: documentPoint), to: root.superview))
    }

    func send(_ type: NSEvent.EventType, _ documentPoint: CGPoint) throws {
        eventNumber += 1
        let location = root.convert(camera.canvasPoint(fromPagePoint: documentPoint), to: nil)
        let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: eventNumber, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)
        guard let event else { throw Failure(description: "Could not construct native mouse event") }
        window.sendEvent(event)
    }

    func stroke(_ points: [CGPoint]) throws {
        try send(.leftMouseDown, points.first!)
        for p in points.dropFirst().dropLast() { try send(.leftMouseDragged, p) }
        try send(.leftMouseUp, points.last!)
    }
}

@MainActor @main private struct NotebookRegression {
    static var passed = 0
    static var failed = 0
    static func test(_ name: String, _ body: () throws -> Void) {
        if let filter = CommandLine.arguments.dropFirst().first, !name.localizedCaseInsensitiveContains(filter) { return }
        do { try body(); passed += 1; print("PASS \(name)") }
        catch { failed += 1; print("FAIL \(name): \(error)") }
    }

    static func scenario(in context: ModelContext) throws -> Notebook {
        let notebook = Notebook(title: "Style scenario", template: .grid, pageColor: .cream)
        let p1 = Page(createdAt: Date(timeIntervalSince1970: 1), pageSize: .a4Portrait)
        notebook.pages.append(p1)
        p1.notebook = notebook
        context.insert(notebook)
        guard let p2 = notebook.appendContinuationPage(after: p1),
              let p3 = notebook.appendContinuationPage(after: p2) else { throw Failure(description: "p1 -> p2 -> p3 failed") }
        try expect(notebook.pages.allSatisfy { $0.effectiveTemplate == .grid && $0.effectivePageColor == .cream && $0.pageSize == .a4Portrait }, "Initial grid/cream inheritance or size lost")
        notebook.template = .dots
        notebook.pageColor = .dark
        try expect(notebook.pages.allSatisfy { $0.effectiveTemplate == .dots && $0.effectivePageColor == .dark }, "Default dots/dark did not propagate")
        p2.customizeStyle()
        try expect(p2.template == .dots && p2.pageColor == .dark, "Customization did not capture effective style")
        p2.template = .blank
        p2.pageColor = .white
        p2.pageSize = .letterPortrait
        notebook.template = .ruled
        notebook.pageColor = .cream
        guard let p4 = notebook.appendContinuationPage(after: p3) else { throw Failure(description: "p4 not appended") }
        try expect(p4.inheritsNotebookStyle && p4.effectiveTemplate == .ruled && p4.effectivePageColor == .cream, "p4 did not inherit latest default")
        try expect(!p2.inheritsNotebookStyle && p2.effectiveTemplate == .blank && p2.effectivePageColor == .white, "p2 override lost")
        for page in [p1, p3, p4] {
            try expect(page.pageSize == .a4Portrait && page.effectiveTemplate == .ruled && page.effectivePageColor == .cream, "Default edit changed size or inherited style")
        }
        try expect(p2.pageSize == .letterPortrait, "Default edit changed custom size")
        try expect(notebook.appendContinuationPage(after: p3) == nil && notebook.appendContinuationPage(after: p1) == nil && notebook.pages.count == 4, "Duplicate/old source appended")
        try expect(Notebook(title: "Foreign").appendContinuationPage(after: p4) == nil, "Foreign source appended")
        p1.hasDrawingContent = true
        return notebook
    }

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        // SwiftUI otherwise omits its lazy accessibility tree in an unbundled test process.
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXManualAccessibility"))
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        DispatchQueue.main.async { runTests() }
        NSApp.run()
    }

    static func runTests() {
        let size = PageSize.letterPortrait.dimensions
        let triggerCases: [(String, [CGPoint], [Int])] = [
            ("tap", Array(repeating: point(100, 780), count: 8), []),
            ("jitter", (0..<40).map { point(100 + CGFloat($0 % 2), 780) }, []),
            ("top", [point(100, 10), point(106, 10), point(112, 10)], []),
            ("wrong x", [point(600, 780), point(620, 780), point(640, 780)], []),
            ("outside start", [point(-30, 780), point(-20, 780), point(-10, 780)], []),
            ("two samples", [point(100, 780), point(120, 780)], []),
            ("travel below 12", [point(100, 780), point(104, 780), point(111.99, 780)], []),
            ("displacement below 8", [point(100, 780), point(97, 780), point(107.99, 780)], []),
            ("above 56pt margin", [point(100, 735.99), point(106, 735.99), point(112, 735.99)], []),
            ("exact thresholds, once", [point(100, 736), point(98, 736), point(108, 736), point(120, 780)], [2]),
            ("nonfinite samples", [point(.nan, 780), point(100, .infinity)], [])
        ]
        for (name, points, expected) in triggerCases {
            test("continuation: \(name)") {
                var trigger = PageContinuationTrigger()
                let actual = points.indices.filter { trigger.record(points[$0], pageSize: size) }
                try expect(actual == expected, "Expected emissions \(expected), got \(actual)")
            }
        }
        test("model scenario and in-memory save/reload (not a migration test)") {
            let container = try memoryContainer()
            let id: UUID = try {
                let context = ModelContext(container)
                context.autosaveEnabled = false
                let notebook = try scenario(in: context)
                let legacy = Page(text: "Legacy-style fixture", template: .grid, pageSize: .letterPortrait,
                                  pageColor: .dark, hasDrawingContent: true, inheritsNotebookStyle: false)
                let old = Notebook(title: "Legacy flag fixture", template: .dots, pageColor: .white, pages: [legacy])
                legacy.notebook = old
                context.insert(old)
                try context.save()
                return notebook.id
            }()
            let reloaded = ModelContext(container)
            let notebooks = try reloaded.fetch(FetchDescriptor<Notebook>())
            guard let notebook = notebooks.first(where: { $0.id == id }) else { throw Failure(description: "Notebook missing on reload") }
            let pages = notebook.pages.sorted { $0.createdAt < $1.createdAt }
            try expect(pages.count == 4 && pages.map(\.inheritsNotebookStyle) == [true, false, true, true], "Inherited/custom flags did not persist")
            try expect(pages.map(\.hasDrawingContent) == [true, false, false, false], "Content flags did not persist")
            try expect(pages.map(\.effectiveTemplate) == [.ruled, .blank, .ruled, .ruled] && pages.map(\.effectivePageColor) == [.cream, .white, .cream, .cream], "Effective styles changed after reload")
            try expect(pages.map(\.pageSize) == [.a4Portrait, .letterPortrait, .a4Portrait, .a4Portrait], "Sizes changed after reload")
            guard let legacy = notebooks.first(where: { $0.id != id })?.pages.first else { throw Failure(description: "Legacy fixture missing") }
            try expect(!legacy.inheritsNotebookStyle && legacy.hasDrawingContent && legacy.effectiveTemplate == .grid && legacy.effectivePageColor == .dark, "Legacy false flag overridden")
            pages[1].useNotebookStyle()
            try expect(pages[1].effectiveTemplate == .ruled && pages[1].effectivePageColor == .cream, "Reset to notebook style failed")
            try expect(pages.allSatisfy { $0.drawingFileName == nil }, "Fixture unexpectedly references drawing files")
        }
        for flipped in [false, true] {
            for scale: CGFloat in [0.65, 1, 1.6] {
                test("native hitTest/pen/eraser/shape: flipped=\(flipped), scale=\(scale)") {
                    let f = try CanvasFixture(flipped: flipped, scale: scale, secondPage: true)
                    defer { f.window.close() }
                    let source = f.adapters[0]
                    try expect(f.hit(point(138, 780)) === source, "Bottom hitTest did not accept superview coordinates")
                    try expect(f.hit(point(138, 840)) === f.adapters[1], "Second page hit selected wrong adapter")
                    try expect(f.hit(point(138, 806)) === f.root && f.hit(point(-1, 780)) === f.root, "Gap/outside paper accepted ink")
                    try expect(f.root.hitTest(f.root.convert(point(-1, 20), to: f.root.superview)) == nil, "Outside root accepted hit")
                    let points = [point(110, 770), point(124, 775), point(138, 780)]
                    try f.stroke(points)
                    try expect(source.strokes.count == 1, "NSWindow pen events did not commit one stroke")
                    try expect(source.strokes[0].points.count == 3 && zip(source.strokes[0].points, points).allSatisfy { near($0.cgPoint, $1) }, "Pen points not page-local")
                    f.root.updateToolState(selectedTool: .eraser, toolSettings: f.root.toolSettings)
                    try f.stroke([point(400, 780), point(420, 780), point(440, 780)])
                    try expect(source.strokes.count == 1 && f.saves[0]?.count == 1, "Missed eraser changed/saved existing ink")
                    try f.stroke([point(124, 775), point(124, 775)])
                    try expect(source.strokes.isEmpty && f.saves[0]?.count == 2, "Native eraser missed pen or save count wrong")
                    try f.stroke([point(400, 780), point(420, 780), point(440, 780)])
                    try expect(f.saves[0]?.count == 2, "No-op eraser invoked save callback")
                    f.root.updateToolState(selectedTool: .rectangle, toolSettings: f.root.toolSettings)
                    try f.stroke(points)
                    try expect(source.strokes.count == 1 && source.strokes[0].tool == .rectangle && source.strokes[0].points.count == 5, "Native shape did not commit rectangle")
                    try expect(near(source.strokes[0].points[0].cgPoint, points[0]) && near(source.strokes[0].points[2].cgPoint, points[2]), "Shape coordinates not page-local")
                    try expect(f.notebook.pages.count == 2, "Writing on old source appended a page")
                }
            }
        }
        test("unchanged tool/page state does not invalidate native adapters") {
            let f = try CanvasFixture(secondPage: true)
            defer { f.window.close() }
            f.window.display()
            f.root.superview?.needsDisplay = false
            f.root.needsDisplay = false
            f.adapters.forEach { $0.needsDisplay = false }
            try expect(f.adapters.allSatisfy { !$0.needsDisplay }, "Fixture could not clear initial invalidation")
            for _ in 0..<10 {
                f.root.updateToolState(selectedTool: f.root.selectedTool, toolSettings: f.root.toolSettings)
                f.root.updatePages(f.notebook.pages.sorted { $0.createdAt < $1.createdAt })
            }
            try expect(f.adapters.allSatisfy { !$0.needsDisplay }, "Unchanged state forced needsDisplay")
        }
        test("native scroll/zoom and tap do not append") {
            let f = try CanvasFixture()
            defer { f.window.close() }
            let before = f.camera.viewport
            for command in [false, true] {
                guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -12, wheel2: 0, wheel3: 0) else { throw Failure(description: "Scroll construction failed") }
                cg.flags = command ? .maskCommand : []
                guard let event = NSEvent(cgEvent: cg) else { throw Failure(description: "Native scroll conversion failed") }
                f.root.scrollWheel(with: event)
            }
            try expect(f.camera.viewport != before, "Scroll/zoom did not exercise camera")
            try expect(f.notebook.pages.count == 1 && f.saves.isEmpty, "Reading/scrolling appended or saved ink")
            f.camera.actualSize(centeredOn: CGRect(origin: .zero, size: size))
            try expect(f.hit(point(100, 780)) === f.adapters[0], "Tap fixture is outside visible page")
            try f.stroke([point(100, 780), point(100, 780)])
            try expect(f.saves[0]?.count == 1 && f.notebook.pages.count == 1, "Tap was not delivered or appended")
        }
        for tool: MacDrawingTool in [.pen, .pencil, .highlighter] {
            test("native continuous \(tool.rawValue): append, camera, handoff, captured style") {
                let f = try CanvasFixture()
                defer { f.window.close() }
                if tool == .pencil { f.camera.viewport.mode = .fit }
                var settings = EditorToolSettings()
                settings.pen = InkToolSettings(color: .red, width: 5)
                settings.pencil = settings.pen
                settings.highlighter = settings.pen
                f.root.updateToolState(selectedTool: tool, toolSettings: settings)
                let expectedStyle = MacStrokeStyle(color: .red, width: 5, opacity: tool == .pencil ? 0.9 : tool == .highlighter ? settings.highlighterOpacity : 1)
                let source = f.adapters[0], before = f.camera.viewport
                try f.send(.leftMouseDown, point(100, 760))
                settings.pen = InkToolSettings(color: .blue, width: 17)
                settings.pencil = settings.pen
                settings.highlighter = settings.pen
                f.root.updateToolState(selectedTool: .eraser, toolSettings: settings)
                try f.send(.leftMouseDragged, point(106, 770))
                try expect(f.notebook.pages.count == 1, "Two samples appended")
                try f.send(.leftMouseDragged, point(112, 780))
                try expect(f.notebook.pages.count == 2 && f.adapters[0] === source, "Content did not append synchronously or replaced source")
                try expect(f.camera.viewport == before, "Append changed camera snapshot")
                let next = f.adapters[1]
                try f.send(.leftMouseDragged, point(140, 840))
                try f.send(.leftMouseDragged, point(150, 860))
                try f.send(.leftMouseUp, point(160, 880))
                try expect(source.strokes.count == 1 && next.strokes.count == 1, "Continuous gesture lost source/destination segment")
                let a = source.strokes[0], b = next.strokes[0]
                try expect(a.points.count == 4 && near(a.points.first?.cgPoint, point(100, 760)) && near(a.points.last?.cgPoint, point(117.6, 792)), "Source segment/boundary wrong")
                try expect(b.points.count == 4 && near(b.points[0].cgPoint, point(117.6, -32)) && near(b.points[1].cgPoint, point(140, 16)) && near(b.points.last?.cgPoint, point(160, 56)), "Destination coords lost document origin/gap")
                try expect(a.tool == tool && b.tool == tool && a.style == expectedStyle && b.style == expectedStyle, "Mid-stroke tool/color mutation changed captured ink")
                try expect(f.camera.viewport == before && !source.isHandlingInkGesture && !next.isHandlingInkGesture, "Handoff changed camera or left gesture active")
                try expect(f.saves[0]?.count == 1 && f.saves[824]?.count == 1, "Expected exactly one commit per segment")
                try expect(next.pageColor == .cream && next.template == .grid && next.pageSize == size, "Appended page style/size wrong")
                f.root.updateToolState(selectedTool: .pen, toolSettings: settings)
                try f.stroke([point(200, 924), point(210, 930), point(220, 936)])
                try expect(source.strokes[0] == a && next.strokes.first == b && next.strokes.count == 2, "Later tool changes modified old ink")
                try expect(next.strokes[1].style == MacStrokeStyle(color: .blue, width: 17), "New ink did not use new color/width")
            }
        }
        test("native sparse overflow: third sample qualifies on mouseUp, original points and first-crossing interpolation") {
            let f = try CanvasFixture()
            defer { f.window.close() }
            let source = f.adapters[0], before = f.camera.viewport
            try f.send(.leftMouseDown, point(100, 770))
            try f.send(.leftMouseDragged, point(130, 800))
            try expect(f.notebook.pages.count == 1 && source.strokes.isEmpty, "Two samples appended or prematurely committed")
            try f.send(.leftMouseUp, point(170, 810))
            try expect(f.notebook.pages.count == 2 && source.strokes.count == 1 && f.adapters[1].strokes.count == 1,
                       "Qualifying mouseUp lost source/destination segment")
            let a = source.strokes[0], b = f.adapters[1].strokes[0]
            try expect(a.points.count == 2 && b.points.count == 3, "Sparse handoff omitted/duplicated original samples")
            try expect(near(a.points[0].cgPoint, point(100, 770))
                && near(b.points[1].cgPoint, point(130, -24)) && near(b.points[2].cgPoint, point(170, -14)),
                "Original sparse samples were lost or translated incorrectly: \(a.points), \(b.points)")
            try expect(f.camera.viewport == before && !source.isHandlingInkGesture && !f.adapters[1].isHandlingInkGesture
                && f.saves[0]?.count == 1 && f.saves[824]?.count == 1, "Sparse handoff changed camera/commit count or left gesture active")
            // The boundary belongs to the 770 -> 800 segment, not 770 -> 810.
            try expect(near(a.points[1].cgPoint, point(122, 792)) && near(b.points[0].cgPoint, point(122, -32)),
                       "Expected first-crossing boundary (122,792)/(122,-32), got \(a.points[1].cgPoint)/\(b.points[0].cgPoint)")
        }
        test("native Page 2 -> 3, notebook defaults/page override, then Page 3 -> 4") {
            let f = try CanvasFixture(secondPage: true)
            defer { f.window.close() }
            f.camera.viewport.offset.height = 600 - (824 + 780)
            f.root.invalidatePageViews()
            let originalAdapters = f.adapters
            try f.stroke([point(100, 824 + 760), point(106, 824 + 770), point(112, 824 + 780), point(140, 824 + 840)])
            try expect(f.notebook.pages.count == 3 && f.adapters[1].strokes.count == 1 && f.adapters[2].strokes.count == 1,
                       "Native Page 2 -> 3 did not append/handoff")
            let pages = f.notebook.pages.sorted { $0.createdAt < $1.createdAt }
            let oldInk = f.adapters.map(\.strokes)
            f.notebook.template = .dots
            f.notebook.pageColor = .dark
            f.root.updatePages(pages)
            try expect(f.adapters.allSatisfy { $0.template == .dots && $0.pageColor == .dark }, "First notebook default edit did not reach adapters")
            pages[1].customizeStyle()
            pages[1].template = .blank
            pages[1].pageColor = .white
            f.notebook.template = .ruled
            f.notebook.pageColor = .cream
            f.root.updatePages(pages)
            var settings = f.root.toolSettings
            settings.pen = InkToolSettings(color: .blue, width: 9)
            f.root.updateToolState(selectedTool: .pen, toolSettings: settings)
            f.camera.viewport.offset.height = 600 - (1648 + 780)
            f.root.invalidatePageViews()
            let before = f.camera.viewport
            try f.stroke([point(200, 1648 + 760), point(206, 1648 + 770), point(212, 1648 + 780), point(240, 1648 + 840)])
            try expect(f.notebook.pages.count == 4 && f.camera.viewport == before, "Page 3 -> 4 append changed camera/count")
            try expect(f.adapters[0] === originalAdapters[0] && f.adapters[1] === originalAdapters[1], "Style edits replaced native roots")
            try expect(f.adapters.map(\.template) == [.ruled, .blank, .ruled, .ruled]
                && f.adapters.map(\.pageColor) == [.cream, .white, .cream, .cream]
                && f.adapters.allSatisfy { $0.pageSize == size }, "Page 4 did not inherit latest defaults/size or Page 2 override lost")
            try expect(f.adapters[0].strokes == oldInk[0] && f.adapters[1].strokes == oldInk[1]
                && f.adapters[2].strokes.first == oldInk[2].first, "Native style/default edits changed original ink")
            try expect(f.adapters[2].strokes.count == 2 && f.adapters[3].strokes.count == 1
                && f.adapters[3].strokes[0].style == MacStrokeStyle(color: .blue, width: 9)
                && near(f.adapters[3].strokes[0].points.last?.cgPoint, point(240, 16)), "Page 3 -> 4 ink style/coordinates lost")
            try expect(f.notebook.pages.allSatisfy { $0.drawingFileName == nil }, "Regression wrote drawing references")
        }
        let swatches: [(String, Color)] = [
            ("Black", .black), ("Dark Gray", Color(white: 0.3)), ("Gray", .gray), ("Red", .red),
            ("Orange", .orange), ("Yellow", .yellow), ("Green", .green), ("Blue", .blue),
            ("Purple", .purple), ("Pink", .pink), ("Brown", .brown), ("White", .white)
        ]
        let toolbarLabels = ["Move Writing Toolbar", "Pen", "Pencil", "Highlighter", "Eraser", "Lasso"] + swatches.map(\.0)
        test("hosted NotebookView: 12 named swatches physically clickable, shared per-tool native state") {
            let f = try HostedFixture()
            defer { f.window.close() }
            let root = f.root!, adapter = f.adapters[0]
            let initial = root.toolSettings
            for (name, color) in swatches {
                let element = try f.element(name)
                try expect(element.accessibilityRole() == .button && element.isAccessibilityEnabled(), "\(name) is not an enabled accessible button")
                try f.click(name)
                try expect(root.toolSettings.pen.color == color && adapter.toolSettings.pen.color == color,
                           "Clicking hosted \(name) did not update shared pen color")
                try expect(root.toolSettings.pencil == initial.pencil && root.toolSettings.highlighter == initial.highlighter
                    && root.toolSettings.pen.width == initial.pen.width, "Pen swatch changed another tool/width")
            }
            for (tool, label, colorName): (MacDrawingTool, String, String) in [
                (.pen, "Pen", "Red"), (.pencil, "Pencil", "Blue"), (.highlighter, "Highlighter", "Yellow")
            ] {
                try f.click(label)
                try expect(root.selectedTool == tool && adapter.selectedTool == tool, "Hosted \(label) selection did not reach native state")
                try f.click(colorName)
            }
            try f.click("Pen")
            try expect(root.toolSettings.pen.color == .red && root.toolSettings.pencil.color == .blue
                && root.toolSettings.highlighter.color == .yellow && adapter.toolSettings == root.toolSettings,
                "Switching tools lost independent/shared color state")
            try expect(root.toolSettings.pen.width == initial.pen.width && root.toolSettings.pencil.width == initial.pencil.width
                && root.toolSettings.highlighter.width == initial.highlighter.width
                && root.toolSettings.highlighterOpacity == initial.highlighterOpacity, "Swatches changed widths/opacity")
            for label in ["Eraser", "Lasso"] {
                try f.click(label)
                try expect(try f.element("Red").isAccessibilityEnabled() == false, "\(label) left ink swatches enabled")
            }
            try expect(f.root === root && f.adapters[0] === adapter && adapter.strokes.isEmpty && f.saves.isEmpty,
                       "Toolbar interaction replaced native views or leaked ink through palette")
            for (tool, label, color, width, opacity): (MacDrawingTool, String, Color, CGFloat, CGFloat) in [
                (.pen, "Pen", .red, initial.pen.width, 1),
                (.pencil, "Pencil", .blue, initial.pencil.width, 0.9),
                (.highlighter, "Highlighter", .yellow, initial.highlighter.width, initial.highlighterOpacity)
            ] {
                let original = adapter.strokes
                try f.click(label)
                guard let x = [CGFloat(100), 300, 450].first(where: { x in
                    (0..<3).allSatisfy { f.hit(f.documentPoint(point(x + CGFloat($0) * 10, 500))) === adapter }
                }) else { throw Failure(description: "No exposed native paper for hosted color stroke") }
                try f.send(.leftMouseDown, f.documentPoint(point(x, 500)))
                try f.send(.leftMouseDragged, f.documentPoint(point(x + 10, 500)))
                try f.send(.leftMouseUp, f.documentPoint(point(x + 20, 500)))
                try expect(adapter.strokes.count == original.count + 1 && Array(adapter.strokes.dropLast()) == original
                    && adapter.strokes.last?.tool == tool
                    && adapter.strokes.last?.style == MacStrokeStyle(color: color, width: width, opacity: opacity),
                    "Hosted \(label) ink did not capture chosen color/width/opacity or changed old ink")
            }
            try expect(f.saves[ObjectIdentifier(adapter)]?.count == 3 && f.notebook.pages.count == 1
                && f.notebook.pages[0].drawingFileName == nil, "Hosted tool settings test escaped in-memory stroke interception")
            try f.screenshot("hosted-swatches")
        }
        test("hosted floating toolbar: drag keeps native root/camera, bounded hit region and lower-page input") {
            let f = try HostedFixture()
            defer { f.window.close() }
            let root = f.root!, adapter = f.adapters[0], camera = root.camera!
            let originalFrame = root.frame, originalBounds = root.bounds, before = camera.viewport
            let frames = try toolbarLabels.map(f.frame)
            let handle = frames[0]
            let start = point(handle.midX, handle.midY)
            try expect(f.hit(start) != nil && f.hit(start) !== root && !(f.hit(start) is MacCanvasNSView), "Toolbar handle hit falls through to ink")
            let delta = point(start.x < f.host.bounds.midX ? 170 : -170, start.y < f.host.bounds.midY ? 120 : -120)
            try f.send(.leftMouseDown, start)
            for step in 1...4 {
                try f.send(.leftMouseDragged, point(start.x + delta.x * CGFloat(step) / 4, start.y + delta.y * CGFloat(step) / 4))
                try expect(f.root === root && f.adapters[0] === adapter && root.frame == originalFrame && root.bounds == originalBounds
                    && camera.viewport == before, "Toolbar drag moved/replaced/resized native root or changed camera: frame \(originalFrame) -> \(root.frame), bounds \(originalBounds) -> \(root.bounds), camera \(before) -> \(camera.viewport)")
            }
            try f.send(.leftMouseUp, point(start.x + delta.x, start.y + delta.y))
            let moved = try toolbarLabels.map(f.frame)
            for (a, b) in zip(frames, moved) {
                try expect(a.size == b.size && near(b.origin, point(a.minX + delta.x, a.minY + delta.y)),
                           "Actual toolbar did not translate rigidly by \(delta): \(a) -> \(b)")
            }
            let palette = moved.reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -8, dy: -8)
            let viewport = root.convert(root.bounds, to: f.host)
            var sampled = 0
            for y in stride(from: viewport.minY + 15, to: viewport.maxY - 15, by: 35) {
                for x in stride(from: viewport.minX + 15, to: viewport.maxX - 15, by: 35) where !palette.contains(point(x, y)) {
                    let hit = f.hit(point(x, y))
                    try expect(hit === root || hit is MacCanvasNSView,
                               "Outside palette intercepted at \(point(x, y)); hit \(String(describing: hit))")
                    sampled += 1
                }
            }
            let candidates = [100, 250, 420].map { CGFloat($0) }
            guard let x = candidates.first(where: { x in
                (0..<3).allSatisfy { index in
                    let p = f.documentPoint(point(x + CGFloat(index) * 10, 770))
                    return viewport.contains(p) && !palette.contains(p) && f.hit(p) === adapter
                }
            }) else { throw Failure(description: "No exposed lower-page sample outside actual palette") }
            try expect(adapter.strokes.isEmpty && f.saves.isEmpty, "Toolbar drag leaked ink")
            try f.send(.leftMouseDown, f.documentPoint(point(x, 770)))
            try f.send(.leftMouseDragged, f.documentPoint(point(x + 10, 770)))
            try f.send(.leftMouseUp, f.documentPoint(point(x + 20, 770)))
            try f.screenshot("hosted-toolbar-drag")
            try expect(adapter.strokes.count == 1 && adapter.strokes[0].points.count == 3
                && near(adapter.strokes[0].points.first?.cgPoint, point(x, 770))
                && near(adapter.strokes[0].points.last?.cgPoint, point(x + 20, 770))
                && f.notebook.pages.count == 2, "Hosted lower-page input was intercepted or failed to append: pages=\(f.notebook.pages.count), strokes=\(adapter.strokes)")
            try expect(f.notebook.pages.allSatisfy { $0.drawingFileName == nil }, "Hosted test wrote ink references")
            print("HOSTED hit-region samples outside moved palette: \(sampled); lower-page native stroke appended page 2")
        }
        test("hosted floating toolbar: native zoom/pan changes camera, not toolbar position/size") {
            let f = try HostedFixture()
            defer { f.window.close() }
            let root = f.root!, adapter = f.adapters[0], camera = root.camera!
            let frames = try toolbarLabels.map(f.frame), nativeFrame = root.frame
            for command in [true, false] {
                let before = camera.viewport
                guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: -20, wheel2: -10, wheel3: 0) else {
                    throw Failure(description: "Cannot construct hosted native scroll")
                }
                cg.flags = command ? .maskCommand : []
                guard let event = NSEvent(cgEvent: cg) else { throw Failure(description: "Cannot convert hosted native scroll") }
                root.scrollWheel(with: event)
                settle(f.window)
                try expect(camera.viewport != before, "Hosted native \(command ? "zoom" : "pan") did not move camera")
                try expect(try toolbarLabels.map(f.frame) == frames, "Zoom/pan moved or resized actual floating toolbar")
                try expect(f.root === root && f.adapters[0] === adapter && root.frame == nativeFrame, "Zoom/pan replaced/moved native root")
            }
            try expect(f.notebook.pages.count == 1 && adapter.strokes.isEmpty && f.saves.isEmpty, "Hosted zoom/pan generated ink/pages")
        }
        test("PDF actual-page count, ordered mixed media boxes, no layout gaps") {
            let container = try memoryContainer()
            let notebook = try scenario(in: container.mainContext)
            let pages = notebook.pages.sorted { $0.createdAt < $1.createdAt }
            let data = PDFExporter.makePDF(pages: pages.map { PDFExportPage(size: $0.pageSize.dimensions, color: $0.effectivePageColor, template: $0.effectiveTemplate, strokes: []) })
            guard let provider = CGDataProvider(data: data as CFData), let pdf = CGPDFDocument(provider) else { throw Failure(description: "Invalid PDF") }
            try expect(pdf.numberOfPages == 4, "Expected four actual pages, got \(pdf.numberOfPages)")
            for (index, page) in pages.enumerated() {
                let box = pdf.page(at: index + 1)!.getBoxRect(.mediaBox)
                try expect(box == CGRect(origin: .zero, size: page.pageSize.dimensions), "PDF page \(index + 1) box \(box), expected \(page.pageSize.dimensions)")
            }
            try expect(PDFExporter.makePDF(pages: []).isEmpty, "Empty notebook exported phantom page")
        }
        let appearances: [(PageTemplate, PageColor)] = [(.blank, .white), (.ruled, .cream), (.grid, .white), (.dots, .dark)]
        let stroke = MacStroke(points: [MacPoint(point(200, 50)), MacPoint(point(220, 50))], style: MacStrokeStyle(red: 1, green: 0, blue: 0, width: 6))
        let orderedPDF = PDFExporter.makePDF(pages: appearances.map { PDFExportPage(size: size, color: $0.1, template: $0.0, strokes: [stroke]) })
        for (index, appearance) in appearances.enumerated() {
            let (template, color) = appearance
            test("PDF ordered page \(index + 1): \(template.rawValue)/\(color.rawValue), background/pattern/stored ink") {
                guard let provider = CGDataProvider(data: orderedPDF as CFData), let pdf = CGPDFDocument(provider), let page = pdf.page(at: index + 1) else { throw Failure(description: "Invalid PDF") }
                try expect(pdf.numberOfPages == appearances.count, "PDF inserted/omitted actual pages")
                let width = Int(size.width * 2), height = Int(size.height * 2)
                guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue), let pixels = ctx.data else { throw Failure(description: "Raster allocation failed") }
                ctx.translateBy(x: 0, y: CGFloat(height))
                ctx.scaleBy(x: 2, y: -2)
                ctx.drawPDFPage(page)
                func sample(_ p: CGPoint) -> [Double] {
                    // Bitmap memory rows are bottom-up; assertions use the canvas's top-left origin.
                    let offset = ((height - 1 - Int(p.y * 2)) * width + Int(p.x * 2)) * 4
                    return (0..<3).map { Double(pixels.load(fromByteOffset: offset + $0, as: UInt8.self)) / 255 }
                }
                let background = sample(point(21, 21))
                let expected: [Double] = color == .white ? [1, 1, 1] : color == .cream ? [0.98, 0.96, 0.88] : [0.12, 0.12, 0.13]
                try expect(zip(background, expected).allSatisfy { abs($0 - $1) < 0.015 }, "Background pixel \(background), expected \(expected)")
                let marks = [point(20, 36), point(32, 20), point(16, 16)].map(sample)
                let changed = marks.map { zip($0, background).contains { abs($0 - $1) > 0.025 } }
                let expectedMarks = [template == .ruled, template == .grid, template == .dots]
                try expect(changed == expectedMarks, "Pattern samples \(changed), expected \(expectedMarks)")
                let ink = sample(point(210, 50))
                try expect(ink[0] > 0.95 && ink[1] < 0.05 && ink[2] < 0.05, "Stored red ink rendered incorrectly: \(ink)")
            }
        }
        print("RESULT: \(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}
