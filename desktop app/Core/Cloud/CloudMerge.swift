#if os(macOS)
import Foundation

/// A three-way merge uses the last acknowledged document, not upload times.
/// Independent strokes/pages merge; incompatible edits to the same item don't.
enum CloudMerge {
    struct Conflict: Error {}
    static func value<T: Equatable>(_ base: T, _ local: T, _ remote: T) throws -> T {
        if local == base { return remote }
        if remote == base || local == remote { return local }
        throw Conflict()
    }
    static func normalized(_ document: LocalCloudDocument) throws -> LocalCloudDocument {
        LocalCloudDocument(title: document.title.trimmingCharacters(in: .whitespacesAndNewlines), template: document.template, color: document.color, pages: try document.pages.map { page in
            LocalCloudPage(id: page.id.lowercased(), size: page.size, template: page.template, color: page.color, inheritsStyle: page.inheritsStyle,
                content: SharedPageContent(text: page.content.text, strokes: try page.content.strokes.map { SharedStroke(try $0.native()) }), image: page.image, imageKind: page.imageKind)
        })
    }
    private static func items<T: Equatable>(_ base: [T], _ local: [T], _ remote: [T], id: (T) -> String, combine: (T, T, T) throws -> T) throws -> [T] {
        let b = Dictionary(uniqueKeysWithValues: base.map { (id($0), $0) }), l = Dictionary(uniqueKeysWithValues: local.map { (id($0), $0) }), r = Dictionary(uniqueKeysWithValues: remote.map { (id($0), $0) })
        var merged: [String: T] = [:]
        for key in Set(b.keys).union(l.keys).union(r.keys) {
            if l[key] == b[key] { merged[key] = r[key] }
            else if r[key] == b[key] || l[key] == r[key] { merged[key] = l[key] }
            else if let original = b[key], let left = l[key], let right = r[key] { merged[key] = try combine(original, left, right) }
            else { throw Conflict() } // delete-vs-edit, or different additions with the same ID
        }
        let common = Set(base.map(id)).intersection(local.map(id)).intersection(remote.map(id))
        let originalOrder = base.map(id).filter { common.contains($0) }, leftOrder = local.map(id).filter { common.contains($0) }, rightOrder = remote.map(id).filter { common.contains($0) }
        if leftOrder != originalOrder && rightOrder != originalOrder && leftOrder != rightOrder { throw Conflict() }
        let preferred = leftOrder != originalOrder ? local : remote
        let remaining = leftOrder != originalOrder ? remote : local
        var seen = Set<String>()
        return (preferred + remaining).compactMap { item in let key = id(item); guard seen.insert(key).inserted else { return nil }; return merged[key] }
    }
    static func merge(base: LocalCloudDocument, local: LocalCloudDocument, remote: LocalCloudDocument) throws -> LocalCloudDocument {
        let b = try normalized(base), l = try normalized(local), r = try normalized(remote)
        let pages = try items(b.pages, l.pages, r.pages, id: { $0.id }) { original, left, right in
            let strokes = try items(original.content.strokes, left.content.strokes, right.content.strokes, id: { $0.id }) { _, _, _ in throw Conflict() }
            return LocalCloudPage(id: original.id,
                size: try value(original.size, left.size, right.size), template: try value(original.template, left.template, right.template),
                color: try value(original.color, left.color, right.color), inheritsStyle: try value(original.inheritsStyle, left.inheritsStyle, right.inheritsStyle),
                content: SharedPageContent(text: try value(original.content.text, left.content.text, right.content.text), strokes: strokes),
                image: try value(original.image, left.image, right.image), imageKind: try value(original.imageKind, left.imageKind, right.imageKind))
        }
        guard !pages.isEmpty, pages.count <= 300 else { throw Conflict() }
        return LocalCloudDocument(title: try value(b.title, l.title, r.title), template: try value(b.template, l.template, r.template), color: try value(b.color, l.color, r.color), pages: pages)
    }
}
#endif
