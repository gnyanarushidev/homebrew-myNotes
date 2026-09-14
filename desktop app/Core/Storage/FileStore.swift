import Foundation

enum FileStore {
    // AccountRoot owns this selection. Background sync always captures explicit URLs.
    static var accountRoot: URL?
    static var saveFailures: [String: String] = [:]
    static var legacyDrawingsDirectory: URL {
        (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory).appendingPathComponent("Drawings", isDirectory: true)
    }
    static var readDrawingsDirectory: URL { accountRoot?.appendingPathComponent("Drawings", isDirectory: true) ?? legacyDrawingsDirectory }
    static var drawingsDirectory: URL {
        let directory = readDrawingsDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func url(forDrawing fileName: String) -> URL {
        drawingsDirectory.appendingPathComponent(fileName)
    }
}
