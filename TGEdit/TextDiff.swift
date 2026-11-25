import Foundation

/// Maps an old string onto a new one, grapheme by grapheme.
///
/// Strategy (similar in spirit to diff-match-patch's semantic cleanup):
/// 1. Tokenise both texts into words / whitespace / newlines / single symbols.
/// 2. Myers diff on tokens, so whole words stay matched even when the text around them changes.
/// 3. Inside every replaced block, a character-level Myers diff — accepted only when the two
///    sides are similar enough (a typo fix keeps its letters; an unrelated word is replaced).
/// 4. Remaining whole-word deletions and insertions with identical text are paired as moves.
struct TextDiffResult {
    /// old grapheme index → new grapheme index, for characters that survive (in place or moved).
    var mapping: [Int: Int] = [:]
    var moved: Set<Int> = []
    var removed: [Int] = []
    var inserted: [Int] = []

    var keptCount: Int { mapping.count }
}

enum TextDiff {
    private enum TokenKind { case word, space, newline, symbol }

    private struct Token {
        let text: String
        let start: Int
        let length: Int
        let kind: TokenKind
    }

    private static func isWordCharacter(_ c: Character) -> Bool {
        if c.isLetter || c.isNumber || c == "_" { return true }
        return false
    }

    private static func isEmoji(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first else { return false }
        return scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && c.unicodeScalars.count > 1)
    }

    private static func tokenize(_ chars: [Character]) -> [Token] {
        var tokens: [Token] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            var j = i + 1
            let kind: TokenKind
            if c.isNewline {
                kind = .newline
            } else if c.isWhitespace {
                kind = .space
                while j < chars.count, chars[j].isWhitespace, !chars[j].isNewline { j += 1 }
            } else if isWordCharacter(c) {
                kind = .word
                while j < chars.count {
                    let next = chars[j]
                    if isWordCharacter(next) {
                        j += 1
                    } else if (next == "'" || next == "’" || next == "-") && j + 1 < chars.count && isWordCharacter(chars[j + 1]) {
                        j += 1
                    } else {
                        break
                    }
                }
            } else {
                kind = .symbol
            }
            tokens.append(Token(text: String(chars[i ..< j]), start: i, length: j - i, kind: kind))
            i = j
        }
        return tokens
    }

    private enum Op {
        case equal(Int, Int)
        case delete(Int)
        case insert(Int)
    }

    /// Ordered alignment (LCS) of two sequences using Swift's Myers implementation.
    private static func align<T: Hashable>(_ old: [T], _ new: [T]) -> [Op] {
        let difference = new.difference(from: old)
        var removed = Set<Int>()
        var insertedSet = Set<Int>()
        for change in difference {
            switch change {
            case let .remove(offset, _, _): removed.insert(offset)
            case let .insert(offset, _, _): insertedSet.insert(offset)
            }
        }
        var ops: [Op] = []
        var i = 0, j = 0
        while i < old.count || j < new.count {
            if i < old.count && removed.contains(i) {
                ops.append(.delete(i)); i += 1
            } else if j < new.count && insertedSet.contains(j) {
                ops.append(.insert(j)); j += 1
            } else if i < old.count && j < new.count {
                ops.append(.equal(i, j)); i += 1; j += 1
            } else if i < old.count {
                ops.append(.delete(i)); i += 1
            } else {
                ops.append(.insert(j)); j += 1
            }
        }
        return ops
    }

    static func diff(old: [Character], new: [Character]) -> TextDiffResult {
        var result = TextDiffResult()
        let oldTokens = tokenize(old)
        let newTokens = tokenize(new)
        let ops = align(oldTokens.map(\.text), newTokens.map(\.text))

        var removedTokens: [Int] = []   // fully removed old tokens (move candidates)
        var insertedTokens: [Int] = []  // fully inserted new tokens

        var pendingDeletes: [Int] = []
        var pendingInserts: [Int] = []

        func flushBlock() {
            defer { pendingDeletes.removeAll(); pendingInserts.removeAll() }
            if pendingDeletes.isEmpty && pendingInserts.isEmpty { return }
            if pendingDeletes.isEmpty {
                insertedTokens.append(contentsOf: pendingInserts); return
            }
            if pendingInserts.isEmpty {
                removedTokens.append(contentsOf: pendingDeletes); return
            }
            // Replace block: try a character-level alignment.
            let oldStart = oldTokens[pendingDeletes.first!].start
            let oldEnd = oldTokens[pendingDeletes.last!].start + oldTokens[pendingDeletes.last!].length
            let newStart = newTokens[pendingInserts.first!].start
            let newEnd = newTokens[pendingInserts.last!].start + newTokens[pendingInserts.last!].length
            let oldChars = Array(old[oldStart ..< oldEnd])
            let newChars = Array(new[newStart ..< newEnd])
            let charOps = align(oldChars, newChars)
            var matched = 0
            var matchedVisible = 0
            for op in charOps {
                if case let .equal(a, _) = op {
                    matched += 1
                    if !oldChars[a].isWhitespace { matchedVisible += 1 }
                }
            }
            let longest = max(oldChars.count, newChars.count)
            let similarity = Double(matched) / Double(max(1, longest))
            let accept = matchedVisible > 0 && similarity >= 0.5 && longest <= 80
            if accept {
                for op in charOps {
                    switch op {
                    case let .equal(a, b): result.mapping[oldStart + a] = newStart + b
                    case let .delete(a): result.removed.append(oldStart + a)
                    case let .insert(b): result.inserted.append(newStart + b)
                    }
                }
            } else {
                removedTokens.append(contentsOf: pendingDeletes)
                insertedTokens.append(contentsOf: pendingInserts)
            }
        }

        for op in ops {
            switch op {
            case let .equal(a, b):
                flushBlock()
                let ta = oldTokens[a], tb = newTokens[b]
                for k in 0 ..< ta.length { result.mapping[ta.start + k] = tb.start + k }
            case let .delete(a):
                pendingDeletes.append(a)
            case let .insert(b):
                pendingInserts.append(b)
            }
        }
        flushBlock()

        // Pair identical words that changed position into moves.
        var availableInserts = insertedTokens
        var unmatchedRemoved: [Int] = []
        for r in removedTokens {
            let token = oldTokens[r]
            let movable = (token.kind == .word && token.length >= 2) || (token.kind == .symbol && token.text.count == 1 && isEmoji(Character(token.text)))
            if movable, let idx = availableInserts.firstIndex(where: { newTokens[$0].text == token.text }) {
                let target = newTokens[availableInserts[idx]]
                availableInserts.remove(at: idx)
                for k in 0 ..< token.length {
                    result.mapping[token.start + k] = target.start + k
                    result.moved.insert(token.start + k)
                }
            } else {
                unmatchedRemoved.append(r)
            }
        }
        for r in unmatchedRemoved {
            let token = oldTokens[r]
            for k in 0 ..< token.length { result.removed.append(token.start + k) }
        }
        for b in availableInserts {
            let token = newTokens[b]
            for k in 0 ..< token.length { result.inserted.append(token.start + k) }
        }
        result.removed.sort()
        result.inserted.sort()

        // A near-total rewrite: a few stray letters "surviving" and flying across the bubble reads
        // as noise. Below 25% visible overlap, treat it as a full replacement and let it melt.
        let oldVisible = old.filter { !$0.isWhitespace }.count
        let newVisible = new.filter { !$0.isWhitespace }.count
        let keptVisible = result.mapping.keys.filter { $0 < old.count && !old[$0].isWhitespace }.count
        if keptVisible > 0, Double(keptVisible) < 0.25 * Double(max(oldVisible, newVisible)) {
            var full = TextDiffResult()
            full.removed = Array(0 ..< old.count)
            full.inserted = Array(0 ..< new.count)
            return full
        }
        return result
    }
}
