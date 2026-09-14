import Foundation
import SwiftData

enum DataController {
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