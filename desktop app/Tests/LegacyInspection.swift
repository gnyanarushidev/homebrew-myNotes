import Foundation
import SwiftData

// Read-only application-level inspection. Reports counts/validation failures,
// never credentials or the user's drawing/text contents.
@main struct LegacyInspection {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count >= 3 else { throw CloudError.message("Pass a store path and drawing-directory path.") }
        let store = URL(fileURLWithPath: CommandLine.arguments[1])
        let drawings = URL(fileURLWithPath: CommandLine.arguments[2])
        guard FileManager.default.fileExists(atPath: store.path) else { throw CloudError.message("The source store does not exist.") }
        let schema = Schema([Notebook.self, Page.self])
        let config = ModelConfiguration("Inspection", schema: schema, url: store, allowsSave: false, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let notebooks = try container.mainContext.fetch(FetchDescriptor<Notebook>())
        print("Store: \(store.path) — \(notebooks.count) notebooks")
        for notebook in notebooks {
            print("Notebook \(notebook.id.uuidString.lowercased()): \(notebook.pages.count) pages")
            do {
                let snapshot = try CloudCodec.snapshot(notebook, directory: drawings)
                print("  Valid snapshot: \(snapshot.pages.reduce(0) { $0 + $1.content.strokes.count }) strokes; digest \(CloudCodec.hash(try CloudCodec.encode(snapshot)))")
            } catch {
                print("  Snapshot failed: \(error.localizedDescription)")
                for page in notebook.pages {
                    guard let filename = page.drawingFileName else { continue }
                    do {
                        let strokes = try MacDrawingStorage.read(from: filename, directory: drawings)
                        let empty = strokes.filter { $0.points.isEmpty }.count
                        let invalidColors = strokes.filter { ![$0.style.red, $0.style.green, $0.style.blue, $0.style.alpha].allSatisfy { $0.isFinite && (0...1).contains($0) } }.count
                        let invalidCoordinates = strokes.filter { !$0.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 10000 && abs($0.y) <= 10000 } }.count
                        let invalidWidths = strokes.filter { !(0.1...100).contains($0.style.width) || !(0.01...1).contains($0.style.opacity) }.count
                        print("  Page \(page.id): strokes=\(strokes.count), empty=\(empty), colors=\(invalidColors), coordinates=\(invalidCoordinates), widths=\(invalidWidths), largestStroke=\(strokes.map { $0.points.count }.max() ?? 0)")
                    } catch { print("  File \(filename): \(error.localizedDescription)") }
                }
            }
        }
        let journalURL = store.deletingLastPathComponent().appendingPathComponent("sync-state.json")
        if FileManager.default.fileExists(atPath: journalURL.path) {
            let journal = try JSONDecoder().decode(SyncJournal.self, from: Data(contentsOf: journalURL))
            print("Journal: \(journal.baselines.count) baselines, \(journal.migrated.count) migrated, cursor \(journal.cursor), pending \(journal.pending?.id ?? "none")")
            for (id, baseline) in journal.baselines { print("  Baseline \(id): revision=\(baseline.revision), digest=\(baseline.localHash)") }
        }
    }
}
