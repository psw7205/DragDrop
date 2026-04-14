import SwiftUI
import ImageIO

struct ShelfItemView: View {
    let item: ShelfItem
    let isSelected: Bool
    let dragURLs: [URL]
    let onRemove: () -> Void
    let onTap: (NSEvent.ModifierFlags) -> Void

    private func thumbnail(for url: URL, maxSize: CGFloat = 96) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.content {
        case .image(let url):
            if let thumb = thumbnail(for: url) {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(nsImage: item.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
            }
        case .text(_, let snippet):
            Text(snippet)
                .font(.system(size: 7, design: .monospaced))
                .lineLimit(5)
                .multilineTextAlignment(.leading)
                .padding(4)
                .frame(width: 48, height: 48, alignment: .topLeading)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        case .file:
            Image(nsImage: item.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                contentPreview
                    .frame(width: 48, height: 48)

                Text(item.displayName)
                    .font(.system(size: 10))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 76, height: 80)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.3) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .overlay(
                DragSourceView(
                    urls: dragURLs,
                    icon: item.icon,
                    onClick: onTap
                )
            )

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white, .gray.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .frame(width: ShelfLayout.itemWidth, height: ShelfLayout.itemHeight)
    }
}
