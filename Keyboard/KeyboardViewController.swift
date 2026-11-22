import UIKit

final class KeyboardViewController: UIInputViewController {
    private enum Layer { case letters, numbers, symbols }

    private struct Pending {
        let original: String   // exact text (incl. whitespace) of the current line that will be replaced
        let result: RewriteResult
    }

    private let bar = SuggestionBarView()
    private let keysStack = UIStackView()
    private var layer: Layer = .letters
    private var shifted = false
    private var capsLock = false
    private var letterBases: [(button: KeyButton, base: String)] = []
    private var shiftButton: KeyButton?

    private enum Language { case english, korean }
    private var language: Language = .english
    private var composer = HangulComposer()
    private let bufferBar = BufferBarView()
    private var heightConstraint: NSLayoutConstraint!
    private var bufferHeight: NSLayoutConstraint!
    private var returnButton: KeyButton?
    private static let shiftedJamo: [String: String] = [
        "ㅂ": "ㅃ", "ㅈ": "ㅉ", "ㄷ": "ㄸ", "ㄱ": "ㄲ", "ㅅ": "ㅆ", "ㅐ": "ㅒ", "ㅔ": "ㅖ",
    ]

    private var tone = AppSettings.tone
    private var pending: Pending?
    private var task: Task<Void, Never>?
    private var autoTimer: Timer?
    private var cache: [String: RewriteResult] = [:]
    private var lastShiftTap = Date.distantPast

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = KeyboardTheme.background

        bar.translatesAutoresizingMaskIntoConstraints = false
        keysStack.axis = .vertical
        keysStack.spacing = 10
        keysStack.distribution = .fillEqually
        keysStack.translatesAutoresizingMaskIntoConstraints = false
        bufferBar.translatesAutoresizingMaskIntoConstraints = false
        bufferBar.isHidden = true
        bufferBar.onClear = { [weak self] in self?.clearBuffer() }
        view.addSubview(bufferBar)
        view.addSubview(bar)
        view.addSubview(keysStack)

        heightConstraint = view.heightAnchor.constraint(equalToConstant: 276)
        heightConstraint.priority = .init(999)
        bufferHeight = bufferBar.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            heightConstraint,
            bufferHeight,
            // Native-tone strip sits at the very top of the keyboard; the Korean compose buffer is below it.
            bar.topAnchor.constraint(equalTo: view.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 44),
            bufferBar.topAnchor.constraint(equalTo: bar.bottomAnchor),
            bufferBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bufferBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keysStack.topAnchor.constraint(equalTo: bufferBar.bottomAnchor, constant: 8),
            keysStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 3),
            keysStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -3),
            keysStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
        ])

        bar.setTone(tone)
        bar.onTrigger = { [weak self] in self?.triggerRewrite() }
        bar.onApply = { [weak self] in self?.applySuggestion() }
        bar.onToneTap = { [weak self] in self?.cycleTone() }
        bar.onStateChange = { [weak self] in self?.updateReturnLabel() }

        rebuildKeys()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tone = AppSettings.tone
        bar.setTone(tone)
        bar.autoMode = AppSettings.autoSuggest
        bar.set(.idle)
        updateAutoShift()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateAutoShift()
    }

    // MARK: - Rewrite

    private func currentLine() -> String {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        return before.components(separatedBy: "\n").last ?? ""
    }

    /// `auto` = fired by the typing-pause timer (quiet about empty/short input); otherwise from the ✨ tap.
    private func triggerRewrite(auto: Bool = false) {
        autoTimer?.invalidate()
        let line = language == .korean ? composer.text : currentLine()
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if auto {
            // Only suggest for something sentence-like, and not for text we already handled.
            let longEnough = language == .korean
                ? trimmed.count >= 3
                : trimmed.split(separator: " ").count >= 3
            guard hasFullAccess, longEnough,
                  trimmed.count <= AppConfig.maxInputLength else { return }
        } else {
            guard hasFullAccess else {
                bar.set(.message("설정에서 '전체 접근 허용'을 켜주세요"))
                return
            }
            guard !trimmed.isEmpty else {
                bar.set(.message("교정할 문장을 먼저 입력하세요"))
                return
            }
        }

        let selectedTone = tone
        let cacheKey = "\(selectedTone.rawValue)|\(AppSettings.explainLanguage.rawValue)|\(trimmed)"
        task?.cancel()
        pending = nil

        if let cached = cache[cacheKey] {
            show(cached, line: line, trimmed: trimmed)
            return
        }

        bar.set(.loading)
        task = Task { [weak self] in
            do {
                let r = try await NativeToneClient.shared.rewrite(
                    text: trimmed,
                    tone: selectedTone,
                    context: nil,
                    explainLanguage: AppSettings.explainLanguage
                )
                guard let self, !Task.isCancelled else { return }
                if self.cache.count > 30 { self.cache.removeAll() }
                self.cache[cacheKey] = r
                self.show(r, line: line, trimmed: trimmed)
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.bar.set(.message(error.localizedDescription))
            }
        }
    }

    private func show(_ r: RewriteResult, line: String, trimmed: String) {
        if r.best == trimmed {
            pending = nil
            bar.set(.ok("자연스러운 문장이에요 ✓"))
        } else {
            pending = Pending(original: line, result: r)
            bar.set(.result(r.best))
        }
    }

    private func applySuggestion() {
        guard let p = pending else { return }
        if language == .korean {
            // Korean compose buffer -> insert the English result into the host field.
            guard composer.text == p.original else {
                pending = nil
                bar.set(.idle)
                return
            }
            textDocumentProxy.insertText(p.result.best)
            composer.clear()
            pending = nil
            updateBuffer()
            bar.set(.idle)
            return
        }
        // Make sure the text hasn't changed since the suggestion was requested.
        guard currentLine() == p.original else {
            pending = nil
            bar.set(.message("문장이 바뀌었어요. ✨ 를 다시 눌러주세요"))
            return
        }
        for _ in 0..<p.original.count { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(p.result.best)
        pending = nil
        bar.set(.idle)
        updateAutoShift()
    }

    private func invalidateSuggestion() {
        task?.cancel()
        if pending != nil { pending = nil }
        switch bar.state {
        case .idle: break
        default: bar.set(.idle)
        }
    }

    private func cycleTone() {
        tone = tone.next
        AppSettings.tone = tone
        bar.setTone(tone)
        // Re-run immediately if a suggestion is showing.
        switch bar.state {
        case .result, .ok: triggerRewrite()
        default: break
        }
    }

    /// SmartBoard-style: once typing pauses, a natural version appears above the keys by itself.
    private func scheduleAutoSuggest() {
        autoTimer?.invalidate()
        guard AppSettings.autoSuggest, hasFullAccess else { return }
        autoTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { [weak self] _ in
            self?.triggerRewrite(auto: true)
        }
    }

    // MARK: - Typing

    private func type(_ s: String) {
        if language == .korean { typeKorean(s); return }
        invalidateSuggestion()
        textDocumentProxy.insertText(s)
        if shifted && !capsLock { shifted = false; refreshLetters() }
        if s == " " || s == "\n" { updateAutoShift() }
        scheduleAutoSuggest()
    }

    private func backspace() {
        if language == .korean && !composer.isEmpty {
            invalidateSuggestion()
            composer.backspace()
            updateBuffer()
            scheduleAutoSuggest()
            return
        }
        invalidateSuggestion()
        textDocumentProxy.deleteBackward()
        updateAutoShift()
        scheduleAutoSuggest()
    }

    private func updateAutoShift() {
        guard language == .english, layer == .letters, !capsLock else { return }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let should = before.isEmpty
            || before.hasSuffix("\n")
            || before.hasSuffix(". ") || before.hasSuffix("! ") || before.hasSuffix("? ")
        if should != shifted { shifted = should; refreshLetters() }
    }

    private func tapShift() {
        let now = Date()
        if now.timeIntervalSince(lastShiftTap) < 0.35 {
            capsLock = true; shifted = true
        } else if capsLock {
            capsLock = false; shifted = false
        } else {
            shifted.toggle()
        }
        lastShiftTap = now
        refreshLetters()
    }

    private func refreshLetters() {
        for (b, base) in letterBases {
            b.setTitle(displayTitle(base), for: .normal)
        }
        shiftButton?.setActive(shifted)
        shiftButton?.setImage(
            UIImage(systemName: capsLock ? "capslock.fill" : (shifted ? "shift.fill" : "shift")),
            for: .normal
        )
    }

    // MARK: - Korean compose mode

    private func displayTitle(_ base: String) -> String {
        if language == .korean { return shifted ? (Self.shiftedJamo[base] ?? base) : base }
        return shifted ? base.uppercased() : base.lowercased()
    }

    private func typeKorean(_ s: String) {
        // With nothing being composed, spaces/punctuation go straight to the host field.
        if composer.isEmpty && !HangulComposer.isJamo(s) {
            textDocumentProxy.insertText(s)
            return
        }
        invalidateSuggestion()
        if HangulComposer.isJamo(s), let ch = s.first {
            composer.input(ch)
        } else {
            composer.commitLiteral(s)
        }
        if shifted && !capsLock { shifted = false; refreshLetters() }
        updateBuffer()
        scheduleAutoSuggest()
    }

    private func updateBuffer() {
        bufferBar.setText(composer.text)
    }

    private func clearBuffer() {
        composer.clear()
        invalidateSuggestion()
        autoTimer?.invalidate()
        updateBuffer()
    }

    private func toggleLanguage() {
        language = language == .english ? .korean : .english
        composer.clear()
        invalidateSuggestion()
        autoTimer?.invalidate()
        shifted = false
        capsLock = false
        layer = .letters
        let korean = language == .korean
        bufferBar.isHidden = !korean
        bufferHeight.constant = korean ? 52 : 0
        heightConstraint.constant = korean ? 276 + 52 : 276
        bar.set(.idle)
        updateBuffer()
        rebuildKeys()
        updateAutoShift()
    }

    private func tapReturn() {
        if language == .korean {
            if case .result = bar.state { applySuggestion(); return }
            if !composer.isEmpty { triggerRewrite(); return }
            textDocumentProxy.insertText("\n")
            return
        }
        type("\n")
    }

    private func updateReturnLabel() {
        guard let returnButton else { return }
        var title = "return"
        if language == .korean {
            if case .result = bar.state { title = "입력" } else { title = "변환" }
        }
        returnButton.setTitle(title, for: .normal)
    }

    // MARK: - Layout

    private func rebuildKeys() {
        keysStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        letterBases = []
        shiftButton = nil

        let rows: [[String]]
        switch layer {
        case .letters where language == .korean:
            rows = [Array("ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ").map(String.init), Array("ㅁㄴㅇㄹㅎㅗㅓㅏㅣ").map(String.init), Array("ㅋㅌㅊㅍㅠㅜㅡ").map(String.init)]
        case .letters:
            rows = [Array("qwertyuiop").map(String.init), Array("asdfghjkl").map(String.init), Array("zxcvbnm").map(String.init)]
        case .numbers:
            rows = [Array("1234567890").map(String.init), ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""], [".", ",", "?", "!", "'"]]
        case .symbols:
            rows = [["[", "]", "{", "}", "#", "%", "^", "*", "+", "="], ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"], [".", ",", "?", "!", "'"]]
        }

        // Row 1 defines the reference key width (equal fill).
        let row1 = UIStackView()
        row1.axis = .horizontal; row1.spacing = 5; row1.distribution = .fillEqually
        let row1Keys = rows[0].map(makeCharKey)
        row1Keys.forEach(row1.addArrangedSubview)
        keysStack.addArrangedSubview(row1)
        let ref = row1Keys[0]

        // Row 2: centered, same width as row-1 keys.
        let row2Keys = rows[1].map(makeCharKey)
        let row2 = centeredRow(row2Keys)
        keysStack.addArrangedSubview(row2)
        // Constraints across views need a common ancestor, so activate after the row is in the hierarchy.
        row2Keys.forEach { $0.widthAnchor.constraint(equalTo: ref.widthAnchor).isActive = true }

        // Row 3: [special] chars [delete]
        let leftSpecial: KeyButton
        switch layer {
        case .letters:
            leftSpecial = KeyButton(symbol: "shift", style: .special)
            leftSpecial.onTap = { [weak self] in self?.tapShift() }
            shiftButton = leftSpecial
        case .numbers:
            leftSpecial = KeyButton(title: "#+=", style: .special, fontSize: 16)
            leftSpecial.onTap = { [weak self] in self?.layer = .symbols; self?.rebuildKeys() }
        case .symbols:
            leftSpecial = KeyButton(title: "123", style: .special, fontSize: 16)
            leftSpecial.onTap = { [weak self] in self?.layer = .numbers; self?.rebuildKeys() }
        }
        let delete = KeyButton(symbol: "delete.left", style: .special)
        delete.onRepeat = { [weak self] in self?.backspace() }
        let row3Keys = rows[2].map(makeCharKey)
        let row3 = UIStackView(arrangedSubviews: [leftSpecial] + row3Keys + [delete])
        row3.axis = .horizontal; row3.spacing = 5; row3.distribution = .fill
        keysStack.addArrangedSubview(row3) // must be in the hierarchy before cross-view constraints
        let wide = layer == .letters ? 1.4 : 1.5
        leftSpecial.widthAnchor.constraint(equalTo: ref.widthAnchor, multiplier: wide).isActive = true
        // Delete takes whatever width is left, so row 3 always matches row 1 exactly (no overlap).
        delete.setContentHuggingPriority(.init(1), for: .horizontal)
        if layer == .letters {
            row3Keys.forEach { $0.widthAnchor.constraint(equalTo: ref.widthAnchor).isActive = true }
        } else {
            // Fewer keys: the middle keys share the remaining width equally.
            for k in row3Keys.dropFirst() { k.widthAnchor.constraint(equalTo: row3Keys[0].widthAnchor).isActive = true }
        }

        // Bottom row: [123/ABC] [한/EN] [space] [return]  (iOS draws its own globe below the keyboard)
        let letterTitle = language == .korean ? "가나다" : "ABC"
        let modeKey = KeyButton(title: layer == .letters ? "123" : letterTitle, style: .special, fontSize: 16)
        modeKey.onTap = { [weak self] in
            guard let self else { return }
            self.layer = self.layer == .letters ? .numbers : .letters
            self.rebuildKeys()
            self.updateAutoShift()
        }
        let langKey = KeyButton(title: language == .english ? "한" : "EN", style: .special, fontSize: 16)
        langKey.onTap = { [weak self] in self?.toggleLanguage() }
        let space = KeyButton(title: language == .korean ? "간격" : "space", style: .letter, fontSize: 16)
        space.onTap = { [weak self] in self?.type(" ") }
        let ret = KeyButton(title: "return", style: .special, fontSize: 16)
        ret.onTap = { [weak self] in self?.tapReturn() }
        returnButton = ret
        updateReturnLabel()

        let bottom = UIStackView(arrangedSubviews: [modeKey, langKey, space, ret])
        bottom.axis = .horizontal; bottom.spacing = 5; bottom.distribution = .fill
        keysStack.addArrangedSubview(bottom)
        modeKey.widthAnchor.constraint(equalTo: ref.widthAnchor, multiplier: 1.4).isActive = true
        langKey.widthAnchor.constraint(equalTo: ref.widthAnchor, multiplier: 1.2).isActive = true
        ret.widthAnchor.constraint(equalTo: ref.widthAnchor, multiplier: 2.2).isActive = true

        refreshLetters()
    }

    private func makeCharKey(_ ch: String) -> KeyButton {
        let b = KeyButton(title: ch, style: .letter)
        b.onTap = { [weak self, weak b] in
            guard let self else { return }
            self.type(b?.title(for: .normal) ?? ch)
        }
        if layer == .letters { letterBases.append((b, ch)) }
        return b
    }

    private func centeredRow(_ keys: [KeyButton]) -> UIView {
        let container = UIView()
        let stack = UIStackView(arrangedSubviews: keys)
        stack.axis = .horizontal; stack.spacing = 5; stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }
}
