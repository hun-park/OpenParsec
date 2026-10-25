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
