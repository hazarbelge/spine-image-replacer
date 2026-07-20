import Carbon.HIToolbox
import Foundation

final class GlobalHotKeyController {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let action: () -> Void

    private static let hotKeyID = EventHotKeyID(signature: 0x5350494E, id: 1) // SPIN

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @discardableResult
    func start() -> Bool {
        guard hotKey == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            spineHotKeyHandler,
            1,
            &eventType,
            context,
            &eventHandler
        )
        guard handlerStatus == noErr else { return false }

        let modifiers = UInt32(cmdKey | shiftKey)
        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_I),
            modifiers,
            Self.hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        if registrationStatus != noErr {
            if let eventHandler { RemoveEventHandler(eventHandler) }
            eventHandler = nil
            return false
        }
        return true
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil
        eventHandler = nil
    }

    fileprivate func invoke() {
        DispatchQueue.main.async { [weak self] in self?.action() }
    }

    deinit {
        stop()
    }
}

private let spineHotKeyHandler: EventHandlerUPP = { _, _, context in
    guard let context else { return OSStatus(eventNotHandledErr) }
    Unmanaged<GlobalHotKeyController>.fromOpaque(context).takeUnretainedValue().invoke()
    return noErr
}
