/// This storage helper manages audio files that are waiting for transcription.
/// It keeps them in a `CapturedAudio` folder beside the shared SwiftData store,
/// where import, Watch delivery, transcription, and History retry paths can find them.
/// Successful work removes its file; awaiting or failed work keeps it for recovery.

import Foundation

enum AudioStorage {
    static var directory: URL {
        let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupSuite
        ) ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("CapturedAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    static func delete(_ filename: String?) {
        guard let filename, !filename.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(for: filename))
    }

    // Removes a persisted audio file while surfacing failures to callers that
    // need deletion to participate in a durability boundary.
    static func remove(_ filename: String) throws {
        guard !filename.isEmpty else { return }
        let fileURL = url(for: filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    static func exists(_ filename: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: filename).path)
    }

    static func finalFilename(for id: UUID, sourceExtension: String) -> String {
        let sanitizedExtension = sourceExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "")
        return sanitizedExtension.isEmpty
            ? id.uuidString
            : "\(id.uuidString).\(sanitizedExtension)"
    }

    static func incomingURL(for id: UUID, sourceExtension: String) -> URL {
        let suffix = sourceExtension.isEmpty ? "" : ".\(sourceExtension)"
        return directory.appendingPathComponent(".\(id.uuidString).incoming\(suffix)")
    }

    static func incomingItemID(for url: URL) -> UUID? {
        let components = url.lastPathComponent.split(separator: ".", omittingEmptySubsequences: true)
        guard components.count >= 2,
              components[1] == "incoming",
              let id = UUID(uuidString: String(components[0])) else {
            return nil
        }
        return id
    }

    // Publishes a byte-complete staged import with a same-volume rename.
    static func publishIncomingFile(at incomingURL: URL, as filename: String) throws {
        let destination = url(for: filename)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            try FileManager.default.removeItem(at: incomingURL)
            return
        }
        try FileManager.default.moveItem(at: incomingURL, to: destination)
    }
}
