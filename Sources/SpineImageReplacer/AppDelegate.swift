import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var windowController: ReplacementWindowController!
    private var overlayController: SpineOverlayController!
    private var hotKeyController: GlobalHotKeyController!
    private let loginItemController = LoginItemController()
    private var attachMenuItem: NSMenuItem!
    private var launchAtLoginMenuItem: NSMenuItem!
    private var workspaceObservers: [NSObjectProtocol] = []
    private let launchPromptDefaultsKey = "hasAskedToLaunchAtLogin"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        windowController = ReplacementWindowController()
        windowController.onClose = { [weak self] in self?.restoreSpineFocus() }
        overlayController = SpineOverlayController { [weak self] in
            self?.showReplacementWindow()
        }
        overlayController.start()
        hotKeyController = GlobalHotKeyController { [weak self] in
            guard SpineApplicationLocator.runningApplications.contains(where: \.isActive) else { return }
            self?.showReplacementWindow()
        }
        installHotKeyLifecycleObservers()
        updateHotKeyRegistration()
        configureStatusItem()
        offerLaunchAtLoginIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlayController.stop()
        hotKeyController.stop()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
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
        let replaceItem = menu.addItem(
            withTitle: "Replace Images…",
            action: #selector(showReplacementWindow),
            keyEquivalent: "i"
        )
        replaceItem.keyEquivalentModifierMask = [.command, .shift]
        replaceItem.target = self

        attachMenuItem = NSMenuItem(
            title: "Attach Button to Spine",
            action: #selector(toggleAttachedButton),
            keyEquivalent: ""
        )
        attachMenuItem.target = self
        attachMenuItem.state = .on
        menu.addItem(attachMenuItem)

        launchAtLoginMenuItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginMenuItem.target = self
        menu.addItem(launchAtLoginMenuItem)
        refreshLaunchAtLoginMenuItem()
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func showReplacementWindow() {
        windowController.prepareForActiveSpineProject()
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleAttachedButton() {
        overlayController.isEnabled.toggle()
        attachMenuItem.state = overlayController.isEnabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        guard loginItemController.isInstalledApplication else {
            showLoginItemAlert(
                message: "Move Spine Image Replacer to Applications first.",
                information: "macOS can launch the companion automatically after it is placed in /Applications or your user Applications folder."
            )
            return
        }
        do {
            try loginItemController.setEnabled(!loginItemController.isEnabled)
            refreshLaunchAtLoginMenuItem()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Launch at Login needs approval"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Open Login Items Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                loginItemController.openSettings()
            }
            refreshLaunchAtLoginMenuItem()
        }
    }

    private func offerLaunchAtLoginIfNeeded() {
        let defaults = UserDefaults.standard
        guard loginItemController.isInstalledApplication,
              !loginItemController.isEnabled,
              !defaults.bool(forKey: launchPromptDefaultsKey)
        else { return }
        defaults.set(true, forKey: launchPromptDefaultsKey)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let alert = NSAlert()
            alert.messageText = "Keep Image Replacer ready for Spine?"
            alert.informativeText = "Launch it automatically when you log in. It stays quiet until Spine is active."
            alert.addButton(withTitle: "Enable Launch at Login")
            alert.addButton(withTitle: "Not Now")
            if alert.runModal() == .alertFirstButtonReturn {
                do {
                    try self.loginItemController.setEnabled(true)
                } catch {
                    self.showLoginItemAlert(
                        message: "Launch at Login could not be enabled.",
                        information: error.localizedDescription
                    )
                }
            }
            self.refreshLaunchAtLoginMenuItem()
        }
    }

    private func refreshLaunchAtLoginMenuItem() {
        launchAtLoginMenuItem?.state = loginItemController.isEnabled ? .on : .off
    }

    private func showLoginItemAlert(message: String, information: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = information
        alert.runModal()
    }

    private func restoreSpineFocus() {
        SpineApplicationLocator.activeApplication?.activate(options: [.activateIgnoringOtherApps])
    }

    private func installHotKeyLifecycleObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ]
        workspaceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.updateHotKeyRegistration()
            }
        }
    }

    private func updateHotKeyRegistration() {
        if SpineApplicationLocator.runningApplications.contains(where: \.isActive) {
            _ = hotKeyController.start()
        } else {
            hotKeyController.stop()
        }
    }
}
