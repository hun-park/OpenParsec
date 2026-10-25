import Foundation

enum ControlProfileID: String, Codable, CaseIterable {
	case game, desktop
	var title: String { self == .game ? "게임" : "PC" }
}

struct QuickKeyChoice: Identifiable {
	let id: UInt32
	let title: String
	static let all: [QuickKeyChoice] = {
		var keys: [QuickKeyChoice] = [
		.init(id: 41, title: "Esc"), .init(id: 44, title: "Space"),
		.init(id: 40, title: "Enter"), .init(id: 43, title: "Tab"),
		.init(id: 144, title: "한/영"),
		.init(id: 42, title: "Backspace"), .init(id: 76, title: "Del"),
		.init(id: 82, title: "↑"), .init(id: 81, title: "↓"),
		.init(id: 80, title: "←"), .init(id: 79, title: "→"),
		.init(id: 224, title: "Ctrl"), .init(id: 225, title: "Shift"),
		.init(id: 226, title: "Alt"), .init(id: 227, title: "Win")
		]
		keys += Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").enumerated().map {
		QuickKeyChoice(id: UInt32($0.offset + 4), title: String($0.element))
		}
		keys += (1...12).map { QuickKeyChoice(id: UInt32($0 + 57), title: "F\($0)") }
		keys += (1...9).map { QuickKeyChoice(id: UInt32($0 + 29), title: "\($0)") }
		keys.append(.init(id: 39, title: "0"))
		return keys
	}()
	static func title(_ code: UInt32) -> String { all.first { $0.id == code }?.title ?? "?" }
}

struct QuickKeyLayout: Codable, Equatable {
	var x: Double
	var y: Double
	var size: Double = 48
	var opacity: Double = 0.8
	var clamped: QuickKeyLayout {
		guard x.isFinite, y.isFinite, size.isFinite, opacity.isFinite else {
			return QuickKeyLayout(x: 0.9, y: 0.5)
		}
		return QuickKeyLayout(x: min(1, max(0, x)), y: min(1, max(0, y)),
		                      size: min(88, max(44, size)), opacity: min(1, max(0.25, opacity)))
	}
}

struct QuickControlButton: Codable, Identifiable {
	var id = UUID().uuidString
	var code: UInt32
	var layouts: [String: QuickKeyLayout] = [:]
	func layout(landscape: Bool, index: Int) -> QuickKeyLayout {
		if let stored = layouts[landscape ? "landscape" : "portrait"] { return stored.clamped }
		if index < 3 {
			return QuickKeyLayout(x: 0.94, y: 0.5 + Double(index - 1) * (landscape ? 0.18 : 0.09))
		}
		return QuickKeyLayout(x: 0.76 - Double((index - 3) / 5) * 0.16,
		                      y: 0.18 + Double((index - 3) % 5) * 0.15)
	}
}

struct ControlStreamSettings: Codable, Equatable {
	var resolution: String
	var bitrate: Int
	var constantFps: Bool
	var cursorMode: Int
	var zoomEnabled: Bool
	var preset: String
}

struct ControlProfile: Codable {
	var buttons: [QuickControlButton]
	var stream: ControlStreamSettings
	static let maximumButtons = 12
	static func defaults(_ stream: ControlStreamSettings) -> ControlProfile {
		ControlProfile(buttons: [41, 22, 44].map { QuickControlButton(code: $0) }, stream: stream)
	}
	mutating func sanitize() {
		var codes = Set<UInt32>()
		var ids = Set<String>()
		buttons = Array(buttons.filter { button in
			QuickKeyChoice.all.contains { $0.id == button.code } && codes.insert(button.code).inserted
		}.prefix(Self.maximumButtons))
		for index in buttons.indices {
			if !ids.insert(buttons[index].id).inserted { buttons[index].id = UUID().uuidString }
		}
		if buttons.isEmpty { buttons = Self.defaults(stream).buttons }
	}
	@discardableResult mutating func add(code: UInt32) -> String? {
		guard buttons.count < Self.maximumButtons, !buttons.contains(where: { $0.code == code }),
		      QuickKeyChoice.all.contains(where: { $0.id == code }) else { return nil }
		let button = QuickControlButton(code: code)
		buttons.append(button)
		return button.id
	}
	mutating func changeKey(id: String, code: UInt32) {
		guard let index = buttons.firstIndex(where: { $0.id == id }),
		      !buttons.contains(where: { $0.id != id && $0.code == code }),
		      QuickKeyChoice.all.contains(where: { $0.id == code }) else { return }
		buttons[index].code = code
	}
	mutating func remove(id: String) {
		guard buttons.count > 1 else { return }
		buttons.removeAll { $0.id == id }
	}
}

struct ControlProfileArchive: Codable {
	var active: ControlProfileID = .game
	var profiles: [String: ControlProfile]
	init(current: ControlStreamSettings, desktop: ControlStreamSettings, legacy: [String: QuickKeyLayout]) {
		var game = ControlProfile.defaults(current)
		for index in game.buttons.indices {
			for orientation in ["portrait", "landscape"] {
				game.buttons[index].layouts[orientation] = legacy["\(orientation).\(index)"]?.clamped
			}
		}
		// Value copies keep existing placements in both profiles on migration.
		var pc = game
		pc.stream = desktop
		profiles = [ControlProfileID.game.rawValue: game, ControlProfileID.desktop.rawValue: pc]
	}
	mutating func sanitize(fallback: ControlProfileArchive) {
		for id in ControlProfileID.allCases {
			if profiles[id.rawValue] == nil { profiles[id.rawValue] = fallback.profiles[id.rawValue] }
			profiles[id.rawValue]?.sanitize()
		}
	}
}

// A short PARSEC_OK interval must not refill an outage's retry budget.
struct ReconnectRecovery {
	var attempts = 0
	private(set) var healthySince: TimeInterval?
	mutating func noteFailure() { healthySince = nil }
	mutating func noteHealthy(at now: TimeInterval) {
		if healthySince == nil { healthySince = now }
		if let start = healthySince, now - start >= 5 { attempts = 0 }
	}
}

struct HardwareKeyPacket: Equatable {
	var code: UInt32
	var pressed: Bool
}

// Same HID usages on iPad and Windows for Ctrl/Option/Command. Store the
// key-down mapping so a setting change cannot orphan a different key on key-up.
struct WindowsHardwareKeyState {
	private(set) var held: [UInt32: UInt32] = [:]
	static func mappedCode(_ raw: UInt32, capsToHangul: Bool) -> UInt32? {
		guard (4...231).contains(raw) else { return nil }
		return raw == 57 && capsToHangul ? 144 : raw
	}
	mutating func transition(raw: UInt32, pressed: Bool, capsToHangul: Bool, controlSpaceToHangul: Bool = false) -> [HardwareKeyPacket] {
		if pressed {
			guard held[raw] == nil, let code = Self.mappedCode(raw, capsToHangul: capsToHangul) else { return [] }
			let controls = held.keys.filter { ($0 == 224 || $0 == 228) && held[$0] == $0 }.sorted()
			if raw == 44, controlSpaceToHangul, controlSpaceReady {
				// Consume Space until key-up. Pulse Hangul with Ctrl released on the
				// host. Consume delayed Ctrl releases instead of re-holding Ctrl over
				// the next typed letter (some Bluetooth keyboards delay modifier-up).
				held[raw] = 0
				for control in controls { held[control] = 0 }
				return controls.map { .init(code: $0, pressed: false) }
					+ [.init(code: 144, pressed: true), .init(code: 144, pressed: false)]
			}
			held[raw] = code
			// A dedicated LANG1 and remapped Caps Lock can share one host key.
			return held.filter { $0.value == code }.count == 1 ? [.init(code: code, pressed: true)] : []
		}
		guard let code = held.removeValue(forKey: raw), code != 0, !held.values.contains(code) else { return [] }
		return [.init(code: code, pressed: false)]
	}
	mutating func reconcileModifiers(_ activeLeftCodes: Set<UInt32>) -> [HardwareKeyPacket] {
		var output: [HardwareKeyPacket] = []
		for left in [UInt32(224), 225, 226, 227] {
			let right = left + 4
			if activeLeftCodes.contains(left) {
				if held[left] == nil && held[right] == nil {
					output += transition(raw: left, pressed: true, capsToHangul: false)
				}
			} else {
				output += transition(raw: left, pressed: false, capsToHangul: false)
				output += transition(raw: right, pressed: false, capsToHangul: false)
			}
		}
		return output
	}
	var controlAltOnly: Bool {
		let modifiers = held.filter { (224...231).contains($0.key) && $0.value != 0 }.map(\.key)
		return modifiers.contains(where: { $0 == 224 || $0 == 228 })
			&& modifiers.contains(where: { $0 == 226 || $0 == 230 })
			&& modifiers.allSatisfy { [224, 228, 226, 230].contains($0) }
	}
	var controlSpaceReady: Bool {
		held.contains(where: { ($0.key == 224 || $0.key == 228) && $0.value != 0 })
			&& held.keys.allSatisfy { $0 == 224 || $0 == 228 }
	}
	var altOnly: Bool {
		let modifiers = held.filter { (224...231).contains($0.key) && $0.value != 0 }.map(\.key)
		return !modifiers.isEmpty && modifiers.allSatisfy { $0 == 226 || $0 == 230 }
	}
	mutating func consumeShortcut(raw: UInt32) -> [HardwareKeyPacket] {
		var releases: [HardwareKeyPacket] = []
		if let key = held[raw], key != 0 { releases.append(.init(code: key, pressed: false)) }
		let modifiers = held.filter { (224...231).contains($0.key) && $0.value != 0 }.map(\.key).sorted()
		for modifier in modifiers { held[modifier] = 0 }
		held[raw] = 0
		return releases + modifiers.map { .init(code: $0, pressed: false) }
	}
	mutating func reset() { held.removeAll() }
	static func repeats(_ code: UInt32) -> Bool { code < 224 && code != 57 && code != 144 && code != 145 }
}

enum HardwareKeySource: Hashable { case gameController, uiKit }

enum HardwareShortcut: Hashable { case altTab, hangul, nextDisplay }
enum HardwareShortcutSource: Hashable { case raw, command }
struct HardwareShortcutGate {
	private var last: [HardwareShortcut: [HardwareShortcutSource: TimeInterval]] = [:]
	mutating func allow(_ shortcut: HardwareShortcut, source: HardwareShortcutSource, at now: TimeInterval) -> Bool {
		let other: HardwareShortcutSource = source == .raw ? .command : .raw
		if let time = last[shortcut]?[other], now >= time, now - time <= 0.08 { return false }
		last[shortcut, default: [:]][source] = now
		return true
	}
	mutating func reset() { last.removeAll() }
}

// Availability of GCKeyboard is not evidence of key delivery. Accept the first
// actual source per press and deduplicate mirrored events from the other source.
struct HardwareInputMux {
	private var owners: [UInt32: HardwareKeySource] = [:]
	private var pendingUps: [UInt32: Set<HardwareKeySource>] = [:]
	private var staleUps: [UInt32: Set<HardwareKeySource>] = [:]
	private var completed: [UInt32: (source: HardwareKeySource, time: TimeInterval)] = [:]
	private var suppressed: [UInt32: Set<HardwareKeySource>] = [:]
	mutating func accept(code: UInt32, pressed: Bool, source: HardwareKeySource, at now: TimeInterval) -> Bool {
		if pressed {
			if suppressed[code]?.contains(source) == true { return false }
			staleUps[code]?.remove(source)
			if owners[code] != nil {
				pendingUps[code, default: []].insert(source)
				return false
			}
			if let last = completed[code], last.source != source, now >= last.time, now - last.time <= 0.03 {
				suppressed[code, default: []].insert(source)
				return false
			}
			owners[code] = source
			pendingUps[code] = [source]
			return true
		}
		if suppressed[code]?.remove(source) != nil { return false }
		if staleUps[code]?.remove(source) != nil { return false }
		guard let owner = owners.removeValue(forKey: code) else { return false }
		let remaining = (pendingUps.removeValue(forKey: code) ?? []).subtracting([source])
		staleUps[code, default: []].formUnion(remaining)
		completed[code] = (owner, now)
		return true
	}
	mutating func reset() {
		owners.removeAll(); pendingUps.removeAll(); staleUps.removeAll(); completed.removeAll(); suppressed.removeAll()
	}
}

enum DisplayCycle {
	static func next(ids: [String], current: String) -> String? {
		var seen = Set<String>()
		let outputs = ids.filter { !$0.isEmpty && $0 != "none" && seen.insert($0).inserted }
		guard !outputs.isEmpty else { return nil }
		guard let index = outputs.firstIndex(of: current) else { return outputs.first }
		return outputs[(index + 1) % outputs.count]
	}
}
