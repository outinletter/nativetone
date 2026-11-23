import UIKit

final class KeyboardViewController: UIInputViewController {
    private enum Layer { case letters, numbers, symbols }

    private struct Pending {
        let original: String   // exact text (incl. whitespace) of the current line that will be replaced
        let result: RewriteResult
    }

    private static let barHeight: CGFloat = 40
    private static let barOverhang: CGFloat = 17
    private let bar = SuggestionBarView(overhang: KeyboardViewController.barOverhang)
    private let keysStack = UIStackView()
    private var layer: Layer = .letters
    private var shifted = false
    private var capsLock = false
    private var letterBases: [(button: KeyButton, base: String)] = []
    private var shiftButton: KeyButton?

    private enum Language { case english, korean, japanese, chinese }
    private var language: Language = .english
    private var availableLanguages: [Language] = []
    private var kanaMode = AppSettings.japaneseLayout == .kana
    private var composer = HangulComposer()
    private var latin = LatinComposer()

    /// Every language types into the top bar. English does too, except in URL / email / number / secure fields.
    private var aiOn: Bool { AppSettings.aiEnabled }
    private var isCompose: Bool { language != .english || (aiOn && englishComposeAllowed) }
    private var composeCaret: Int { language == .korean ? composer.caretIndex : latin.caretIndex }
    private var englishComposeAllowed: Bool {
        guard AppSettings.composeEnglish, textDocumentProxy.isSecureTextEntry != true else { return false }
        switch textDocumentProxy.keyboardType ?? .default {
        case .URL, .emailAddress, .webSearch, .numberPad, .phonePad, .decimalPad, .namePhonePad, .asciiCapableNumberPad, .twitter:
            return false
        default:
            return true
        }
    }
    private var composeText: String {
        switch language {
        case .korean: return composer.text
        case .english, .japanese, .chinese: return latin.text
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
    private var heightConstraint: NSLayoutConstraint!
    private var returnButton: KeyButton?
    private static let shiftedJamo: [String: String] = [
        "ㅂ": "ㅃ", "ㅈ": "ㅉ", "ㄷ": "ㄸ", "ㄱ": "ㄲ", "ㅅ": "ㅆ", "ㅐ": "ㅒ", "ㅔ": "ㅖ",
    ]

    private var tone = AppSettings.tone

    // SmartBoard-style live conversion: the field always holds the latest translation of the compose buffer.
    private var liveText = ""          // translation currently placed in the host field
    private var liveSource = ""        // compose text it was made from
    private var commitAfterResult = false
    private var composeResult: String?   // converted text waiting for the send button
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
        view.addSubview(bar)
        view.addSubview(keysStack)

        heightConstraint = view.heightAnchor.constraint(equalToConstant: currentHeight())
        heightConstraint.priority = .init(999)
        NSLayoutConstraint.activate([
            heightConstraint,
            // Native-tone strip sits at the very top of the keyboard; the Korean compose buffer is below it.
            bar.topAnchor.constraint(equalTo: view.topAnchor, constant: -Self.barOverhang),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: Self.barHeight + Self.barOverhang),
            keysStack.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 4),
            keysStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 3),
            keysStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -3),
            keysStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
        ])

        bar.setTone(tone)
        bar.onTrigger = { [weak self] in self?.triggerRewrite() }
        bar.onApply = { [weak self] in self?.applySuggestion() }
        bar.onToneTap = { [weak self] in self?.cycleTone() }
        bar.onAIToggle = { [weak self] in self?.toggleAI() }
        bar.onClear = { [weak self] in self?.clearAll() }
        bar.onSend = { [weak self] in self?.deliver() }
        bar.onCaretTap = { [weak self] in self?.moveCaret(to: $0) }
        bar.onStateChange = { [weak self] in self?.updateReturnLabel() }

        rebuildKeys()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in self?.watchForDictation() }
        tone = AppSettings.tone
        bar.setTone(tone)
        bar.autoMode = AppSettings.autoSuggest
        bar.aiEnabled = AppSettings.aiEnabled
        let kana = AppSettings.japaneseLayout == .kana
        if kana != kanaMode {
            kanaMode = kana
            if language == .japanese { rebuildKeys() }
        }
        let langs = languages()
        if langs != availableLanguages {
            availableLanguages = langs
            if !langs.contains(language) {
                language = .english
                composeClear()
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
        watchForDictation()
    }

    // MARK: - Own edits and dictation

    private var ownUntil = Date.distantPast
    private var knownContext = ""
    private var knownAfter = ""
    private var pollTimer: Timer?
    private var dictBaseline: String?
    private var dictTimer: Timer?

    private func ownInsert(_ s: String) {
        ownUntil = Date().addingTimeInterval(0.5)
        textDocumentProxy.insertText(s)
    }

    private func ownDelete() {
        ownUntil = Date().addingTimeInterval(0.5)
        textDocumentProxy.deleteBackward()
    }

    /// Text the system dictation (mic key) writes into the field is pulled into the top bar instead.
    private func watchForDictation() {
        let ctx = textDocumentProxy.documentContextBeforeInput ?? ""
        let after = textDocumentProxy.documentContextAfterInput ?? ""
        if dictBaseline == nil {
            defer { knownContext = ctx; knownAfter = after }
            // The user tapped a new cursor position in the host field (not in the top bar): finish composing
            // so the text already in the field can be edited directly.
            if isCompose, !composeText.isEmpty, Date() > ownUntil, after != knownAfter {
                commitLive()
                return
            }
            // Moving the cursor also grows the "before" text; real dictation leaves the text after the cursor untouched.
            guard isCompose, aiOn, Date() > ownUntil, after == knownAfter,
                  ctx.count > knownContext.count, ctx.hasPrefix(knownContext) else { return }
            dictBaseline = knownContext
        }
        dictTimer?.invalidate()
        dictTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            self?.flushDictation()
        }
    }

    private func flushDictation() {
        guard let base = dictBaseline else { return }
        dictBaseline = nil
        let ctx = textDocumentProxy.documentContextBeforeInput ?? ""
        knownContext = ctx
        knownAfter = textDocumentProxy.documentContextAfterInput ?? ""
        guard ctx.hasPrefix(base), ctx.count > base.count else { return }
        let added = String(ctx.dropFirst(base.count))
        for _ in 0..<added.count { ownDelete() }
        let clean = added.replacingOccurrences(of: "\n", with: " ")
        invalidateSuggestion()
        if language == .korean { composer.commitLiteral(clean) } else { latin.commitLiteral(clean) }
        updateBuffer()
        if !aiOn { commitLive() }
        scheduleAutoSuggest()
    }

    /// Clears everything typed into the top bar, and the translation already shown in the field.
    private func clearAll() {
        autoTimer?.invalidate()
        task?.cancel()
        removeLive()
        commitAfterResult = false
        composeClear()
        invalidateSuggestion()
        bar.set(.idle)
        updateBuffer()
    }

    /// Height from the app setting, plus room for the Korean compose bar.
    private func currentHeight() -> CGFloat {
        // The taller bar is added on top so the keys keep their size.
        AppSettings.keyboardHeight.points + (Self.barHeight - 44)
    }

    // MARK: - Rewrite

    private func currentLine() -> String {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        return before.components(separatedBy: "\n").last ?? ""
    }

    /// `auto` = fired by the typing-pause timer (quiet about empty/short input); otherwise by tapping the bar.
    private func triggerRewrite(auto: Bool = false) {
        autoTimer?.invalidate()
        guard aiOn else { return }
        let line = isCompose ? composeText : currentLine()
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if auto {
            // Only suggest for something sentence-like, and not for text we already handled.
            let longEnough: Bool
            switch language {
            case .korean, .japanese, .chinese: longEnough = !trimmed.isEmpty // live translation: any pause converts
            case .english: longEnough = trimmed.split(separator: " ").count >= 2
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
        let cacheKey = "fast|\(AppSettings.targetLanguage.rawValue)|\(sourceCode ?? "en")|\(selectedTone.rawValue)|\(AppSettings.explainLanguage.rawValue)|\(trimmed)"
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

    /// Puts `text` into the host field, replacing the previous live translation.
    private func replaceLive(with text: String) {
        var keep = 0
        if !liveText.isEmpty {
            let before = textDocumentProxy.documentContextBeforeInput ?? ""
            // Only touch our own text; if the cursor moved elsewhere, leave the old text alone.
            if before.hasSuffix(liveText) {
                // Keep the common beginning so only the changed tail is rewritten (no whole-text blink).
                let old = Array(liveText), new = Array(text)
                while keep < old.count, keep < new.count, old[keep] == new[keep] { keep += 1 }
                for _ in 0..<(old.count - keep) { ownDelete() }
            }
        }
        let rest = String(text.dropFirst(keep))
        if !rest.isEmpty { ownInsert(rest) }
        liveText = text
    }

    /// The compose buffer was emptied: take the translation back out of the field.
    private func removeLive() {
        if !liveText.isEmpty {
            let before = textDocumentProxy.documentContextBeforeInput ?? ""
            if before.hasSuffix(liveText) {
                for _ in 0..<liveText.count { ownDelete() }
            }
        }
        liveText = ""
        liveSource = ""
    }

    /// Keeps the translation in the field and clears the compose buffer.
    private func commitLive() {
        if liveText.isEmpty && !composeText.isEmpty {
            if aiOn, let r = composeResult, liveSource == composeText {
                ownInsert(r)
                AppSettings.queueKeyboardResult(r, tone: tone)
            } else {
                ownInsert(composeText)   // nothing converted yet: keep what was typed
            }
        } else if aiOn && !liveText.isEmpty {
            AppSettings.queueKeyboardResult(liveText, tone: tone)
        }
        liveText = ""
        liveSource = ""
        composeResult = nil
        commitAfterResult = false
        composeClear()
        updateBuffer()
    }

    /// Send button / return: puts the converted text into the host field (converting first if needed).
    private func deliver() {
        guard aiOn, !composeText.isEmpty else { return }
        if let r = composeResult, liveSource == composeText {
            ownInsert(r)
            AppSettings.queueKeyboardResult(r, tone: tone)
            liveSource = ""
            composeResult = nil
            commitAfterResult = false
            composeClear()
            bar.set(.idle)
            updateBuffer()
            updateAutoShift()
        } else {
            commitAfterResult = true
            triggerRewrite()
        }
    }

    private func show(_ r: RewriteResult, line: String, trimmed: String) {
        if isCompose {
            guard composeText == line else { return } // typed more while the request was in flight
            pending = nil
            liveSource = line
            if !aiOn { return }
            composeResult = r.best
            bar.set(.result(r.best))
            if commitAfterResult { deliver() }
            return
        }
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
            ownInsert(p.result.best)
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
        for _ in 0..<p.original.count { ownDelete() }
        ownInsert(p.result.best)
        AppSettings.queueKeyboardResult(p.result.best, tone: tone)
        pending = nil
        bar.set(.idle)
        updateAutoShift()
    }

    private func invalidateSuggestion() {
        task?.cancel()
        composeResult = nil
        commitAfterResult = false
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
        guard aiOn, AppSettings.autoSuggest, hasFullAccess else { return }
        autoTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.triggerRewrite(auto: true)
        }
    }

    // MARK: - Typing

    private func type(_ s: String) {
        if language == .korean { typeKorean(s); return }
        if language == .japanese || language == .chinese || isCompose { typeLatin(s); return }
        invalidateSuggestion()
        ownInsert(s)
        if shifted && !capsLock { shifted = false; refreshLetters() }
        if s == " " || s == "\n" { updateAutoShift() }
        scheduleAutoSuggest()
    }

    private func backspace() {
        if isCompose && !composeText.isEmpty {
            invalidateSuggestion()
            if language == .korean { composer.backspace() } else { latin.backspace() }
            updateBuffer()
            if composeText.isEmpty { removeLive() } else { scheduleAutoSuggest() }
            return
        }
        invalidateSuggestion()
        ownDelete()
        updateAutoShift()
        scheduleAutoSuggest()
    }

    private func updateAutoShift() {
        guard language == .english, layer == .letters, !capsLock else { return }
        // While composing, the text being typed lives in the top bar, not in the host field.
        let before = (isCompose && aiOn && !composeText.isEmpty) ? composeText : (textDocumentProxy.documentContextBeforeInput ?? "")
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
            ownInsert(s)
            return
        }
        invalidateSuggestion()
        let isLiteral = !HangulComposer.isJamo(s)
        if HangulComposer.isJamo(s), let ch = s.first {
            composer.input(ch)
        } else {
            composer.commitLiteral(s)
        }
        if shifted && !capsLock { shifted = false; refreshLetters() }
        updateBuffer()
        if !aiOn && isLiteral { commitLive() }
        scheduleAutoSuggest()
    }

    /// Japanese (romaji) and Chinese (pinyin): letters are composed in the buffer, then converted to English.
    private func typeLatin(_ s: String) {
        if latin.isEmpty && !LatinComposer.isLetter(s) {
            ownInsert(s)
            return
        }
        invalidateSuggestion()
        if LatinComposer.isLetter(s), let ch = s.first {
            // English keeps the case the shift key produced; romaji and pinyin are lowercase.
            latin.input(language == .english ? ch : Character(ch.lowercased()))
        } else {
            latin.commitLiteral(s)
        }
        if shifted && !capsLock { shifted = false; refreshLetters() }
        updateBuffer()
        if !aiOn && !LatinComposer.isLetter(s) { commitLive() }
        scheduleAutoSuggest()
    }

    private func updateBuffer() {
        bar.setComposing(aiOn ? composeText : "", caret: composeCaret)
        if !aiOn && language != .english { mirrorToField() }
        updateReturnLabel()
    }

    /// AI off: behave like a plain keyboard. The composed text is written straight into the host field.
    private func mirrorToField() {
        let t = composeText
        guard t != liveText else { return }
        replaceLive(with: t)
        liveSource = t
    }

    private func moveCaret(to index: Int) {
        invalidateSuggestion()
        if language == .korean { composer.moveCaret(to: index) } else { latin.moveCaret(to: index) }
        updateBuffer()
    }

    private func toggleAI() {
        autoTimer?.invalidate()
        task?.cancel()
        commitLive()                       // keep what the field already holds
        AppSettings.aiEnabled.toggle()
        bar.aiEnabled = AppSettings.aiEnabled
        pending = nil
        bar.set(.idle)
        updateBuffer()
    }

    private func toggleLanguage() {
        let list = availableLanguages.isEmpty ? languages() : availableLanguages
        let i = list.firstIndex(of: language) ?? 0
        language = list[(i + 1) % list.count]
        latin.japanese = language == .japanese
        commitLive()
        invalidateSuggestion()
        autoTimer?.invalidate()
        shifted = false
        capsLock = false
        layer = .letters
        heightConstraint.constant = currentHeight()
        bar.set(.idle)
        updateBuffer()
        rebuildKeys()
        updateAutoShift()
    }

    private func tapReturn() {
        if isCompose {
            if composeText.isEmpty {
                ownInsert("\n")
            } else if !aiOn {
                commitLive()
                ownInsert("\n")
            } else {
                deliver()
            }
            return
        }
        type("\n")
    }

    private func updateReturnLabel() {
        guard let returnButton else { return }
        var title = "return"
        if isCompose && aiOn && !composeText.isEmpty { title = L("완료", "Done") }
        returnButton.setTitle(title, for: .normal)
    }

    // MARK: - Layout

    private func rebuildKeys() {
        keysStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        letterBases = []
        shiftButton = nil

        if language == .japanese && layer == .letters && AppSettings.japaneseLayout == .kana {
            buildKanaKeys()
            return
        }

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
        attachSpaceCursor(space)
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

    // MARK: - Japanese kana (12-key flick) layout

    private func nextLanguageLabel() -> String {
        let list = availableLanguages.isEmpty ? languages() : availableLanguages
        let next = list[((list.firstIndex(of: language) ?? 0) + 1) % list.count]
        switch next {
        case .english: return "EN"
        case .korean: return InputLanguage.korean.keyLabel
        case .japanese: return InputLanguage.japanese.keyLabel
        case .chinese: return InputLanguage.chinese.keyLabel
        }
    }

    private func makeFlick(_ chars: [String]) -> FlickKey {
        let k = FlickKey(chars: chars)
        k.onCommit = { [weak self] in self?.typeKana($0) }
        return k
    }

    // MARK: - Space bar cursor

    private var cursorRemainder: CGFloat = 0
    private var cursorLastX: CGFloat = 0

    /// Press and hold the space bar, then slide left or right to move the text cursor (like the iOS trackpad).
    private func attachSpaceCursor(_ key: KeyButton) {
        let g = UILongPressGestureRecognizer(target: self, action: #selector(spaceCursor(_:)))
        g.minimumPressDuration = 0.3
        g.allowableMovement = 10_000
        key.addGestureRecognizer(g)
    }

    @objc private func spaceCursor(_ g: UILongPressGestureRecognizer) {
        let x = g.location(in: view).x
        switch g.state {
        case .began:
            commitLive()                     // finish any composed text first
            updateBuffer()
            cursorLastX = x; cursorRemainder = 0
            if AppSettings.haptics { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            (g.view as? KeyButton)?.setCursorMode(true)
        case .changed:
            cursorRemainder += x - cursorLastX
            cursorLastX = x
            let step: CGFloat = 9
            let n = Int(cursorRemainder / step)
            if n != 0 {
                cursorRemainder -= CGFloat(n) * step
                ownUntil = Date().addingTimeInterval(0.5)
                textDocumentProxy.adjustTextPosition(byCharacterOffset: n)
            }
        case .ended, .cancelled, .failed:
            (g.view as? KeyButton)?.setCursorMode(false)
        default:
            break
        }
    }

    private func typeKana(_ s: String) {
        // With nothing composed, punctuation goes straight to the host field.
        if latin.isEmpty && ["、", "。", "？", "！", "…"].contains(s) {
            ownInsert(s)
            return
        }
        invalidateSuggestion()
        latin.commitLiteral(s)
        updateBuffer()
        if !aiOn && ["、", "。", "？", "！", "…"].contains(s) { commitLive() }
        scheduleAutoSuggest()
    }

    private func moveCursor(_ offset: Int) {
        guard composeText.isEmpty else { return }
        ownUntil = Date().addingTimeInterval(0.5)
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
    }

    private func buildKanaKeys() {
        func hstack(_ views: [UIView]) -> UIStackView {
            let s = UIStackView(arrangedSubviews: views)
            s.axis = .horizontal; s.spacing = 5; s.distribution = .fillEqually
            return s
        }
        func vstack(_ views: [UIView], fill: Bool = false) -> UIStackView {
            let s = UIStackView(arrangedSubviews: views)
            s.axis = .vertical; s.spacing = 10
            s.distribution = fill ? .fill : .fillEqually
            return s
        }

        // Middle: 3 columns of flick keys + bottom row [小゛゜] [わ] [、。?!]
        let kana: [[[String]]] = [
            [["あ", "い", "う", "え", "お"], ["か", "き", "く", "け", "こ"], ["さ", "し", "す", "せ", "そ"]],
            [["た", "ち", "つ", "て", "と"], ["な", "に", "ぬ", "ね", "の"], ["は", "ひ", "ふ", "へ", "ほ"]],
            [["ま", "み", "む", "め", "も"], ["や", "（", "ゆ", "）", "よ"], ["ら", "り", "る", "れ", "ろ"]],
        ]
        var midRows: [UIView] = kana.map { hstack($0.map(makeFlick)) }
        let voicing = KeyButton(title: "小゛゜", style: .special, fontSize: 17)
        voicing.onTap = { [weak self] in
            guard let self else { return }
            self.invalidateSuggestion()
            self.latin.toggleVoicing()
            self.updateBuffer()
            self.scheduleAutoSuggest()
        }
        midRows.append(hstack([voicing, makeFlick(["わ", "を", "ん", "ー", "〜"]), makeFlick(["、", "。", "？", "！", "…"])]))
        let mid = vstack(midRows)

        // Left column: 123, cursor left/right, language switch
        let num = KeyButton(title: "123", style: .special, fontSize: 16)
        num.onTap = { [weak self] in self?.layer = .numbers; self?.rebuildKeys() }
        let left = KeyButton(symbol: "chevron.left", style: .special)
        left.onTap = { [weak self] in self?.moveCursor(-1) }
        let right = KeyButton(symbol: "chevron.right", style: .special)
        right.onTap = { [weak self] in self?.moveCursor(1) }
        let lang = KeyButton(title: nextLanguageLabel(), style: .special, fontSize: 16)
        lang.onTap = { [weak self] in self?.toggleLanguage() }
        let leftCol = vstack([num, left, right, lang])

        // Right column: delete, tall space, return
        let del = KeyButton(symbol: "delete.left", style: .special)
        del.onRepeat = { [weak self] in self?.backspace() }
        let space = KeyButton(title: "空白", style: .letter, fontSize: 16)
        space.onTap = { [weak self] in self?.type(" ") }
        attachSpaceCursor(space)
        let ret = KeyButton(title: "return", style: .special, fontSize: 16)
        ret.onTap = { [weak self] in self?.tapReturn() }
        returnButton = ret
        updateReturnLabel()
        let rightCol = vstack([del, space, ret], fill: true)

        let grid = UIStackView(arrangedSubviews: [leftCol, mid, rightCol])
        grid.axis = .horizontal; grid.spacing = 5; grid.distribution = .fill
        keysStack.addArrangedSubview(grid)

        // Constraints across views need the grid in the hierarchy first.
        rightCol.widthAnchor.constraint(equalTo: leftCol.widthAnchor).isActive = true
        mid.widthAnchor.constraint(equalTo: leftCol.widthAnchor, multiplier: 3, constant: 10).isActive = true
        ret.heightAnchor.constraint(equalTo: del.heightAnchor).isActive = true
        space.heightAnchor.constraint(equalTo: del.heightAnchor, multiplier: 2, constant: 10).isActive = true
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
