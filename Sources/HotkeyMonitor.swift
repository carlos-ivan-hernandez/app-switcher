import AppKit
import Carbon.HIToolbox

/// Intercepts Cmd+Tab (and related keys while switching) with a CGEvent tap,
/// so the system switcher never sees them.
final class HotkeyMonitor {
    enum Event {
        case next, previous, commit, cancel
        case commandReleased
        case type(String)
        case deleteBackward
    }

    /// Set by the owner: true while the switcher is open.
    var isSwitching = false

    private let handler: (Event) -> Void
    private var tap: CFMachPort?

    init(handler: @escaping (Event) -> Void) {
        self.handler = handler
    }

    /// Returns false if the tap can't be created (usually missing Accessibility permission).
    func start() -> Bool {
        if tap != nil { return true }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo!).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    private func emit(_ event: Event) {
        handler(event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables taps that are slow or interrupted; turn it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let command = flags.contains(.maskCommand)

        switch type {
        case .keyDown:
            if command && keyCode == kVK_Tab {
                emit(flags.contains(.maskShift) ? .previous : .next)
                return nil
            }
            if isSwitching {
                switch keyCode {
                case kVK_Escape: emit(.cancel)
                case kVK_Return, kVK_ANSI_KeypadEnter: emit(.commit)
                case kVK_UpArrow, kVK_LeftArrow: emit(.previous)
                case kVK_DownArrow, kVK_RightArrow: emit(.next)
                case kVK_Delete: emit(.deleteBackward)
                default:
                    if !flags.contains(.maskControl), let text = Self.typedText(event) { emit(.type(text)) }
                }
                return nil // swallow everything else while the switcher is open
            }

        case .keyUp:
            if isSwitching || (command && keyCode == kVK_Tab) { return nil }

        case .flagsChanged:
            if isSwitching && !command { emit(.commandReleased) }

        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    /// The printable text a key press would type, if any.
    private static func typedText(_ event: CGEvent) -> String? {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
        let text = String(utf16CodeUnits: chars, count: length)
        guard !text.isEmpty,
              text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return text
    }
}
