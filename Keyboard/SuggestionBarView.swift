import UIKit

/// Two-row strip above the keys. Top row: [style] [converted suggestion] [undo] [AI] [apply].
/// Bottom row: the text typed in the host field, with a caret; tapping it moves the cursor.
/// Both rows are plain UILabels (not system buttons) so updating them on every keystroke never cross-fades or flickers.
final class SuggestionBarView: UIView, UIGestureRecognizerDelegate {
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
    /// Double tap on the typed text: select the word at that index. Triple tap: select everything.
    var onWordSelect: ((Int) -> Void)?
    var onSelectAll: (() -> Void)?
    /// Clears the whole typed sentence (the x icon at the left of the input row, always shown).
    var onClear: (() -> Void)?
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

    private let label = UILabel()          // top row: suggestion / hints
    private let topScroll = UIScrollView() // lets a long suggestion slide sideways
    private let typedLabel = UILabel()     // bottom row: typed text with caret
    private let aiButton = UIButton(type: .custom)
    private let toneButton = UIButton(type: .system)
    private let undoButton = UIButton(type: .system)
    private let undoSlot = UIView()
    private let applyButton = UIButton(type: .system)
    private let applySlot = UIView()
    private let clearButton = UIButton(type: .system)
    private static let circle: CGFloat = 30
    static let rowHeight: CGFloat = 34

    private var shownKey = ""
    private var shownTypedKey = ""

    /// Extra height the bar extends above the keyboard view to cover the system's top padding.
    private let overhang: CGFloat

    init(overhang: CGFloat = 0) {
        self.overhang = overhang
        super.init(frame: .zero)
        backgroundColor = KeyboardTheme.bar

        label.numberOfLines = 1
        label.isUserInteractionEnabled = true
        label.lineBreakMode = .byClipping
        topScroll.showsHorizontalScrollIndicator = false
        topScroll.contentInset.right = 8
        topScroll.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(labelTapped(_:))))
        topScroll.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(labelLongPressed(_:))))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byClipping
        topScroll.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: topScroll.contentLayoutGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: topScroll.contentLayoutGuide.trailingAnchor),
            label.topAnchor.constraint(equalTo: topScroll.contentLayoutGuide.topAnchor),
            label.bottomAnchor.constraint(equalTo: topScroll.contentLayoutGuide.bottomAnchor),
            label.heightAnchor.constraint(equalTo: topScroll.frameLayoutGuide.heightAnchor),
            label.widthAnchor.constraint(greaterThanOrEqualTo: topScroll.frameLayoutGuide.widthAnchor, constant: -8),
        ])
        typedLabel.numberOfLines = 1
        typedLabel.isUserInteractionEnabled = true
        typedLabel.lineBreakMode = .byClipping
        typedLabel.translatesAutoresizingMaskIntoConstraints = false
        typedLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(typedTapped(_:))))
        let slide = UILongPressGestureRecognizer(target: self, action: #selector(typedPressed(_:)))
        slide.minimumPressDuration = 0.25
        slide.allowableMovement = 10_000
        typedLabel.addGestureRecognizer(slide)
        let double = UITapGestureRecognizer(target: self, action: #selector(typedDoubleTapped(_:)))
        double.numberOfTapsRequired = 2
        let triple = UITapGestureRecognizer(target: self, action: #selector(typedTripleTapped(_:)))
        triple.numberOfTapsRequired = 3
        for g in [double, triple] { g.delegate = self; typedLabel.addGestureRecognizer(g) }
        typedLabel.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }.forEach { $0.delegate = self }
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        topScroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        topScroll.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

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

        let stack = UIStackView(arrangedSubviews: [toneSlot, topScroll, undoSlot, aiSlot, applySlot])
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        addSubview(typedLabel)
        clearButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular, scale: .medium)), for: .normal)
        clearButton.tintColor = UIColor.systemGray      // the standard grey clear button
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.addAction(UIAction { [weak self] _ in
            Haptics.tap()
            self?.onClear?()
        }, for: .touchUpInside)
        addSubview(clearButton)
        updateClearButton()
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: overhang),
            stack.heightAnchor.constraint(equalToConstant: Self.rowHeight),
            typedLabel.topAnchor.constraint(equalTo: stack.bottomAnchor),
            typedLabel.leadingAnchor.constraint(equalTo: topScroll.leadingAnchor),
            typedLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            typedLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            clearButton.centerXAnchor.constraint(equalTo: toneSlot.centerXAnchor),
            clearButton.centerYAnchor.constraint(equalTo: typedLabel.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: Self.circle),
            clearButton.heightAnchor.constraint(equalToConstant: Self.circle),
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
        if typedLabel.bounds.width != lastWidth || topScroll.bounds.width != lastTopWidth {
            lastWidth = typedLabel.bounds.width; lastTopWidth = topScroll.bounds.width
            shownKey = ""; shownTypedKey = ""; render()
        }
    }
    private var lastWidth: CGFloat = 0
    private var lastTopWidth: CGFloat = 0

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
    /// Always shown while AI is on; dimmed and inactive when there is nothing to clear.
    private func updateClearButton() {
        clearButton.isHidden = !aiEnabled
        let ready = !composing.isEmpty
        clearButton.isEnabled = ready
        clearButton.alpha = ready ? 1 : 0.35
    }

    private func updateApplyButton() {
        updateClearButton()
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
    private var selection: Range<Int>?
    private var caret = 0
    private var windowStart = 0

    /// Highlights the selected characters of the typed text (nil clears it).
    func setSelection(_ r: Range<Int>?) {
        selection = r
        render()
    }

    /// Text being composed (Korean / Japanese / Chinese / English) and the caret position inside it.
    func setComposing(_ text: String, caret: Int) {
        composing = text
        self.caret = max(0, min(caret, text.count))
        updateClearButton()
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
            statusText = L("입력하면 \(tone.adjective) \(target) 원어민 표현으로 바꿔요", "Type to get a \(tone.adjective) native \(target) version")
            statusColor = .tertiaryLabel
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

    private func render() {
        renderTop()
        renderTyped()
    }

    /// Top row: suggestion (gold), hint, loading dots or a notice.
    private func renderTop() {
        let attributed: NSAttributedString
        let key: String
        if !aiEnabled {
            attributed = NSAttributedString(string: "")
            key = "off"
        } else {
            var isResult = false
            if case .result = state { isResult = true }
            var text = statusText
            if case .idle = state, !composing.isEmpty { text = "" }   // typed text is below; nothing to hint at
            attributed = NSAttributedString(string: text, attributes: [.font: isResult ? Self.composeFont : UIFont.systemFont(ofSize: 15), .foregroundColor: statusColor])
            key = "s|\(text)|\(statusColor.hash)"
        }
        if key == shownKey { return }
        shownKey = key
        UIView.performWithoutAnimation {
            label.attributedText = attributed
            topScroll.setContentOffset(CGPoint(x: -topScroll.contentInset.left, y: 0), animated: false)
            topScroll.layoutIfNeeded()
        }
    }

    /// Bottom row: the typed text with a caret, scrolled so the caret stays in view.
    private func renderTyped() {
        let attributed: NSAttributedString
        let key: String
        if !aiEnabled {
            attributed = NSAttributedString(string: "")
            key = "off"
        } else if composing.isEmpty {
            let text = canPaste ? L("탭하여 붙여넣고 변환", "Tap to paste and convert") : ""
            attributed = NSAttributedString(string: text, attributes: [.font: Self.composeFont, .foregroundColor: UIColor.secondaryLabel])
            key = "p|\(text)"
        } else {
            windowStart = min(windowStart, caret)
            let chars = Array(composing)
            let avail = max(typedLabel.bounds.width, 60) - 22
            while windowStart < caret, leftWidth(chars, from: windowStart, to: caret, ellipsis: true) > avail { windowStart += 1 }
            while windowStart > 0, leftWidth(chars, from: windowStart - 1, to: caret, ellipsis: windowStart - 1 > 0) <= avail { windowStart -= 1 }

            let out = NSMutableAttributedString()
            let attrs: [NSAttributedString.Key: Any] = [.font: Self.composeFont, .foregroundColor: UIColor.label]
            let marked: [NSAttributedString.Key: Any] = attrs.merging([.backgroundColor: KeyboardTheme.accent.withAlphaComponent(0.4)]) { $1 }
            /// Characters [from, to) with the selected ones highlighted.
            func run(_ from: Int, _ to: Int) -> NSAttributedString {
                let r = NSMutableAttributedString()
                for i in from..<to {
                    let on = selection.map { $0.contains(i) } ?? false
                    r.append(NSAttributedString(string: String(chars[i]), attributes: on ? marked : attrs))
                }
                return r
            }
            if windowStart > 0 { out.append(NSAttributedString(string: "…", attributes: attrs)) }
            out.append(run(windowStart, caret))
            out.append(caretAttachment())
            out.append(run(caret, chars.count))
            attributed = out
            key = "c|\(composing)|\(caret)|\(windowStart)|\(selection.map { "\($0.lowerBound)-\($0.upperBound)" } ?? "")"
        }
        if key == shownTypedKey { return }
        shownTypedKey = key
        UIView.performWithoutAnimation {
            typedLabel.attributedText = attributed
            typedLabel.layoutIfNeeded()
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

    /// Top row: tapping a long suggestion slides it so all of it can be read; the arrow button applies it.
    @objc private func labelTapped(_ g: UITapGestureRecognizer) {
        guard aiEnabled else { return }
        switch state {
        case .result: slideSuggestion()
        case .idle, .message: onTrigger?()
        case .loading, .ok: break
        }
    }

    /// A suggestion longer than the row slides to its end on tap (and back on the next tap); it can also be dragged.
    private func slideSuggestion() {
        topScroll.layoutIfNeeded()
        let maxX = topScroll.contentSize.width - topScroll.bounds.width + topScroll.contentInset.right
        guard maxX > 4 else { return }
        let target: CGFloat = topScroll.contentOffset.x < maxX / 2 ? maxX : 0
        let seconds = min(max(Double(abs(target - topScroll.contentOffset.x)) / 90, 0.6), 4)
        UIView.animate(withDuration: seconds, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
            self.topScroll.contentOffset = CGPoint(x: target, y: 0)
        }
    }

    // The single, double and triple taps all fire in turn, like the system keyboard's tap counts.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        g is UITapGestureRecognizer && other is UITapGestureRecognizer
    }

    @objc private func typedDoubleTapped(_ g: UITapGestureRecognizer) {
        guard aiEnabled, !composing.isEmpty else { return }
        onWordSelect?(characterIndex(atX: g.location(in: typedLabel).x))
    }

    @objc private func typedTripleTapped(_ g: UITapGestureRecognizer) {
        guard aiEnabled, !composing.isEmpty else { return }
        onSelectAll?()
    }

    /// Bottom row: press and hold, then slide left or right to move the cursor along the text.
    @objc private func typedPressed(_ g: UILongPressGestureRecognizer) {
        guard aiEnabled else { return }
        if composing.isEmpty {
            if g.state == .began { onPaste?() }      // nothing typed: a long press pastes
            return
        }
        switch g.state {
        case .began, .changed:
            if g.state == .began { Haptics.tap() }
            let index = characterIndex(atX: g.location(in: typedLabel).x)
            if index != caret { onCaretTap?(index) }
        default:
            break
        }
    }

    /// Bottom row: tapping the typed text puts the cursor there (or pastes, when it is empty and the clipboard has text).
    @objc private func typedTapped(_ g: UITapGestureRecognizer) {
        guard aiEnabled else { return }
        if composing.isEmpty { onTrigger?(); return }
        onCaretTap?(characterIndex(atX: g.location(in: typedLabel).x))
    }
}
