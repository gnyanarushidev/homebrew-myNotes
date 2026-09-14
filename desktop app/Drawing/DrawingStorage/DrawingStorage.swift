import Foundation
import PencilKit
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct PDFExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    
    var data: Data
    var pageCount: Int
    var pageSize: CGSize
    
    init(data: Data = Data(), pageCount: Int = 1, pageSize: CGSize = CGSize(width: 595, height: 842)) {
        self.data = data
        self.pageCount = pageCount
        self.pageSize = pageSize
    }
    
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        pageCount = 1
        pageSize = CGSize(width: 595, height: 842)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct PDFExportPage {
    let size: CGSize
    let color: PageColor
    let template: PageTemplate
#if os(iOS)
    let drawing: PKDrawing
#else
    let strokes: [MacStroke]
#endif
}

enum PDFExporter {
#if os(iOS)
    static func makePDF(
        from drawing: PKDrawing,
        pageSize: CGSize = CGSize(width: 595, height: 842),
        color: PageColor = .white,
        template: PageTemplate = .blank
    ) -> Data {
        makePDF(pages: [PDFExportPage(size: pageSize, color: color, template: template, drawing: drawing)])
    }

    static func makePDF(pages: [PDFExportPage]) -> Data {
        guard let firstPage = pages.first else { return Data() }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: firstPage.size))
        return renderer.pdfData { context in
            for page in pages {
                let pageBox = CGRect(origin: .zero, size: page.size)
                context.beginPage(withBounds: pageBox, pageInfo: [:])
                context.cgContext.saveGState()
                context.cgContext.clip(to: pageBox)
                drawBackground(for: page, in: context.cgContext)
                drawTemplate(for: page, in: context.cgContext)
                if !page.drawing.strokes.isEmpty {
                    // PencilKit coordinates already belong to this page, including blank margins.
                    page.drawing.image(from: pageBox, scale: 2).draw(in: pageBox)
                }
                context.cgContext.restoreGState()
            }
        }
    }
#else
    static func makePDF(pages: [PDFExportPage]) -> Data {
        guard let firstPage = pages.first else { return Data() }
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else { return Data() }
        var mediaBox = CGRect(origin: .zero, size: firstPage.size)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        for page in pages {
            var pageBox = CGRect(origin: .zero, size: page.size)
            let mediaBoxData = Data(bytes: &pageBox, count: MemoryLayout<CGRect>.size)
            context.beginPDFPage([
                kCGPDFContextMediaBox as String: mediaBoxData
            ] as CFDictionary)
            context.saveGState()
            context.translateBy(x: 0, y: page.size.height)
            context.scaleBy(x: 1, y: -1)

            drawBackground(for: page, in: context)
            drawTemplate(for: page, in: context)

            context.saveGState()
            context.clip(to: pageBox)
            drawStrokes(page.strokes, in: context)
            context.restoreGState()

            context.restoreGState()
            context.endPDFPage()
        }

        context.closePDF()
        return output as Data
    }
#endif

    private static func drawBackground(for page: PDFExportPage, in context: CGContext) {
        let color: CGColor
        switch page.color {
        case .white:
            color = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        case .cream:
            color = CGColor(srgbRed: 0.98, green: 0.96, blue: 0.88, alpha: 1)
        case .dark:
            color = CGColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1)
        }
        context.setFillColor(color)
        context.fill(CGRect(origin: .zero, size: page.size))
    }

    private static func drawTemplate(for page: PDFExportPage, in context: CGContext) {
        guard page.template != .blank else { return }
        let templateColor = page.color == .dark
            ? CGColor(srgbRed: 0.45, green: 0.65, blue: 1, alpha: 0.32)
            : CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 0.16)
        context.setStrokeColor(templateColor)
        context.setFillColor(templateColor)
        context.setLineWidth(0.7)

        switch page.template {
        case .ruled:
            var y: CGFloat = 36
            while y <= page.size.height {
                context.move(to: CGPoint(x: 0, y: y))
                context.addLine(to: CGPoint(x: page.size.width, y: y))
                context.strokePath()
                y += 32
            }
        case .grid:
            var x: CGFloat = 0
            while x <= page.size.width {
                context.move(to: CGPoint(x: x, y: 0))
                context.addLine(to: CGPoint(x: x, y: page.size.height))
                context.strokePath()
                x += 32
            }
            var y: CGFloat = 0
            while y <= page.size.height {
                context.move(to: CGPoint(x: 0, y: y))
                context.addLine(to: CGPoint(x: page.size.width, y: y))
                context.strokePath()
                y += 32
            }
        case .dots:
            var x: CGFloat = 16
            while x <= page.size.width {
                var y: CGFloat = 16
                while y <= page.size.height {
                    context.fillEllipse(in: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5))
                    y += 24
                }
                x += 24
            }
        case .blank:
            break
        }
    }

#if os(macOS)
    private static func drawStrokes(_ strokes: [MacStroke], in context: CGContext) {
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for stroke in strokes {
            guard let firstPoint = stroke.points.first, stroke.points.count > 1 else { continue }
            context.beginPath()
            context.move(to: firstPoint.cgPoint)
            for point in stroke.points.dropFirst() {
                context.addLine(to: point.cgPoint)
            }
            context.setStrokeColor(CGColor(
                srgbRed: CGFloat(stroke.style.red),
                green: CGFloat(stroke.style.green),
                blue: CGFloat(stroke.style.blue),
                alpha: CGFloat(stroke.style.alpha * stroke.style.opacity)
            ))
            context.setLineWidth(CGFloat(stroke.style.width))
            context.strokePath()
        }
    }
#endif
}

#if os(iOS)
extension Notification.Name {
    static let flushNotebookDrawings = Notification.Name("MyNotes.flushNotebookDrawings")
}

// Filled synchronously by loaded editors before the exporter reads other pages from disk.
@MainActor
final class NotebookDrawingExportRequest {
    let notebookID: UUID
    var drawings: [UUID: PKDrawing] = [:]

    init(notebookID: UUID) {
        self.notebookID = notebookID
    }
}
#endif

enum DrawingStorage {
    static func loadDrawing(from fileName: String) -> PKDrawing? {
        let url = urlForReading(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try PKDrawing(data: data)
        } catch {
            return nil
        }
    }

    @discardableResult
    static func saveDrawing(_ drawing: PKDrawing, to fileName: String) -> Bool {
        let url = FileStore.url(forDrawing: fileName)
        do {
            try drawing.dataRepresentation().write(to: url, options: .atomic)
            return true
        } catch {
            // Drawing save failure should not crash the editor session.
            return false
        }
    }

    static func deleteDrawing(named fileName: String) {
        let url = urlForReading(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    fileprivate static func urlForReading(_ fileName: String) -> URL {
        // FileStore's write URL creates the directory; reads must remain side-effect free.
        return FileStore.readDrawingsDirectory.appendingPathComponent(fileName)
    }
}

#if os(macOS)
enum MacDrawingStorage {
    static func read(from name: String, directory: URL) throws -> [MacStroke] {
        guard name == URL(fileURLWithPath: name).lastPathComponent else { throw NotebookTransferError.invalidFile }
        return try JSONDecoder().decode([MacStroke].self, from: Data(contentsOf: directory.appendingPathComponent(name)))
    }
    static func write(_ strokes: [MacStroke], name: String, directory: URL) throws {
        guard name == URL(fileURLWithPath: name).lastPathComponent else { throw NotebookTransferError.invalidFile }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(strokes).write(to: directory.appendingPathComponent(name), options: .atomic)
    }
    static func loadForExport(from fileName: String) throws -> [MacStroke] {
        do {
            let data = try Data(contentsOf: DrawingStorage.urlForReading(fileName))
            return try JSONDecoder().decode([MacStroke].self, from: data)
        } catch {
            throw NotebookTransferError.unreadableDrawing(fileName)
        }
    }

    static func load(from fileName: String) -> [MacStroke] {
        let url = DrawingStorage.urlForReading(fileName)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([MacStroke].self, from: data)) ?? []
    }

    static func save(_ strokes: [MacStroke], to fileName: String) {
        let url = FileStore.url(forDrawing: fileName)
        guard let data = try? JSONEncoder().encode(strokes) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
#endif
