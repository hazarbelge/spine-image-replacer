import AppKit
import CoreGraphics

final class SpineOverlayController {
    var isEnabled = true {
        didSet {
            if !isEnabled { panel.orderOut(nil) }
        }
    }

    private let panel: NSPanel
    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private let onClick: () -> Void
    private let buttonTarget = ButtonTarget()

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 44, height: 34),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel()
    }

    func start() {
        installWorkspaceObservers()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.20, repeats: true) { [weak self] _ in
            self?.updatePosition()
        }
        RunLoop.main.add(timer!, forMode: .common)
        updatePosition()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
        panel.orderOut(nil)
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.ignoresMouseEvents = false

        let effect = NSVisualEffectView(frame: panel.contentView!.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .titlebar
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 7
        effect.layer?.masksToBounds = true

        let button = NSButton(title: "", target: nil, action: nil)
        button.frame = effect.bounds.insetBy(dx: 3, dy: 3)
        button.autoresizingMask = [.width, .height]
        button.bezelStyle = .texturedRounded
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        button.image = NSImage(
            systemSymbolName: "photo.badge.arrow.down",
            accessibilityDescription: "Replace Images"
        )?.withSymbolConfiguration(symbolConfiguration)
        button.imagePosition = .imageOnly
        button.contentTintColor = .systemOrange
        button.toolTip = "Replace and align Spine images (⌘⇧I)"
        buttonTarget.action = { [weak self] in self?.onClick() }
        button.target = buttonTarget
        button.action = #selector(ButtonTarget.performAction)
        effect.addSubview(button)
        panel.contentView = effect
    }

    private func updatePosition() {
        guard isEnabled,
              let spine = SpineApplicationLocator.activeApplication,
              spine.isActive,
              let windowBounds = largestWindowBounds(for: spine.processIdentifier),
              let frame = appKitFrame(for: windowBounds)
        else {
            panel.orderOut(nil)
            return
        }

        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.maxX - size.width - 12,
            y: frame.maxY - size.height - 8
        )
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    private func installWorkspaceObservers() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification
        ]
        workspaceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.updatePosition()
            }
        }
    }

    private func largestWindowBounds(for pid: pid_t) -> CGRect? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        return windowList.compactMap { info -> CGRect? in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                  ownerPID.int32Value == pid,
                  let layer = info[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width > 400, frame.height > 300
            else { return nil }
            return frame
        }.max(by: { $0.width * $0.height < $1.width * $1.height })
    }

    private func appKitFrame(for cgFrame: CGRect) -> CGRect? {
        let center = CGPoint(x: cgFrame.midX, y: cgFrame.midY)
        for screen in NSScreen.screens {
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let displayBounds = CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value))
            if displayBounds.contains(center) {
                let x = screen.frame.minX + cgFrame.minX - displayBounds.minX
                let y = screen.frame.maxY - (cgFrame.minY - displayBounds.minY) - cgFrame.height
                return CGRect(x: x, y: y, width: cgFrame.width, height: cgFrame.height)
            }
        }
        return nil
    }
}

private final class ButtonTarget: NSObject {
    var action: (() -> Void)?

    @objc func performAction() {
        action?()
    }
}
