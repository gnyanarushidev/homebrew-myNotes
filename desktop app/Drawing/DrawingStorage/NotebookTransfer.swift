#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NotebookJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data = Data()
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw NotebookTransferError.invalidFile }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

enum NotebookTransferError: LocalizedError {
    case invalidFile, unreadableDrawing(String), invalidImage, unsupportedContent, tooLarge
    var errorDescription: String? {
        switch self {
        case .invalidFile: return "This notebook file could not be read."
        case .unreadableDrawing(let name): return "The drawing \(name) is missing or unreadable. Restore it before exporting; no pages were discarded."
        case .invalidImage: return "A page image could not be decoded. The notebook was not exported."
        case .unsupportedContent: return "This notebook exceeds the web document limits or contains unsupported drawing values. Use a title of at most 120 characters and at most 300 pages."
        case .tooLarge: return "This notebook exceeds the current 2.9 MB web import limit. Export a smaller notebook until large-asset cloud transfer is available."
        }
    }
}

extension Notification.Name {
    static let captureMacNotebookExport = Notification.Name("MyNotes.captureMacNotebookExport")
}

@MainActor final class MacNotebookExportRequest {
    let notebookID: UUID
    var strokes: [UUID: [MacStroke]] = [:]
    init(notebookID: UUID) { self.notebookID = notebookID }
}

struct MacNotebookArchive: Codable {
    let format: String
    let version: Int
    let notebook: Content
    struct Content: Codable {
        let id: UUID
        let title: String
        let template: PageTemplate
        let color: PageColor
        let pages: [ExportPage]
    }
    struct ExportPage: Codable {
        let id: UUID
        let size: PageSize
        let template: PageTemplate
        let color: PageColor
        let inheritsStyle: Bool
        let text: String
        let strokes: [MacStroke]
        let image: ExportImage?
    }
    struct ExportImage: Codable {
        let mimeType: String
        let data: String
    }
}

@MainActor enum NotebookWebExporter {
    static func data(for notebook: Notebook, snapshots: [UUID: [MacStroke]] = [:], load: (String) throws -> [MacStroke] = MacDrawingStorage.loadForExport) throws -> Data {
        let title = notebook.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count <= 120, !notebook.pages.isEmpty, notebook.pages.count <= 300 else { throw NotebookTransferError.unsupportedContent }
        let pages = try notebook.pages.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }.map { page in
            let strokes: [MacStroke]
            if let name = page.drawingFileName {
                // The legacy canvas treats unreadable files as empty. Verify
                // the source even when a loaded canvas supplies an empty snapshot.
                let persisted = try load(name)
                strokes = snapshots[page.id] ?? persisted
            }
            else if let snapshot = snapshots[page.id] { strokes = snapshot }
            else if page.hasDrawingContent { throw NotebookTransferError.unreadableDrawing(page.id.uuidString) }
            else { strokes = [] }
            guard page.text.count <= 100_000, strokes.count <= 20_000, Set(strokes.map(\.id)).count == strokes.count else { throw NotebookTransferError.unsupportedContent }
            for stroke in strokes {
                let style = stroke.style
                guard stroke.tool != .eraser, stroke.tool != .lasso,
                      !stroke.points.isEmpty, stroke.points.count <= 50_000,
                      stroke.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 10_000 && abs($0.y) <= 10_000 }),
                      [style.red, style.green, style.blue, style.alpha].allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                      style.width.isFinite, (0.1...100).contains(style.width),
                      style.opacity.isFinite, (0.01...1).contains(style.opacity) else { throw NotebookTransferError.unsupportedContent }
            }
            var image: MacNotebookArchive.ExportImage?
            if let data = page.imageData {
                guard let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else { throw NotebookTransferError.invalidImage }
                image = .init(mimeType: "image/png", data: png.base64EncodedString())
            }
            return MacNotebookArchive.ExportPage(id: page.id, size: page.pageSize, template: page.template, color: page.pageColor, inheritsStyle: page.inheritsNotebookStyle, text: page.text, strokes: strokes, image: image)
        }
        let archive = MacNotebookArchive(format: "mynotes-mac", version: 1, notebook: .init(id: notebook.id, title: title.isEmpty ? "Untitled Notebook" : title, template: notebook.template, color: notebook.pageColor, pages: pages))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(archive)
        guard data.count <= 2_900_000 else { throw NotebookTransferError.tooLarge }
        return data
    }
}
#endif
