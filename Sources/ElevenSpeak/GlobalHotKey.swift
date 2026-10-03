import AppKit
import Carbon.HIToolbox

final class GlobalHotKey {
    struct Configuration: Equatable {
        let keyCode: UInt32
        let modifiers: UInt32
        let displayName: String
    }

    static let presets: [Configuration] = [
        .init(keyCode: UInt32(kVK_Escape), modifiers: UInt32(optionKey), displayName: "⌥ Esc"),
        .init(keyCode: UInt32(kVK_Escape), modifiers: UInt32(optionKey | controlKey), displayName: "⌃⌥ Esc"),
        .init(keyCode: UInt32(kVK_Escape), modifiers: UInt32(optionKey | cmdKey), displayName: "⌘⌥ Esc"),
        .init(keyCode: UInt32(kVK_Escape), modifiers: UInt32(optionKey | shiftKey), displayName: "⇧⌥ Esc")
    ]

    private var ref: EventHotKeyRef?
    private var handler: (() -> Void)?
    private var eventHandler: EventHandlerRef?

    func register(_ configuration: Configuration, handler: @escaping () -> Void) {
        unregister()
        self.handler = handler

        var id = EventHotKeyID(
            signature: OSType(0x4553504B),
            id: 1
        )

        RegisterEventHotKey(
            configuration.keyCode,
            configuration.modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                hotKey.handler?()
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    func unregister() {
        if let ref {
            UnregisterEventHotKey(ref)
            self.ref = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    deinit {
        unregister()
    }
}
