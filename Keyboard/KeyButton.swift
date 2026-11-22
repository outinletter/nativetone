import UIKit

enum KeyboardTheme {
    static let background = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.17, alpha: 1) : UIColor(red: 0.82, green: 0.84, blue: 0.86, alpha: 1) }
    static let letterKey = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.42, alpha: 1) : .white }
    static let specialKey = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.27, alpha: 1) : UIColor(red: 0.67, green: 0.70, blue: 0.74, alpha: 1) }
    static let bar = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.12, alpha: 1) : UIColor(white: 0.95, alpha: 1) }
}

final class KeyButton: UIButton {
    enum Style { case letter, special }

    var onTap: (() -> Void)?
    var onRepeat: (() -> Void)?

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
            if self.onRepeat == nil { self.onTap?() }
        }, for: .touchUpInside)

        addAction(UIAction { [weak self] _ in
            if AppSettings.haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            self?.showPopup()
            self?.beginRepeat()
        }, for: .touchDown)
        for e: UIControl.Event in [.touchUpInside, .touchUpOutside, .touchCancel] {
            addAction(UIAction { [weak self] _ in self?.endRepeat(); self?.hidePopup() }, for: e)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    /// Visual state for toggles such as shift.
    func setActive(_ active: Bool) {
        backgroundColor = active ? KeyboardTheme.letterKey : KeyboardTheme.specialKey
    }

    /// iOS-style key preview bubble above the pressed character key.
    private func showPopup() {
        guard style == .letter, let t = title(for: .normal), t.count == 1, popup == nil else { return }
        let l = UILabel()
        l.text = t
        l.font = .systemFont(ofSize: 34)
        l.textColor = .label
        l.textAlignment = .center
        l.backgroundColor = KeyboardTheme.letterKey
        l.layer.cornerRadius = 8
        l.layer.masksToBounds = true
        let h = bounds.height * 1.15
        l.frame = CGRect(x: -bounds.width * 0.25, y: -h - 4, width: bounds.width * 1.5, height: h)
        addSubview(l)
        layer.zPosition = 10
        popup = l
    }

    private func hidePopup() {
        popup?.removeFromSuperview(); popup = nil
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
