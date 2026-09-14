import Foundation
import SwiftData

enum PageTemplate: String, Codable, CaseIterable, Identifiable {
    case blank
    case ruled
    case grid
    case dots

    var id: String { rawValue }
}

enum PageSize: String, Codable, CaseIterable, Identifiable {
    case letterPortrait
    case a4Portrait

    var id: String { rawValue }

    var dimensions: CGSize {
        switch self {
        case .letterPortrait: return CGSize(width: 612, height: 792)
        case .a4Portrait: return CGSize(width: 595, height: 842)
        }
    }
}

enum PageColor: String, Codable, CaseIterable, Identifiable {
    case white
    case cream
    case dark

    var id: String { rawValue }
}

@Model
final class Page {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date

    var notebook: Notebook?

    var text: String
    var drawingFileName: String?
    // Remote IDs remain stable even when two imported notebooks share page IDs.
    var cloudPageID: String?
    @Attribute(.externalStorage) var imageData: Data?
    var templateRawValue: String = PageTemplate.blank.rawValue
    var pageSizeRawValue: String = PageSize.letterPortrait.rawValue
    var pageColorRawValue: String = PageColor.white.rawValue
    var hasDrawingContent = false
    // Existing notebooks keep their stored page appearance as an override.
    var inheritsNotebookStyle = false

    var template: PageTemplate {
        get { PageTemplate(rawValue: templateRawValue) ?? .blank }
        set { templateRawValue = newValue.rawValue }
    }

    var pageSize: PageSize {
        get { PageSize(rawValue: pageSizeRawValue) ?? .letterPortrait }
        set { pageSizeRawValue = newValue.rawValue }
    }

    var pageColor: PageColor {
        get { PageColor(rawValue: pageColorRawValue) ?? .white }
        set { pageColorRawValue = newValue.rawValue }
    }

    var effectiveTemplate: PageTemplate {
        inheritsNotebookStyle ? notebook?.template ?? template : template
    }

    var effectivePageColor: PageColor {
        inheritsNotebookStyle ? notebook?.pageColor ?? pageColor : pageColor
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        text: String = "",
        drawingFileName: String? = nil,
        imageData: Data? = nil,
        template: PageTemplate = .blank,
        pageSize: PageSize = .letterPortrait,
        pageColor: PageColor = .white,
        hasDrawingContent: Bool = false,
        inheritsNotebookStyle: Bool = true
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.text = text
        self.drawingFileName = drawingFileName
        self.imageData = imageData
        self.templateRawValue = template.rawValue
        self.pageSizeRawValue = pageSize.rawValue
        self.pageColorRawValue = pageColor.rawValue
        self.hasDrawingContent = hasDrawingContent
        self.inheritsNotebookStyle = inheritsNotebookStyle
    }


    func customizeStyle() {
        guard inheritsNotebookStyle else { return }
        template = effectiveTemplate
        pageColor = effectivePageColor
        inheritsNotebookStyle = false
    }

    func useNotebookStyle() {
        inheritsNotebookStyle = true
    }
}
