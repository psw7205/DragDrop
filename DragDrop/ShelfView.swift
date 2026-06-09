import SwiftUI
import AppKit

private final class ShelfActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(performHandler), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func performHandler() {
        handler()
    }
}

struct ShelfView: View {
    @ObservedObject var viewModel: ShelfViewModel
    private let openItems: ([ShelfItem]) -> Void
    private let revealItem: (ShelfItem) -> Void
    private let copyItems: ([ShelfItem]) -> Void
    private let quickLookItems: ([ShelfItem]) -> Void

    private let columns = Array(
        repeating: GridItem(.fixed(ShelfLayout.itemWidth), spacing: ShelfLayout.gridSpacing),
        count: ShelfLayout.columns
    )

    init(
        viewModel: ShelfViewModel,
        openItems: @escaping ([ShelfItem]) -> Void = { _ in },
        revealItem: @escaping (ShelfItem) -> Void = { _ in },
        copyItems: @escaping ([ShelfItem]) -> Void = { _ in },
        quickLookItems: @escaping ([ShelfItem]) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.openItems = openItems
        self.revealItem = revealItem
        self.copyItems = copyItems
        self.quickLookItems = quickLookItems
    }

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
        .alert(
            "Failed to add files",
            isPresented: Binding(
                get: { viewModel.lastErrorMessage != nil },
                set: { if !$0 { viewModel.lastErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.lastErrorMessage = nil
            }
        } message: {
            Text(viewModel.lastErrorMessage ?? "Please try again.")
        }
        .alert(
            "Delete all items?",
            isPresented: $viewModel.showDeleteAllConfirmation
        ) {
            Button("Delete", role: .destructive) {
                viewModel.removeSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(viewModel.items.count) items will be permanently deleted.")
        }
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
                controls
                if viewModel.visibleItems.isEmpty {
                    searchEmptyState
                } else {
                    itemGrid
                }
            }
        }
        .frame(width: ShelfLayout.expandedWidth, height: viewModel.expandedHeight)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        HStack(spacing: 4) {
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
            .overlay(WindowDragView())

            Button {
                viewModel.toggleShelf()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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

    private var controls: some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12, height: 20)

                TextField("Search", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .frame(height: 20)
            }
            .padding(.horizontal, 7)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 6) {
                sortMenu
                Spacer()
                Text("\(viewModel.visibleItems.count)/\(viewModel.items.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .frame(height: ShelfLayout.controlsHeight)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(ShelfSortMode.allCases) { mode in
                Button {
                    viewModel.sortMode = mode
                } label: {
                    if viewModel.sortMode == mode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Text(mode.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 9))
                Text(viewModel.sortMode.title)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .frame(height: 18)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var searchEmptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text("No matches")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var itemGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(viewModel.visibleItems) { item in
                    let isSelected = viewModel.selectedIDs.contains(item.id)
                    let dragItems = viewModel.dragItems(for: item.id)
                    ShelfItemView(
                        item: item,
                        isSelected: isSelected,
                        dragURLs: dragItems.map(\.fileURL),
                        dragItemIDs: dragItems.map(\.id),
                        metadata: viewModel.metadata(for: item),
                        onRemove: { viewModel.removeItem(item) },
                        onTap: { modifiers in
                            if modifiers.contains(.command) {
                                viewModel.toggleSelection(item.id)
                            } else {
                                viewModel.selectOnly(item.id)
                            }
                        },
                        contextMenu: { contextMenu(for: item) }
                    )
                }
            }
            .padding(ShelfLayout.gridPadding)
        }
    }

    private func contextMenu(for item: ShelfItem) -> NSMenu {
        let menu = NSMenu()
        let contextItems = viewModel.contextMenuItems(for: item.id)
        guard !contextItems.isEmpty else { return menu }

        if contextItems.count > 1 {
            menu.addItem(ShelfActionMenuItem(title: "Quick Look Selected") {
                quickLookItems(contextItems)
            })
            menu.addItem(ShelfActionMenuItem(title: "Copy Selected") {
                copyItems(contextItems)
            })
            menu.addItem(.separator())
            menu.addItem(ShelfActionMenuItem(title: "Delete Selected") {
                viewModel.requestRemoveSelected()
            })
        } else if let singleItem = contextItems.first {
            menu.addItem(ShelfActionMenuItem(title: "Open") {
                openItems([singleItem])
            })
            menu.addItem(ShelfActionMenuItem(title: "Quick Look") {
                quickLookItems([singleItem])
            })
            menu.addItem(ShelfActionMenuItem(title: "Reveal in Finder") {
                revealItem(singleItem)
            })
            menu.addItem(ShelfActionMenuItem(title: "Copy") {
                copyItems([singleItem])
            })
            menu.addItem(.separator())
            menu.addItem(ShelfActionMenuItem(title: "Delete") {
                viewModel.removeItem(singleItem)
            })
        }

        return menu
    }
}
