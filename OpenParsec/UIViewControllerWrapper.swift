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

// A small native control surface so holding a key does not open the iOS keyboard
// or forward that finger to the stream's mouse/touch overlay.
struct QuickKeysOverlay: UIViewRepresentable {
	var enabled: Bool

	func makeUIView(context: Context) -> QuickKeysPanel {
		QuickKeysPanel()
	}

	func updateUIView(_ uiView: QuickKeysPanel, context: Context) {
		if !enabled { uiView.releaseAllKeys() }
		uiView.isUserInteractionEnabled = enabled
		uiView.alpha = enabled ? 1 : 0.4
	}

	static func dismantleUIView(_ uiView: QuickKeysPanel, coordinator: ()) {
		uiView.releaseAllKeys()
	}
}

final class QuickKeysPanel: UIView {
	private let keys = [
		QuickKeyButton(title: "Esc", keyCode: 41),
		QuickKeyButton(title: "S", keyCode: 22),
		QuickKeyButton(title: "Space", keyCode: 44)
	]

	init() {
		super.init(frame: .zero)
		let stack = UIStackView(arrangedSubviews: keys)
		stack.axis = .vertical
		stack.spacing = 10
		stack.distribution = .fillEqually
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),
			stack.topAnchor.constraint(equalTo: topAnchor),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor)
		])
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	func releaseAllKeys() { keys.forEach { $0.releaseKey() } }

	override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
		// Let the stream receive touches in the transparent gaps between keys.
		keys.contains { $0.point(inside: convert(point, to: $0), with: event) }
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

// Store normalized centers separately for each orientation. Clamp at display time
// so a layout saved on another screen or with a keyboard stays reachable.
struct QuickKeyLayout: Codable {
	var x: Double
	var y: Double
	var size: Double = 48
	var opacity: Double = 0.8
}

final class QuickControlSettings: ObservableObject {
	static let shared = QuickControlSettings()
	@Published private var layouts: [String: QuickKeyLayout]
	static let titles = ["Esc", "S", "Space"]
	static let codes: [UInt32] = [41, 22, 44]
	private init() {
		if let data = UserDefaults.standard.data(forKey: "quickKeyLayoutsV1"),
		   let decoded = try? JSONDecoder().decode([String: QuickKeyLayout].self, from: data) {
			layouts = decoded
		} else { layouts = [:] }
	}
	func layout(_ index: Int, landscape: Bool) -> QuickKeyLayout {
		let key = "\(landscape ? "landscape" : "portrait").\(index)"
		let fallback = QuickKeyLayout(x: 0.94, y: 0.5 + Double(index - 1) * (landscape ? 0.18 : 0.09))
		guard var value = layouts[key], value.x.isFinite, value.y.isFinite,
		      value.size.isFinite, value.opacity.isFinite else { return fallback }
		value.x = min(1, max(0, value.x)); value.y = min(1, max(0, value.y))
		value.size = min(88, max(44, value.size)); value.opacity = min(1, max(0.25, value.opacity))
		return value
	}

	func save(_ value: QuickKeyLayout, index: Int, landscape: Bool) {
		layouts["\(landscape ? "landscape" : "portrait").\(index)"] = value
		if let data = try? JSONEncoder().encode(layouts) {
			UserDefaults.standard.set(data, forKey: "quickKeyLayoutsV1")
		}
	}

	func reset(landscape: Bool) {
		for index in 0..<3 { layouts.removeValue(forKey: "\(landscape ? "landscape" : "portrait").\(index)") }
		if let data = try? JSONEncoder().encode(layouts) {
			UserDefaults.standard.set(data, forKey: "quickKeyLayoutsV1")
		}
	}
}

private struct SingleQuickKey: UIViewRepresentable {
	let index: Int
	let enabled: Bool
	func makeUIView(context: Context) -> QuickKeyButton {
		QuickKeyButton(title: QuickControlSettings.titles[index], keyCode: QuickControlSettings.codes[index])
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
	@State private var selected = 0
	@State private var dragOrigin: CGPoint?

	var body: some View {
		GeometryReader { geometry in
			let landscape = geometry.size.width > geometry.size.height
			ZStack {
				if editing {
					Color.black.opacity(0.25).contentShape(Rectangle())
				}
				ForEach(0..<3) { index in
					key(index, size: geometry.size, landscape: landscape)
				}
				if editing {
					editor(landscape: landscape)
						.frame(maxWidth: 320)
						.padding(8)
						.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
				}
			}
			.onChange(of: editing) { _ in
				dragOrigin = nil
				CParsec.sendReleaseMessage()
			}
		}
	}

	private func center(_ layout: QuickKeyLayout, size: CGSize) -> CGPoint {
		let halfWidth = CGFloat(layout.size * 1.4 / 2) + 8
		let halfHeight = CGFloat(layout.size / 2) + 8
		return CGPoint(x: min(max(halfWidth, size.width - halfWidth), max(halfWidth, CGFloat(layout.x) * size.width)),
		               y: min(max(halfHeight, size.height - halfHeight), max(halfHeight, CGFloat(layout.y) * size.height)))
	}

	@ViewBuilder private func key(_ index: Int, size: CGSize, landscape: Bool) -> some View {
		let layout = settings.layout(index, landscape: landscape)
		let position = center(layout, size: size)
		Group {
			if editing {
				Text(QuickControlSettings.titles[index])
					.font(.system(size: 14, weight: .semibold))
					.frame(width: layout.size * 1.4, height: layout.size)
					.background(selected == index ? Color.blue : Color.black.opacity(0.8))
					.cornerRadius(10)
					.overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white, lineWidth: 2))
					.gesture(DragGesture(minimumDistance: 0)
						.onChanged { value in
							selected = index
							if dragOrigin == nil { dragOrigin = position }
							guard let origin = dragOrigin, size.width > 0, size.height > 0 else { return }
							var updated = layout
							updated.x = min(1, max(0, Double((origin.x + value.translation.width) / size.width)))
							updated.y = min(1, max(0, Double((origin.y + value.translation.height) / size.height)))
							settings.save(updated, index: index, landscape: landscape)
						}
						.onEnded { _ in dragOrigin = nil })
			} else {
				SingleQuickKey(index: index, enabled: enabled)
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
				Text(landscape ? "가로 버튼 배치" : "세로 버튼 배치").font(.headline)
				Spacer()
				Button("완료") { editing = false }
			}
			Text("버튼을 드래그해서 이동 · 자동 저장").font(.caption)
			Picker("버튼", selection: $selected) {
				ForEach(0..<3) { Text(QuickControlSettings.titles[$0]).tag($0) }
			}.pickerStyle(SegmentedPickerStyle())
			HStack {
				Text("크기").font(.caption)
				Slider(value: binding(\.size, landscape: landscape), in: 44...88, step: 2)
			}
			HStack {
				Text("투명도").font(.caption)
				Slider(value: binding(\.opacity, landscape: landscape), in: 0.25...1, step: 0.05)
			}
			Toggle("가벼운 진동", isOn: $haptics).font(.caption)
			Button("현재 방향 배치 초기화") { settings.reset(landscape: landscape) }.font(.caption)
		}
		.padding(12)
		.background(Color.black.opacity(0.9))
		.foregroundColor(.white)
		.cornerRadius(12)
	}

	private func binding(_ path: WritableKeyPath<QuickKeyLayout, Double>, landscape: Bool) -> Binding<Double> {
		Binding(get: { settings.layout(selected, landscape: landscape)[keyPath: path] }, set: { value in
			var layout = settings.layout(selected, landscape: landscape)
			layout[keyPath: path] = value
			settings.save(layout, index: selected, landscape: landscape)
		})
	}
}
