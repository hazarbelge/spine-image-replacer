import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var windowController: ReplacementWindowController!
    private var overlayController: SpineOverlayController!
    private var hotKeyController: GlobalHotKeyController!
    private let loginItemController = LoginItemController()
    private let applicationMover = ApplicationMover()
    private var attachMenuItem: NSMenuItem!
    private var launchAtLoginMenuItem: NSMenuItem!
    private var workspaceObservers: [NSObjectProtocol] = []
    private let movePromptDefaultsKey = "hasAskedToMoveToApplications"
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
        if offerMoveToApplicationsIfNeeded() { return }
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
            _ = offerMoveToApplicationsIfNeeded(force: true)
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

    @discardableResult
    private func offerMoveToApplicationsIfNeeded(force: Bool = false) -> Bool {
        let defaults = UserDefaults.standard
        guard !loginItemController.isInstalledApplication,
              force || !defaults.bool(forKey: movePromptDefaultsKey)
        else { return false }
        defaults.set(true, forKey: movePromptDefaultsKey)

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move Spine Image Replacer to Applications?"
        alert.informativeText = applicationMover.destinationExists
            ? "An existing copy in Applications will be replaced. The installed app can launch at login and stay ready whenever Spine is open."
            : "The installed app can launch at login and stay ready whenever Spine is open. It will reopen from \(applicationMover.destinationURL.deletingLastPathComponent().path)."
        alert.addButton(withTitle: applicationMover.destinationExists ? "Replace in Applications" : "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        do {
            let installedURL = try applicationMover.installCurrentApplication()
            applicationMover.relaunchInstalledApplication(at: installedURL) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .success:
                        self.applicationMover.trashOriginalApplicationIfPossible(installedURL: installedURL)
                        NSApp.terminate(nil)
                    case .failure(let error):
                        self.showLoginItemAlert(
                            message: "The installed app could not be opened.",
                            information: error.localizedDescription
                        )
                    }
                }
            }
            return true
        } catch {
            showLoginItemAlert(
                message: "Spine Image Replacer could not be moved.",
                information: error.localizedDescription
            )
            return false
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
