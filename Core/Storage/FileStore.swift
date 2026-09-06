import Foundation

enum FileStore {
    static var drawingsDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Drawings", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func url(forDrawing fileName: String) -> URL {
        drawingsDirectory.appendingPathComponent(fileName)
    }
}