import Foundation
import AppKit
import UniformTypeIdentifiers

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
            return ShelfItem(id: id, content: Self.classifyContent(url: destFile))
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
            return ShelfItem(id: id, content: Self.classifyContent(url: destFile))
        } catch {
            try? FileManager.default.removeItem(at: destDir)
            throw error
        }
    }

    func saveLink(from originalURL: URL) throws -> ShelfItem {
        let id = UUID()
        let destDir = storageURL.appendingPathComponent(id.uuidString, isDirectory: true)
        let host = originalURL.host ?? "link"
        let destFile = destDir.appendingPathComponent("\(host).webloc")

        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            let plist: [String: String] = ["URL": originalURL.absoluteString]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: destFile)
            return ShelfItem(id: id, content: .link(url: destFile, originalURL: originalURL))
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
                ShelfItem(id: uuid, content: Self.classifyContent(url: fileURL), addedAt: createdAt)
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

    static func classifyContent(url: URL) -> ShelfContent {
        let ext = url.pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else {
            return .file(url: url, fileName: url.lastPathComponent)
        }

        if ext.lowercased() == "webloc", let originalURL = readWeblocURL(from: url) {
            return .link(url: url, originalURL: originalURL)
        }

        if type.conforms(to: .image) {
            return .image(url: url)
        }

        if type.conforms(to: .plainText) {
            let snippet = Self.readSnippet(from: url)
            return .text(url: url, snippet: snippet)
        }

        return .file(url: url, fileName: url.lastPathComponent)
    }

    private static func readSnippet(from url: URL, maxBytes: Int = 512, maxChars: Int = 200) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes) else { return "" }
        let raw = String(decoding: data, as: UTF8.self)
        if raw.count <= maxChars { return raw }
        return String(raw.prefix(maxChars)) + "…"
    }

    private static func readWeblocURL(from url: URL) -> URL? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let urlString = plist["URL"] as? String,
              let originalURL = URL(string: urlString) else {
            return nil
        }
        return originalURL
    }
}
