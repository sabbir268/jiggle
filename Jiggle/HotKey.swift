import Carbon.HIToolbox
import Combine

/// One global hotkey via Carbon `RegisterEventHotKey` (default ⌃⌥⌘J). No Accessibility permission needed.
@MainActor
final class HotKey: ObservableObject {
    static let displayString = "⌃⌥⌘J"

    @Published private(set) var isRegistered = false
    /// True when registration was attempted and failed (e.g. another app owns the shortcut).
    @Published private(set) var registrationFailed = false

    private let keyCode: UInt32
    private let modifiers: UInt32
    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(
        keyCode: UInt32 = UInt32(kVK_ANSI_J),
        modifiers: UInt32 = UInt32(controlKey | optionKey | cmdKey),
        action: @escaping () -> Void
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.action = action
    }

    func setEnabled(_ enabled: Bool) {
        enabled ? register() : unregister()
    }

    private func register() {
        guard hotKeyRef == nil else { return }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x4A49_474C), id: 1)  // 'JIGL'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        hotKeyRef = status == noErr ? ref : nil
        isRegistered = hotKeyRef != nil
        registrationFailed = hotKeyRef == nil
    }

    private func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        isRegistered = false
        registrationFailed = false
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, context, &handlerRef)
    }
}
