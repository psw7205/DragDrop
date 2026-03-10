import SwiftUI

struct ShelfView: View {
    @ObservedObject var viewModel: ShelfViewModel

    private let columns = [
        GridItem(.fixed(80), spacing: 4),
        GridItem(.fixed(80), spacing: 4)
    ]

    var body: some View {
        Group {
            switch viewModel.displayState {
            case .hidden:
                Color.clear
            case .indicator:
                indicatorView
            case .expanded:
                expandedView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: viewModel.displayState)
        .animation(.easeInOut(duration: 0.2), value: viewModel.items.count)
    }

    // MARK: - Indicator

    private var indicatorView: some View {
        Image(systemName: "tray.and.arrow.down.fill")
            .font(.system(size: 22))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Color.gray.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Expanded Shelf

    private var expandedView: some View {
        VStack(spacing: 0) {
            header
            if viewModel.items.isEmpty {
                emptyState
            } else {
                itemGrid
            }
        }
        .frame(width: 200, height: viewModel.expandedHeight)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        HStack {
            Text("DragDrop")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if !viewModel.items.isEmpty {
                Text("\(viewModel.items.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(WindowDragView())
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Drop files here")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var itemGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(viewModel.items) { item in
                    let isSelected = viewModel.selectedIDs.contains(item.id)
                    let dragURLs = isSelected
                        ? viewModel.selectedItems.map(\.fileURL)
                        : [item.fileURL]
                    ShelfItemView(
                        item: item,
                        isSelected: isSelected,
                        dragURLs: dragURLs,
                        onRemove: { viewModel.removeItem(item) },
                        onTap: { modifiers in
                            if modifiers.contains(.command) {
                                viewModel.toggleSelection(item.id)
                            } else {
                                viewModel.selectOnly(item.id)
                            }
                        }
                    )
                }
            }
            .padding(8)
        }
    }
}
