import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: ShelfPanel?
    let viewModel = ShelfViewModel()
    var dragMonitor: GlobalDragMonitor?
    private var displayStateCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupPanel()
        setupDragMonitor()
    }

    private func setupPanel() {
        let panel = ShelfPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let hostingView = ShelfHostingView(rootView: ShelfView(viewModel: viewModel))
        hostingView.onDragEntered = { [weak self] in
            self?.viewModel.isDragHovering = true
        }
        hostingView.onDragExited = { [weak self] in
            self?.viewModel.isDragHovering = false
        }
        hostingView.onFilesDropped = { [weak self] urls in
            self?.viewModel.addFiles(from: urls)
            self?.viewModel.isDragHovering = false
            self?.viewModel.isExternalDragging = false
        }

        panel.contentView = hostingView
        panel.ignoresMouseEvents = true
        panel.orderFront(nil)
        self.panel = panel

        displayStateCancellable = viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.updatePanelFrame()
            }
    }

    private func setupDragMonitor() {
        let monitor = GlobalDragMonitor()
        monitor.onDragStarted = { [weak self] in
            self?.viewModel.isExternalDragging = true
        }
        monitor.onDragEnded = { [weak self] in
            self?.viewModel.isExternalDragging = false
            self?.viewModel.isDragHovering = false
        }
        self.dragMonitor = monitor
    }

    private func updatePanelFrame() {
        guard let panel, let screen = NSScreen.main else { return }
        let rightEdge = screen.visibleFrame.maxX - 16
        let centerY = screen.visibleFrame.midY

        switch viewModel.displayState {
        case .hidden:
            panel.ignoresMouseEvents = true
        case .indicator:
            panel.ignoresMouseEvents = false
            let w: CGFloat = 60
            let h: CGFloat = 60
            panel.setFrame(NSRect(x: rightEdge - w, y: centerY - h / 2, width: w, height: h), display: true)
        case .expanded:
            panel.ignoresMouseEvents = false
            let w: CGFloat = 200
            let h = viewModel.expandedHeight
            panel.setFrame(NSRect(x: rightEdge - w, y: centerY - h / 2, width: w, height: h), display: true)
        }
    }
}
