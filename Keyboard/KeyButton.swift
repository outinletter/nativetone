import UIKit

enum KeyboardTheme {
    static let background = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.133, green: 0.137, blue: 0.145, alpha: 1) : UIColor(red: 0.82, green: 0.84, blue: 0.86, alpha: 1) }
    static let letterKey = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.42, alpha: 1) : .white }
    static let specialKey = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.27, alpha: 1) : UIColor(red: 0.67, green: 0.70, blue: 0.74, alpha: 1) }
    /// The top strip carries the brand colour: ink navy (dark) / ivory (light), with a gold accent.
    static let bar = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.07, green: 0.12, blue: 0.22, alpha: 1) : UIColor(red: 0.95, green: 0.92, blue: 0.85, alpha: 1) }
    static let accent = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.79, green: 0.66, blue: 0.42, alpha: 1) : UIColor(red: 0.60, green: 0.48, blue: 0.25, alpha: 1) }
    static let onAccent = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.04, green: 0.08, blue: 0.15, alpha: 1) : .white }
}

/// One reused, pre-warmed generator: creating a new one per key press adds noticeable latency.
enum Haptics {
    static var enabled = AppSettings.haptics
    private static let light = UIImpactFeedbackGenerator(style: .light)
    static func tap() {
        guard enabled else { return }
        light.impactOccurred()
        light.prepare()
    }
}

final class KeyButton: UIButton {
    enum Style { case letter, special }

    var onTap: (() -> Void)?
    var onRepeat: (() -> Void)?
    /// Character keys insert the moment the finger lands, like the system keyboard. Keys that also take
    /// a long press (space) or are not characters (shift, 123, return) fire when the finger lifts.
    lazy var triggersOnTouchDown: Bool = style == .letter
    private var firedOnDown = false

    private let style: Style
    private var popup: UILabel?
    private var delayTimer: Timer?
    private var repeatTimer: Timer?

    init(title: String? = nil, symbol: String? = nil, style: Style = .letter, fontSize: CGFloat = 22) {
        self.style = style
        super.init(frame: .zero)
        backgroundColor = style == .letter ? KeyboardTheme.letterKey : KeyboardTheme.specialKey
        layer.cornerRadius = 5
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        layer.shadowOpacity = 0.3
        setTitleColor(.label, for: .normal)
        titleLabel?.font = .systemFont(ofSize: fontSize)
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.6
        tintColor = .label
        if let title { setTitle(title, for: .normal) }
        if let symbol {
            setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17)), for: .normal)
        }

        addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if self.firedOnDown { self.firedOnDown = false; return }
            if self.onRepeat == nil { self.onTap?() }
        }, for: .touchUpInside)

        addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.firedOnDown = false
            if self.triggersOnTouchDown, self.onRepeat == nil, let tap = self.onTap {
                self.firedOnDown = true
                tap()
            }
            Haptics.tap()
            self.showPopup()
            self.beginRepeat()
        }, for: .touchDown)
        for e: UIControl.Event in [.touchUpInside, .touchUpOutside, .touchCancel] {
            addAction(UIAction { [weak self] _ in self?.endRepeat(); self?.hidePopup(); if e != .touchUpInside { self?.firedOnDown = false } }, for: e)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// A fixed shadow path keeps the key shadow out of the slow off-screen rendering pass on every touch.
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    /// Visual state for toggles such as shift.
    func setActive(_ active: Bool) {
        backgroundColor = active ? KeyboardTheme.letterKey : KeyboardTheme.specialKey
    }

    /// iOS-style key preview bubble above the pressed character key.
    private func showPopup() {
        guard style == .letter, let t = title(for: .normal), t.count == 1 else { return }
        // The bubble is built once per key and only shown or hidden afterwards.
        if popup == nil {
            let l = UILabel()
            l.font = .systemFont(ofSize: 34)
            l.textColor = .label
            l.textAlignment = .center
            l.backgroundColor = KeyboardTheme.letterKey
            l.layer.cornerRadius = 8
            l.isHidden = true
            addSubview(l)
            popup = l
        }
        guard let l = popup else { return }
        l.text = t
        let h = bounds.height * 1.15
        l.frame = CGRect(x: -bounds.width * 0.25, y: -h - 4, width: bounds.width * 1.5, height: h)
        l.isHidden = false
        layer.zPosition = 10
    }

    private var savedTitle: String?

    /// Shows arrows on the space bar while its cursor-slide mode is active.
    func setCursorMode(_ on: Bool) {
        if on {
            savedTitle = title(for: .normal)
            setTitle("◂   ▸", for: .normal)
        } else if let t = savedTitle {
            setTitle(t, for: .normal)
            savedTitle = nil
        }
    }

    private func hidePopup() {
        popup?.isHidden = true
        layer.zPosition = 0
    }

    private func beginRepeat() {
        guard let onRepeat else { return }
        onRepeat()
        delayTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { _ in onRepeat() }
        }
    }

    private func endRepeat() {
        delayTimer?.invalidate(); delayTimer = nil
        repeatTimer?.invalidate(); repeatTimer = nil
    }
}
