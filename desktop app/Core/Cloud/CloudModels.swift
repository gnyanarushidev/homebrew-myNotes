#if os(macOS)
import Foundation
import CryptoKit
import SwiftData
import AppKit

struct CloudAccount: Codable, Equatable { let id: String; let email: String; let isAdmin: Bool }
struct CloudConfiguration: Codable { let supabaseUrl: String; let publishableKey: String }
struct CloudFile: Codable, Equatable { var key: String; let sha256: String; let bytes: Int; let kind: String }
struct CloudPage: Codable { var id: String; let size: String; let template: String; let color: String; let inheritsStyle: Bool; var content: CloudFile; var image: CloudFile? }
struct CloudManifest: Codable { var version = 1; var title: String; let template: String; let color: String; var pages: [CloudPage] }
struct CloudNotebook: Codable { let id: String; let manifest: CloudManifest; let revision: Int; let change_seq: Int; let deleted: Bool; let updated_at: String; let created_at: String; let mutation_id: String }
struct CloudDownloads: Codable { let record: CloudNotebook; let urls: [String: String] }
struct CloudChanges: Codable { let records: [CloudNotebook]; let cursor: Int; let more: Bool }
struct CloudReceipt: Codable { let id: String; let revision: Int; let sequence: Int; let conflict: Bool; let deleted: Bool }
struct CloudRGBA: Codable, Equatable { let red: Double; let green: Double; let blue: Double; let alpha: Double }
struct SharedStroke: Codable, Equatable {
    let id: String; let tool: String; let points: [MacPoint]; let color: String
    let width: Double; let opacity: Double; let geometry: String?; let rgba: CloudRGBA?
    init(_ stroke: MacStroke) {
        id = stroke.id.uuidString.lowercased(); tool = stroke.tool.rawValue; points = stroke.points
        let s = stroke.style
        color = String(format: "#%02x%02x%02x", Int((s.red * 255).rounded()), Int((s.green * 255).rounded()), Int((s.blue * 255).rounded()))
        width = s.width; opacity = s.opacity; geometry = "polyline"
        rgba = CloudRGBA(red: s.red, green: s.green, blue: s.blue, alpha: s.alpha)
    }
    func native() throws -> MacStroke {
        guard let uuid = UUID(uuidString: id), let tool = MacDrawingTool(rawValue: tool), tool != .eraser, tool != .lasso,
              !points.isEmpty, points.count <= 50_000, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              width.isFinite, (0.1...100).contains(width), opacity.isFinite, (0.01...1).contains(opacity) else { throw CloudError.invalidDocument }
        let rgb: CloudRGBA
        if let rgba { rgb = rgba }
        else {
            guard color.count == 7, color.first == "#", let hex = UInt32(color.dropFirst(), radix: 16) else { throw CloudError.invalidDocument }
            rgb = CloudRGBA(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
        }
        guard [rgb.red, rgb.green, rgb.blue, rgb.alpha].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw CloudError.invalidDocument }
        var path = points
        if geometry != "polyline" {
            let a = points.first!.cgPoint, b = points.last!.cgPoint
            switch tool {
            case .rectangle: path = [a, CGPoint(x: b.x, y: a.y), b, CGPoint(x: a.x, y: b.y), a].map(MacPoint.init)
            case .circle: path = (0...64).map { i in MacPoint(CGPoint(x: (a.x + b.x) / 2 + abs(b.x - a.x) / 2 * cos(Double(i) * .pi / 32), y: (a.y + b.y) / 2 + abs(b.y - a.y) / 2 * sin(Double(i) * .pi / 32))) }
            case .line: path = [MacPoint(a), MacPoint(b)]
            case .arrow:
                let angle = atan2(b.y - a.y, b.x - a.x)
                path = [a, b, CGPoint(x: b.x - 14 * cos(angle - .pi / 6), y: b.y - 14 * sin(angle - .pi / 6)), b, CGPoint(x: b.x - 14 * cos(angle + .pi / 6), y: b.y - 14 * sin(angle + .pi / 6))].map(MacPoint.init)
            default: break
            }
        }
        return MacStroke(id: uuid, points: path, tool: tool, style: MacStrokeStyle(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: rgb.alpha, width: width, opacity: opacity))
    }
}
struct SharedPageContent: Codable, Equatable { var version = 1; let text: String; let strokes: [SharedStroke] }
struct LocalCloudPage: Codable, Equatable { var id: String; let size: String; let template: String; let color: String; let inheritsStyle: Bool; let content: SharedPageContent; let image: Data?; let imageKind: String? }
struct LocalCloudDocument: Codable, Equatable { var title: String; let template: String; let color: String; var pages: [LocalCloudPage] }
enum CloudError: LocalizedError {
    case message(String), http(Int, String), invalidDocument, invalidCallback, signedOut
    var errorDescription: String? {
        switch self { case .message(let m), .http(_, let m): return m
        case .invalidDocument: return "The notebook or drawing document is invalid. Local work has been retained."
        case .invalidCallback: return "The sign-in callback is invalid or no longer pending."
        case .signedOut: return "Sign in to continue synchronizing." }
    }
}
enum CloudCodec {
    static func encode<T: Encodable>(_ value: T) throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value) }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func stableID(_ string: String) -> String {
        var bytes = Array(SHA256.hash(data: Data(string.utf8)).prefix(16)); bytes[6] = (bytes[6] & 15) | 0x50; bytes[8] = (bytes[8] & 63) | 0x80
        let h = bytes.map { String(format: "%02x", $0) }.joined()
        let parts = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { range in String(h[h.index(h.startIndex, offsetBy: range.lowerBound)..<h.index(h.startIndex, offsetBy: range.upperBound)]) }
        return parts.joined(separator: "-")
    }
    @MainActor static func snapshot(_ notebook: Notebook, directory: URL) throws -> LocalCloudDocument {
        guard notebook.title.utf16.count <= 120 else { throw CloudError.message("Use a notebook title of at most 120 characters before synchronizing.") }
        var totalBytes = 0
        let pages = try notebook.pages.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }.map { page in
            var name = page.drawingFileName
            // Recover an atomic first drawing write whose model save was interrupted.
            let fallback = "\(page.id.uuidString).drawing.json"
            if name == nil, FileManager.default.fileExists(atPath: directory.appendingPathComponent(fallback).path) { name = fallback }
            let strokes = try name.map { try MacDrawingStorage.read(from: $0, directory: directory) } ?? []
            if name == nil && page.hasDrawingContent { throw NotebookTransferError.unreadableDrawing(page.id.uuidString) }
            guard page.text.utf16.count <= 100_000, strokes.count <= 20_000, Set(strokes.map(\.id)).count == strokes.count else { throw CloudError.invalidDocument }
            for stroke in strokes {
                let style = stroke.style
                guard !stroke.points.isEmpty, stroke.points.count <= 50_000, stroke.tool != .eraser, stroke.tool != .lasso,
                      stroke.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
                      [style.red, style.green, style.blue, style.alpha].allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                      style.width.isFinite, (0.1...100).contains(style.width), style.opacity.isFinite, (0.01...1).contains(style.opacity) else { throw CloudError.invalidDocument }
            }
            var png: Data?
            var imageKind: String?
            if let image = page.imageData {
                if image.prefix(8) == Data([137, 80, 78, 71, 13, 10, 26, 10]) { png = image; imageKind = "image/png" }
                else if image.prefix(3) == Data([255, 216, 255]) { png = image; imageKind = "image/jpeg" }
                else { guard let rep = NSBitmapImageRep(data: image), let data = rep.representation(using: .png, properties: [:]) else { throw NotebookTransferError.invalidImage }; png = data; imageKind = "image/png" }
            }
            let content = SharedPageContent(text: page.text, strokes: strokes.map(SharedStroke.init))
            let encoded = try encode(content); totalBytes += encoded.count + (png?.count ?? 0)
            guard encoded.count <= 16_000_000, (png?.count ?? 0) <= 8_000_000, totalBytes <= 128_000_000 else { throw CloudError.message("A notebook exceeds the initial 16 MB/page, 8 MB/image or 128 MB/notebook transfer limit.") }
            return LocalCloudPage(id: page.cloudPageID ?? page.id.uuidString.lowercased(), size: page.pageSize.rawValue, template: page.template.rawValue, color: page.pageColor.rawValue, inheritsStyle: page.inheritsNotebookStyle, content: content, image: png, imageKind: imageKind)
        }
        guard !pages.isEmpty, pages.count <= 300 else { throw CloudError.invalidDocument }
        return LocalCloudDocument(title: notebook.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Notebook" : notebook.title, template: notebook.template.rawValue, color: notebook.pageColor.rawValue, pages: pages)
    }
    @MainActor static func apply(_ document: LocalCloudDocument, id: String, context: ModelContext, directory: URL) throws -> Notebook {
        guard let uuid = UUID(uuidString: id), !document.pages.isEmpty, document.pages.count <= 300,
              Set(document.pages.map(\.id)).count == document.pages.count else { throw CloudError.invalidDocument }
        let all = try context.fetch(FetchDescriptor<Notebook>())
        let notebook = all.first { $0.id == uuid } ?? Notebook(id: uuid, title: document.title)
        // Validate and atomically write all files before changing visible metadata.
        var files: [String: String] = [:]
        for page in document.pages {
            guard UUID(uuidString: page.id) != nil, PageSize(rawValue: page.size) != nil, PageTemplate(rawValue: page.template) != nil, PageColor(rawValue: page.color) != nil else { throw CloudError.invalidDocument }
            let strokes = try page.content.strokes.map { try $0.native() }
            guard Set(strokes.map(\.id)).count == strokes.count else { throw CloudError.invalidDocument }
            let name = "\(id)-\(page.id)-\(hash(try encode(page.content))).drawing.json"
            try MacDrawingStorage.write(strokes, name: name, directory: directory); files[page.id] = name
        }
        if notebook.modelContext == nil { context.insert(notebook) }
        notebook.title = document.title; notebook.template = PageTemplate(rawValue: document.template) ?? .blank; notebook.pageColor = PageColor(rawValue: document.color) ?? .white
        let valid = Set(document.pages.map(\.id))
        for old in notebook.pages where !valid.contains(old.cloudPageID ?? old.id.uuidString.lowercased()) { context.delete(old) }
        let existingPages = try context.fetch(FetchDescriptor<Page>())
        var ordered: [Page] = []
        for (index, value) in document.pages.enumerated() {
            let page: Page
            if let existing = notebook.pages.first(where: { ($0.cloudPageID ?? $0.id.uuidString.lowercased()) == value.id }) { page = existing }
            else {
                var localID = UUID(uuidString: value.id)!
                if existingPages.contains(where: { $0.id == localID }) { localID = UUID(uuidString: stableID("\(id):\(value.id):local"))! }
                if existingPages.contains(where: { $0.id == localID }) { localID = UUID() }
                page = Page(id: localID)
            }
            page.cloudPageID = value.id
            page.createdAt = Date(timeIntervalSince1970: Double(index)); page.updatedAt = .now
            page.template = PageTemplate(rawValue: value.template)!; page.pageSize = PageSize(rawValue: value.size)!; page.pageColor = PageColor(rawValue: value.color)!
            page.inheritsNotebookStyle = value.inheritsStyle; page.text = value.content.text; page.imageData = value.image
            page.drawingFileName = files[value.id]; page.hasDrawingContent = !value.content.strokes.isEmpty; page.notebook = notebook; ordered.append(page)
        }
        notebook.pages = ordered; notebook.updatedAt = .now
        do { try context.save() } catch { context.rollback(); throw error }
        return notebook
    }
}
#endif
