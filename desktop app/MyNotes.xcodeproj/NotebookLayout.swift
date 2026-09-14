#if false // Disabled: duplicate of existing NotebookLayout usage
import Foundation
import CoreGraphics

public struct NotebookPageFrame {
    public let pageID: UUID
    public let origin: CGPoint
    public let size: CGSize
    
    public var rect: CGRect {
        CGRect(origin: origin, size: size)
    }
}

public struct NotebookLayout {
    public var gap: CGFloat = 32
    public private(set) var frames: [NotebookPageFrame]
    public private(set) var documentBounds: CGRect
    
    /// Initialize NotebookLayout by vertically stacking pages in order, left-aligned at x=0, with the given gap between pages.
    /// The gap is part of document space.
    /// - Parameters:
    ///   - pages: Array of tuples (id: UUID, size: CGSize)
    ///   - gap: vertical gap between pages in document space
    public init(pages: [(id: UUID, size: CGSize)], gap: CGFloat = 32) {
        self.gap = gap
        var frames: [NotebookPageFrame] = []
        var currentY: CGFloat = 0
        
        for page in pages {
            let frame = NotebookPageFrame(pageID: page.id,
                                          origin: CGPoint(x: 0, y: currentY),
                                          size: page.size)
            frames.append(frame)
            currentY += page.size.height + gap
        }
        
        // Remove the last gap if there is at least one page
        if !frames.isEmpty {
            currentY -= gap
        }
        
        self.frames = frames
        let maxWidth = frames.map { $0.size.width }.max() ?? 0
        self.documentBounds = CGRect(x: 0, y: 0, width: maxWidth, height: currentY)
    }
    
    /// Returns the NotebookPageFrame if the document point lies within any page's rect.
    /// Hit-testing excludes gaps.
    /// - Parameter p: point in document coordinate space
    /// - Returns: page frame containing the point or nil
    public func page(atDocumentPoint p: CGPoint) -> NotebookPageFrame? {
        for frame in frames {
            if frame.rect.contains(p) {
                return frame
            }
        }
        return nil
    }
    
    /// Returns the nearest page frame to the document point.
    /// If multiple pages equally near, returns the first found.
    /// - Parameter p: point in document coordinate space
    /// - Returns: nearest page frame or nil if no pages
    public func nearestPage(toDocumentPoint p: CGPoint) -> NotebookPageFrame? {
        guard !frames.isEmpty else { return nil }
        var nearestFrame = frames[0]
        var nearestDistance = distance(from: p, to: frames[0].rect)
        
        for frame in frames.dropFirst() {
            let dist = distance(from: p, to: frame.rect)
            if dist < nearestDistance {
                nearestDistance = dist
                nearestFrame = frame
            }
        }
        return nearestFrame
    }
    
    /// Returns the index of the page with the given UUID.
    /// - Parameter pageID: UUID of the page
    /// - Returns: index or nil if not found
    public func index(of pageID: UUID) -> Int? {
        frames.firstIndex(where: { $0.pageID == pageID })
    }
    
    /// Returns the frame of the page with the given UUID.
    /// - Parameter pageID: UUID of the page
    /// - Returns: NotebookPageFrame or nil if not found
    public func frame(of pageID: UUID) -> NotebookPageFrame? {
        frames.first(where: { $0.pageID == pageID })
    }
    
    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        if rect.contains(point) {
            return 0
        }
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return sqrt(dx*dx + dy*dy)
    }
}

public extension NotebookLayout {
    /// Maps a point from page local coordinate space to document coordinate space.
    /// - Parameters:
    ///   - pageID: UUID of the page
    ///   - point: point in page local coordinates (origin at page top-left)
    /// - Returns: point in document coordinate space or .zero if page not found
    func mapPageLocalToDocument(pageID: UUID, point: CGPoint) -> CGPoint {
        guard let frame = frame(of: pageID) else {
            return .zero
        }
        return CGPoint(x: frame.origin.x + point.x, y: frame.origin.y + point.y)
    }
    
    /// Maps a point from document coordinate space to page local coordinate space.
    /// - Parameters:
    ///   - pageID: UUID of the page
    ///   - point: point in document coordinate space
    /// - Returns: point in page local coordinates or .zero if page not found
    func mapDocumentToPageLocal(pageID: UUID, point: CGPoint) -> CGPoint {
        guard let frame = frame(of: pageID) else {
            return .zero
        }
        return CGPoint(x: point.x - frame.origin.x, y: point.y - frame.origin.y)
    }
}
#endif
