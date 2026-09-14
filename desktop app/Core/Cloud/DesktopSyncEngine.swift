#if os(macOS)
import Foundation
import SwiftData
import SwiftUI

struct SyncBaseline: Codable { var revision: Int; var localHash: String; var manifest: CloudManifest?; var pageHashes: [String: String] }
struct PendingCloudOperation: Codable { let id: String; let operationId: String; let baseRevision: Int; let document: LocalCloudDocument?; let deleted: Bool }
struct SyncJournal: Codable {
    var accountId: String
    var cursor = 0
    var baselines: [String: SyncBaseline] = [:]
    var pending: PendingCloudOperation?
    var migrated: [String] = []
}
struct UploadDescriptor: Codable { let id: String; let sha256: String; let bytes: Int; let kind: String }
struct UploadPreparation: Codable { let operationId: String; let files: [UploadDescriptor] }
struct UploadTicket: Decodable { let id: String; let key: String; let sha256: String; let bytes: Int; let kind: String; let url: String; let headers: [String: String] }
struct UploadTickets: Decodable { let files: [UploadTicket] }
struct FinalizedFiles: Codable { let files: [CloudFile] }
struct CloudCommit: Codable { let id: String; let operationId: String; let baseRevision: Int; let manifest: CloudManifest; let deleted: Bool; let keepBoth: Bool }
struct CloudUsage: Decodable { let storedBytes: Int64 }

@MainActor final class DesktopSyncEngine: ObservableObject {
    let account: CloudAccount
    let container: ModelContainer
    let root: URL
    let directory: URL
    @Published var status = "Opening account…"
    @Published var lastError = ""
    @Published var running = false
    @Published var availableOffline = false
    @Published var storageBytes: Int64?
    private let api: (String, String, Data?) async throws -> Data
    private var journal: SyncJournal
    private var timer: Task<Void, Never>?
    private var flight: Task<Void, Error>?
    private var stopped = false
    private var journalURL: URL { root.appendingPathComponent("sync-state.json") }
    private var migrationURL: URL { root.deletingLastPathComponent().appendingPathComponent("\(account.id).migration.json") }

    static func accountsRoot(origin: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("MyNotes/Accounts/\(CloudCodec.hash(Data(origin.utf8)))", isDirectory: true)
    }
    static func cleanupMarkedAccounts(origin: String) throws {
        let base = accountsRoot(origin: origin)
        guard FileManager.default.fileExists(atPath: base.path) else { return }
        for marker in try FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) where marker.pathExtension == "cleanup" {
            let target = marker.deletingPathExtension()
            guard UUID(uuidString: target.lastPathComponent) != nil else { continue }
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.removeItem(at: marker)
        }
    }
    init(account: CloudAccount, origin: String, rootOverride: URL? = nil, api: @escaping (String, String, Data?) async throws -> Data) throws {
        guard UUID(uuidString: account.id) != nil else { throw CloudError.invalidDocument }
        self.account = account; self.api = api
        root = rootOverride ?? Self.accountsRoot(origin: origin).appendingPathComponent(account.id.lowercased(), isDirectory: true)
        directory = root.appendingPathComponent("Drawings", isDirectory: true)
        let cleanup = root.appendingPathExtension("cleanup")
        if FileManager.default.fileExists(atPath: cleanup.path) {
            if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
            try FileManager.default.removeItem(at: cleanup)
        }
        container = try DataController.accountContainer(at: root)
        container.mainContext.autosaveEnabled = false
        let stateURL = root.appendingPathComponent("sync-state.json")
        if FileManager.default.fileExists(atPath: stateURL.path) {
            journal = try JSONDecoder().decode(SyncJournal.self, from: Data(contentsOf: stateURL))
            guard journal.accountId == account.id else { throw CloudError.message("The local store belongs to a different account.") }
        } else { journal = SyncJournal(accountId: account.id) }
        let migrationIndex = root.deletingLastPathComponent().appendingPathComponent("\(account.id).migration.json")
        if FileManager.default.fileExists(atPath: migrationIndex.path) {
            journal.migrated = Array(Set(journal.migrated + (try JSONDecoder().decode([String].self, from: Data(contentsOf: migrationIndex)))))
        }
        FileStore.accountRoot = root
        try persist()
    }
    private func persist() throws { try CloudCodec.encode(journal).write(to: journalURL, options: .atomic) }
    private func checkActive() throws { if stopped || Task.isCancelled { throw CancellationError() } }
    private func isEditing(_ id: String) -> Bool {
        guard let uuid = UUID(uuidString: id) else { return false }
        let request = MacNotebookExportRequest(notebookID: uuid)
        NotificationCenter.default.post(name: .captureMacNotebookExport, object: request)
        return request.isEditing
    }
    func start() {
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await self?.synchronize() } catch { }
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }
    func stop() { stopped = true; timer?.cancel(); timer = nil; flight?.cancel() }
    func markForCleanup() {
        // A durable marker permits cleanup after SwiftData and NSViews release
        // the store; it is consumed before this account is ever reopened.
        try? Data().write(to: root.appendingPathExtension("cleanup"), options: .atomic)
    }
    private func notebooks() throws -> [Notebook] { try container.mainContext.fetch(FetchDescriptor<Notebook>()) }
    private func local(_ id: String) throws -> LocalCloudDocument? {
        guard let notebook = try notebooks().first(where: { $0.id.uuidString.lowercased() == id }) else { return nil }
        return try CloudCodec.snapshot(notebook, directory: directory)
    }
    private func digest(_ document: LocalCloudDocument) throws -> String { CloudCodec.hash(try CloudCodec.encode(document)) }
    private func pageHashes(_ document: LocalCloudDocument) throws -> [String: String] {
        var hashes: [String: String] = [:]
        for page in document.pages { hashes[page.id] = CloudCodec.hash(try CloudCodec.encode(page.content)); if let image = page.image { hashes[page.id + ":image"] = CloudCodec.hash(image) } }
        return hashes
    }
    func isClean() throws -> Bool {
        if journal.pending != nil { return false }
        if FileStore.saveFailures.keys.contains(where: { $0.hasPrefix(directory.path + "/") }) { return false }
        let values = try notebooks()
        if Set(values.map { $0.id.uuidString.lowercased() }) != Set(journal.baselines.keys) { return false }
        for notebook in values { if isEditing(notebook.id.uuidString.lowercased()) { return false }; if try digest(CloudCodec.snapshot(notebook, directory: directory)) != journal.baselines[notebook.id.uuidString.lowercased()]?.localHash { return false } }
        return true
    }
    func synchronize() async throws {
        if let flight { return try await flight.value }
        guard !stopped else { return }
        let task = Task { @MainActor in
            self.running = true; self.lastError = ""; self.status = "Synchronizing…"
            defer { self.running = false }
            do { let complete = try await self.work(); self.status = complete ? "Synced · \(Date().formatted(date: .omitted, time: .shortened))" : "Saved locally · waiting for the current edit"; if complete { self.availableOffline = true } }
            catch {
                if !(error is CancellationError) { self.lastError = error.localizedDescription; self.status = error is URLError ? "Offline · local changes retained" : "Sync needs attention" }
                throw error
            }
        }
        flight = task; defer { flight = nil }; try await task.value
    }
    private func work() async throws -> Bool {
        try checkActive()
        if let issue = FileStore.saveFailures.first(where: { $0.key.hasPrefix(directory.path + "/") }) { throw CloudError.message("A local save failed: \(issue.value). Resolve local storage before synchronizing.") }
        try container.mainContext.save()
        if let pending = journal.pending { if isEditing(pending.id) { return false }; try await send(pending) }
        for notebook in try notebooks() {
            try checkActive()
            let id = notebook.id.uuidString.lowercased(), document = try CloudCodec.snapshot(notebook, directory: directory)
            if isEditing(id) { return false }
            if try digest(document) == journal.baselines[id]?.localHash { continue }
            let pending = PendingCloudOperation(id: id, operationId: UUID().uuidString.lowercased(), baseRevision: journal.baselines[id]?.revision ?? 0, document: document, deleted: false)
            journal.pending = pending; try persist(); try await send(pending)
        }
        let ids = Set(try notebooks().map { $0.id.uuidString.lowercased() })
        for id in Array(journal.baselines.keys) where !ids.contains(id) {
            let pending = PendingCloudOperation(id: id, operationId: UUID().uuidString.lowercased(), baseRevision: journal.baselines[id]!.revision, document: nil, deleted: true)
            journal.pending = pending; try persist(); try await send(pending)
        }
        var more = true
        while more {
            try checkActive()
            let changes = try JSONDecoder().decode(CloudChanges.self, from: await api("/api/v1/sync?cursor=\(journal.cursor)", "GET", nil))
            for record in changes.records {
                try checkActive()
                if isEditing(record.id) { return false }
                let current = try local(record.id)
                if let current, try digest(current) != journal.baselines[record.id]?.localHash { continue }
                if record.deleted {
                    if let notebook = try notebooks().first(where: { $0.id.uuidString.lowercased() == record.id }) { container.mainContext.delete(notebook); try container.mainContext.save() }
                    journal.baselines.removeValue(forKey: record.id)
                } else if record.revision != journal.baselines[record.id]?.revision || current == nil {
                    let download = try await fetch(record.id)
                    try checkActive()
                    // Editing may have continued during the download.
                    if let now = try local(record.id), try digest(now) != journal.baselines[record.id]?.localHash { continue }
                    try adopt(download.document, record: download.record)
                }
            }
            journal.cursor = changes.cursor; try persist(); more = changes.more
        }
        // Cleanup is restartable and only touches server-verified unreferenced objects.
        _ = try? await api("/api/v1/sync/cleanup", "POST", Data("{}".utf8))
        if let usage = try? await api("/api/v1/sync/usage", "GET", nil), let value = try? JSONDecoder().decode(CloudUsage.self, from: usage) { storageBytes = value.storedBytes }
        let clean = try isClean()
        if clean { try CloudCodec.encode(journal.migrated).write(to: migrationURL, options: .atomic) }
        return clean
    }
    private func upload(_ data: Data, kind: String, operation: String) async throws -> CloudFile {
        let descriptor = UploadDescriptor(id: UUID().uuidString.lowercased(), sha256: CloudCodec.hash(data), bytes: data.count, kind: kind)
        let response = try JSONDecoder().decode(UploadTickets.self, from: await api("/api/v1/sync/uploads", "POST", CloudCodec.encode(UploadPreparation(operationId: operation, files: [descriptor]))))
        guard let ticket = response.files.first, let url = URL(string: ticket.url) else { throw CloudError.invalidDocument }
        var request = URLRequest(url: url); request.httpMethod = "PUT"; request.timeoutInterval = 120
        for (key, value) in ticket.headers { request.setValue(value, forHTTPHeaderField: key) }
        let (_, raw) = try await URLSession.shared.upload(for: request, from: data)
        guard let status = (raw as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else { throw CloudError.message("A page upload failed. The pending snapshot will be retried.") }
        try checkActive()
        let staged = CloudFile(key: ticket.key, sha256: ticket.sha256, bytes: ticket.bytes, kind: ticket.kind)
        let finalized = try JSONDecoder().decode(FinalizedFiles.self, from: await api("/api/v1/sync/files", "POST", CloudCodec.encode(FinalizedFiles(files: [staged]))))
        guard let file = finalized.files.first else { throw CloudError.invalidDocument }; return file
    }
    private func prepare(_ pending: PendingCloudOperation, forceUpload: Bool = false) async throws -> CloudManifest {
        guard let document = pending.document else { return journal.baselines[pending.id]?.manifest ?? CloudManifest(title: "Deleted notebook", template: "blank", color: "white", pages: []) }
        var manifest = CloudManifest(title: document.title, template: document.template, color: document.color, pages: [])
        let baseline = journal.baselines[pending.id]
        for (index, page) in document.pages.enumerated() {
            try checkActive(); status = "Syncing page \(index + 1) of \(document.pages.count)…"
            let old = baseline?.manifest?.pages.first { $0.id == page.id }, data = try CloudCodec.encode(page.content)
            let content: CloudFile
            if !forceUpload, let old, baseline?.pageHashes[page.id] == CloudCodec.hash(data) { content = old.content }
            else { content = try await upload(data, kind: "page", operation: pending.operationId) }
            var image: CloudFile?
            if let bytes = page.image {
                if !forceUpload, let previous = old?.image, baseline?.pageHashes[page.id + ":image"] == CloudCodec.hash(bytes) { image = previous }
                else { image = try await upload(bytes, kind: page.imageKind ?? "image/png", operation: pending.operationId) }
            }
            manifest.pages.append(CloudPage(id: page.id, size: page.size, template: page.template, color: page.color, inheritsStyle: page.inheritsStyle, content: content, image: image))
        }
        return manifest
    }
    private func send(_ pending: PendingCloudOperation) async throws {
        var manifest = try await prepare(pending)
        func commit() async throws -> CloudReceipt {
            try JSONDecoder().decode(CloudReceipt.self, from: await api("/api/v1/sync/commit", "POST", CloudCodec.encode(CloudCommit(id: pending.id, operationId: pending.operationId, baseRevision: pending.baseRevision, manifest: manifest, deleted: pending.deleted, keepBoth: true))))
        }
        let receipt: CloudReceipt
        do { receipt = try await commit() }
        catch CloudError.http(let code, _) where code == 410 { manifest = try await prepare(pending, forceUpload: true); receipt = try await commit() }
        catch CloudError.http(let code, _) where code == 409 && pending.deleted {
            let remote = try await fetch(pending.id); try checkActive(); try adopt(remote.document, record: remote.record)
            journal.pending = nil; try persist(); status = "A newer cloud notebook was restored instead of deleted."; return
        }
        try checkActive()
        if receipt.deleted { journal.baselines.removeValue(forKey: pending.id) }
        else if receipt.conflict {
            let copy = try await fetch(receipt.id)
            let originalRecord = try JSONDecoder().decode(CloudNotebook.self, from: await api("/api/v1/sync/notebooks/\(pending.id)", "GET", nil))
            let original = originalRecord.deleted ? nil : try await fetch(pending.id)
            try checkActive()
            if isEditing(pending.id) { throw CloudError.message("Finish the current drawing gesture before resolving the cloud conflict. Both versions are retained.") }
            // A partial prior resolution may already have created an edited local copy.
            var retained = try local(receipt.id)
            if retained == nil {
                retained = try local(pending.id) ?? pending.document!
                retained!.title = copy.document.title
                retained!.pages = retained!.pages.map { page in var next = page; next.id = CloudCodec.stableID("\(receipt.id):\(page.id.lowercased())"); return next }
            }
            _ = try CloudCodec.apply(retained!, id: receipt.id, context: container.mainContext, directory: directory)
            journal.baselines[receipt.id] = SyncBaseline(revision: copy.record.revision, localHash: try digest(copy.document), manifest: copy.record.manifest, pageHashes: try pageHashes(copy.document))
            if let original { try adopt(original.document, record: original.record) }
            else {
                if let local = try notebooks().first(where: { $0.id.uuidString.lowercased() == pending.id }) { container.mainContext.delete(local); try container.mainContext.save() }
                journal.baselines.removeValue(forKey: pending.id)
            }
            status = "Conflict copy preserved in your library."
        } else if let snapshot = pending.document {
            let latest = try JSONDecoder().decode(CloudNotebook.self, from: await api("/api/v1/sync/notebooks/\(receipt.id)", "GET", nil))
            let sameRevision = latest.revision == receipt.revision
            journal.baselines[pending.id] = SyncBaseline(revision: receipt.revision, localHash: try digest(snapshot), manifest: sameRevision ? latest.manifest : nil, pageHashes: sameRevision ? try pageHashes(snapshot) : [:])
        }
        journal.pending = nil; try persist()
    }
    private func bytes(_ file: CloudFile, urls: [String: String]) async throws -> Data {
        guard let value = urls[file.key], let url = URL(string: value) else { throw CloudError.invalidDocument }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count == file.bytes, CloudCodec.hash(data) == file.sha256 else { throw CloudError.message("Downloaded drawing integrity check failed. Retry synchronization.") }
        try checkActive(); return data
    }
    private func fetch(_ id: String) async throws -> (record: CloudNotebook, document: LocalCloudDocument) {
        let result = try JSONDecoder().decode(CloudDownloads.self, from: await api("/api/v1/sync/notebooks/\(id)?downloads=1", "GET", nil))
        guard result.record.manifest.pages.count <= 300, result.record.manifest.pages.reduce(0, { $0 + $1.content.bytes + ($1.image?.bytes ?? 0) }) <= 128_000_000 else { throw CloudError.message("This notebook exceeds the initial 128 MB download limit.") }
        var pages: [LocalCloudPage] = []
        for page in result.record.manifest.pages {
            let content = try JSONDecoder().decode(SharedPageContent.self, from: await bytes(page.content, urls: result.urls))
            guard content.version == 1, content.strokes.count <= 20_000, content.text.count <= 100_000 else { throw CloudError.invalidDocument }
            let image = try await page.image.mapAsync { try await self.bytes($0, urls: result.urls) }
            pages.append(LocalCloudPage(id: page.id, size: page.size, template: page.template, color: page.color, inheritsStyle: page.inheritsStyle, content: content, image: image, imageKind: page.image?.kind))
        }
        return (result.record, LocalCloudDocument(title: result.record.manifest.title, template: result.record.manifest.template, color: result.record.manifest.color, pages: pages))
    }
    private func adopt(_ document: LocalCloudDocument, record: CloudNotebook) throws {
        let notebook = try CloudCodec.apply(document, id: record.id, context: container.mainContext, directory: directory)
        let normalized = try CloudCodec.snapshot(notebook, directory: directory)
        journal.baselines[record.id] = SyncBaseline(revision: record.revision, localHash: try digest(normalized), manifest: record.manifest, pageHashes: try pageHashes(normalized))
    }
    func migrateLegacy(from legacyOverride: ModelContainer? = nil, directory sourceDirectory: URL? = nil) async throws {
        guard !running else { throw CloudError.message("Wait for the current sync to finish before importing local notebooks.") }
        let legacy = try legacyOverride ?? DataController.legacyContainer()
        let claimURL = root.deletingLastPathComponent().appendingPathComponent("legacy-owner.json")
        if legacyOverride == nil {
            if FileManager.default.fileExists(atPath: claimURL.path) {
                guard try JSONDecoder().decode(String.self, from: Data(contentsOf: claimURL)) == account.id else { throw CloudError.message("These legacy notebooks have already been associated with another account on this Mac.") }
            } else { try CloudCodec.encode(account.id).write(to: claimURL, options: .atomic) }
        }
        for source in try legacy.mainContext.fetch(FetchDescriptor<Notebook>()) {
            let sourceID = source.id.uuidString.lowercased()
            if journal.migrated.contains(sourceID) { continue }
            var document = try CloudCodec.snapshot(source, directory: sourceDirectory ?? FileStore.legacyDrawingsDirectory)
            var destination = sourceID
            if let existing = try local(sourceID), try digest(existing) != digest(document) {
                destination = CloudCodec.stableID("\(account.id):legacy:\(sourceID):\(try digest(document))")
                document.title = "\(document.title.prefix(96)) (local import)"
                document.pages = document.pages.map { page in var next = page; next.id = CloudCodec.stableID("\(destination):\(page.id)"); return next }
            }
            _ = try CloudCodec.apply(document, id: destination, context: container.mainContext, directory: directory)
            journal.migrated.append(sourceID); try persist()
        }
        try await synchronize()
    }
}
private extension Optional {
    func mapAsync<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        switch self { case .some(let value): return try await transform(value); case .none: return nil }
    }
}
#endif
