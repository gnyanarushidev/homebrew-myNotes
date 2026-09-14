import AppKit
import SwiftData
import SwiftUI

@main struct TransferRegression {
    @MainActor static func main() throws {
        let container = try ModelContainer(for: Notebook.self, Page.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let notebook = Notebook(id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, title: "Mac drawing transfer", template: .grid, pageColor: .cream)
        let page = Page(id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!, text: "Original local notes", template: .dots, pageSize: .a4Portrait, pageColor: .white, hasDrawingContent: true, inheritsNotebookStyle: false)
        page.notebook = notebook; notebook.pages = [page]; container.mainContext.insert(notebook)
        let stroke = MacStroke(id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!, points: [CGPoint(x: 120, y: 160), CGPoint(x: 240, y: 190), CGPoint(x: 210, y: 310), CGPoint(x: 90, y: 280), CGPoint(x: 120, y: 160)].map(MacPoint.init), tool: .rectangle, style: .init(red: 0.123456789, green: 0.4, blue: 0.8, alpha: 0.7, width: 4.5, opacity: 0.6))
        let data = try NotebookWebExporter.data(for: notebook, snapshots: [page.id: [stroke]])
        let archive = try JSONDecoder().decode(MacNotebookArchive.self, from: data)
        let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("web-app/tests/fixtures/mac-notebook.json")
        let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as! NSDictionary
        let actual = try JSONSerialization.jsonObject(with: data) as! NSDictionary
        precondition(actual == expected, "The browser fixture must match the actual Swift exporter")
        precondition(archive.notebook.pages[0].strokes == [stroke], "Points/styles/IDs must survive export exactly")
        precondition(archive.notebook.id == notebook.id && archive.notebook.pages[0].id == page.id)
        precondition(archive.notebook.pages[0].text == page.text && archive.notebook.pages[0].size == .a4Portrait)
        precondition(!archive.notebook.pages[0].inheritsStyle && archive.notebook.template == .grid)
        precondition(page.drawingFileName == nil && page.hasDrawingContent, "Export must not modify original storage")
        print("PASS: native path, full-precision style, IDs, text, order, paper, and source preservation")

        // This is also consumed by browser tests: actual Swift Codable output.
        if CommandLine.arguments.contains("--fixture") { print(String(decoding: data, as: UTF8.self)) }
        do {
            _ = try NotebookWebExporter.data(for: notebook)
            preconditionFailure("Missing ink must fail instead of exporting a blank page")
        } catch NotebookTransferError.unreadableDrawing { print("PASS: missing drawing rejects export") }
        page.drawingFileName = "unreadable.drawing.json"
        do {
            _ = try NotebookWebExporter.data(for: notebook, snapshots: [page.id: []], load: { _ in throw NotebookTransferError.invalidFile })
            preconditionFailure("Unreadable drawing must fail")
        } catch NotebookTransferError.invalidFile { print("PASS: unreadable drawing rejects export even with an empty legacy canvas snapshot") }
        let legacy = Data("[{\"id\":\"33333333-3333-4333-8333-333333333333\",\"points\":[{\"x\":1,\"y\":2},{\"x\":3,\"y\":4}],\"tool\":\"highlighter\"}]".utf8)
        let decoded = try JSONDecoder().decode([MacStroke].self, from: legacy)
        precondition(decoded[0].style.width == 14 && decoded[0].style.opacity == 0.35)
        print("PASS: legacy drawing styles decode for export")

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        var pixel = [255, 0, 0, 255]
        for x in 0..<2 { for y in 0..<2 { bitmap.setPixel(&pixel, atX: x, y: y) } }
        let earlierPage = Page(createdAt: Date(timeIntervalSince1970: 0), text: "Earlier page", imageData: bitmap.representation(using: .png, properties: [:]))
        earlierPage.notebook = notebook; notebook.pages.append(earlierPage); page.drawingFileName = nil
        let withImage = try JSONDecoder().decode(MacNotebookArchive.self, from: NotebookWebExporter.data(for: notebook, snapshots: [page.id: [stroke]]))
        precondition(withImage.notebook.pages.map(\.id) == [earlierPage.id, page.id], "Export order must follow native creation order")
        let exportedImage = withImage.notebook.pages[0].image!
        let roundTripImage = NSBitmapImageRep(data: Data(base64Encoded: exportedImage.data)!)!
        precondition(exportedImage.mimeType == "image/png" && roundTripImage.pixelsWide == 2 && roundTripImage.pixelsHigh == 2)
        precondition(roundTripImage.colorAt(x: 0, y: 0)!.usingColorSpace(.sRGB)!.redComponent > 0.99)
        print("PASS: out-of-order pages and page images preserve order and image content")
    }
}
