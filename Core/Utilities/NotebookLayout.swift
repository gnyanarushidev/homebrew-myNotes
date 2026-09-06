import SwiftUI

struct NotebookLayout {
    var pageGap: CGFloat = 32

    func pageFrame(for page: Page, at index: Int, precedingPageSizes: [CGSize]) -> CGRect {
        let size = page.pageSize.dimensions
        return CGRect(x: 0, y: documentY(forPageAt: index, pageSizes: precedingPageSizes), width: size.width, height: size.height)
    }

    func documentY(forPageAt index: Int, pageSizes: [CGSize]) -> CGFloat {
        pageSizes.prefix(index).reduce(0) { $0 + $1.height + pageGap }
    }

    func totalDocumentHeight(pageSizes: [CGSize]) -> CGFloat {
        guard !pageSizes.isEmpty else { return 0 }
        return pageSizes.reduce(0) { $0 + $1.height } + pageGap * CGFloat(max(pageSizes.count - 1, 0))
    }

    func pageIndex(at documentPoint: CGPoint, pageSizes: [CGSize]) -> Int? {
        for index in pageSizes.indices {
            let frame = CGRect(
                x: 0,
                y: documentY(forPageAt: index, pageSizes: pageSizes),
                width: pageSizes[index].width,
                height: pageSizes[index].height
            )
            if frame.contains(documentPoint) { return index }
        }
        return nil
    }

    /// Selects the closest page for page-navigation UI. Input hit testing uses
    /// `pageIndex(at:)` and therefore continues to reject inter-page gaps.
    func nearestPageIndex(to documentPoint: CGPoint, pageSizes: [CGSize]) -> Int? {
        guard !pageSizes.isEmpty else { return nil }
        if let exactIndex = pageIndex(at: documentPoint, pageSizes: pageSizes) {
            return exactIndex
        }

        return pageSizes.indices.min { lhs, rhs in
            let lhsFrame = CGRect(x: 0, y: documentY(forPageAt: lhs, pageSizes: pageSizes), width: pageSizes[lhs].width, height: pageSizes[lhs].height)
            let rhsFrame = CGRect(x: 0, y: documentY(forPageAt: rhs, pageSizes: pageSizes), width: pageSizes[rhs].width, height: pageSizes[rhs].height)
            return distance(from: documentPoint, to: lhsFrame) < distance(from: documentPoint, to: rhsFrame)
        }
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}
