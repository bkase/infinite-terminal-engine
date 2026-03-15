import AppKit
import Carbon.HIToolbox
import CoreGraphics
import GhosttyKit

struct GhosttyKeyInput: Equatable {
    let action: UInt8
    let mods: UInt16
    let consumedMods: UInt16
    let keyCode: UInt16
    let text: String
    let unshiftedCodepoint: UInt32
    let composing: Bool
}

struct GhosttyMouseButtonInput: Equatable {
    let state: Int32
    let button: Int32
    let mods: Int32
    let location: CGPoint
}

struct GhosttyScrollInput: Equatable {
    let deltaX: Double
    let deltaY: Double
    let scrollMods: Int32
}

enum GhosttyKeyActionCode {
    static let release: UInt8 = 0
    static let press: UInt8 = 1
    static let repeatPress: UInt8 = 2
}

enum TerminalInputRoute: Equatable {
    case ignored
    case controlPlane
    case terminalInteraction
    case terminalBytes(Data)
    case copySelection
    case pasteRequest
}

enum InputNormalizer {
    static func panDelta(from start: CGPoint, to end: CGPoint) -> CGSize {
        CGSize(width: end.x - start.x, height: end.y - start.y)
    }

    static func zoomFactor(forMagnification magnification: CGFloat) -> Float {
        Float(max(0.25, min(4, 1 + magnification)))
    }

    static func fallbackZoomFactor(forScrollDeltaY deltaY: CGFloat) -> Float {
        let step = deltaY / 240
        let unclamped = pow(1.25, -step)
        return Float(max(0.25, min(4, unclamped)))
    }

    static func normalizedKeyInput(from event: NSEvent, action: UInt8? = nil) -> GhosttyKeyInput? {
        normalizedKeyInput(
            keyCode: Int(event.keyCode),
            characters: event.characters ?? "",
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            modifierFlags: event.modifierFlags,
            isRepeat: event.isARepeat,
            action: action
        )
    }

    static func normalizedKeyInput(
        keyCode: Int,
        characters: String,
        charactersIgnoringModifiers: String,
        modifierFlags: NSEvent.ModifierFlags,
        isRepeat: Bool,
        action: UInt8? = nil
    ) -> GhosttyKeyInput? {
        guard let mappedKeyCode = ghosttyKeyCode(for: keyCode) else { return nil }
        let scalar = charactersIgnoringModifiers.unicodeScalars.first
        let resolvedAction = action ?? (isRepeat ? GhosttyKeyActionCode.repeatPress : GhosttyKeyActionCode.press)
        return GhosttyKeyInput(
            action: resolvedAction,
            mods: ghosttyMods(from: modifierFlags),
            consumedMods: 0,
            keyCode: mappedKeyCode,
            text: characters,
            unshiftedCodepoint: scalar.map(\.value) ?? 0,
            composing: false
        )
    }

    @MainActor
    static func normalizedMouseButtonInput(from event: NSEvent, in view: NSView, pressed: Bool) -> GhosttyMouseButtonInput {
        GhosttyMouseButtonInput(
            state: Int32((pressed ? GHOSTTY_MOUSE_PRESS : GHOSTTY_MOUSE_RELEASE).rawValue),
            button: ghosttyMouseButton(for: event.type),
            mods: Int32(ghosttyMods(from: event.modifierFlags)),
            location: view.convert(event.locationInWindow, from: nil)
        )
    }

    static func normalizedScrollInput(from event: NSEvent) -> GhosttyScrollInput {
        GhosttyScrollInput(
            deltaX: Double(event.scrollingDeltaX),
            deltaY: Double(event.scrollingDeltaY),
            scrollMods: packedScrollMods(precision: event.hasPreciseScrollingDeltas, momentumPhase: event.momentumPhase)
        )
    }

    static func ghosttyMods(from flags: NSEvent.ModifierFlags) -> UInt16 {
        var mods: UInt16 = 0
        if flags.contains(.shift) { mods |= UInt16(GHOSTTY_MODS_SHIFT.rawValue) }
        if flags.contains(.control) { mods |= UInt16(GHOSTTY_MODS_CTRL.rawValue) }
        if flags.contains(.option) { mods |= UInt16(GHOSTTY_MODS_ALT.rawValue) }
        if flags.contains(.command) { mods |= UInt16(GHOSTTY_MODS_SUPER.rawValue) }
        if flags.contains(.capsLock) { mods |= UInt16(GHOSTTY_MODS_CAPS.rawValue) }
        if flags.contains(.numericPad) { mods |= UInt16(GHOSTTY_MODS_NUM.rawValue) }
        return mods
    }

    static func encodedPasteBytes(for text: String, bracketed: Bool) -> Data {
        let safeText = sanitizedPasteText(text)
        if bracketed {
            return Data("\u{1b}[200~".utf8) + Data(safeText.utf8) + Data("\u{1b}[201~".utf8)
        }

        let normalized = safeText
            .replacingOccurrences(of: "\r\n", with: "\r")
            .replacingOccurrences(of: "\n", with: "\r")
        return Data(normalized.utf8)
    }

    static func sanitizedPasteText(_ text: String) -> String {
        let endMarker = "\u{1b}[201~"
        return text.replacingOccurrences(of: endMarker, with: "")
    }

    private static func packedScrollMods(precision: Bool, momentumPhase: NSEvent.Phase) -> Int32 {
        var raw = UInt8(precision ? 1 : 0)
        raw |= UInt8(momentumBits(for: momentumPhase) << 1)
        return Int32(raw)
    }

    private static func momentumBits(for phase: NSEvent.Phase) -> UInt8 {
        switch phase {
        case .began: return 1
        case .stationary: return 2
        case .changed: return 3
        case .ended: return 4
        case .cancelled: return 5
        case .mayBegin: return 6
        default: return 0
        }
    }

    private static func ghosttyMouseButton(for type: NSEvent.EventType) -> Int32 {
        switch type {
        case .rightMouseDown, .rightMouseUp:
            return Int32(GHOSTTY_MOUSE_RIGHT.rawValue)
        case .otherMouseDown, .otherMouseUp:
            return Int32(GHOSTTY_MOUSE_MIDDLE.rawValue)
        default:
            return Int32(GHOSTTY_MOUSE_LEFT.rawValue)
        }
    }

    private static func ghosttyKeyCode(for keyCode: Int) -> UInt16? {
        switch keyCode {
        case kVK_Return: return UInt16(GHOSTTY_KEY_ENTER.rawValue)
        case kVK_Tab: return UInt16(GHOSTTY_KEY_TAB.rawValue)
        case kVK_Space: return UInt16(GHOSTTY_KEY_SPACE.rawValue)
        case kVK_Delete: return UInt16(GHOSTTY_KEY_BACKSPACE.rawValue)
        case kVK_Escape: return UInt16(GHOSTTY_KEY_ESCAPE.rawValue)
        case kVK_Command: return UInt16(GHOSTTY_KEY_META_LEFT.rawValue)
        case kVK_RightCommand: return UInt16(GHOSTTY_KEY_META_RIGHT.rawValue)
        case kVK_Shift: return UInt16(GHOSTTY_KEY_SHIFT_LEFT.rawValue)
        case kVK_RightShift: return UInt16(GHOSTTY_KEY_SHIFT_RIGHT.rawValue)
        case kVK_Option: return UInt16(GHOSTTY_KEY_ALT_LEFT.rawValue)
        case kVK_RightOption: return UInt16(GHOSTTY_KEY_ALT_RIGHT.rawValue)
        case kVK_Control: return UInt16(GHOSTTY_KEY_CONTROL_LEFT.rawValue)
        case kVK_RightControl: return UInt16(GHOSTTY_KEY_CONTROL_RIGHT.rawValue)
        case kVK_ForwardDelete: return UInt16(GHOSTTY_KEY_DELETE.rawValue)
        case kVK_Home: return UInt16(GHOSTTY_KEY_HOME.rawValue)
        case kVK_End: return UInt16(GHOSTTY_KEY_END.rawValue)
        case kVK_PageUp: return UInt16(GHOSTTY_KEY_PAGE_UP.rawValue)
        case kVK_PageDown: return UInt16(GHOSTTY_KEY_PAGE_DOWN.rawValue)
        case kVK_LeftArrow: return UInt16(GHOSTTY_KEY_ARROW_LEFT.rawValue)
        case kVK_RightArrow: return UInt16(GHOSTTY_KEY_ARROW_RIGHT.rawValue)
        case kVK_DownArrow: return UInt16(GHOSTTY_KEY_ARROW_DOWN.rawValue)
        case kVK_UpArrow: return UInt16(GHOSTTY_KEY_ARROW_UP.rawValue)
        case kVK_F1: return UInt16(GHOSTTY_KEY_F1.rawValue)
        case kVK_F2: return UInt16(GHOSTTY_KEY_F2.rawValue)
        case kVK_F3: return UInt16(GHOSTTY_KEY_F3.rawValue)
        case kVK_F4: return UInt16(GHOSTTY_KEY_F4.rawValue)
        case kVK_F5: return UInt16(GHOSTTY_KEY_F5.rawValue)
        case kVK_F6: return UInt16(GHOSTTY_KEY_F6.rawValue)
        case kVK_F7: return UInt16(GHOSTTY_KEY_F7.rawValue)
        case kVK_F8: return UInt16(GHOSTTY_KEY_F8.rawValue)
        case kVK_F9: return UInt16(GHOSTTY_KEY_F9.rawValue)
        case kVK_F10: return UInt16(GHOSTTY_KEY_F10.rawValue)
        case kVK_F11: return UInt16(GHOSTTY_KEY_F11.rawValue)
        case kVK_F12: return UInt16(GHOSTTY_KEY_F12.rawValue)
        case kVK_ANSI_A: return UInt16(GHOSTTY_KEY_A.rawValue)
        case kVK_ANSI_B: return UInt16(GHOSTTY_KEY_B.rawValue)
        case kVK_ANSI_C: return UInt16(GHOSTTY_KEY_C.rawValue)
        case kVK_ANSI_D: return UInt16(GHOSTTY_KEY_D.rawValue)
        case kVK_ANSI_E: return UInt16(GHOSTTY_KEY_E.rawValue)
        case kVK_ANSI_F: return UInt16(GHOSTTY_KEY_F.rawValue)
        case kVK_ANSI_G: return UInt16(GHOSTTY_KEY_G.rawValue)
        case kVK_ANSI_H: return UInt16(GHOSTTY_KEY_H.rawValue)
        case kVK_ANSI_I: return UInt16(GHOSTTY_KEY_I.rawValue)
        case kVK_ANSI_J: return UInt16(GHOSTTY_KEY_J.rawValue)
        case kVK_ANSI_K: return UInt16(GHOSTTY_KEY_K.rawValue)
        case kVK_ANSI_L: return UInt16(GHOSTTY_KEY_L.rawValue)
        case kVK_ANSI_M: return UInt16(GHOSTTY_KEY_M.rawValue)
        case kVK_ANSI_N: return UInt16(GHOSTTY_KEY_N.rawValue)
        case kVK_ANSI_O: return UInt16(GHOSTTY_KEY_O.rawValue)
        case kVK_ANSI_P: return UInt16(GHOSTTY_KEY_P.rawValue)
        case kVK_ANSI_Q: return UInt16(GHOSTTY_KEY_Q.rawValue)
        case kVK_ANSI_R: return UInt16(GHOSTTY_KEY_R.rawValue)
        case kVK_ANSI_S: return UInt16(GHOSTTY_KEY_S.rawValue)
        case kVK_ANSI_T: return UInt16(GHOSTTY_KEY_T.rawValue)
        case kVK_ANSI_U: return UInt16(GHOSTTY_KEY_U.rawValue)
        case kVK_ANSI_V: return UInt16(GHOSTTY_KEY_V.rawValue)
        case kVK_ANSI_W: return UInt16(GHOSTTY_KEY_W.rawValue)
        case kVK_ANSI_X: return UInt16(GHOSTTY_KEY_X.rawValue)
        case kVK_ANSI_Y: return UInt16(GHOSTTY_KEY_Y.rawValue)
        case kVK_ANSI_Z: return UInt16(GHOSTTY_KEY_Z.rawValue)
        case kVK_ANSI_0: return UInt16(GHOSTTY_KEY_DIGIT_0.rawValue)
        case kVK_ANSI_1: return UInt16(GHOSTTY_KEY_DIGIT_1.rawValue)
        case kVK_ANSI_2: return UInt16(GHOSTTY_KEY_DIGIT_2.rawValue)
        case kVK_ANSI_3: return UInt16(GHOSTTY_KEY_DIGIT_3.rawValue)
        case kVK_ANSI_4: return UInt16(GHOSTTY_KEY_DIGIT_4.rawValue)
        case kVK_ANSI_5: return UInt16(GHOSTTY_KEY_DIGIT_5.rawValue)
        case kVK_ANSI_6: return UInt16(GHOSTTY_KEY_DIGIT_6.rawValue)
        case kVK_ANSI_7: return UInt16(GHOSTTY_KEY_DIGIT_7.rawValue)
        case kVK_ANSI_8: return UInt16(GHOSTTY_KEY_DIGIT_8.rawValue)
        case kVK_ANSI_9: return UInt16(GHOSTTY_KEY_DIGIT_9.rawValue)
        case kVK_ANSI_Minus: return UInt16(GHOSTTY_KEY_MINUS.rawValue)
        case kVK_ANSI_Equal: return UInt16(GHOSTTY_KEY_EQUAL.rawValue)
        case kVK_ANSI_LeftBracket: return UInt16(GHOSTTY_KEY_BRACKET_LEFT.rawValue)
        case kVK_ANSI_RightBracket: return UInt16(GHOSTTY_KEY_BRACKET_RIGHT.rawValue)
        case kVK_ANSI_Backslash: return UInt16(GHOSTTY_KEY_BACKSLASH.rawValue)
        case kVK_ANSI_Semicolon: return UInt16(GHOSTTY_KEY_SEMICOLON.rawValue)
        case kVK_ANSI_Quote: return UInt16(GHOSTTY_KEY_QUOTE.rawValue)
        case kVK_ANSI_Grave: return UInt16(GHOSTTY_KEY_BACKQUOTE.rawValue)
        case kVK_ANSI_Comma: return UInt16(GHOSTTY_KEY_COMMA.rawValue)
        case kVK_ANSI_Period: return UInt16(GHOSTTY_KEY_PERIOD.rawValue)
        case kVK_ANSI_Slash: return UInt16(GHOSTTY_KEY_SLASH.rawValue)
        default:
            return nil
        }
    }
}
