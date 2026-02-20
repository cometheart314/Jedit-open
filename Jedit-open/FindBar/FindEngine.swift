//
//  FindEngine.swift
//  Jedit-open
//
//  検索/置換エンジン。NSRegularExpression ベースで正規表現・通常検索を統一的に処理する。
//

import Cocoa

// MARK: - Find Options

struct FindOptions {
    var caseSensitive: Bool = false
    var useRegex: Bool = false
    var wholeWord: Bool = false
    var wrapAround: Bool = true
}

// MARK: - Find Result

struct FindResult {
    var ranges: [NSRange]
    var currentIndex: Int

    var isEmpty: Bool { ranges.isEmpty }
    var count: Int { ranges.count }

    var currentRange: NSRange? {
        guard currentIndex >= 0, currentIndex < ranges.count else { return nil }
        return ranges[currentIndex]
    }

    static let empty = FindResult(ranges: [], currentIndex: -1)
}

// MARK: - Find Engine

class FindEngine {

    var searchText: String = ""
    var replaceText: String = ""
    var options: FindOptions = FindOptions()

    // MARK: - Find All Matches

    /// 全マッチ範囲を返す
    func findAllMatches(in text: String) -> [NSRange] {
        guard !searchText.isEmpty else { return [] }

        let nsText = text as NSString

        if options.useRegex || options.wholeWord {
            return findAllWithRegex(in: nsText)
        } else {
            return findAllWithString(in: nsText)
        }
    }

    // MARK: - Find Next / Previous

    /// from の位置から前方検索。wrapAround 対応。
    func findNext(in text: String, from location: Int) -> NSRange? {
        guard !searchText.isEmpty else { return nil }

        let nsText = text as NSString
        let textLength = nsText.length

        // location 以降で検索
        if let range = findFirst(in: nsText, searchRange: NSRange(location: location, length: textLength - location)) {
            return range
        }

        // ラップアラウンド: 先頭から location まで検索
        if options.wrapAround, location > 0 {
            return findFirst(in: nsText, searchRange: NSRange(location: 0, length: min(location + (searchText as NSString).length, textLength)))
        }

        return nil
    }

    /// from の位置から後方検索。wrapAround 対応。
    func findPrevious(in text: String, from location: Int) -> NSRange? {
        guard !searchText.isEmpty else { return nil }

        let nsText = text as NSString
        let textLength = nsText.length

        // location より前で最後のマッチを探す
        if location > 0 {
            if let range = findLast(in: nsText, searchRange: NSRange(location: 0, length: location)) {
                return range
            }
        }

        // ラップアラウンド: location 以降の最後のマッチ
        if options.wrapAround, location < textLength {
            return findLast(in: nsText, searchRange: NSRange(location: location, length: textLength - location))
        }

        return nil
    }

    // MARK: - Replace

    /// 指定範囲のマッチを置換し、置換後の範囲を返す。
    /// textView 経由で Undo 対応。
    func replaceMatch(in textView: NSTextView, at range: NSRange) -> NSRange? {
        let textStorage = textView.textStorage!
        let replacement = computeReplacement(for: range, in: textStorage.string)

        // 置換前のカーソル位置を保存
        let savedSelection = textView.selectedRange()

        // カーソル復元を先に登録（Undo 時は LIFO なので最後に実行される）
        textView.undoManager?.registerUndo(withTarget: textView) { tv in
            tv.setSelectedRange(savedSelection)
            tv.scrollRangeToVisible(savedSelection)
        }

        textView.insertText(replacement, replacementRange: range)

        return NSRange(location: range.location, length: (replacement as NSString).length)
    }

    /// 全マッチを置換し、置換数を返す。textView 経由で Undo 対応。
    func replaceAll(in textView: NSTextView) -> Int {
        let text = textView.string
        let matches = findAllMatches(in: text)
        guard !matches.isEmpty else { return 0 }

        // 置換前のカーソル位置を保存
        let savedSelection = textView.selectedRange()

        // 全置換を一つの Undo グループにまとめる
        textView.undoManager?.beginUndoGrouping()

        // カーソル復元を最初に登録（Undo 時は LIFO なので最後に実行される）
        textView.undoManager?.registerUndo(withTarget: textView) { tv in
            tv.setSelectedRange(savedSelection)
            tv.scrollRangeToVisible(savedSelection)
        }

        // 後方から置換してインデックスずれを防止
        for range in matches.reversed() {
            let replacement = computeReplacement(for: range, in: textView.string)
            textView.insertText(replacement, replacementRange: range)
        }

        textView.undoManager?.endUndoGrouping()

        return matches.count
    }

    // MARK: - Regex Validation

    /// 現在の searchText が有効な正規表現かチェック
    func validateRegex() -> Bool {
        guard options.useRegex else { return true }
        let pattern = options.wholeWord ? "\\b\(searchText)\\b" : searchText
        do {
            _ = try NSRegularExpression(pattern: pattern, options: regexOptions())
            return true
        } catch {
            return false
        }
    }

    /// 正規表現エラーメッセージを返す（エラーがなければ nil）
    func regexError() -> String? {
        guard options.useRegex else { return nil }
        let pattern = options.wholeWord ? "\\b\(searchText)\\b" : searchText
        do {
            _ = try NSRegularExpression(pattern: pattern, options: regexOptions())
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Private: String Search

    private func findAllWithString(in text: NSString) -> [NSRange] {
        var results: [NSRange] = []
        var searchRange = NSRange(location: 0, length: text.length)

        let compareOptions = stringCompareOptions()

        while searchRange.location < text.length {
            let foundRange = text.range(of: searchText, options: compareOptions, range: searchRange)
            if foundRange.location == NSNotFound { break }

            results.append(foundRange)
            let nextStart = foundRange.location + max(foundRange.length, 1)
            if nextStart >= text.length { break }
            searchRange = NSRange(location: nextStart, length: text.length - nextStart)
        }

        return results
    }

    private func findFirst(in text: NSString, searchRange: NSRange) -> NSRange? {
        guard searchRange.location + searchRange.length <= text.length,
              searchRange.length >= 0 else { return nil }

        if options.useRegex || options.wholeWord {
            guard let regex = buildRegex() else { return nil }
            let match = regex.firstMatch(in: text as String, range: searchRange)
            return match?.range
        } else {
            let foundRange = text.range(of: searchText, options: stringCompareOptions(), range: searchRange)
            return foundRange.location == NSNotFound ? nil : foundRange
        }
    }

    private func findLast(in text: NSString, searchRange: NSRange) -> NSRange? {
        guard searchRange.location + searchRange.length <= text.length,
              searchRange.length >= 0 else { return nil }

        if options.useRegex || options.wholeWord {
            guard let regex = buildRegex() else { return nil }
            var lastMatch: NSRange?
            regex.enumerateMatches(in: text as String, range: searchRange) { result, _, _ in
                if let range = result?.range {
                    lastMatch = range
                }
            }
            return lastMatch
        } else {
            // .backwards オプションで末尾から検索
            let foundRange = text.range(of: searchText, options: stringCompareOptions().union(.backwards), range: searchRange)
            return foundRange.location == NSNotFound ? nil : foundRange
        }
    }

    // MARK: - Private: Regex Search

    private func findAllWithRegex(in text: NSString) -> [NSRange] {
        guard let regex = buildRegex() else { return [] }

        var results: [NSRange] = []
        let fullRange = NSRange(location: 0, length: text.length)

        regex.enumerateMatches(in: text as String, range: fullRange) { result, _, _ in
            if let range = result?.range {
                results.append(range)
            }
        }

        return results
    }

    // MARK: - Private: Replacement

    private func computeReplacement(for range: NSRange, in text: String) -> String {
        if options.useRegex {
            return computeRegexReplacement(for: range, in: text)
        } else {
            return replaceText
        }
    }

    private func computeRegexReplacement(for range: NSRange, in text: String) -> String {
        guard let regex = buildRegex() else { return replaceText }

        let nsText = text as NSString
        let matched = nsText.substring(with: range)
        let matchedRange = NSRange(location: 0, length: (matched as NSString).length)

        guard let match = regex.firstMatch(in: matched, range: matchedRange) else {
            return replaceText
        }

        return regex.replacementString(for: match, in: matched, offset: 0, template: replaceText)
    }

    // MARK: - Private: Helpers

    private func buildRegex() -> NSRegularExpression? {
        let pattern: String
        if options.wholeWord {
            if options.useRegex {
                pattern = "\\b(?:\(searchText))\\b"
            } else {
                pattern = "\\b\(NSRegularExpression.escapedPattern(for: searchText))\\b"
            }
        } else {
            if options.useRegex {
                pattern = searchText
            } else {
                pattern = NSRegularExpression.escapedPattern(for: searchText)
            }
        }

        return try? NSRegularExpression(pattern: pattern, options: regexOptions())
    }

    private func stringCompareOptions() -> NSString.CompareOptions {
        var opts: NSString.CompareOptions = []
        if !options.caseSensitive { opts.insert(.caseInsensitive) }
        return opts
    }

    private func regexOptions() -> NSRegularExpression.Options {
        var opts: NSRegularExpression.Options = []
        if !options.caseSensitive { opts.insert(.caseInsensitive) }
        return opts
    }
}
