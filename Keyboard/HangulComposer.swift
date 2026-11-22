import Foundation

/// 2-set (두벌식) Hangul composer working on Compatibility Jamo input.
/// `text` = already committed text + the syllable currently being composed.
struct HangulComposer {
    private static let choList: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    private static let jungList: [Character] = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    private static let jongList: [Character] = Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ") // jong index = position + 1

    private static let vowelCompounds: [String: Character] = [
        "ㅗㅏ": "ㅘ", "ㅗㅐ": "ㅙ", "ㅗㅣ": "ㅚ", "ㅜㅓ": "ㅝ", "ㅜㅔ": "ㅞ", "ㅜㅣ": "ㅟ", "ㅡㅣ": "ㅢ",
    ]
    private static let finalCompounds: [String: Character] = [
        "ㄱㅅ": "ㄳ", "ㄴㅈ": "ㄵ", "ㄴㅎ": "ㄶ", "ㄹㄱ": "ㄺ", "ㄹㅁ": "ㄻ", "ㄹㅂ": "ㄼ",
        "ㄹㅅ": "ㄽ", "ㄹㅌ": "ㄾ", "ㄹㅍ": "ㄿ", "ㄹㅎ": "ㅀ", "ㅂㅅ": "ㅄ",
    ]

    private(set) var committed = ""
    private var cho: Character?
    private var jung: Character?
    private var jong: Character?

    var composing: String {
        switch (cho, jung) {
        case let (c?, v?):
            let ci = Self.choList.firstIndex(of: c)!
            let vi = Self.jungList.firstIndex(of: v)!
            let ji = jong.flatMap { Self.jongList.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            let code = 0xAC00 + (ci * 21 + vi) * 28 + ji
            return String(UnicodeScalar(code).map(Character.init) ?? c)
        case let (c?, nil): return String(c)
        case let (nil, v?): return String(v)
        default: return ""
        }
    }

    var text: String { committed + composing }
    var isEmpty: Bool { committed.isEmpty && cho == nil && jung == nil }

    static func isJamo(_ s: String) -> Bool {
        guard s.count == 1, let v = s.unicodeScalars.first?.value else { return false }
        return (0x3131...0x3163).contains(v)
    }

    mutating func clear() {
        committed = ""
        cho = nil; jung = nil; jong = nil
    }

    /// Commit the syllable being composed.
    private mutating func flush() {
        committed += composing
        cho = nil; jung = nil; jong = nil
    }

    /// Space, punctuation, digits…
    mutating func commitLiteral(_ s: String) {
        flush()
        committed += s
    }

    mutating func input(_ ch: Character) {
        if Self.jungList.contains(ch) { inputVowel(ch) } else { inputConsonant(ch) }
    }

    private mutating func inputVowel(_ v: Character) {
        if cho == nil && jung == nil {
            jung = v                      // lone vowel
        } else if jung == nil {
            jung = v                      // cho + vowel
        } else if let j = jong {
            // Move the final consonant to the new syllable.
            if let (a, b) = Self.splitFinal(j) {
                jong = a
                flush()
                cho = b
            } else {
                jong = nil
                flush()
                cho = j
            }
            jung = v
        } else if let cur = jung, cho != nil, let combined = Self.vowelCompounds[String([cur, v])] {
            jung = combined
        } else {
            flush()
            jung = v
        }
    }

    private mutating func inputConsonant(_ c: Character) {
        if cho == nil && jung == nil {
            cho = c
        } else if jung == nil {
            flush()
            cho = c
        } else if cho == nil {
            flush()
            cho = c
        } else if let j = jong {
            if let combined = Self.finalCompounds[String([j, c])] {
                jong = combined
            } else {
                flush()
                cho = c
            }
        } else if Self.jongList.contains(c) {
            jong = c
        } else {
            flush()
            cho = c
        }
    }

    /// Returns true if anything was removed.
    @discardableResult
    mutating func backspace() -> Bool {
        if let j = jong {
            jong = Self.splitFinal(j)?.0
            return true
        }
        if let v = jung {
            if cho != nil, let (a, _) = Self.splitVowel(v) {
                jung = a
            } else {
                jung = nil
            }
            return true
        }
        if cho != nil {
            cho = nil
            return true
        }
        if !committed.isEmpty {
            committed.removeLast()
            return true
        }
        return false
    }

    private static func splitFinal(_ c: Character) -> (Character, Character)? {
        for (k, v) in finalCompounds where v == c {
            let p = Array(k)
            return (p[0], p[1])
        }
        return nil
    }

    private static func splitVowel(_ c: Character) -> (Character, Character)? {
        for (k, v) in vowelCompounds where v == c {
            let p = Array(k)
            return (p[0], p[1])
        }
        return nil
    }
}
