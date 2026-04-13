import Foundation
import AppKit

class ShelfStorage {
    private let storageURL: URL

    init() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DragDrop/Items", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            NSLog("DragDrop: Failed to create storage directory: %@", error.localizedDescription)
        }
        self.storageURL = url
    }

    func copyFile(from url: URL) throws -> ShelfItem {
        let id = UUID()
        let destDir = storageURL.appendingPathComponent(id.uuidString, isDirectory: true)
        let destFile = destDir.appendingPathComponent(url.lastPathComponent)

        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destFile)
            return ShelfItem(id: id, content: .file(url: destFile, fileName: url.lastPathComponent))
        } catch {
            try? FileManager.default.removeItem(at: destDir)
            throw error
        }
    }

    func saveData(_ data: Data, fileName: String) throws -> ShelfItem {
        let id = UUID()
        let destDir = storageURL.appendingPathComponent(id.uuidString, isDirectory: true)
        let destFile = destDir.appendingPathComponent(fileName)

        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            try data.write(to: destFile)
            return ShelfItem(id: id, content: .file(url: destFile, fileName: fileName))
        } catch {
            try? FileManager.default.removeItem(at: destDir)
            throw error
        }
    }

    func removeItem(_ item: ShelfItem) {
        let dir = item.fileURL.deletingLastPathComponent()
        guard dir.standardizedFileURL.path.hasPrefix(storageURL.standardizedFileURL.path + "/") else { return }
        do {
            try FileManager.default.removeItem(at: dir)
        } catch {
            NSLog("DragDrop: Failed to remove item directory %@: %@", dir.path, error.localizedDescription)
        }
    }

    func loadPersistedItems() -> [ShelfItem] {
        let fileManager = FileManager.default
        guard let directories = try? fileManager.contentsOfDirectory(
            at: storageURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var loaded: [ShelfItem] = []
        var staleDirectories: [URL] = []

        for directory in directories {
            guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true else {
                continue
            }
            guard let uuid = UUID(uuidString: directory.lastPathComponent) else {
                staleDirectories.append(directory)
                continue
            }

            guard let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            ), let fileURL = files.first else {
                staleDirectories.append(directory)
                continue
            }

            if files.count > 1 {
                for extra in files.dropFirst() {
                    do {
                        try fileManager.removeItem(at: extra)
                    } catch {
                        NSLog("DragDrop: Failed to remove extra persisted file %@: %@",
                              extra.path, error.localizedDescription)
                    }
                }
            }

            let createdAt = (try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            loaded.append(
                ShelfItem(id: uuid, content: .file(url: fileURL, fileName: fileURL.lastPathComponent), addedAt: createdAt)
            )
        }

        for directory in staleDirectories {
            do {
                try fileManager.removeItem(at: directory)
            } catch {
                NSLog("DragDrop: Failed to remove stale directory %@: %@",
                      directory.path, error.localizedDescription)
            }
        }

        return loaded.sorted { $0.addedAt < $1.addedAt }
    }

    func isOwnFile(_ url: URL) -> Bool {
        let normalizedStorage = storageURL.standardizedFileURL.path
        let normalizedURL = url.standardizedFileURL.path
        return normalizedURL == normalizedStorage || normalizedURL.hasPrefix(normalizedStorage + "/")
    }
}
