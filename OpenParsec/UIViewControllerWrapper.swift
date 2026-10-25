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
