import AppKit

struct ClipboardService {
    enum Content {
        case files([URL])
        case image(Data, suggestedName: String)
        case text(String, suggestedName: String)
    }

    func read() -> Content? {
        let pasteboard = NSPasteboard.general

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) as? [URL], !urls.isEmpty {
            return .files(urls)
        }

        let timestamp = Self.timestamp()

        if let image = NSImage(pasteboard: pasteboard),
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            return .image(pngData, suggestedName: "Clipboard \(timestamp).png")
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return .text(text, suggestedName: "Clipboard \(timestamp).txt")
        }

        return nil
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        return formatter.string(from: Date())
    }
}
