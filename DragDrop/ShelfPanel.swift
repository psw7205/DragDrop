import Cocoa

class ShelfPanel: NSPanel {
    convenience init(contentRect: NSRect) {
        self.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
    }

    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: backing,
            defer: flag
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        isMovable = false
        level = .statusBar + 1
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
        ]
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isFloatingPanel = true
    }

    var onSelectAll: (() -> Void)?
    var onDeleteSelected: (() -> Void)?
    var onPaste: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            makeKey()
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            switch event.keyCode {
            case 0: // Cmd+A
                onSelectAll?()
                return true
            case 9: // Cmd+V
                onPaste?()
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            onDeleteSelected?()
            return
        }
        super.keyDown(with: event)
    }
}
