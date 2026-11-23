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
    var onClear: (() -> Void)?
    var onSend: (() -> Void)?
    /// Called with the character index the user tapped while composing.
    var onCaretTap: ((Int) -> Void)?
    var onStateChange: (() -> Void)?

    private(set) var state: State = .idle
    private var tone: Tone = AppSettings.tone

    private let label = UILabel()
    private let aiButton = UIButton(type: .custom)
    private let toneButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)

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
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        aiButton.setTitle("AI", for: .normal)
        aiButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        aiButton.layer.cornerRadius = 12
        aiButton.layer.borderWidth = 1
        aiButton.addAction(UIAction { [weak self] _ in
            if AppSettings.haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            self?.onAIToggle?()
        }, for: .touchUpInside)

        toneButton.tintColor = KeyboardTheme.accent
        toneButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        toneButton.titleLabel?.adjustsFontSizeToFitWidth = true
        toneButton.addAction(UIAction { [weak self] _ in self?.onToneTap?() }, for: .touchUpInside)

        clearButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17)), for: .normal)
        clearButton.tintColor = .tertiaryLabel
        clearButton.isHidden = true
        clearButton.addAction(UIAction { [weak self] _ in
            if AppSettings.haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            self?.onClear?()
        }, for: .touchUpInside)

        sendButton.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26)), for: .normal)
        sendButton.tintColor = KeyboardTheme.accent
        sendButton.addAction(UIAction { [weak self] _ in
            if AppSettings.haptics { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            self?.onSend?()
        }, for: .touchUpInside)

        let aiWrap = UIView()
        aiButton.translatesAutoresizingMaskIntoConstraints = false
        aiWrap.addSubview(aiButton)
        NSLayoutConstraint.activate([
            aiButton.centerYAnchor.constraint(equalTo: aiWrap.centerYAnchor),
            aiButton.leadingAnchor.constraint(equalTo: aiWrap.leadingAnchor),
            aiButton.trailingAnchor.constraint(equalTo: aiWrap.trailingAnchor),
            aiButton.heightAnchor.constraint(equalToConstant: 24),
            aiWrap.widthAnchor.constraint(equalToConstant: 38),
        ])

        let stack = UIStackView(arrangedSubviews: [toneButton, label, clearButton, aiWrap, sendButton])
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: overhang),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            toneButton.widthAnchor.constraint(equalToConstant: 36),
            clearButton.widthAnchor.constraint(equalToConstant: 32),
            sendButton.widthAnchor.constraint(equalToConstant: 36),
        ])
        toneButton.setContentCompressionResistancePriority(.required, for: .horizontal)
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
        updateSendButton()
        set(.idle)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

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

    /// Always visible while AI is on; dimmed when there is nothing to send.
    private func updateSendButton() {
        sendButton.isHidden = !aiEnabled
        let ready = !composing.isEmpty
        sendButton.alpha = ready ? 1 : 0.35
        sendButton.isEnabled = ready
    }

    private func applyAIAppearance() {
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
            updateSendButton()
        }
    }

    func setTone(_ tone: Tone) {
        self.tone = tone
        UIView.performWithoutAnimation {
            let symbol: String
            switch tone {
            case .casual: symbol = "face.smiling"
            case .academic: symbol = "graduationcap"
            case .slang: symbol = "bubble.left.and.text.bubble.right"
            }
            toneButton.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)), for: .normal)
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
        clearButton.isHidden = !(aiEnabled && !text.isEmpty)
        updateSendButton()
        render()
    }

    private var statusText = ""
    private var statusColor: UIColor = .secondaryLabel
    private var statusIsMessage = false

    func set(_ newState: State) {
        state = newState
        defer { onStateChange?() }
        statusIsMessage = false
        switch newState {
        case .idle:
            let target = AppSettings.targetLanguage.hintName
            statusText = L("입력하면 \(tone.adjective) \(target) 원어민 표현으로 바꿔요", "Type to get a \(tone.adjective) native \(target) version")
            statusColor = .tertiaryLabel
        case .loading:
            statusText = "…"; statusColor = .secondaryLabel
        case .result(let text):
            statusText = text; statusColor = .label
        case .ok(let text):
            statusText = text; statusColor = .secondaryLabel
        case .message(let text):
            statusText = text; statusColor = Self.softAlert; statusIsMessage = true
        }
        render()
    }

    private static let composeFont = UIFont.systemFont(ofSize: 18)
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
            attributed = NSAttributedString(string: statusText, attributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: statusColor])
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

    @objc private func labelTapped(_ g: UITapGestureRecognizer) {
        guard aiEnabled else { return }
        if showsResult { onCaretTap?(composing.count); return }   // back to the typed text
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
