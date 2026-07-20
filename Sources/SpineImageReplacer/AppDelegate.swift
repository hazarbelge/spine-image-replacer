import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var windowController: ReplacementWindowController!
    private var overlayController: SpineOverlayController!
    private var attachMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        windowController = ReplacementWindowController()
        overlayController = SpineOverlayController { [weak self] in
            self?.showReplacementWindow()
        }
        overlayController.start()
        configureStatusItem()
        showReplacementWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlayController.stop()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "photo.on.rectangle.angled",
                accessibilityDescription: "Spine Image Replacer"
            )
        }

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Replace Images…",
            action: #selector(showReplacementWindow),
            keyEquivalent: "r"
        ).target = self

        attachMenuItem = NSMenuItem(
            title: "Attach Button to Spine",
            action: #selector(toggleAttachedButton),
            keyEquivalent: ""
        )
        attachMenuItem.target = self
        attachMenuItem.state = .on
        menu.addItem(attachMenuItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func showReplacementWindow() {
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleAttachedButton() {
        overlayController.isEnabled.toggle()
        attachMenuItem.state = overlayController.isEnabled ? .on : .off
    }
}
