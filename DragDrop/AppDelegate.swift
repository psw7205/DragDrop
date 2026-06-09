import AppKit
import SwiftUI
import Combine
import QuickLookUI
import Carbon.HIToolbox
import ServiceManagement

private enum PreferencesWindowError: LocalizedError {
    case appUnavailable

    var errorDescription: String? {
        switch self {
        case .appUnavailable:
            "DragDrop is unavailable."
        }
    }
}

struct ShelfHotKey: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let identifier: UInt32

    static let toggleShelf = ShelfHotKey(
        keyCode: UInt32(kVK_ANSI_D),
        carbonModifiers: UInt32(optionKey | shiftKey),
        identifier: 1
    )

    var eventHotKeyID: EventHotKeyID {
        EventHotKeyID(signature: Self.signature, id: identifier)
    }

    private static let signature: OSType = {
        UInt32("D".unicodeScalars.first!.value) << 24
            | UInt32("D".unicodeScalars.first!.value) << 16
            | UInt32("S".unicodeScalars.first!.value) << 8
            | UInt32("H".unicodeScalars.first!.value)
    }()
}

enum CarbonHotKeyError: LocalizedError {
    case handlerInstallFailed(OSStatus)
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .handlerInstallFailed(let status):
            "Failed to install hot key handler: \(status)"
        case .registrationFailed(let status):
            "Failed to register hot key: \(status)"
        }
    }
}

final class CarbonHotKeyRegistration {
    fileprivate let hotKeyRef: EventHotKeyRef?
    fileprivate let eventHandlerRef: EventHandlerRef?
    fileprivate let callbackBox: CarbonHotKeyCallbackBox?

    init() {
        hotKeyRef = nil
        eventHandlerRef = nil
        callbackBox = nil
    }

    fileprivate init(
        hotKeyRef: EventHotKeyRef? = nil,
        eventHandlerRef: EventHandlerRef? = nil,
        callbackBox: CarbonHotKeyCallbackBox? = nil
    ) {
        self.hotKeyRef = hotKeyRef
        self.eventHandlerRef = eventHandlerRef
        self.callbackBox = callbackBox
    }
}

private final class CarbonHotKeyCallbackBox {
    let hotKey: ShelfHotKey
    let onPressed: () -> Void

    init(hotKey: ShelfHotKey, onPressed: @escaping () -> Void) {
        self.hotKey = hotKey
        self.onPressed = onPressed
    }
}

final class CarbonHotKeyMonitor {
    typealias Register = (ShelfHotKey, @escaping () -> Void) throws -> CarbonHotKeyRegistration
    typealias Unregister = (CarbonHotKeyRegistration) -> Void

    private let hotKey: ShelfHotKey
    private let onPressed: () -> Void
    private let register: Register
    private let unregister: Unregister
    private var registration: CarbonHotKeyRegistration?

    @MainActor init(
        hotKey: ShelfHotKey,
        onPressed: @escaping () -> Void
    ) {
        self.hotKey = hotKey
        self.onPressed = onPressed
        register = Self.registerWithCarbon
        unregister = Self.unregisterWithCarbon
    }

    @MainActor init(
        hotKey: ShelfHotKey,
        onPressed: @escaping () -> Void,
        register: @escaping Register,
        unregister: @escaping Unregister
    ) {
        self.hotKey = hotKey
        self.onPressed = onPressed
        self.register = register
        self.unregister = unregister
    }

    func start() throws {
        guard registration == nil else { return }
        registration = try register(hotKey, onPressed)
    }

    func stop() {
        guard let registration else { return }
        unregister(registration)
        self.registration = nil
    }

    deinit {
        stop()
    }

    private static func registerWithCarbon(
        hotKey: ShelfHotKey,
        onPressed: @escaping () -> Void
    ) throws -> CarbonHotKeyRegistration {
        let callbackBox = CarbonHotKeyCallbackBox(hotKey: hotKey, onPressed: onPressed)
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var eventHandlerRef: EventHandlerRef?
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let box = Unmanaged<CarbonHotKeyCallbackBox>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                var eventHotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &eventHotKeyID
                )
                guard parameterStatus == noErr,
                      eventHotKeyID.signature == box.hotKey.eventHotKeyID.signature,
                      eventHotKeyID.id == box.hotKey.identifier else {
                    return noErr
                }
                DispatchQueue.main.async {
                    box.onPressed()
                }
                return noErr
            },
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(callbackBox).toOpaque()),
            &eventHandlerRef
        )
        guard handlerStatus == noErr else {
            throw CarbonHotKeyError.handlerInstallFailed(handlerStatus)
        }

        let hotKeyID = hotKey.eventHotKeyID
        var hotKeyRef: EventHotKeyRef?
        let registrationStatus = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registrationStatus == noErr else {
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
            }
            throw CarbonHotKeyError.registrationFailed(registrationStatus)
        }

        return CarbonHotKeyRegistration(
            hotKeyRef: hotKeyRef,
            eventHandlerRef: eventHandlerRef,
            callbackBox: callbackBox
        )
    }

    private static func unregisterWithCarbon(_ registration: CarbonHotKeyRegistration) {
        if let hotKeyRef = registration.hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef = registration.eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var panel: ShelfPanel?
    private let viewModel = ShelfViewModel()
    private let preferences = ShelfPreferences()
    private var dragMonitor: GlobalDragMonitor?
    private var statusItem: NSStatusItem?
    private var preferencesWindowController: NSWindowController?
    private var geometryCancellable: AnyCancellable?
    private var selectionCancellable: AnyCancellable?
    private var panelMoveObserver: NSObjectProtocol?
    private var panelCenterY: CGFloat?
    private var panelCenterX: CGFloat?
    private var preferredScreenID: NSNumber?
    private var isUpdatingFrame = false
    private var hotKeyMonitor: CarbonHotKeyMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupPanel()
        setupDragMonitor()
        setupStatusItem()
        setupGlobalHotkey()
    }

    private func setupPanel() {
        let panel = ShelfPanel(contentRect: NSRect(x: 0, y: 0, width: ShelfLayout.expandedWidth, height: ShelfLayout.maxHeight))

        let shelfView = ShelfView(
            viewModel: viewModel,
            openItems: { [weak self] items in
                self?.openItems(items)
            },
            revealItem: { [weak self] item in
                self?.revealItemInFinder(item)
            },
            copyItems: { [weak self] items in
                self?.copyItemsToPasteboard(items)
            },
            quickLookItems: { [weak self] items in
                self?.showQuickLook(for: items)
            }
        )
        let hostingView = ShelfHostingView(rootView: shelfView)
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
        hostingView.onItemsReordered = { [weak self] sourceIDs, targetIndex in
            self?.viewModel.moveItems(withIDs: sourceIDs, toIndex: targetIndex)
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
                DispatchQueue.main.async { [weak self] in
                    self?.updatePanelFrame()
                    self?.updateStatusIcon()
                }
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
        guard !Self.isRunningUnitTests else { return }

        let monitor = CarbonHotKeyMonitor(hotKey: .toggleShelf) { [weak self] in
            self?.toggleShelfFromHotkey()
        }
        do {
            try monitor.start()
            hotKeyMonitor = monitor
        } catch {
            NSLog("DragDrop: Failed to register global hot key: %@", error.localizedDescription)
        }
    }

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
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
            showQuickLookPanel()
        }
    }

    private func showQuickLook(for items: [ShelfItem]) {
        guard !items.isEmpty else { return }
        viewModel.selectedIDs = Set(items.map(\.id))
        showQuickLookPanel()
    }

    private func showQuickLookPanel() {
        guard !viewModel.selectedItems.isEmpty else { return }
        let panel = QLPreviewPanel.shared()!
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    private func openItems(_ items: [ShelfItem]) {
        for item in items {
            NSWorkspace.shared.open(item.fileURL)
        }
    }

    private func revealItemInFinder(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
    }

    private func copyItemsToPasteboard(_ items: [ShelfItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items.map { $0.fileURL as NSURL })
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

        let preferencesItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        let cleanupItem = NSMenuItem(
            title: "Clean Up Storage...",
            action: #selector(confirmStorageCleanup),
            keyEquivalent: ""
        )
        cleanupItem.target = self
        menu.addItem(cleanupItem)

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
            try setLaunchAtLogin(enabled: SMAppService.mainApp.status != .enabled)
        } catch {
            NSLog("DragDrop: Failed to toggle launch at login: %@", error.localizedDescription)
        }
    }

    @objc private func showPreferences() {
        if let preferencesWindowController {
            preferencesWindowController.showWindow(nil)
            preferencesWindowController.window?.makeKeyAndOrderFront(nil)
            activatePreferencesWindow()
            return
        }

        let preferencesView = PreferencesView(
            preferences: preferences,
            isLaunchAtLoginEnabled: {
                SMAppService.mainApp.status == .enabled
            },
            setLaunchAtLoginEnabled: { [weak self] enabled in
                guard let self else { throw PreferencesWindowError.appUnavailable }
                try self.setLaunchAtLogin(enabled: enabled)
            },
            loadStorageMetrics: { [weak self] in
                guard let self else { throw PreferencesWindowError.appUnavailable }
                return try self.currentStorageMetrics()
            },
            cleanNow: { [weak self] in
                guard let self else { throw PreferencesWindowError.appUnavailable }
                return try self.cleanUpStorageFromPreferences()
            }
        )

        let hostingController = NSHostingController(rootView: preferencesView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Preferences"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        preferencesWindowController = controller
        controller.showWindow(nil)
        activatePreferencesWindow()
    }

    private func activatePreferencesWindow() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func setLaunchAtLogin(enabled: Bool) throws {
        let isEnabled = SMAppService.mainApp.status == .enabled
        guard isEnabled != enabled else { return }

        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    @objc private func confirmStorageCleanup() {
        let alert = NSAlert()
        alert.messageText = "Clean Up Storage?"
        alert.informativeText = preferences.cleanupDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clean Up")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        cleanUpStorage()
    }

    private func cleanUpStorage() {
        do {
            let result = try cleanUpStorageFromPreferences()
            showStorageCleanupResult(result)
        } catch {
            showStorageCleanupError(error)
        }
    }

    private func currentStorageMetrics() throws -> ShelfStorageMetrics {
        try viewModel.storageMetrics()
    }

    private func cleanUpStorageFromPreferences() throws -> ShelfCleanupResult {
        let result = try viewModel.cleanupStorage(using: preferences.cleanupPolicy)
        updatePanelFrame()
        updateStatusIcon()
        return result
    }

    private func showStorageCleanupResult(_ result: ShelfCleanupResult) {
        let alert = NSAlert()
        alert.messageText = "Storage Cleaned Up"
        alert.alertStyle = .informational

        if result.removedItemIDs.isEmpty {
            alert.informativeText = "No shelf items matched the cleanup policy."
        } else {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let reclaimed = formatter.string(fromByteCount: result.reclaimedBytes)
            alert.informativeText = "Removed \(result.removedItemIDs.count) item(s) and reclaimed \(reclaimed)."
        }

        alert.runModal()
    }

    private func showStorageCleanupError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Storage Cleanup Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
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
        hotKeyMonitor?.stop()
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
