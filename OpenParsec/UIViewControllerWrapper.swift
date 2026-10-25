import SwiftUI
import UIKit

struct UIViewControllerWrapper<Wrapped: UIViewController>: UIViewControllerRepresentable {
	typealias UIViewControllerType = Wrapped

	let wrappedController: Wrapped

	init(_ wrappedController: Wrapped) {
		self.wrappedController = wrappedController
	}

	func makeUIViewController(context: Context) -> Wrapped {
		return wrappedController
	}

	func updateUIViewController(_ uiViewController: Wrapped, context: Context) {
		// No-op
	}
}

final class QuickKeyButton: UIButton {
	private let keyCode: UInt32
	private var keyIsDown = false
	private let feedback = UIImpactFeedbackGenerator(style: .light)

	init(title: String, keyCode: UInt32) {
		self.keyCode = keyCode
		super.init(frame: .zero)
		setTitle(title, for: .normal)
		setTitleColor(.white, for: .normal)
		titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
		backgroundColor = UIColor.black.withAlphaComponent(0.55)
		layer.cornerRadius = 10
		layer.borderWidth = 1
		layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
		accessibilityLabel = title == "Esc" ? "Escape" : title
		accessibilityIdentifier = "quickKey.\(keyCode)"
		addTarget(self, action: #selector(pressKey), for: [.touchDown, .touchDragEnter])
		addTarget(self, action: #selector(releaseKey), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
		NotificationCenter.default.addObserver(self, selector: #selector(releaseKey),
			name: UIApplication.willResignActiveNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(resetPressedState),
			name: NSNotification.Name("ParsecInputReleased"), object: nil)
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	deinit { NotificationCenter.default.removeObserver(self) }

	override func didMoveToWindow() {
		super.didMoveToWindow()
		if window == nil { releaseKey() }
	}

	@objc private func pressKey() {
		guard !keyIsDown else { return }
		keyIsDown = true
		if UserDefaults.standard.object(forKey: "quickKeyHaptics") as? Bool != false {
			feedback.impactOccurred(intensity: 0.45)
			feedback.prepare()
		}
		backgroundColor = UIColor.systemBlue.withAlphaComponent(0.85)
		// Raw HID S (22) avoids adding Shift just because the label is uppercase.
		CParsec.sendKeyboardMessage(keyCode: keyCode, pressed: true)
	}

	@objc func releaseKey() {
		guard keyIsDown else { return }
		resetPressedState()
		CParsec.sendKeyboardMessage(keyCode: keyCode, pressed: false)
	}

	@objc private func resetPressedState() {
		keyIsDown = false
		backgroundColor = UIColor.black.withAlphaComponent(0.55)
	}

	override func accessibilityActivate() -> Bool {
		guard isUserInteractionEnabled else { return false }
		pressKey()
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in self?.releaseKey() }
		return true
	}
}

final class QuickControlSettings: ObservableObject {
	static let shared = QuickControlSettings()
	@Published private var archive: ControlProfileArchive
	private var persistence = ControlProfilePersistence()
	var active: ControlProfileID { archive.active }
	var buttons: [QuickControlButton] { profile.buttons }
	var profile: ControlProfile { archive.profiles[active.rawValue]! }
	private init() {
		let current = Self.currentStream()
		let pc = ControlStreamSettings(resolution: ParsecResolution.client.rawValue, bitrate: 25,
			constantFps: true, cursorMode: CursorMode.touchpad.rawValue, zoomEnabled: false, preset: "quality")
		let oldData = UserDefaults.standard.data(forKey: "quickKeyLayoutsV1")
		let legacy = oldData.flatMap { try? JSONDecoder().decode([String: QuickKeyLayout].self, from: $0) } ?? [:]
		let fallback = ControlProfileArchive(current: current, desktop: pc, legacy: legacy)
		if let data = UserDefaults.standard.data(forKey: "controlProfilesV2"),
		   var decoded = try? JSONDecoder().decode(ControlProfileArchive.self, from: data) {
			decoded.sanitize(fallback: fallback)
			archive = decoded
		} else { archive = fallback }
		persist()
	}

	static func currentStream() -> ControlStreamSettings {
		ControlStreamSettings(resolution: SettingsHandler.resolution.rawValue, bitrate: SettingsHandler.bitrate,
			constantFps: SettingsHandler.constantFps, cursorMode: SettingsHandler.cursorMode.rawValue,
			zoomEnabled: SettingsHandler.zoomEnabled, preset: UserDefaults.standard.string(forKey: "streamQuickPreset") ?? "")
	}
	func persist() {
		if let data = try? persistence.dataIfChanged(archive) { UserDefaults.standard.set(data, forKey: "controlProfilesV2") }
	}
	func captureStream() {
		var updated = profile
		let stream = Self.currentStream()
		guard updated.stream != stream else { persist(); return }
		updated.stream = stream
		archive.profiles[active.rawValue] = updated
		persist()
	}
	func switchProfile() -> ControlStreamSettings {
		captureStream()
		archive.active = active == .game ? .desktop : .game
		persist()
		return profile.stream
	}
	private func update(_ operation: (inout ControlProfile) -> Void, persistNow: Bool = true) {
		var updated = profile
		operation(&updated)
		guard updated != profile else {
			if persistNow { persist() }
			return
		}
		archive.profiles[active.rawValue] = updated
		if persistNow { persist() }
	}
	func layout(_ id: String, landscape: Bool) -> QuickKeyLayout {
		guard let index = buttons.firstIndex(where: { $0.id == id }) else { return QuickKeyLayout(x: 0.9, y: 0.5) }
		return buttons[index].layout(landscape: landscape, index: index)
	}
	func save(_ value: QuickKeyLayout, id: String, landscape: Bool, persistNow: Bool = true) {
		update({ profile in
			guard let index = profile.buttons.firstIndex(where: { $0.id == id }) else { return }
			profile.buttons[index].layouts[landscape ? "landscape" : "portrait"] = value.clamped
		}, persistNow: persistNow)
	}
	func changeKey(id: String, code: UInt32) {
		CParsec.sendReleaseMessage()
		update { $0.changeKey(id: id, code: code) }
	}
	func add(code: UInt32) -> String? {
		var id: String?
		update { id = $0.add(code: code) }
		return id
	}
	func remove(id: String) {
		CParsec.sendReleaseMessage()
		update { $0.remove(id: id) }
	}
	func reset(landscape: Bool) {
		update { profile in
			for index in profile.buttons.indices { profile.buttons[index].layouts.removeValue(forKey: landscape ? "landscape" : "portrait") }
		}
	}
}

private struct SingleQuickKey: UIViewRepresentable {
	let code: UInt32
	let enabled: Bool
	func makeUIView(context: Context) -> QuickKeyButton {
		QuickKeyButton(title: QuickKeyChoice.title(code), keyCode: code)
	}
	func updateUIView(_ view: QuickKeyButton, context: Context) {
		if !enabled { view.releaseKey() }
		view.isUserInteractionEnabled = enabled
	}
	static func dismantleUIView(_ view: QuickKeyButton, coordinator: ()) { view.releaseKey() }
}

struct CustomQuickControls: View {
	let enabled: Bool
	@Binding var editing: Bool
	@ObservedObject private var settings = QuickControlSettings.shared
	@AppStorage("quickKeyHaptics") private var haptics = true
	@State private var selectedID = ""
	@State private var dragOrigin: CGPoint?
	private var selection: String {
		settings.buttons.contains(where: { $0.id == selectedID }) ? selectedID : settings.buttons.first!.id
	}
	private var selectedButton: QuickControlButton { settings.buttons.first { $0.id == selection }! }
	private var availableKeys: [QuickKeyChoice] {
		QuickKeyChoice.all.filter { choice in !settings.buttons.contains { $0.code == choice.id } }
	}
	private var selectableKeys: [QuickKeyChoice] {
		QuickKeyChoice.all.filter { choice in choice.id == selectedButton.code || !settings.buttons.contains(where: { $0.code == choice.id }) }
	}

	var body: some View {
		GeometryReader { geometry in
			let landscape = geometry.size.width > geometry.size.height
			ZStack {
				if editing { Color.black.opacity(0.25).contentShape(Rectangle()) }
				ForEach(settings.buttons) { button in
					key(button, size: geometry.size, landscape: landscape)
				}
				if editing {
					editor(landscape: landscape)
						.frame(maxWidth: 320, maxHeight: max(100, geometry.size.height - 16))
						.padding(8)
						.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
				}
			}
			.onChange(of: editing) { _ in
				dragOrigin = nil
				settings.persist()
				CParsec.sendReleaseMessage()
			}
			.onChange(of: landscape) { _ in dragOrigin = nil; settings.persist() }
			.onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
				dragOrigin = nil
				settings.persist()
			}
		}
	}

	private func center(_ layout: QuickKeyLayout, size: CGSize) -> CGPoint {
		let halfWidth = CGFloat(layout.size * 1.4 / 2) + 8
		let halfHeight = CGFloat(layout.size / 2) + 8
		return CGPoint(x: min(max(halfWidth, size.width - halfWidth), max(halfWidth, CGFloat(layout.x) * size.width)),
		               y: min(max(halfHeight, size.height - halfHeight), max(halfHeight, CGFloat(layout.y) * size.height)))
	}

	@ViewBuilder private func key(_ button: QuickControlButton, size: CGSize, landscape: Bool) -> some View {
		let layout = settings.layout(button.id, landscape: landscape)
		let position = center(layout, size: size)
		Group {
			if editing {
				Text(QuickKeyChoice.title(button.code))
					.font(.system(size: 14, weight: .semibold))
					.frame(width: layout.size * 1.4, height: layout.size)
					.background(selection == button.id ? Color.blue : Color.black.opacity(0.8))
					.cornerRadius(10)
					.overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white, lineWidth: 2))
					.gesture(DragGesture(minimumDistance: 0)
						.onChanged { value in
							selectedID = button.id
							if dragOrigin == nil { dragOrigin = position }
							guard let origin = dragOrigin, size.width > 0, size.height > 0 else { return }
							var updated = layout
							updated.x = Double((origin.x + value.translation.width) / size.width)
							updated.y = Double((origin.y + value.translation.height) / size.height)
							settings.save(updated, id: button.id, landscape: landscape, persistNow: false)
						}
						.onEnded { _ in dragOrigin = nil; settings.persist() })
			} else {
				SingleQuickKey(code: button.code, enabled: enabled)
					.id("\(settings.active.rawValue).\(button.id).\(button.code)")
					.frame(width: layout.size * 1.4, height: layout.size)
			}
		}
		.foregroundColor(.white)
		.opacity(editing ? 1 : layout.opacity * (enabled ? 1 : 0.4))
		.position(position)
	}

	private func editor(landscape: Bool) -> some View {
		VStack(spacing: 8) {
			HStack {
				Text("\(settings.active.title) · \(landscape ? "가로" : "세로")").font(.headline)
				Spacer()
				Button("완료") { settings.persist(); editing = false }
			}
			ScrollView {
				VStack(spacing: 10) {
					Text("버튼 드래그로 이동 · 자동 저장").font(.caption)
					Picker("편집할 버튼", selection: Binding(get: { selection }, set: { selectedID = $0 })) {
						ForEach(settings.buttons) { Text(QuickKeyChoice.title($0.code)).tag($0.id) }
					}.pickerStyle(MenuPickerStyle())
					Picker("키 변경", selection: Binding(get: { selectedButton.code }, set: { settings.changeKey(id: selection, code: $0) })) {
						ForEach(selectableKeys) { choice in
							Text(QuickKeyChoice.title(choice.id)).tag(choice.id)
						}
					}.pickerStyle(MenuPickerStyle())
					HStack {
						Menu("버튼 추가") {
							ForEach(availableKeys) { choice in
								Button(choice.title) { if let id = settings.add(code: choice.id) { selectedID = id } }
							}
						}.disabled(settings.buttons.count >= ControlProfile.maximumButtons)
						Spacer()
						Button("선택 삭제") { settings.remove(id: selection); selectedID = "" }
							.disabled(settings.buttons.count <= 1)
					}
					HStack { Text("크기").font(.caption); Slider(value: binding(\.size, landscape: landscape), in: 44...88, step: 2) }
					HStack { Text("투명도").font(.caption); Slider(value: binding(\.opacity, landscape: landscape), in: 0.25...1, step: 0.05) }
					Toggle("가벼운 진동", isOn: $haptics).font(.caption)
					Text("Ctrl·Alt·Shift·Win은 누르고 있는 동안 적용됩니다.").font(.caption)
					Button("현재 방향 배치 초기화") { settings.reset(landscape: landscape) }.font(.caption)
				}
			}
		}
		.padding(12)
		.background(Color.black.opacity(0.9))
		.foregroundColor(.white)
		.cornerRadius(12)
	}

	private func binding(_ path: WritableKeyPath<QuickKeyLayout, Double>, landscape: Bool) -> Binding<Double> {
		Binding(get: { settings.layout(selection, landscape: landscape)[keyPath: path] }, set: { value in
			var layout = settings.layout(selection, landscape: landscape)
			layout[keyPath: path] = value
			settings.save(layout, id: selection, landscape: landscape)
		})
	}
}
