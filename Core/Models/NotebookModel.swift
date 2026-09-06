import Foundation
import SwiftData

@Model
final class Notebook {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var templateRawValue: String = PageTemplate.blank.rawValue
    var pageColorRawValue: String = PageColor.white.rawValue

    var template: PageTemplate {
        get { PageTemplate(rawValue: templateRawValue) ?? .blank }
        set { templateRawValue = newValue.rawValue }
    }

    var pageColor: PageColor {
        get { PageColor(rawValue: pageColorRawValue) ?? .white }
        set { pageColorRawValue = newValue.rawValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \Page.notebook)
    var pages: [Page]

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        template: PageTemplate = .blank,
        pageColor: PageColor = .white,
        pages: [Page] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.templateRawValue = template.rawValue
        self.pageColorRawValue = pageColor.rawValue
        self.pages = pages
    }

    /// Called when scrolling past the final page. Its ink enables one more
    /// page; the new blank page prevents repeated scrolling from adding more.
    @discardableResult
    func appendContinuationPage(after page: Page) -> Page? {
        guard !page.isDeleted, page.notebook === self, page.hasDrawingContent,
              pages.max(by: { $0.createdAt < $1.createdAt })?.id == page.id else { return nil }
        let next = Page(
            createdAt: max(.now, page.createdAt.addingTimeInterval(0.001)),
            pageSize: page.pageSize,
            inheritsNotebookStyle: true
        )
        pages.append(next)
        next.notebook = self
        updatedAt = .now
        return next
    }
}
