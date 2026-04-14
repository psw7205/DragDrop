import AppKit
import SwiftUI
import Combine
import QuickLookUI
import Carbon.HIToolbox
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var panel: ShelfPanel?
    private let viewModel = ShelfViewModel()
    private var dragMonitor: GlobalDragMonitor?
    private var statusItem: NSStatusItem?
    private var geometryCancellable: AnyCancellable?
    private var selectionCancellable: AnyCancellable?
    private var panelMoveObserver: NSObjectProtocol?
    private var panelCenterY: CGFloat?
    private var panelCenterX: CGFloat?
    private var preferredScreenID: NSNumber?
    private var isUpdatingFrame = false
    private var globalHotkeyMonitor: Any?
    private var localHotkeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupPanel()
        setupDragMonitor()
        setupStatusItem()
        setupGlobalHotkey()
    }

    private func setupPanel() {
        let panel = ShelfPanel(contentRect: NSRect(x: 0, y: 0, width: ShelfLayout.expandedWidth, height: ShelfLayout.maxHeight))

        let hostingView = ShelfHostingView(rootView: ShelfView(viewModel: viewModel))
        hostingView.onDragEntered = { [weak self] in
            self?.viewModel.isDragHovering = true
        }
        hostingView.onDragExited = { [weak self] in
            self?.viewModel.isDragHovering = false
        }
        hostingView.onFilesDropped = { [weak self] urls in
            self?.viewModel.addFilesAsync(from: urls)
            self?.viewModel.isDragHovering = false
            self?.viewModel.isExternalDragging = false
        }
        hostingView.onLinkDropped = { [weak self] url in
            self?.viewModel.addLinkAsync(from: url)
            self?.viewModel.isDragHovering = false
            self?.viewModel.isExternalDragging = false
        }
        hostingView.onItemReordered = { [weak self] sourceID, targetIndex in
            self?.viewModel.moveItem(withID: sourceID, toIndex: targetIndex)
            self?.viewModel.isDragHovering = false
            self?.viewModel.isExternalDragging = false
        }

        panel.onSelectAll = { [weak self] in
            self?.viewModel.selectAll()
        }
        panel.onDeleteSelected = { [weak self] in
            self?.viewModel.requestRemoveSelected()
        }
        panel.onPaste = { [weak self] in
            self?.viewModel.pasteFromClipboard()
        }
        panel.onQuickLook = { [weak self] in
            self?.toggleQuickLook()
        }

        panel.contentView = hostingView
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
        self.panel = panel

        geometryCancellable = viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updatePanelFrame()
                self?.updateStatusIcon()
            }

        selectionCancellable = viewModel.$selectedIDs
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let qlPanel = QLPreviewPanel.shared()!
                if qlPanel.isVisible {
                    qlPanel.dataSource = self
                    qlPanel.reloadData()
                }
            }

        panelMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isUpdatingFrame, let panel = self.panel else { return }
            self.panelCenterX = panel.frame.midX
            self.panelCenterY = panel.frame.midY
            self.preferredScreenID = self.screenID(for: panel.screen)
        }

        updatePanelFrame()
        updateStatusIcon()
    }

    private func setupDragMonitor() {
        let monitor = GlobalDragMonitor()
        monitor.onDragStarted = { [weak self] in
            self?.viewModel.isExternalDragging = true
        }
        monitor.onDragEnded = { [weak self] in
            self?.viewModel.isExternalDragging = false
        }
        monitor.start()
        self.dragMonitor = monitor
    }

    private func setupGlobalHotkey() {
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleHotkey(event)
        }
        localHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleHotkey(event) == true { return nil }
            return event
        }
    }

    @discardableResult
    private func handleHotkey(_ event: NSEvent) -> Bool {
        let required: NSEvent.ModifierFlags = [.option, .shift]
        let forbidden: NSEvent.ModifierFlags = [.command, .control]
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(required), flags.intersection(forbidden).isEmpty,
              Int(event.keyCode) == kVK_ANSI_D else {
            return false
        }
        toggleShelfFromHotkey()
        return true
    }

    private func toggleShelfFromHotkey() {
        viewModel.toggleShelf()
        activateIfVisible()
    }

    private func activateIfVisible() {
        guard viewModel.displayState != .hidden else { return }
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        panel?.makeKey()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "square.stack", accessibilityDescription: "DragDrop")
        button.action = #selector(statusItemClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func toggleQuickLook() {
        guard !viewModel.selectedItems.isEmpty else { return }
        let panel = QLPreviewPanel.shared()!
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.dataSource = self
            panel.delegate = self
            panel.reloadData()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showStatusMenu()
            return
        }

        viewModel.toggleShelf()
        activateIfVisible()
    }

    private func showStatusMenu() {
        let menu = NSMenu()

        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: "About DragDrop",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(
            title: "Quit DragDrop",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("DragDrop: Failed to toggle launch at login: %@", error.localizedDescription)
        }
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let alert = NSAlert()
        alert.messageText = "DragDrop"
        alert.informativeText = "Version \(version)\nA floating shelf for temporary file storage."
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func updateStatusIcon() {
        let name = viewModel.items.isEmpty ? "square.stack" : "square.stack.fill"
        statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "DragDrop")
    }

    private func updatePanelFrame() {
        guard let panel, let screen = resolvedScreen(for: panel) else { return }

        if viewModel.displayState == .hidden {
            panelCenterX = nil
            panelCenterY = nil
            panel.ignoresMouseEvents = true
            panel.orderOut(nil)
            return
        }

        panel.ignoresMouseEvents = false
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }

        let isIndicator = viewModel.displayState == .indicator
        let w: CGFloat = isIndicator ? ShelfLayout.indicatorSize : ShelfLayout.expandedWidth
        let h: CGFloat = isIndicator ? ShelfLayout.indicatorSize : viewModel.expandedHeight
        let rightEdge = screen.visibleFrame.maxX - ShelfLayout.screenEdgeMargin

        let x: CGFloat
        if viewModel.displayState == .indicator {
            x = rightEdge - w
        } else if let savedCX = panelCenterX {
            let candidateX = savedCX - w / 2
            x = min(max(candidateX, screen.visibleFrame.minX), screen.visibleFrame.maxX - w)
        } else {
            x = rightEdge - w
        }

        let currentCenterY = panelCenterY ?? screen.visibleFrame.midY
        let minY = screen.visibleFrame.minY
        let maxY = screen.visibleFrame.maxY
        let clampedCenterY = min(max(currentCenterY, minY + h / 2), maxY - h / 2)
        let frame = NSRect(x: x, y: clampedCenterY - h / 2, width: w, height: h)
        isUpdatingFrame = true
        panel.setFrame(frame, display: true)
        isUpdatingFrame = false
        panelCenterY = frame.midY
        preferredScreenID = screenID(for: panel.screen)
    }

    private func resolvedScreen(for panel: NSPanel) -> NSScreen? {
        if let preferredScreenID,
           let preferred = NSScreen.screens.first(where: { screenID(for: $0) == preferredScreenID }) {
            return preferred
        }

        if let screen = panel.screen {
            return screen
        }

        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return mouseScreen
        }

        return NSScreen.main ?? NSScreen.screens.first
    }

    private func screenID(for screen: NSScreen?) -> NSNumber? {
        screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    }

    deinit {
        if let panelMoveObserver {
            NotificationCenter.default.removeObserver(panelMoveObserver)
        }
        if let globalHotkeyMonitor {
            NSEvent.removeMonitor(globalHotkeyMonitor)
        }
        if let localHotkeyMonitor {
            NSEvent.removeMonitor(localHotkeyMonitor)
        }
    }
}

extension AppDelegate: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        viewModel.selectedItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard index < viewModel.selectedItems.count else { return nil }
        return viewModel.selectedItems[index].fileURL as NSURL
    }
}
