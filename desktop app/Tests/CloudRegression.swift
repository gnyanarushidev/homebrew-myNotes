import Foundation
import SwiftData
import AppKit
private func expect(_ condition: Bool) { precondition(condition) }

private final class TestObjects: @unchecked Sendable {
    static let shared = TestObjects()
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func put(_ key: String, _ data: Data) { lock.lock(); defer { lock.unlock() }; values[key] = data }
    func get(_ key: String) -> Data? { lock.lock(); defer { lock.unlock() }; return values[key] }
}
private final class ObjectProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "objects.mynotes-test.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let key = request.url!.lastPathComponent
        if request.httpMethod == "PUT" {
            var data = request.httpBody ?? Data()
            if data.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }; var bytes = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let n = stream.read(&bytes, maxLength: bytes.count); if n <= 0 { break }; data.append(contentsOf: bytes.prefix(n)) }
            }
            TestObjects.shared.put(key, data)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        } else {
            guard let data = TestObjects.shared.get(key) else { client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist)); return }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
@MainActor private final class TestCloud {
    let owner: String
    var records: [String: CloudNotebook] = [:]
    var receipts: [String: CloudReceipt] = [:]
    var sequence = 0
    var loseNextCommitReply = false
    init(owner: String) { self.owner = owner }
    func call(_ path: String, _ method: String, _ data: Data?) async throws -> Data {
        if path == "/api/v1/sync/cleanup" { return Data("{}".utf8) }
        if path == "/api/v1/sync/files" { return data! }
        if path == "/api/v1/sync/uploads" {
            let request = try JSONDecoder().decode(UploadPreparation.self, from: data!)
            let files: [[String: Any]] = request.files.map { ["id": $0.id, "key": $0.id, "sha256": $0.sha256, "bytes": $0.bytes, "kind": $0.kind, "url": "https://objects.mynotes-test.invalid/\($0.id)", "headers": ["Content-Type": "application/octet-stream"]] }
            return try JSONSerialization.data(withJSONObject: ["files": files])
        }
        if path == "/api/v1/sync/commit" {
            let request = try JSONDecoder().decode(CloudCommit.self, from: data!)
            if let receipt = receipts[request.operationId] { return try CloudCodec.encode(receipt) }
            var id = request.id, manifest = request.manifest, conflict = false
            let current = records[id]
            if (current?.revision ?? 0) != request.baseRevision || (current?.deleted == true && !request.deleted) {
                if request.deleted { throw CloudError.http(409, "Revision conflict") }
                conflict = true; id = CloudCodec.stableID("\(owner):\(request.operationId):conflict")
                manifest.title = "\(manifest.title.prefix(100)) (conflict copy)"
                manifest.pages = manifest.pages.map { page in var next = page; next.id = CloudCodec.stableID("\(id):\(page.id)"); return next }
            }
            for page in manifest.pages where !request.deleted {
                guard let bytes = TestObjects.shared.get(page.content.key), bytes.count == page.content.bytes, CloudCodec.hash(bytes) == page.content.sha256 else { throw CloudError.invalidDocument }
            }
            if request.deleted { manifest.pages = [] }
            sequence += 1; let revision = conflict ? 1 : (current?.revision ?? 0) + 1
            records[id] = CloudNotebook(id: id, manifest: manifest, revision: revision, change_seq: sequence, deleted: request.deleted, updated_at: "2026-01-01T00:00:00Z", created_at: "2026-01-01T00:00:00Z", mutation_id: request.operationId)
            let receipt = CloudReceipt(id: id, revision: revision, sequence: sequence, conflict: conflict, deleted: request.deleted)
            receipts[request.operationId] = receipt
            if loseNextCommitReply { loseNextCommitReply = false; throw URLError(.networkConnectionLost) }
            return try CloudCodec.encode(receipt)
        }
        if path.hasPrefix("/api/v1/sync/notebooks/") {
            let id = String(path.dropFirst("/api/v1/sync/notebooks/".count)).components(separatedBy: "?")[0]
            guard let record = records[id] else { throw CloudError.http(404, "Missing notebook") }
            if path.contains("downloads") {
                var urls: [String: String] = [:]
                for page in record.manifest.pages { urls[page.content.key] = "https://objects.mynotes-test.invalid/\(page.content.key)" }
                return try CloudCodec.encode(CloudDownloads(record: record, urls: urls))
            }
            return try CloudCodec.encode(record)
        }
        if path.hasPrefix("/api/v1/sync?cursor=") {
            let cursor = Int(path.components(separatedBy: "=").last!)!
            return try CloudCodec.encode(CloudChanges(records: records.values.filter { $0.change_seq > cursor }.sorted { $0.change_seq < $1.change_seq }, cursor: sequence, more: false))
        }
        throw CloudError.message("Unexpected test endpoint \(path)")
    }
}
@main struct CloudRegression {
    @MainActor static func main() async throws {
        _ = URLProtocol.registerClass(ObjectProtocol.self)
        let temp = ProcessInfo.processInfo.environment["MYNOTES_TEST_TEMP_ROOT"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory
        let root = temp.appendingPathComponent("mynotes-cloud-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root); FileStore.accountRoot = nil; URLProtocol.unregisterClass(ObjectProtocol.self) }
        let account = CloudAccount(id: "11111111-1111-4111-8111-111111111111", email: "test@example.com", isAdmin: false)
        let cloud = TestCloud(owner: account.id)
        var a: DesktopSyncEngine? = try DesktopSyncEngine(account: account, origin: "https://api.mynotes-test.invalid", rootOverride: root.appendingPathComponent("a/\(account.id)"), api: cloud.call)
        let b = try DesktopSyncEngine(account: account, origin: "https://api.mynotes-test.invalid", rootOverride: root.appendingPathComponent("b/\(account.id)"), api: cloud.call)
        let id = UUID().uuidString.lowercased(), pageID = UUID().uuidString.lowercased(), strokeID = UUID()
        let stroke = MacStroke(id: strokeID, points: [MacPoint(CGPoint(x: 100, y: 150)), MacPoint(CGPoint(x: 200, y: 200))], tool: .pen, style: MacStrokeStyle(red: 0.25, green: 0.4, blue: 0.8, width: 3))
        let document = LocalCloudDocument(title: "Native sync", template: "grid", color: "cream", pages: [LocalCloudPage(id: pageID, size: "a4Portrait", template: "dots", color: "white", inheritsStyle: false, content: SharedPageContent(text: "Local text", strokes: [SharedStroke(stroke)]), image: nil, imageKind: nil)])
        _ = try CloudCodec.apply(document, id: id, context: a!.container.mainContext, directory: a!.directory)
        try await a!.synchronize(); expect(try a!.isClean())
        try await b.synchronize()
        func snapshot(_ engine: DesktopSyncEngine, _ notebookID: String? = nil) throws -> LocalCloudDocument {
            let notebook = try engine.container.mainContext.fetch(FetchDescriptor<Notebook>()).first { $0.id.uuidString.lowercased() == (notebookID ?? id) }!
            return try CloudCodec.snapshot(notebook, directory: engine.directory)
        }
        expect(try CloudCodec.encode(snapshot(b)) == CloudCodec.encode(document))
        print("PASS native upload, verified download, point/style/text/paper round-trip and independent stores")
        func edit(_ engine: DesktopSyncEngine, x: Double) throws {
            let notebook = try engine.container.mainContext.fetch(FetchDescriptor<Notebook>()).first { $0.id.uuidString.lowercased() == id }!, page = notebook.pages[0]
            let changed = MacStroke(id: strokeID, points: [MacPoint(CGPoint(x: x, y: 150)), MacPoint(CGPoint(x: 200, y: 200))], tool: .pen, style: stroke.style)
            try MacDrawingStorage.write([changed], name: page.drawingFileName!, directory: engine.directory)
            page.updatedAt = .now; notebook.updatedAt = .now; try engine.container.mainContext.save()
        }
        try edit(b, x: 220); try await b.synchronize(); try await a!.synchronize()
        expect(try snapshot(a!).pages[0].content.strokes[0].points[0].x == 220)
        print("PASS cloud edits replace only an unchanged local baseline")
        try edit(a!, x: 300); try edit(b, x: 400); try await b.synchronize(); try await a!.synchronize()
        let copies = try a!.container.mainContext.fetch(FetchDescriptor<Notebook>())
        precondition(copies.count == 2)
        let conflict = copies.first { $0.id.uuidString.lowercased() != id }!
        expect(try snapshot(a!, conflict.id.uuidString.lowercased()).pages[0].content.strokes[0].points[0].x == 300)
        expect(try snapshot(a!).pages[0].content.strokes[0].points[0].x == 400)
        print("PASS concurrent local/cloud edits preserve both notebooks")
        try edit(a!, x: 500); cloud.loseNextCommitReply = true
        do { try await a!.synchronize(); preconditionFailure("Expected interrupted acknowledgement") } catch is URLError { }
        let pending = try JSONDecoder().decode(SyncJournal.self, from: Data(contentsOf: a!.root.appendingPathComponent("sync-state.json"))).pending!
        let count = cloud.receipts.count
        a!.stop(); a = nil
        a = try DesktopSyncEngine(account: account, origin: "https://api.mynotes-test.invalid", rootOverride: root.appendingPathComponent("a/\(account.id)"), api: cloud.call)
        try await a!.synchronize()
        precondition(cloud.receipts.count == count && cloud.receipts[pending.operationId] != nil)
        expect(try a!.isClean())
        print("PASS pending operation survives restart and lost acknowledgement is not duplicated")
        let duplicateID = UUID().uuidString.lowercased()
        _ = try CloudCodec.apply(document, id: duplicateID, context: a!.container.mainContext, directory: a!.directory)
        let values = try a!.container.mainContext.fetch(FetchDescriptor<Notebook>())
        let originalPage = values.first { $0.id.uuidString.lowercased() == id }!.pages[0]
        let duplicatePage = values.first { $0.id.uuidString.lowercased() == duplicateID }!.pages[0]
        precondition(originalPage.id != duplicatePage.id && originalPage.drawingFileName != duplicatePage.drawingFileName && duplicatePage.cloudPageID == pageID)
        print("PASS imported notebooks with shared page IDs cannot overwrite each other's local files")
        let valid = URL(string: "mynotes://auth/callback?state=one&code=two")!
        expect(try CloudSession.callbackCode(valid, expectedState: "one") == "two")
        for url in ["mynotes://auth/callback?state=wrong&code=two", "mynotes://elsewhere/callback?state=one&code=two", "mynotes://auth/callback?state=one&state=one&code=two"] {
            do { _ = try CloudSession.callbackCode(URL(string: url)!, expectedState: "one"); preconditionFailure("Invalid callback accepted") } catch CloudError.invalidCallback { }
        }
        print("PASS native OAuth callback rejects incorrect state, destination and duplicate parameters")
        let legacy = try ModelContainer(for: Notebook.self, Page.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let source = Notebook(title: "Legacy source"), sourcePage = Page(text: "Preserve original", drawingFileName: "source.drawing.json", hasDrawingContent: true)
        sourcePage.notebook = source; source.pages = [sourcePage]; legacy.mainContext.insert(source); try legacy.mainContext.save()
        let sourceDirectory = root.appendingPathComponent("legacy")
        try MacDrawingStorage.write([stroke], name: "source.drawing.json", directory: sourceDirectory)
        let originalBytes = try Data(contentsOf: sourceDirectory.appendingPathComponent("source.drawing.json"))
        try await b.migrateLegacy(from: legacy, directory: sourceDirectory)
        let migratedCount = cloud.receipts.count
        try await b.migrateLegacy(from: legacy, directory: sourceDirectory)
        expect(cloud.receipts.count == migratedCount)
        expect(try Data(contentsOf: sourceDirectory.appendingPathComponent("source.drawing.json")) == originalBytes)
        expect(sourcePage.cloudPageID == nil && source.pages[0].drawingFileName == "source.drawing.json")
        expect(try snapshot(b, source.id.uuidString.lowercased()).pages[0].content.strokes[0].id == strokeID.uuidString.lowercased())
        print("PASS legacy migration uploads once and leaves source models and drawing bytes intact")
        try await a!.synchronize(); try await b.synchronize()
        try edit(b, x: 600)
        let removed = try a!.container.mainContext.fetch(FetchDescriptor<Notebook>()).first { $0.id.uuidString.lowercased() == id }!
        a!.container.mainContext.delete(removed); try a!.container.mainContext.save(); try await a!.synchronize()
        expect(cloud.records[id]?.deleted == true)
        try await b.synchronize()
        let recovered = try b.container.mainContext.fetch(FetchDescriptor<Notebook>())
        expect(!recovered.contains { $0.id.uuidString.lowercased() == id })
        expect(try recovered.contains { notebook in try CloudCodec.snapshot(notebook, directory: b.directory).pages.contains { $0.content.strokes.first?.points.first?.x == 600 } })
        expect(cloud.records[id]?.deleted == true)
        print("PASS edits to a deleted notebook become recovered content without resurrecting its tombstone")
        do {
            _ = try DesktopSyncEngine(account: CloudAccount(id: UUID().uuidString.lowercased(), email: "other@example.com", isAdmin: false), origin: "https://api.mynotes-test.invalid", rootOverride: b.root, api: cloud.call)
            preconditionFailure("Another account opened the existing journal")
        } catch CloudError.message { }
        print("PASS account journal rejects a different account identity")
        a?.stop(); b.stop()
    }
}
