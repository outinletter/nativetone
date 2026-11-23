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

    private var aiOn: Bool { AppSettings.aiEnabled }
    /// Korean / Japanese / Chinese letters are composed in a one-word buffer that is mirrored into the host field.
    private var isCompose: Bool { language != .english }
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
    /// The mic (dictation) key listens in the language of the layout that is showing.
    override var primaryLanguage: String? {
        get {
            switch language {
            case .english: return "en-US"
            case .korean: return "ko-KR"
            case .japanese: return "ja-JP"
            case .chinese: return "zh-CN"
            }
        }
        set { }
    }
    private var heightConstraint: NSLayoutConstraint!
    private var returnButton: KeyButton?
    private static let shiftedJamo: [String: String] = [
        "ㅂ": "ㅃ", "ㅈ": "ㅉ", "ㄷ": "ㄸ", "ㄱ": "ㄲ", "ㅅ": "ㅆ", "ㅐ": "ㅒ", "ㅔ": "ㅖ",
    ]

    private var tone = AppSettings.tone

    /// The word being composed, exactly as it currently sits in the host field.
    private var shown = ""
    /// Last applied conversion, kept so the undo button can restore the original.
    private var lastApplied: (original: String, result: String)?
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
        bar.onTrigger = { [weak self] in
            guard let self else { return }
            if self.bar.canPaste { self.pasteFromClipboard() } else { self.triggerRewrite() }
        }
        bar.onPaste = { [weak self] in self?.pasteFromClipboard() }
        bar.onApply = { [weak self] in self?.applySuggestion() }
        bar.onToneTap = { [weak self] in self?.cycleTone() }
        bar.onAIToggle = { [weak self] in self?.toggleAI() }
        bar.onUndo = { [weak self] in self?.undoApply() }
        bar.onStateChange = { [weak self] in self?.updateReturnLabel() }

        rebuildKeys()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Haptics.enabled = AppSettings.haptics
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
        finishWord()
        refreshPasteHint()
        heightConstraint.constant = currentHeight()
        bar.set(.idle)
        updateAutoShift()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // Reading the field's text is a slow cross-process call. Skip it for our own keystrokes
        // so fast typing stays smooth; only outside changes (cursor moves, paste, dictation) are checked.
        guard Date() > ownUntil, !syncPending else { return }
        updateAutoShift()
        refreshPasteHint()
        // The cursor was moved (or the field changed) behind our back: the word buffer no longer matches the field.
        if !shown.isEmpty, Date() > ownUntil {
            let before = textDocumentProxy.documentContextBeforeInput ?? ""
            if !before.hasSuffix(shown) { finishWord() }
        }
    }

    // MARK: - Paste

    /// `hasStrings` does not read the clipboard, so it does not trigger the system paste prompt.
    private func refreshPasteHint() {
        bar.canPaste = aiOn && hasFullAccess && UIPasteboard.general.hasStrings
            && currentLine().isEmpty && (textDocumentProxy.documentContextBeforeInput ?? "").isEmpty
    }

    /// Puts the clipboard text into the field and converts it right away.
    private func pasteFromClipboard() {
        guard hasFullAccess else {
            bar.set(.message(L("설정에서 '전체 접근 허용'을 켜주세요", "Turn on 'Allow Full Access' in Settings")))
            return
        }
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            bar.set(.message(L("클립보드에 붙여넣을 글이 없어요", "Nothing to paste")))
            return
        }
        guard text.count <= AppConfig.maxInputLength else {
            bar.set(.message(L("글이 너무 길어요", "The text is too long")))
            return
        }
        invalidateSuggestion()
        finishWord()
        ownInsert(text)
        bar.canPaste = false
        // Give the host a moment to report the new text before reading the sentence back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.triggerRewrite() }
    }

    // MARK: - Typing straight into the host field

    private var ownUntil = Date.distantPast

    private func ownInsert(_ s: String) {
        ownUntil = Date().addingTimeInterval(0.5)
        textDocumentProxy.insertText(s)
    }

    private func ownDelete() {
        ownUntil = Date().addingTimeInterval(0.5)
        textDocumentProxy.deleteBackward()
    }

    /// Makes the host field show the current word buffer. Keys typed within a few milliseconds of each other
    /// are folded into one update, so a fast burst costs one delete/insert round trip instead of one per key.
    private var syncPending = false
    private func syncField() {
        guard !syncPending else { return }
        syncPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in self?.flushSync() }
    }

    /// Applies a pending update now. Everything that reads or edits the field calls this first.
    private func flushSync() {
        guard syncPending else { return }
        syncPending = false
        let new = composeText
        guard new != shown else { return }
        let old = Array(shown), neu = Array(new)
        var keep = 0
        while keep < old.count, keep < neu.count, old[keep] == neu[keep] { keep += 1 }
        for _ in 0..<(old.count - keep) { ownDelete() }
        let rest = String(neu[keep...])
        if !rest.isEmpty { ownInsert(rest) }
        shown = new
    }

    /// The word is done (space, punctuation, return, cursor move, language switch): its text simply stays in the field.
    private func finishWord() {
        flushSync()
        composeClear()
        shown = ""
    }

    /// Height from the app setting, plus room for the Korean compose bar.
    private func currentHeight() -> CGFloat {
        // The taller bar is added on top so the keys keep their size.
        AppSettings.keyboardHeight.points + (Self.barHeight - 44)
    }

    // MARK: - Rewrite

    /// What a conversion would replace: the selected text, or else the current sentence before the cursor
    /// (everything after the last sentence end or line break, without its leading whitespace).
    private func currentLine() -> String {
        flushSync()
        if let sel = textDocumentProxy.selectedText, !sel.isEmpty { return sel }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let ends: Set<Character> = [".", "!", "?", "。", "！", "？", "\n"]
        var seg = Substring(before)
        if let idx = before.lastIndex(where: { ends.contains($0) }) { seg = before[before.index(after: idx)...] }
        return String(seg.drop(while: { $0 == " " || $0 == "\t" }))
    }

    /// `auto` = fired by the typing-pause timer (quiet about empty/short input); otherwise by tapping the bar.
    private func triggerRewrite(auto: Bool = false) {
        autoTimer?.invalidate()
        guard aiOn else { return }
        let line = currentLine()
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

    private func show(_ r: RewriteResult, line: String, trimmed: String) {
        guard currentLine() == line else { return }   // typed more while the request was in flight
        if r.best == trimmed {
            pending = nil
            bar.set(.ok(L("이미 자연스러운 문장이에요", "Already sounds natural")))
        } else {
            pending = Pending(original: line, result: r)
            bar.set(.result(r.best))
        }
    }

    /// Replaces the sentence in the host field with the suggestion; the undo button can bring the original back.
    private func applySuggestion() {
        guard let p = pending else { return }
        // Make sure the text hasn't changed since the suggestion was requested.
        guard currentLine() == p.original else {
            pending = nil
            bar.set(.message(L("문장이 바뀌었어요. 바를 다시 탭하세요", "The text changed. Tap the bar again")))
            return
        }
        finishWord()
        let hasSelection = !(textDocumentProxy.selectedText ?? "").isEmpty
        let trailing = String(p.original.reversed().prefix(while: { $0 == " " || $0 == "\n" }).reversed())
        let output = p.result.best + (hasSelection ? "" : trailing)
        if !hasSelection { for _ in 0..<p.original.count { ownDelete() } }
        ownInsert(output)
        AppSettings.queueKeyboardResult(p.result.best, tone: tone)
        pending = nil
        bar.set(.idle)
        lastApplied = (p.original, output)
        bar.setUndoAvailable(true)
        updateAutoShift()
    }

    private func undoApply() {
        guard let a = lastApplied else { return }
        lastApplied = nil
        bar.setUndoAvailable(false)
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        guard before.hasSuffix(a.result) else { return }
        for _ in 0..<a.result.count { ownDelete() }
        ownInsert(a.original)
        bar.set(.idle)
        updateAutoShift()
    }

    private func invalidateSuggestion() {
        task?.cancel()
        if lastApplied != nil { lastApplied = nil; bar.setUndoAvailable(false) }
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
        if language == .japanese || language == .chinese { typeLatin(s); return }
        invalidateSuggestion()
        ownInsert(s)
        if shifted && !capsLock { shifted = false; refreshLetters() }
        if s == " " || s == "\n" { updateAutoShift() }
        scheduleAutoSuggest()
    }

    private func backspace() {
        invalidateSuggestion()
        if isCompose && !composeText.isEmpty {
            if language == .korean { composer.backspace() } else { latin.backspace() }
            syncField()
        } else {
            flushSync()      // a pending word update must reach the field before we delete behind it
            ownDelete()
            updateAutoShift()
        }
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
        invalidateSuggestion()
        if HangulComposer.isJamo(s), let ch = s.first {
            composer.input(ch)
            syncField()
        } else {
            finishWord()
            ownInsert(s)
        }
        if shifted && !capsLock { shifted = false; refreshLetters() }
        scheduleAutoSuggest()
    }

    /// Japanese (romaji) and Chinese (pinyin): letters are composed as one word in the field.
    private func typeLatin(_ s: String) {
        invalidateSuggestion()
        if LatinComposer.isLetter(s), let ch = s.first {
            latin.input(Character(ch.lowercased()))
            syncField()
        } else {
            finishWord()
            ownInsert(s)
        }
        if shifted && !capsLock { shifted = false; refreshLetters() }
        scheduleAutoSuggest()
    }

    private func toggleAI() {
        autoTimer?.invalidate()
        task?.cancel()
        AppSettings.aiEnabled.toggle()
        bar.aiEnabled = AppSettings.aiEnabled
        pending = nil
        bar.set(.idle)
    }

    private func toggleLanguage() {
        let list = availableLanguages.isEmpty ? languages() : availableLanguages
        let i = list.firstIndex(of: language) ?? 0
        language = list[(i + 1) % list.count]
        latin.japanese = language == .japanese
        finishWord()
        invalidateSuggestion()
        autoTimer?.invalidate()
        shifted = false
        capsLock = false
        layer = .letters
        heightConstraint.constant = currentHeight()
        bar.set(.idle)
        rebuildKeys()
        updateAutoShift()
    }

    private func tapReturn() {
        type("\n")
    }

    private func updateReturnLabel() {
        returnButton?.setTitle("return", for: .normal)
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
        key.triggersOnTouchDown = false      // a long press slides the cursor instead of typing a space
        let g = UILongPressGestureRecognizer(target: self, action: #selector(spaceCursor(_:)))
        g.minimumPressDuration = 0.3
        g.allowableMovement = 10_000
        key.addGestureRecognizer(g)
    }

    @objc private func spaceCursor(_ g: UILongPressGestureRecognizer) {
        let x = g.location(in: view).x
        switch g.state {
        case .began:
            finishWord()                     // finish any composed text first
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
        invalidateSuggestion()
        if ["、", "。", "？", "！", "…"].contains(s) {
            finishWord()
            ownInsert(s)
        } else {
            latin.commitLiteral(s)
            syncField()
        }
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
            self.syncField()
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
