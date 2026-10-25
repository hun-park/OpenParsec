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
print("All \(passed) control/profile/recovery regression checks passed.")
