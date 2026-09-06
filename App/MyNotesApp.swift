import SwiftUI
import SwiftData

@main
struct MyNotesApp: App {
    private let container: ModelContainer

    init() {
        container = DataController.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .modelContainer(container)
    }
}