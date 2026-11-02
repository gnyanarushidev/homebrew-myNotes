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
    @State private var folderPromptIDs: Set<Notebook.ID> = []
    @State private var isNamingFolder = false
    @State private var newFolderName = ""
    /// Folder names the user collapsed ("" is the Unfiled group), remembered between launches.
    @AppStorage("collapsedNotebookFolders") private var collapsedFoldersJSON = "[]"

    private var collapsedFolders: Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: Data(collapsedFoldersJSON.utf8))) ?? [])
    }

    /// Expanded unless collapsed; searching always expands so matches are never hidden.
    private func expansion(for key: String) -> Binding<Bool> {
        Binding(
            get: { !searchText.isEmpty || !collapsedFolders.contains(key) },
            set: { expanded in
                var folders = collapsedFolders
                if expanded { folders.remove(key) } else { folders.insert(key) }
                if let data = try? JSONEncoder().encode(folders.sorted()) {
                    collapsedFoldersJSON = String(decoding: data, as: UTF8.self)
                }
            }
        )
    }

    /// Folder names across all notebooks, alphabetically.
    private var folderNames: [String] {
        Array(Set(notebooks.compactMap { Notebook.cleanFolder($0.folder) }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

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
                ForEach(folderNames, id: \.self) { name in
                    let members = visibleNotebooks.filter { Notebook.cleanFolder($0.folder) == name }
                    if !members.isEmpty {
                        Section(isExpanded: expansion(for: name)) {
                            notebookRows(members, folder: name)
                        } header: {
                            Label(name, systemImage: "folder")
                                .dropDestination(for: String.self) { items, _ in dropNotebooks(items, into: name) }
                        }
                    }
                }
                let unfiled = visibleNotebooks.filter { Notebook.cleanFolder($0.folder) == nil }
                if folderNames.isEmpty {
                    notebookRows(unfiled, folder: nil)
                } else {
                    // Always shown while folders exist so notebooks can be dragged back out.
                    Section(isExpanded: expansion(for: "")) {
                        notebookRows(unfiled, folder: nil)
                    } header: {
                        Label("Unfiled", systemImage: "tray")
                            .dropDestination(for: String.self) { items, _ in dropNotebooks(items, into: nil) }
                    }
                }
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
                Menu("Move to Folder", systemImage: "folder") {
                    ForEach(folderNames, id: \.self) { name in
                        Button(name) { moveNotebooks(withIDs: ids, to: name) }
                    }
                    if !folderNames.isEmpty { Divider() }
                    Button("New Folder…", systemImage: "folder.badge.plus") {
                        folderPromptIDs = ids
                        newFolderName = ""
                        isNamingFolder = true
                    }
                    Button("No Folder", systemImage: "tray") { moveNotebooks(withIDs: ids, to: nil) }
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
        .alert("New Folder", isPresented: $isNamingFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") { moveNotebooks(withIDs: folderPromptIDs, to: newFolderName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Folders group notebooks by topic. They sync with your account.")
        }
    }

    @ViewBuilder
    private func notebookRows(_ members: [Notebook], folder: String?) -> some View {
        ForEach(members) { notebook in
            Text(notebook.title)
                .tag(notebook.id)
                .draggable(notebook.id.uuidString)
                .dropDestination(for: String.self) { items, _ in dropNotebooks(items, into: folder) }
        }
        .onDelete { offsets in
            for index in offsets { deleteNotebook(notebook: members[index]) }
        }
    }

    /// Accepts dragged notebook IDs and files them; unknown text is rejected.
    private func dropNotebooks(_ items: [String], into folder: String?) -> Bool {
        let ids = Set(items.compactMap(UUID.init(uuidString:))).intersection(notebooks.map(\.id))
        guard !ids.isEmpty else { return false }
        moveNotebooks(withIDs: ids, to: folder)
        if let folder = Notebook.cleanFolder(folder) {
            var collapsed = collapsedFolders
            if collapsed.remove(folder) != nil, let data = try? JSONEncoder().encode(collapsed.sorted()) {
                collapsedFoldersJSON = String(decoding: data, as: UTF8.self)
            }
        }
        return true
    }

    private func moveNotebooks(withIDs ids: Set<Notebook.ID>, to folder: String?) {
        let cleaned = Notebook.cleanFolder(folder)
        for notebook in notebooks where ids.contains(notebook.id) && Notebook.cleanFolder(notebook.folder) != cleaned {
            notebook.folder = cleaned
            notebook.updatedAt = .now
        }
        try? modelContext.save()
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
