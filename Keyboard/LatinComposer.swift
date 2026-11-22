import Foundation

/// Compose buffer for Japanese (romaji -> hiragana) and Chinese (pinyin shown as typed).
/// The buffer is never inserted as-is: it is converted to natural English by the server.
struct LatinComposer {
    var japanese = false
    private(set) var raw = ""

    var text: String { japanese ? Romaji.toKana(raw) : raw }
    var isEmpty: Bool { raw.isEmpty }

    mutating func clear() { raw = "" }
    mutating func input(_ ch: Character) { raw.append(ch) }
    mutating func commitLiteral(_ s: String) { raw += s }
    mutating func backspace() { if !raw.isEmpty { raw.removeLast() } }

    /// 小゛゜ key: cycles the last kana through voiced / semi-voiced / small forms (か→が, は→ば→ぱ, つ→っ→づ).
    mutating func toggleVoicing() {
        guard let last = raw.last, let next = Kana.cycle[last] else { return }
        raw.removeLast()
        raw.append(next)
    }

    static func isLetter(_ s: String) -> Bool {
        s.count == 1 && s.unicodeScalars.allSatisfy { ("a"..."z").contains(Character($0)) || ("A"..."Z").contains(Character($0)) }
    }
}

enum Kana {
    private static let groups: [[Character]] = [
        ["か", "が"], ["き", "ぎ"], ["く", "ぐ"], ["け", "げ"], ["こ", "ご"],
        ["さ", "ざ"], ["し", "じ"], ["す", "ず"], ["せ", "ぜ"], ["そ", "ぞ"],
        ["た", "だ"], ["ち", "ぢ"], ["つ", "っ", "づ"], ["て", "で"], ["と", "ど"],
        ["は", "ば", "ぱ"], ["ひ", "び", "ぴ"], ["ふ", "ぶ", "ぷ"], ["へ", "べ", "ぺ"], ["ほ", "ぼ", "ぽ"],
        ["あ", "ぁ"], ["い", "ぃ"], ["う", "ぅ", "ゔ"], ["え", "ぇ"], ["お", "ぉ"],
        ["や", "ゃ"], ["ゆ", "ゅ"], ["よ", "ょ"], ["わ", "ゎ"],
    ]
    static let cycle: [Character: Character] = {
        var d = [Character: Character]()
        for g in groups { for (i, c) in g.enumerated() { d[c] = g[(i + 1) % g.count] } }
        return d
    }()
}

enum Romaji {
    private static let table: [String: String] = {
        var t = [String: String]()
        let rows: [(String, [String])] = [
            ("", ["あ", "い", "う", "え", "お"]), ("k", ["か", "き", "く", "け", "こ"]), ("g", ["が", "ぎ", "ぐ", "げ", "ご"]),
            ("s", ["さ", "し", "す", "せ", "そ"]), ("z", ["ざ", "じ", "ず", "ぜ", "ぞ"]), ("t", ["た", "ち", "つ", "て", "と"]),
            ("d", ["だ", "ぢ", "づ", "で", "ど"]), ("n", ["な", "に", "ぬ", "ね", "の"]), ("h", ["は", "ひ", "ふ", "へ", "ほ"]),
            ("b", ["ば", "び", "ぶ", "べ", "ぼ"]), ("p", ["ぱ", "ぴ", "ぷ", "ぺ", "ぽ"]), ("m", ["ま", "み", "む", "め", "も"]),
            ("r", ["ら", "り", "る", "れ", "ろ"]),
        ]
        for (c, kana) in rows {
            for (i, v) in "aiueo".enumerated() { t[c + String(v)] = kana[i] }
        }
        t["ya"] = "や"; t["yu"] = "ゆ"; t["yo"] = "よ"; t["wa"] = "わ"; t["wo"] = "を"
        t["shi"] = "し"; t["chi"] = "ち"; t["tsu"] = "つ"; t["fu"] = "ふ"; t["ji"] = "じ"
        for (c, k) in [("k", "き"), ("g", "ぎ"), ("n", "に"), ("h", "ひ"), ("b", "び"), ("p", "ぴ"), ("m", "み"), ("r", "り")] {
            t[c + "ya"] = k + "ゃ"; t[c + "yu"] = k + "ゅ"; t[c + "yo"] = k + "ょ"
        }
        for (c, k) in [("sh", "し"), ("ch", "ち"), ("j", "じ"), ("sy", "し"), ("cy", "ち"), ("ty", "ち"), ("jy", "じ"), ("zy", "じ"), ("dy", "ぢ")] {
            t[c + "a"] = k + "ゃ"; t[c + "u"] = k + "ゅ"; t[c + "o"] = k + "ょ"
        }
        t["she"] = "しぇ"; t["che"] = "ちぇ"; t["je"] = "じぇ"
        t["fa"] = "ふぁ"; t["fi"] = "ふぃ"; t["fe"] = "ふぇ"; t["fo"] = "ふぉ"
        t["xtu"] = "っ"; t["ltu"] = "っ"
        return t
    }()

    private static let vowels = Set("aiueo")
    private static let punctuation: [Character: String] = ["-": "ー", ",": "、", ".": "。", "?": "？", "!": "！"]

    static func toKana(_ input: String) -> String {
        let s = Array(input.lowercased())
        var out = ""
        var i = 0
        while i < s.count {
            let c = s[i]
            if let p = punctuation[c] { out += p; i += 1; continue }
            guard c.isLetter, c.isASCII else { out.append(c); i += 1; continue }

            let next: Character? = i + 1 < s.count ? s[i + 1] : nil
            if let n = next, n == c, c != "n", !vowels.contains(c) { out += "っ"; i += 1; continue }
            if c == "n" {
                if next == "n" { out += "ん"; i += 2; continue }
                if let n = next, !vowels.contains(n), n != "y" { out += "ん"; i += 1; continue }
            }
            var matched = false
            for len in stride(from: min(3, s.count - i), through: 1, by: -1) {
                if let k = table[String(s[i..<i + len])] { out += k; i += len; matched = true; break }
            }
            if !matched { out.append(c); i += 1 } // pending consonant is shown as typed
        }
        return out
    }
}
