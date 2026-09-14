import SwiftUI
import SwiftData

private struct NotebookSidebarVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var notebookSidebarVisible: Bool {
        get { self[NotebookSidebarVisibleKey.self] }
        set { self[NotebookSidebarVisibleKey.self] = newValue }
    }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Notebook.updatedAt, order: .reverse) private var notebooks: [Notebook]

    @State private var selection: Notebook.ID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchText = ""

    private var visibleNotebooks: [Notebook] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return notebooks }
        return notebooks.filter { notebook in
            notebook.title.localizedCaseInsensitiveContains(query)
                || notebook.pages.contains { $0.text.localizedCaseInsensitiveContains(query) }
        }
    }

    private var selectedNotebook: Notebook? {
        guard let selection else { return nil }
        return notebooks.first { $0.id == selection }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                ForEach(visibleNotebooks) { notebook in
                    Text(notebook.title)
                        .tag(notebook.id)
                }
                .onDelete(perform: deleteNotebooks)
            }
            .navigationTitle("MyNotes")
            .searchable(text: $searchText, prompt: "Search notebooks and notes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: addNotebook) {
                        Label("New Notebook", systemImage: "plus")
                    }
                }
            }
            .contextMenu(forSelectionType: Notebook.ID.self) { ids in
                Button("Open", systemImage: "arrow.up.doc") {
                    selection = ids.first
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) {
                    deleteNotebooks(withIDs: ids)
                }
            } primaryAction: { ids in
                selection = ids.first
            }
        } detail: {
            NavigationStack {
                if let notebook = selectedNotebook {
                    NotebookView(notebook: notebook)
                } else {
                    ContentUnavailableView(
                        "Select a Notebook",
                        systemImage: "book",
                        description: Text("Choose a notebook from the sidebar to open it.")
                    )
                }
            }
        }
        .environment(\.notebookSidebarVisible, columnVisibility != .detailOnly)
    }

    private func addNotebook() {
        let notebook = Notebook(title: "Untitled Notebook")
        let page = Page()
        page.notebook = notebook
        notebook.pages.append(page)
        modelContext.insert(notebook)
        try? modelContext.save()
        selection = notebook.id
    }

    private func deleteNotebooks(at offsets: IndexSet) {
        for index in offsets {
            deleteNotebook(notebook: visibleNotebooks[index])
        }
    }

    private func deleteNotebooks(withIDs ids: Set<Notebook.ID>) {
        for id in ids {
            if let notebook = notebooks.first(where: { $0.id == id }) {
                deleteNotebook(notebook: notebook)
            }
        }
    }

    private func deleteNotebook(notebook: Notebook) {
        if selection == notebook.id {
            selection = nil
        }
        let drawings = notebook.pages.compactMap(\.drawingFileName)
        modelContext.delete(notebook)
        do { try modelContext.save(); drawings.forEach(DrawingStorage.deleteDrawing) }
        catch { modelContext.rollback() }
    }
}

#Preview {
    LibraryView()
        .modelContainer(for: [Notebook.self, Page.self], inMemory: true)
}
