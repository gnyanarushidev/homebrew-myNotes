import SwiftUI
import SwiftData

@main
struct MyNotesApp: App {
#if os(macOS)
    @StateObject private var session = CloudSession()
    var body: some Scene { WindowGroup { AccountRootView(session: session) } }
#else
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
#endif
}
