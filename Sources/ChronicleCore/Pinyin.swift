import Foundation

public enum Pinyin {
    /// 常见多音字：ICU 默认读音之外，额外参与检索的读音。
    static let polyphones: [Character: [String]] = [
        "重": ["chong"], "长": ["chang"], "行": ["hang", "xing"], "乐": ["yue"],
        "还": ["huan"], "了": ["liao"], "都": ["du"], "得": ["dei"],
        "地": ["de"], "着": ["zhao", "zhuo"], "数": ["shuo"], "调": ["tiao"],
        "便": ["pian"], "觉": ["jiao"], "藏": ["zang"], "系": ["ji"],
        "差": ["chai", "ci"], "参": ["shen"], "什": ["shi"], "么": ["mo"],
        "和": ["huo"], "会": ["kuai"], "为": ["wei"], "与": ["yu"],
        "给": ["ji"], "曾": ["zeng"], "落": ["la"], "强": ["jiang"],
        "省": ["xing"], "血": ["xie"], "应": ["ying"], "相": ["xiang"],
        "单": ["shan"], "朝": ["zhao"], "曲": ["qu"], "塞": ["se"],
        "薄": ["bo"], "阿": ["e"], "否": ["pi"], "难": ["nan"],
        "没": ["mo"], "更": ["geng"], "供": ["gong"], "假": ["jia"],
        "间": ["jian"], "将": ["jiang"], "教": ["jiao"], "结": ["jie"],
        "解": ["jie"], "看": ["kan"], "论": ["lun"], "少": ["shao"],
        "宿": ["xiu"], "似": ["shi"], "削": ["xue"], "载": ["zai"],
        "转": ["zhuan"], "种": ["zhong"]
    ]

    /// 汉字转拉丁（无声调），英文保持原样并转小写。
    public static func transliterate(_ text: String) -> String {
        let latin = text.applyingTransform(.toLatin, reverse: false) ?? text
        let plain = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        return plain.lowercased()
    }

    /// 按音节切分，例如「重新设计网站」→ ["chong","xin","she","ji","wang","zhan"]
    public static func syllables(_ text: String) -> [String] {
        transliterate(text)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    /// 全拼（无空格），例如「重新设计网站」→ "chongxinshejiwangzhan"
    public static func joined(_ text: String) -> String {
        syllables(text).joined()
    }

    /// 拼音首字母（ICU 默认读音），例如「重新设计网站」→ "zxsjwz"；多音字变体由 variants 提供。
    public static func initials(_ text: String) -> String {
        syllables(text).compactMap { $0.first.map(String.init) }.joined()
    }

    /// 规范化后的带空格全拼，例如 "chong xin she ji wang zhan"
    public static func spaced(_ text: String) -> String {
        syllables(text).joined(separator: " ")
    }

    /// 生成多音字的所有检索变体（全拼 + 首字母），供内存索引匹配使用。
    public static func variants(_ text: String) -> [(joined: String, initials: String)] {
        let groups = syllableGroups(text)
        guard !groups.isEmpty else { return [] }

        var combinations: [[String]] = [[]]
        for group in groups {
            var next: [[String]] = []
            for combination in combinations {
                for option in group.prefix(4) {
                    next.append(combination + [option])
                }
            }
            combinations = Array(next.prefix(64))
        }

        var seen = Set<String>()
        var result: [(String, String)] = []
        for combination in combinations {
            let joined = combination.joined()
            let initials = combination.compactMap { $0.first.map(String.init) }.joined()
            let key = joined + "|" + initials
            guard seen.insert(key).inserted else { continue }
            result.append((joined, initials))
        }
        return result
    }

    public static func makeSource(key: String, text: String, pinyin: String, initials: String) -> PinyinSource {
        let compactPinyin = pinyin.replacingOccurrences(of: " ", with: "")
        let variants = variants(text)
        let alternates = Array(Set(variants.map(\.joined).filter { !$0.isEmpty && $0 != compactPinyin }))
        let alternateInitials = Array(Set(variants.map(\.initials).filter { !$0.isEmpty && $0 != initials }))
        return PinyinSource(
            key: key,
            text: text,
            pinyin: pinyin,
            initials: initials,
            alternates: alternates,
            alternateInitials: alternateInitials
        )
    }

    private static func syllableGroups(_ text: String) -> [[String]] {
        var groups: [[String]] = []
        var latinBuffer = ""

        func flushLatin() {
            guard !latinBuffer.isEmpty else { return }
            for syllable in syllables(latinBuffer) {
                groups.append([syllable])
            }
            latinBuffer = ""
        }

        for character in text {
            if character.isASCII {
                latinBuffer.append(character)
            } else {
                flushLatin()
                let base = syllables(String(character))
                guard !base.isEmpty else { continue }
                var options = base
                if let alternates = polyphones[character] {
                    options.append(contentsOf: alternates)
                }
                groups.append(options)
            }
        }
        flushLatin()
        return groups
    }
}

public struct PinyinSource: Hashable {
    public let key: String
    public let text: String
    public let pinyin: String
    public let initials: String
    public let alternates: [String]
    public let alternateInitials: [String]

    public init(
        key: String,
        text: String,
        pinyin: String,
        initials: String,
        alternates: [String] = [],
        alternateInitials: [String] = []
    ) {
        self.key = key
        self.text = text
        self.pinyin = pinyin
        self.initials = initials
        self.alternates = alternates
        self.alternateInitials = alternateInitials
    }
}

/// 常驻内存的拼音索引：数据库只保存原文，检索用的拼音数据来自缓存表/内存索引。
public struct PinyinIndex {
    private var sources: [PinyinSource] = []

    public init() {}

    public mutating func rebuild(_ items: [PinyinSource]) {
        sources = items
    }

    public mutating func upsert(_ item: PinyinSource) {
        if let index = sources.firstIndex(where: { $0.key == item.key }) {
            sources[index] = item
        } else {
            sources.append(item)
        }
    }

    public mutating func remove(key: String) {
        sources.removeAll { $0.key == key }
    }

    public func search(_ rawQuery: String) -> [String] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return sources.map(\.key) }

        var ranked: [(key: String, score: Int, order: Int)] = []
        for (order, source) in sources.enumerated() {
            if let score = Self.score(query, source) {
                ranked.append((source.key, score, order))
            }
        }
        ranked.sort { lhs, rhs in
            if lhs.score == rhs.score { return lhs.order < rhs.order }
            return lhs.score > rhs.score
        }
        return ranked.map(\.key)
    }

    static func score(_ query: String, _ source: PinyinSource) -> Int? {
        let name = source.text.lowercased()
        if name == query { return 120 }
        if name.hasPrefix(query) { return 110 }
        if name.contains(query) { return 100 }

        let compactQuery = query.replacingOccurrences(of: " ", with: "")
        guard !compactQuery.isEmpty else { return 100 }

        if source.initials == compactQuery { return 96 }
        if source.initials.hasPrefix(compactQuery) { return 90 }
        if source.initials.contains(compactQuery) { return 80 }

        let joinedPinyin = source.pinyin.replacingOccurrences(of: " ", with: "")
        if joinedPinyin.hasPrefix(compactQuery) { return 70 }
        if joinedPinyin.contains(compactQuery) { return 60 }

        for alternate in source.alternates {
            if alternate == compactQuery { return 58 }
            if alternate.hasPrefix(compactQuery) { return 55 }
            if alternate.contains(compactQuery) { return 52 }
            if compactQuery.count >= 3, isSubsequence(compactQuery, alternate) { return 24 }
        }
        for alternate in source.alternateInitials {
            if alternate == compactQuery { return 78 }
            if alternate.hasPrefix(compactQuery) { return 76 }
            if alternate.contains(compactQuery) { return 72 }
        }

        if compactQuery.count >= 2 {
            if matchesSyllableRuns(compactQuery, source.pinyin) { return 45 }
            if isSubsequence(compactQuery, source.initials) { return 35 }
        }
        if compactQuery.count >= 3, isSubsequence(compactQuery, joinedPinyin) { return 25 }
        return nil
    }

    /// 查询的每一段都按顺序命中某个音节的起始部分，例如 "chongxinwangzhan"。
    private static func matchesSyllableRuns(_ query: String, _ pinyin: String) -> Bool {
        let syllables = pinyin.split(separator: " ").map(String.init)
        var position = query.startIndex
        var syllableIndex = 0
        while position < query.endIndex {
            var matched = false
            while syllableIndex < syllables.count {
                let syllable = syllables[syllableIndex]
                syllableIndex += 1
                var cursor = position
                for character in syllable {
                    if cursor < query.endIndex, query[cursor] == character {
                        cursor = query.index(after: cursor)
                    }
                }
                if cursor > position {
                    position = cursor
                    matched = true
                    break
                }
            }
            if !matched { return false }
        }
        return true
    }

    private static func isSubsequence(_ needle: String, _ haystack: String) -> Bool {
        var cursor = haystack.startIndex
        for character in needle {
            guard let found = haystack[cursor...].firstIndex(of: character) else { return false }
            cursor = haystack.index(after: found)
        }
        return true
    }
}
