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

    private enum Language { case english, korean, japanese, chinese }
    private var language: Language = .english
    private var availableLanguages: [Language] = []
    private var composer = HangulComposer()
    private var latin = LatinComposer()

    private var isCompose: Bool { language != .english }
    private var composeText: String {
        switch language {
        case .english: return ""
        case .korean: return composer.text
        case .japanese, .chinese: return latin.text
        }
    }
    private var sourceCode: String? {
        switch language {
        case .english: return nil
        case .korean: return "ko"
        case .japanese: return "ja"
        case .chinese: return "zh"
        }
    }
    private func composeClear() { composer.clear(); latin.clear() }
    private func languages() -> [Language] {
        let on = AppSettings.inputLanguages
        var list: [Language] = [.english]
        if on.contains(.korean) { list.append(.korean) }
        if on.contains(.japanese) { list.append(.japanese) }
        if on.contains(.chinese) { list.append(.chinese) }
        return list
    }
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

        heightConstraint = view.heightAnchor.constraint(equalToConstant: currentHeight())
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
        let langs = languages()
        if langs != availableLanguages {
            availableLanguages = langs
            if !langs.contains(language) {
                language = .english
                composeClear()
                bufferBar.isHidden = true
                bufferHeight.constant = 0
            }
            rebuildKeys()
        }
        updateBuffer()
        heightConstraint.constant = currentHeight()
        bar.set(.idle)
        updateAutoShift()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateAutoShift()
    }

    /// Height from the app setting, plus room for the Korean compose bar.
    private func currentHeight() -> CGFloat {
        AppSettings.keyboardHeight.points + (isCompose ? 40 : 0)
    }

    // MARK: - Rewrite

    private func currentLine() -> String {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        return before.components(separatedBy: "\n").last ?? ""
    }

    /// `auto` = fired by the typing-pause timer (quiet about empty/short input); otherwise by tapping the bar.
    private func triggerRewrite(auto: Bool = false) {
        autoTimer?.invalidate()
        let line = isCompose ? composeText : currentLine()
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if auto {
            // Only suggest for something sentence-like, and not for text we already handled.
            let longEnough: Bool
            switch language {
            case .korean, .japanese: longEnough = trimmed.count >= 3
            case .chinese: longEnough = trimmed.count >= 4
            case .english: longEnough = trimmed.split(separator: " ").count >= 3
            }
            guard hasFullAccess, longEnough,
                  trimmed.count <= AppConfig.maxInputLength else { return }
        } else {
            guard hasFullAccess else {
                bar.set(.message(L("설정에서 '전체 접근 허용'을 켜주세요", "Turn on 'Allow Full Access' in Settings")))
                return
            }
            guard !trimmed.isEmpty else {
                bar.set(.message(L("교정할 문장을 먼저 입력하세요", "Type a sentence first")))
                return
            }
        }

        let selectedTone = tone
        let cacheKey = "fast|\(sourceCode ?? "en")|\(selectedTone.rawValue)|\(AppSettings.explainLanguage.rawValue)|\(trimmed)"
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
                    explainLanguage: AppSettings.explainLanguage,
                    fast: true,
                    source: sourceCode
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
            bar.set(.ok(L("이미 자연스러운 문장이에요", "Already sounds natural")))
        } else {
            pending = Pending(original: line, result: r)
            bar.set(.result(r.best))
        }
    }

    private func applySuggestion() {
        guard let p = pending else { return }
        if isCompose {
            // Compose buffer -> insert the English result into the host field.
            guard composeText == p.original else {
                pending = nil
                bar.set(.idle)
                return
            }
            textDocumentProxy.insertText(p.result.best)
            AppSettings.queueKeyboardResult(p.result.best, tone: tone)
            composeClear()
            pending = nil
            updateBuffer()
            bar.set(.idle)
            return
        }
        // Make sure the text hasn't changed since the suggestion was requested.
        guard currentLine() == p.original else {
            pending = nil
            bar.set(.message(L("문장이 바뀌었어요. 바를 다시 탭하세요", "The text changed. Tap the bar again")))
            return
        }
        for _ in 0..<p.original.count { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(p.result.best)
        AppSettings.queueKeyboardResult(p.result.best, tone: tone)
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
        autoTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.triggerRewrite(auto: true)
        }
    }

    // MARK: - Typing

    private func type(_ s: String) {
        if language == .korean { typeKorean(s); return }
        if language == .japanese || language == .chinese { typeLatin(s); return }
        invalidateSuggestion()
        textDocumentProxy.insertText(s)
        if shifted && !capsLock { shifted = false; refreshLetters() }
        if s == " " || s == "\n" { updateAutoShift() }
        scheduleAutoSuggest()
    }

    private func backspace() {
        if isCompose && !composeText.isEmpty {
            invalidateSuggestion()
            if language == .korean { composer.backspace() } else { latin.backspace() }
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
        let should = AppSettings.autoCapitalize && (before.isEmpty
            || before.hasSuffix("\n")
            || before.hasSuffix(". ") || before.hasSuffix("! ") || before.hasSuffix("? "))
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
        if language != .english { return base.lowercased() }
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

    /// Japanese (romaji) and Chinese (pinyin): letters are composed in the buffer, then converted to English.
    private func typeLatin(_ s: String) {
        if latin.isEmpty && !LatinComposer.isLetter(s) {
            textDocumentProxy.insertText(s)
            return
        }
        invalidateSuggestion()
        if LatinComposer.isLetter(s), let ch = s.first {
            latin.input(Character(ch.lowercased()))
        } else {
            latin.commitLiteral(s)
        }
        if shifted && !capsLock { shifted = false; refreshLetters() }
        updateBuffer()
        scheduleAutoSuggest()
    }

    private func updateBuffer() {
        bufferBar.setText(composeText)
    }

    private func clearBuffer() {
        composeClear()
        invalidateSuggestion()
        autoTimer?.invalidate()
        updateBuffer()
    }

    private func toggleLanguage() {
        let list = availableLanguages.isEmpty ? languages() : availableLanguages
        let i = list.firstIndex(of: language) ?? 0
        language = list[(i + 1) % list.count]
        latin.japanese = language == .japanese
        composeClear()
        invalidateSuggestion()
        autoTimer?.invalidate()
        shifted = false
        capsLock = false
        layer = .letters
        bufferBar.isHidden = !isCompose
        bufferHeight.constant = isCompose ? 40 : 0
        heightConstraint.constant = currentHeight()
        bar.set(.idle)
        updateBuffer()
        rebuildKeys()
        updateAutoShift()
    }

    private func tapReturn() {
        if isCompose {
            if case .result = bar.state { applySuggestion(); return }
            if !composeText.isEmpty { triggerRewrite(); return }
            textDocumentProxy.insertText("\n")
            return
        }
        type("\n")
    }

    private func updateReturnLabel() {
        guard let returnButton else { return }
        var title = "return"
        if isCompose {
            if case .result = bar.state { title = L("입력", "Insert") } else { title = L("변환", "Convert") }
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
        // Shift/123 and delete always match in width, so row 3 lines up with row 1 like the iOS keyboard.
        leftSpecial.widthAnchor.constraint(equalTo: delete.widthAnchor).isActive = true
        if layer == .letters {
            row3Keys.forEach { $0.widthAnchor.constraint(equalTo: ref.widthAnchor).isActive = true }
        } else {
            leftSpecial.widthAnchor.constraint(equalTo: ref.widthAnchor, multiplier: 1.5).isActive = true
            // Punctuation keys share the remaining width equally.
            for k in row3Keys.dropFirst() { k.widthAnchor.constraint(equalTo: row3Keys[0].widthAnchor).isActive = true }
        }

        // Bottom row: [123/ABC] [한/EN] [space] [return]  (iOS draws its own globe below the keyboard)
        let letterTitle: String
        switch language {
        case .english: letterTitle = "ABC"
        case .korean: letterTitle = "가나다"
        case .japanese: letterTitle = "あいう"
        case .chinese: letterTitle = "拼音"
        }
        let modeKey = KeyButton(title: layer == .letters ? "123" : letterTitle, style: .special, fontSize: 16)
        modeKey.onTap = { [weak self] in
            guard let self else { return }
            self.layer = self.layer == .letters ? .numbers : .letters
            self.rebuildKeys()
            self.updateAutoShift()
        }
        let langList = availableLanguages.isEmpty ? languages() : availableLanguages
        let nextLang = langList[((langList.firstIndex(of: language) ?? 0) + 1) % langList.count]
        let nextKey: String
        switch nextLang {
        case .english: nextKey = "EN"
        case .korean: nextKey = InputLanguage.korean.keyLabel
        case .japanese: nextKey = InputLanguage.japanese.keyLabel
        case .chinese: nextKey = InputLanguage.chinese.keyLabel
        }
        let langKey = KeyButton(title: nextKey, style: .special, fontSize: 16)
        langKey.onTap = { [weak self] in self?.toggleLanguage() }
        let spaceTitle: String
        switch language {
        case .english: spaceTitle = "space"
        case .korean: spaceTitle = "간격"
        case .japanese: spaceTitle = "空白"
        case .chinese: spaceTitle = "空格"
        }
        let space = KeyButton(title: spaceTitle, style: .letter, fontSize: 16)
        space.onTap = { [weak self] in self?.type(" ") }
        let ret = KeyButton(title: "return", style: .special, fontSize: 16)
        ret.onTap = { [weak self] in self?.tapReturn() }
        returnButton = ret
        updateReturnLabel()

        let bottom = UIStackView(arrangedSubviews: langList.count > 1 ? [modeKey, langKey, space, ret] : [modeKey, space, ret])
        bottom.axis = .horizontal; bottom.spacing = 5; bottom.distribution = .fill
        keysStack.addArrangedSubview(bottom)
        modeKey.widthAnchor.constraint(equalTo: ref.widthAnchor, multiplier: 1.4).isActive = true
        if langList.count > 1 { langKey.widthAnchor.constraint(equalTo: ref.widthAnchor, multiplier: 1.2).isActive = true }
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
