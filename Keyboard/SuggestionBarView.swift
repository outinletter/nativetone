import UIKit

/// One-line strip above the keys: [typed text / suggestion] [AI] [style].
/// The text is a plain UILabel (not a system button) so updating it on every keystroke never cross-fades or flickers.
/// While composing, the caret is drawn in the text and tapping the text moves it.
final class SuggestionBarView: UIView {
    enum State {
        case idle
        case loading
        case result(String)
        case ok(String)
        case message(String)
    }

    var autoMode = true
    var onTrigger: (() -> Void)?
    var onApply: (() -> Void)?
    var onToneTap: (() -> Void)?
    var onAIToggle: (() -> Void)?
    var onUndo: (() -> Void)?
    /// Long press on the bar: paste the clipboard into the field.
    var onPaste: (() -> Void)?
    /// True when the field is empty and the clipboard has text: the idle hint offers to paste it.
    var canPaste = false {
        didSet { if canPaste != oldValue, case .idle = state { set(.idle) } }
    }
    /// Called with the character index the user tapped while composing.
    var onCaretTap: ((Int) -> Void)?
    var onStateChange: (() -> Void)?

    private(set) var state: State = .idle
    private var tone: Tone = AppSettings.tone

    private let label = UILabel()
    private let aiButton = UIButton(type: .custom)
    private let toneButton = UIButton(type: .system)
    private let undoButton = UIButton(type: .system)
    private let undoSlot = UIView()
    private let applyButton = UIButton(type: .system)
    private let applySlot = UIView()
    private static let circle: CGFloat = 30

    private var shownKey = ""

    /// Extra height the bar extends above the keyboard view to cover the system's top padding.
    private let overhang: CGFloat

    init(overhang: CGFloat = 0) {
        self.overhang = overhang
        super.init(frame: .zero)
        backgroundColor = KeyboardTheme.bar

        label.numberOfLines = 1
        label.isUserInteractionEnabled = true
        label.lineBreakMode = .byClipping
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(labelTapped(_:))))
        label.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(labelLongPressed(_:))))
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Style icon (left) plus round undo and AI buttons (right), all in 30pt slots.
        let d = Self.circle
        aiButton.setTitle("AI", for: .normal)
        aiButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        aiButton.layer.cornerRadius = d / 2
        aiButton.layer.borderWidth = 1.5
        aiButton.addAction(UIAction { [weak self] _ in
            Haptics.tap()
            self?.onAIToggle?()
        }, for: .touchUpInside)

        toneButton.tintColor = KeyboardTheme.accent
        toneButton.addAction(UIAction { [weak self] _ in self?.onToneTap?() }, for: .touchUpInside)

        undoButton.setImage(UIImage(systemName: "arrow.uturn.backward", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)), for: .normal)
        undoButton.tintColor = KeyboardTheme.onAccent
        undoButton.backgroundColor = KeyboardTheme.accent
        undoButton.layer.cornerRadius = d / 2
        undoButton.layer.borderWidth = 1.5
        undoButton.layer.borderColor = KeyboardTheme.accent.cgColor
        undoButton.addAction(UIAction { [weak self] _ in
            Haptics.tap()
            self?.onUndo?()
        }, for: .touchUpInside)
        undoSlot.isHidden = true

        applyButton.setImage(UIImage(systemName: "arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)), for: .normal)
        applyButton.tintColor = KeyboardTheme.onAccent
        applyButton.backgroundColor = KeyboardTheme.accent
        applyButton.layer.cornerRadius = d / 2
        applyButton.layer.borderWidth = 1.5
        applyButton.layer.borderColor = KeyboardTheme.accent.cgColor
        applyButton.addAction(UIAction { [weak self] _ in
            Haptics.tap()
            self?.onApply?()
        }, for: .touchUpInside)
        Self.fill(applySlot, with: applyButton)
        updateApplyButton()

        let toneSlot = Self.slot(toneButton)
        Self.fill(undoSlot, with: undoButton)
        let aiSlot = Self.slot(aiButton)

        let stack = UIStackView(arrangedSubviews: [toneSlot, label, undoSlot, aiSlot, applySlot])
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: overhang),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
        let rule = UIView()
        rule.backgroundColor = KeyboardTheme.accent.withAlphaComponent(0.6)
        rule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rule)
        NSLayoutConstraint.activate([
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: bottomAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1),
        ])
        applyAIAppearance()
        set(.idle)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private static func slot(_ b: UIButton) -> UIView {
        let v = UIView()
        fill(v, with: b)
        return v
    }

    private static func fill(_ slot: UIView, with b: UIButton) {
        b.translatesAutoresizingMaskIntoConstraints = false
        slot.addSubview(b)
        NSLayoutConstraint.activate([
            slot.widthAnchor.constraint(equalToConstant: circle),
            b.widthAnchor.constraint(equalToConstant: circle),
            b.heightAnchor.constraint(equalToConstant: circle),
            b.centerXAnchor.constraint(equalTo: slot.centerXAnchor),
            b.centerYAnchor.constraint(equalTo: slot.centerYAnchor),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The visible window depends on the label width, which is only known after layout.
        if label.bounds.width != lastWidth { lastWidth = label.bounds.width; shownKey = ""; render() }
    }
    private var lastWidth: CGFloat = 0

    // MARK: - AI switch

    /// Off = plain keyboard: no hint text, dimmed style button.
    var aiEnabled = true {
        didSet {
            guard aiEnabled != oldValue else { return }
            applyAIAppearance()
            render()
        }
    }

    /// Shown right after a conversion was applied, so it can be undone.
    func setUndoAvailable(_ on: Bool) { undoSlot.isHidden = !on || !aiEnabled }

    private func applyAIAppearance() {
        updateApplyButton()
        UIView.performWithoutAnimation {
            if aiEnabled {
                aiButton.backgroundColor = KeyboardTheme.accent
                aiButton.layer.borderColor = KeyboardTheme.accent.cgColor
                aiButton.setTitleColor(KeyboardTheme.onAccent, for: .normal)
                toneButton.alpha = 1
            } else {
                aiButton.backgroundColor = .clear
                aiButton.layer.borderColor = UIColor.tertiaryLabel.cgColor
                aiButton.setTitleColor(.secondaryLabel, for: .normal)
                toneButton.alpha = 0.35
            }
            toneButton.isUserInteractionEnabled = aiEnabled
        }
    }

    /// Always shown at the far right while AI is on; lit only when a suggestion is ready to apply.
    private func updateApplyButton() {
        applySlot.isHidden = !aiEnabled
        var ready = false
        if case .result = state { ready = true }
        applyButton.isEnabled = ready
        applyButton.alpha = ready ? 1 : 0.35
    }

    /// Outline smiley drawn by hand so it is never rendered as a filled symbol.
    private static func outlineSmiley(diameter d: CGFloat = 19) -> UIImage {
        let line: CGFloat = 1.5
        let img = UIGraphicsImageRenderer(size: CGSize(width: d + 2, height: d + 2)).image { _ in
            let c = CGPoint(x: (d + 2) / 2, y: (d + 2) / 2)
            let r = d / 2 - line / 2
            UIColor.black.setStroke()
            let face = UIBezierPath(arcCenter: c, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            face.lineWidth = line; face.stroke()
            let smile = UIBezierPath(arcCenter: CGPoint(x: c.x, y: c.y + r * 0.05), radius: r * 0.52,
                                     startAngle: .pi * 0.18, endAngle: .pi * 0.82, clockwise: true)
            smile.lineWidth = line; smile.lineCapStyle = .round; smile.stroke()
            UIColor.black.setFill()
            for dx in [-r * 0.36, r * 0.36] {
                UIBezierPath(arcCenter: CGPoint(x: c.x + dx, y: c.y - r * 0.28), radius: 1.3, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
            }
        }
        return img.withRenderingMode(.alwaysTemplate)
    }

    func setTone(_ tone: Tone) {
        self.tone = tone
        UIView.performWithoutAnimation {
            let symbol: String
            switch tone {
            case .casual: symbol = "smiley"
            case .academic: symbol = "graduationcap"
            case .slang: symbol = "bubble.left.and.bubble.right"
            }
            let icon: UIImage? = tone == .casual
                ? Self.outlineSmiley()
                : UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular, scale: .medium))
            toneButton.setImage(icon, for: .normal)
            toneButton.accessibilityLabel = tone.label
            toneButton.layoutIfNeeded()
        }
        if case .idle = state { set(.idle) }
    }

    // MARK: - Composing text and caret

    private(set) var composing = ""
    private var caret = 0
    private var windowStart = 0

    /// Text being composed (Korean / Japanese / Chinese / English) and the caret position inside it.
    func setComposing(_ text: String, caret: Int) {
        composing = text
        self.caret = max(0, min(caret, text.count))
        render()
    }

    private var statusText = ""
    private var statusColor: UIColor = .secondaryLabel
    private var statusIsMessage = false

    func set(_ newState: State) {
        state = newState
        defer { onStateChange?(); updateApplyButton() }
        statusIsMessage = false
        switch newState {
        case .idle:
            let target = AppSettings.targetLanguage.hintName
            if canPaste {
                statusText = L("탭하여 붙여넣고 \(target)로 변환", "Tap to paste and convert to \(target)")
                statusColor = .secondaryLabel
            } else {
                statusText = L("입력하면 \(tone.adjective) \(target) 원어민 표현으로 바꿔요", "Type to get a \(tone.adjective) native \(target) version")
                statusColor = .tertiaryLabel
            }
        case .loading:
            statusText = "…"; statusColor = .secondaryLabel
        case .result(let text):
            statusText = text; statusColor = KeyboardTheme.accent
        case .ok(let text):
            statusText = text; statusColor = .secondaryLabel
        case .message(let text):
            statusText = text; statusColor = Self.softAlert; statusIsMessage = true
        }
        render()
    }

    /// Typed text and the converted suggestion share this size.
    private static let composeFont = UIFont.systemFont(ofSize: 16)
    private static let caretWidth: CGFloat = 2

    private var showsResult: Bool { if case .result = state { return !composing.isEmpty }; return false }
    private var showsComposing: Bool { aiEnabled && !composing.isEmpty && !statusIsMessage && !showsResult }

    private func render() {
        let attributed: NSAttributedString
        var key: String
        if !aiEnabled {
            attributed = NSAttributedString(string: "")
            key = "off"
        } else if showsComposing {
            // Slide the visible window so the caret always stays in view.
            windowStart = min(windowStart, caret)
            let chars = Array(composing)
            let avail = max(label.bounds.width, 60) - 22
            while windowStart < caret, leftWidth(chars, from: windowStart, to: caret, ellipsis: true) > avail { windowStart += 1 }
            while windowStart > 0, leftWidth(chars, from: windowStart - 1, to: caret, ellipsis: windowStart - 1 > 0) <= avail { windowStart -= 1 }

            let out = NSMutableAttributedString()
            let attrs: [NSAttributedString.Key: Any] = [.font: Self.composeFont, .foregroundColor: UIColor.label]
            if windowStart > 0 { out.append(NSAttributedString(string: "…", attributes: attrs)) }
            out.append(NSAttributedString(string: String(chars[windowStart..<caret]), attributes: attrs))
            out.append(caretAttachment())
            out.append(NSAttributedString(string: String(chars[caret...]), attributes: attrs))
            attributed = out
            key = "c|\(composing)|\(caret)|\(windowStart)"
        } else {
            var isResult = false
            if case .result = state { isResult = true }
            attributed = NSAttributedString(string: statusText, attributes: [.font: isResult ? Self.composeFont : UIFont.systemFont(ofSize: 15), .foregroundColor: statusColor])
            key = "s|\(statusText)|\(statusColor.hash)"
        }
        if key == shownKey { return }
        shownKey = key
        UIView.performWithoutAnimation {
            label.lineBreakMode = showsComposing ? .byClipping : .byTruncatingTail
            label.attributedText = attributed
            label.layoutIfNeeded()
        }
    }

    private func caretAttachment() -> NSAttributedString {
        let h = Self.composeFont.lineHeight
        let img = UIGraphicsImageRenderer(size: CGSize(width: Self.caretWidth, height: h)).image { ctx in
            KeyboardTheme.accent.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: Self.caretWidth, height: h))
        }
        let att = NSTextAttachment()
        att.image = img
        att.bounds = CGRect(x: 0, y: Self.composeFont.descender, width: Self.caretWidth, height: h)
        return NSAttributedString(attachment: att)
    }

    private func width(_ s: String) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: Self.composeFont]).width
    }

    private func leftWidth(_ chars: [Character], from: Int, to: Int, ellipsis: Bool) -> CGFloat {
        width((ellipsis ? "…" : "") + String(chars[from..<to])) + Self.caretWidth
    }

    /// Maps a tap x-position (in label coordinates) to a character index in `composing`.
    private func characterIndex(atX x: CGFloat) -> Int {
        let chars = Array(composing)
        let base = windowStart > 0 ? width("…") : 0
        var best = windowStart, bestDist = CGFloat.greatestFiniteMagnitude
        for i in windowStart...chars.count {
            var w = base + width(String(chars[windowStart..<i]))
            if i > caret { w += Self.caretWidth }
            let d = abs(w - x)
            if d < bestDist { best = i; bestDist = d }
            if w > x + 40 { break }
        }
        return best
    }

    // MARK: - Tap

    /// Muted pastel coral for notices instead of the harsh system red.
    private static let softAlert = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.96, green: 0.72, blue: 0.70, alpha: 1)
            : UIColor(red: 0.78, green: 0.45, blue: 0.43, alpha: 1)
    }

    @objc private func labelLongPressed(_ g: UILongPressGestureRecognizer) {
        guard aiEnabled, g.state == .began else { return }
        onPaste?()
    }

    @objc private func labelTapped(_ g: UITapGestureRecognizer) {
        guard aiEnabled else { return }
        if showsResult { onApply?(); return }   // tapping the suggestion applies it, same as the arrow button
        if showsComposing {
            onCaretTap?(characterIndex(atX: g.location(in: label).x))
            return
        }
        switch state {
        case .result: onApply?()
        case .idle, .message: onTrigger?()
        case .loading, .ok: break
        }
    }
}
