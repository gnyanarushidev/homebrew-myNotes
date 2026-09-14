import Foundation
import SwiftData

enum DataController {
    static func accountContainer(at root: URL) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Drawings"), withIntermediateDirectories: true)
        let schema = Schema([Notebook.self, Page.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration("Account", schema: schema, url: root.appendingPathComponent("notebooks.store"), cloudKitDatabase: .none)])
    }
    static func legacyContainer() throws -> ModelContainer {
        let schema = Schema([Notebook.self, Page.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration("MyNotes", schema: schema)])
    }
    static func makeContainer() -> ModelContainer {
        let schema = Schema([Notebook.self, Page.self])
        do {
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration("MyNotes", schema: schema)]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
