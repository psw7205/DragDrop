import SwiftUI

struct ShelfItemView: View {
    let item: ShelfItem
    let isSelected: Bool
    let dragURLs: [URL]
    let onRemove: () -> Void
    let onTap: (NSEvent.ModifierFlags) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                Image(nsImage: item.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .frame(width: 48, height: 48)

                Text(item.fileName)
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
