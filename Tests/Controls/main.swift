import Foundation

var passed = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
	guard condition() else { fatalError("FAIL: \(name)") }
	passed += 1
	print("PASS: \(name)")
}

let current = ControlStreamSettings(resolution: "Client Resolution", bitrate: 8,
	constantFps: true, cursorMode: 1, zoomEnabled: true, preset: "responsive")
let desktop = ControlStreamSettings(resolution: "Client Resolution", bitrate: 25,
	constantFps: true, cursorMode: 0, zoomEnabled: false, preset: "quality")
let legacy: [String: QuickKeyLayout] = [
	"portrait.0": QuickKeyLayout(x: 0.1, y: 0.8, size: 62, opacity: 0.5),
	"landscape.2": QuickKeyLayout(x: 0.7, y: 0.2, size: 80, opacity: 0.3)
]
let fallback = ControlProfileArchive(current: current, desktop: desktop, legacy: legacy)
var archive = fallback
check(archive.active == .game, "migration selects existing game profile")
check(archive.profiles["game"]!.stream == current, "migration preserves all current stream controls")
check(archive.profiles["desktop"]!.stream == desktop, "PC gets independent stream settings")
check(archive.profiles["game"]!.buttons[0].layout(landscape: false, index: 0) == legacy["portrait.0"], "portrait migration preserves position size opacity")
check(archive.profiles["desktop"]!.buttons[2].layout(landscape: true, index: 2) == legacy["landscape.2"], "landscape migration initializes PC placements")

let gameID = archive.profiles["game"]!.buttons[0].id
archive.profiles["game"]!.changeKey(id: gameID, code: 40)
archive.profiles["game"]!.buttons[0].layouts["portrait"] = QuickKeyLayout(x: 0.4, y: 0.3)
check(archive.profiles["desktop"]!.buttons[0].code == 41, "changing a game key leaves PC unchanged")
check(archive.profiles["desktop"]!.buttons[0].layouts["portrait"] == legacy["portrait.0"], "game layout changes leave PC unchanged")
check(archive.profiles["game"]!.buttons[0].layouts["landscape"] == nil, "portrait changes leave landscape unchanged")

var profile = archive.profiles["game"]!
check(profile.add(code: 40) == nil, "duplicate key cannot acquire a second independent hold")
check(profile.add(code: 999) == nil, "unknown HID key rejected")
let enterID = profile.buttons[0].id
profile.changeKey(id: enterID, code: 22)
check(profile.buttons[0].code == 40, "changing key to one already assigned is rejected")
for choice in QuickKeyChoice.all { _ = profile.add(code: choice.id) }
check(profile.buttons.count == 12, "button count capped at twelve")
for button in profile.buttons { profile.remove(id: button.id) }
check(profile.buttons.count == 1, "cannot remove final control")

var corrupt = ControlProfile(buttons: [QuickControlButton(code: 999), QuickControlButton(code: 22), QuickControlButton(code: 22)], stream: current)
corrupt.sanitize()
check(corrupt.buttons.map(\.code) == [22], "archive sanitation rejects unknown and duplicate codes")
corrupt.buttons = []
corrupt.sanitize()
check(corrupt.buttons.map(\.code) == [41, 22, 44], "empty archive recovers default buttons")
let bounded = QuickKeyLayout(x: -2, y: 4, size: 0, opacity: 0).clamped
check(bounded == QuickKeyLayout(x: 0, y: 1, size: 44, opacity: 0.25), "out-of-range layout remains reachable and visible")
check(QuickKeyLayout(x: .nan, y: 1).clamped.x.isFinite, "non-finite imported layout recovers")
archive.active = .desktop
let data = try JSONEncoder().encode(archive)
var restored = try JSONDecoder().decode(ControlProfileArchive.self, from: data)
restored.sanitize(fallback: fallback)
check(restored.active == .desktop, "profile selection survives archive roundtrip")
check(restored.profiles["game"]!.buttons[0].code == 40, "changed key survives archive roundtrip")
check(restored.profiles["game"]!.buttons[0].layouts["portrait"]!.x == 0.4, "edited layout survives archive roundtrip")
restored.profiles.removeValue(forKey: "desktop")
restored.sanitize(fallback: fallback)
check(restored.profiles["desktop"] != nil, "missing profile recovers without deleting game profile")
check(Set(QuickKeyChoice.all.map(\.id)).count == QuickKeyChoice.all.count, "key catalog has unique HID usages")
check(QuickKeyChoice.title(22) == "S" && QuickKeyChoice.title(227) == "Win", "S and Windows modifier use expected HID usages")

var recovery = ReconnectRecovery()
recovery.attempts = 2
recovery.noteHealthy(at: 100)
recovery.noteHealthy(at: 104.9)
check(recovery.attempts == 2, "brief reconnect does not refill retry budget")
recovery.noteFailure()
recovery.noteHealthy(at: 200)
recovery.noteHealthy(at: 204.9)
check(recovery.attempts == 2, "healthy windows across failures do not accumulate")
recovery.noteHealthy(at: 205)
check(recovery.attempts == 0, "five continuous healthy seconds refill retry budget")
recovery.attempts = 3
recovery.noteFailure()
for tick in 0..<20 {
	recovery.noteHealthy(at: Double(tick * 10))
	recovery.noteFailure()
}
check(recovery.attempts == 3, "flapping connection remains bounded despite repeated PARSEC_OK")
recovery.noteHealthy(at: 400)
recovery.noteFailure() // app resigns active
recovery.noteHealthy(at: 900)
check(recovery.attempts == 3, "background time never counts as healthy foreground time")
var hardware = WindowsHardwareKeyState()
for usage in [UInt32(224), 225, 226, 227, 228, 229, 230, 231] {
	check(hardware.transition(raw: usage, pressed: true, capsToHangul: true) == [.init(code: usage, pressed: true)], "modifier \(usage) maps directly to Windows HID")
	check(hardware.transition(raw: usage, pressed: true, capsToHangul: true).isEmpty, "modifier \(usage) duplicate press suppressed")
	check(hardware.transition(raw: usage, pressed: false, capsToHangul: true) == [.init(code: usage, pressed: false)], "modifier \(usage) releases Windows HID")
}
check(hardware.transition(raw: 57, pressed: true, capsToHangul: true) == [.init(code: 230, pressed: true), .init(code: 230, pressed: false)], "Caps Lock sends a complete Windows Right Alt IME tap")
check(hardware.transition(raw: 57, pressed: false, capsToHangul: false) .isEmpty, "consumed language keyup stays silent even if setting changed")
check(hardware.transition(raw: 57, pressed: true, capsToHangul: false) == [.init(code: 57, pressed: true)], "Caps remapping can be disabled")
_ = hardware.transition(raw: 57, pressed: false, capsToHangul: false)
check(hardware.transition(raw: 999, pressed: true, capsToHangul: true).isEmpty, "unknown hardware usage rejected")
_ = hardware.transition(raw: 57, pressed: true, capsToHangul: true)
check(hardware.transition(raw: 144, pressed: true, capsToHangul: true).isEmpty, "Caps and LANG1 do not double-toggle when both held")
check(hardware.transition(raw: 57, pressed: false, capsToHangul: true).isEmpty, "Caps release stays silent after atomic language pulse")
check(hardware.transition(raw: 144, pressed: false, capsToHangul: true) .isEmpty, "shared language key release never sends a second toggle")
check(hardware.reconcileModifiers([224, 226]) == [.init(code: 224, pressed: true), .init(code: 226, pressed: true)], "UIKit flags recover missing Ctrl and Option down events")
check(hardware.reconcileModifiers([224, 226]).isEmpty, "unchanged UIKit flags do not duplicate modifiers")
check(hardware.transition(raw: 6, pressed: true, capsToHangul: true) == [.init(code: 6, pressed: true)], "Ctrl+C forwards raw C without uppercase Shift")
_ = hardware.transition(raw: 6, pressed: false, capsToHangul: true)
check(hardware.reconcileModifiers([]) == [.init(code: 224, pressed: false), .init(code: 226, pressed: false)], "cleared flags release missing modifier up events")
_ = hardware.transition(raw: 228, pressed: true, capsToHangul: true)
check(hardware.reconcileModifiers([224]).isEmpty, "right Ctrl does not synthesize an extra left Ctrl")
hardware.reset()
check(hardware.held.isEmpty, "mode changes/background/release reset held-key bookkeeping")
check(!WindowsHardwareKeyState.repeats(144) && !WindowsHardwareKeyState.repeats(57) && !WindowsHardwareKeyState.repeats(224), "language and modifier keys never autorepeat")
check(WindowsHardwareKeyState.repeats(4) && WindowsHardwareKeyState.repeats(42), "letters and Backspace can repeat")
hardware.reset()
_ = hardware.transition(raw: 224, pressed: true, capsToHangul: true)
let controlSpace: [HardwareKeyPacket] = [.init(code: 224, pressed: false), .init(code: 230, pressed: true), .init(code: 230, pressed: false)]
check(hardware.transition(raw: 44, pressed: true, capsToHangul: true, controlSpaceToHangul: true) == controlSpace, "Control+Space pulses Hangul and immediately consumes held Ctrl")
check(hardware.transition(raw: 44, pressed: true, capsToHangul: true, controlSpaceToHangul: true).isEmpty, "holding Control+Space does not repeatedly change language")
check(hardware.transition(raw: 44, pressed: false, capsToHangul: true, controlSpaceToHangul: true).isEmpty, "consumed Space never leaks a Space keyup")
check(hardware.reconcileModifiers([224]).isEmpty, "stale Ctrl flags after language switching cannot restore Ctrl")
check(hardware.transition(raw: 44, pressed: true, capsToHangul: true, controlSpaceToHangul: true) == [.init(code: 44, pressed: true)], "ordinary Space after consumed Ctrl does not toggle language again")
_ = hardware.transition(raw: 44, pressed: false, capsToHangul: true)
check(hardware.transition(raw: 224, pressed: false, capsToHangul: true).isEmpty, "delayed physical Ctrl release is consumed after language chord")
_ = hardware.transition(raw: 224, pressed: true, capsToHangul: true)
check(hardware.transition(raw: 44, pressed: true, capsToHangul: true, controlSpaceToHangul: false) == [.init(code: 44, pressed: true)], "Control+Space language override can be disabled")
hardware.reset()
_ = hardware.transition(raw: 224, pressed: true, capsToHangul: true)
_ = hardware.transition(raw: 225, pressed: true, capsToHangul: true)
check(hardware.transition(raw: 44, pressed: true, capsToHangul: true, controlSpaceToHangul: true) == [.init(code: 44, pressed: true)], "Control+Shift+Space remains an ordinary chord")
check(DisplayCycle.next(ids: ["a", "b", "c"], current: "a") == "b", "display cycling advances one output")
check(DisplayCycle.next(ids: ["a", "b", "c"], current: "c") == "a", "display cycling wraps to first output")
check(DisplayCycle.next(ids: ["a", "b"], current: "none") == "a", "unknown initial output selects first available monitor")
check(DisplayCycle.next(ids: [], current: "a") == nil, "empty monitor list does not switch")
check(DisplayCycle.next(ids: ["", "none", "a", "a", "b"], current: "a") == "b", "invalid and duplicate monitor IDs are excluded")
check(DisplayCycle.next(ids: ["b", "c"], current: "removed") == "b", "removed monitor recovers to remaining output")
var mux = HardwareInputMux()
check(mux.accept(code: 43, pressed: true, source: .uiKit, at: 1), "UIKit input accepted even when a GC keyboard exists but emits nothing")
check(!mux.accept(code: 43, pressed: true, source: .gameController, at: 1.001), "mirrored GC keydown does not duplicate UIKit press")
check(mux.accept(code: 43, pressed: false, source: .uiKit, at: 1.01), "first actual keyup releases a merged press")
check(mux.accept(code: 43, pressed: true, source: .uiKit, at: 1.015), "a fast next press from the same source is retained")
check(!mux.accept(code: 43, pressed: false, source: .gameController, at: 1.016), "late duplicate keyup cannot release the next fast press")
check(mux.accept(code: 43, pressed: false, source: .uiKit, at: 1.02), "next fast press still receives its matching release")
mux.reset()
check(mux.accept(code: 4, pressed: true, source: .uiKit, at: 2), "UIKit-only keydown accepted")
check(mux.accept(code: 4, pressed: false, source: .uiKit, at: 2.01), "UIKit-only keyup accepted")
check(!mux.accept(code: 4, pressed: true, source: .gameController, at: 2.015), "late mirrored complete tap is suppressed across sources")
check(!mux.accept(code: 4, pressed: false, source: .gameController, at: 2.02), "late mirror release is suppressed")
check(mux.accept(code: 4, pressed: true, source: .gameController, at: 3), "GC source can take over after UIKit becomes unavailable")
check(!mux.accept(code: 4, pressed: true, source: .uiKit, at: 3.001), "mirrored UIKit event does not duplicate GC press")
check(mux.accept(code: 4, pressed: false, source: .gameController, at: 3.02), "GC-only press releases normally")
check(!mux.accept(code: 4, pressed: false, source: .uiKit, at: 3.021), "mirrored UIKit release is ignored")
mux.reset()
check(mux.accept(code: 224, pressed: true, source: .gameController, at: 4), "reset permits a fresh modifier press")
check(mux.accept(code: 224, pressed: false, source: .uiKit, at: 4.01), "secondary source recovers missing primary keyup")

hardware.reset()
_ = hardware.transition(raw: 224, pressed: true, capsToHangul: true)
_ = hardware.transition(raw: 226, pressed: true, capsToHangul: true)
check(hardware.controlAltOnly, "Ctrl+Option is detected as Windows Ctrl+Alt for monitor shortcut")
check(hardware.consumeShortcut(raw: 16) == [.init(code: 224, pressed: false), .init(code: 226, pressed: false)], "monitor shortcut releases and consumes modifiers without sending M")
check(!hardware.controlAltOnly, "consumed monitor shortcut does not retrigger from stale modifier flags")
check(hardware.transition(raw: 16, pressed: false, capsToHangul: true).isEmpty, "monitor shortcut M release never reaches Windows")
check(hardware.reconcileModifiers([224, 226]).isEmpty, "delayed Ctrl+Alt flags cannot re-hold consumed monitor modifiers")
hardware.reset()
var altTabPackets: [HardwareKeyPacket] = []
altTabPackets += hardware.transition(raw: 226, pressed: true, capsToHangul: true)
altTabPackets += hardware.transition(raw: 43, pressed: true, capsToHangul: true)
altTabPackets += hardware.transition(raw: 43, pressed: false, capsToHangul: true)
altTabPackets += hardware.transition(raw: 226, pressed: false, capsToHangul: true)
check(altTabPackets == [.init(code: 226, pressed: true), .init(code: 43, pressed: true), .init(code: 43, pressed: false), .init(code: 226, pressed: false)], "Option+Tab produces complete Windows Alt+Tab sequence")
hardware.reset()
_ = hardware.transition(raw: 226, pressed: true, capsToHangul: true)
_ = hardware.transition(raw: 43, pressed: true, capsToHangul: true)
check(hardware.consumeShortcut(raw: 43) == [.init(code: 43, pressed: false), .init(code: 226, pressed: false)], "command fallback closes already-forwarded native Alt+Tab without another Tab press")
_ = hardware.transition(raw: 226, pressed: true, capsToHangul: true)
check(hardware.consumeShortcut(raw: 43).isEmpty, "late mirrored Alt down stays consumed until real release")
check(WindowsHardwareKeyState.mappedCode(57, capsToHangul: true) == WindowsHardwareKeyState.mappedCode(144, capsToHangul: true), "Caps and LANG1 aliases are canonicalized before native source deduplication")

var shortcutGate = HardwareShortcutGate()
check(shortcutGate.allow(.altTab, source: .raw, at: 10), "native shortcut accepted")
check(!shortcutGate.allow(.altTab, source: .command, at: 10.01), "UIKeyCommand does not duplicate the native shortcut")
check(shortcutGate.allow(.altTab, source: .command, at: 11), "UIKeyCommand can handle a later shortcut with missing native input")
check(!shortcutGate.allow(.altTab, source: .raw, at: 11.01), "late native shortcut does not duplicate UIKeyCommand")
check(shortcutGate.allow(.altTab, source: .command, at: 11.02), "same-source repeated shortcut remains available")
check(shortcutGate.allow(.hangul, source: .raw, at: 11.03), "different shortcut is not suppressed by recent Alt+Tab")
shortcutGate.reset()
check(shortcutGate.allow(.altTab, source: .raw, at: 11.04), "reset clears shortcut deduplication state")

check(WindowsHardwareKeyState.mappedCode(41, capsToHangul: true, escapeAsOption: true) == 226, "reported HID 41 Option maps to left Alt in compatibility mode")
check(WindowsHardwareKeyState.mappedCode(41, capsToHangul: true, escapeAsOption: false) == 41, "disabling compatibility retains physical Escape")
check(WindowsHardwareKeyState.mappedCode(224, capsToHangul: true, escapeAsOption: true) == 224, "working physical Ctrl is unchanged")
hardware.reset()
let mappedOption = WindowsHardwareKeyState.mappedCode(41, capsToHangul: true, escapeAsOption: true)!
_ = hardware.transition(raw: mappedOption, pressed: true, capsToHangul: true)
check(hardware.reconcileModifiers([226]).isEmpty && hardware.altOnly, "compatibility Option remains held across UIKit Tab with no alternate flag")
check(hardware.transition(raw: 43, pressed: true, capsToHangul: true) == [.init(code: 43, pressed: true)], "compatibility Option plus Tab reaches Windows as Alt Tab")
_ = hardware.transition(raw: 43, pressed: false, capsToHangul: true)
check(hardware.transition(raw: mappedOption, pressed: false, capsToHangul: true) == [.init(code: 226, pressed: false)], "compatibility Option releases Alt")
hardware.reset()
let pulse: [HardwareKeyPacket] = [.init(code: 230, pressed: true), .init(code: 230, pressed: false)]
check(hardware.transition(raw: 144, pressed: true, capsToHangul: true) == pulse, "semantic language usage sends Right Alt instead of ineffective LANG1")
check(!hardware.held.values.contains(230), "host language key is not held while physical release is delayed")
check(hardware.transition(raw: 144, pressed: true, capsToHangul: true).isEmpty, "language key repeat cannot repeatedly toggle IME")
_ = hardware.transition(raw: 144, pressed: false, capsToHangul: true)
check(hardware.transition(raw: 144, pressed: true, capsToHangul: true) == pulse, "next language press can toggle after release")


hardware.reset()
_ = hardware.transition(raw: 224, pressed: true, capsToHangul: true)
_ = hardware.transition(raw: 225, pressed: true, capsToHangul: true)
check(hardware.transition(raw: 57, pressed: true, capsToHangul: true) == [.init(code: 224, pressed: false), .init(code: 225, pressed: false)] + pulse, "Caps language tap releases Ctrl and Shift before Right Alt")
check(hardware.reconcileModifiers([224, 225]).isEmpty, "stale modifier flags after Caps cannot modify subsequent typing")
check(hardware.transition(raw: 4, pressed: true, capsToHangul: true) == [.init(code: 4, pressed: true)], "typing immediately after Caps sends a plain letter")
check(hardware.transition(raw: 224, pressed: false, capsToHangul: true).isEmpty, "late Ctrl up after Caps remains consumed")
hardware.reset()
check(hardware.pulseHangul(raw: 44) == pulse, "UIKeyCommand Control Space uses the same Windows Right Alt tap")
check(hardware.transition(raw: 44, pressed: false, capsToHangul: true).isEmpty, "command shortcut consumes trailing Space release")


var languageMux = HardwareInputMux()
var languageState = WindowsHardwareKeyState()
var languagePackets: [HardwareKeyPacket] = []
let languageTrace: [(UInt32, Bool, HardwareKeySource, TimeInterval)] = [
 (57, true, .uiKit, 20), (144, true, .gameController, 20.001),
 (57, false, .uiKit, 20.01), (144, false, .gameController, 20.011),
 (57, true, .uiKit, 21), (57, false, .uiKit, 21.01)
]
for (raw, pressed, source, time) in languageTrace {
 let routed = WindowsHardwareKeyState.mappedCode(raw, capsToHangul: true)!
 if languageMux.accept(code: routed, pressed: pressed, source: source, at: time) {
  languagePackets += languageState.transition(raw: routed, pressed: pressed, capsToHangul: true)
 }
}
check(languagePackets == pulse + pulse, "real HID 57 trace with mirrored LANG1 yields exactly two Right Alt taps")
check(!languagePackets.contains { $0.code == 57 || $0.code == 144 }, "hardware language route never leaks Caps Lock or ineffective LANG1 to Windows")
check(languageState.held.isEmpty, "complete physical language trace leaves no held keys")

print("All \(passed) control/profile/recovery/hardware keyboard/display regression checks passed.")
