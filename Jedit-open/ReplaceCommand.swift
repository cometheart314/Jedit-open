//
//  ReplaceCommand.swift
//  Jedit-open
//
//  AppleScript replace command handler.
//

//
//  This file is part of Jedit-open.
//  Copyright (C) 2025 Satoshi Matsumoto
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
//

import Cocoa

/// AppleScript "replace" コマンドの実装
/// replace for "text" by "replacement" in document 1 [case sensitive true] [using regular expression true] [replacing all true]
class ReplaceCommand: NSScriptCommand {

    /// 置換の本体ロジック。コマンドハンドラ・responds-to ハンドラの両方から呼ばれる。
    static func performReplace(document: Document, args: [String: Any]?) -> Any? {
        guard let searchText = args?["forText"] as? String else { return NSNumber(value: 0) }
        guard let replacementText = args?["byText"] as? String else { return NSNumber(value: 0) }

        let caseSensitive = args?["caseSensitive"] as? Bool ?? false
        let useRegex = args?["usingRegularExpression"] as? Bool ?? false
        let replaceAll = args?["replacingAll"] as? Bool ?? false

        let textStorage = document.textStorage
        let text = textStorage.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)

        var options: NSString.CompareOptions = []
        if !caseSensitive { options.insert(.caseInsensitive) }
        if useRegex { options.insert(.regularExpression) }

        // 全出現箇所を収集
        var ranges: [NSRange] = []
        var searchRange = fullRange
        while searchRange.location < text.length {
            let foundRange = text.range(of: searchText, options: options, range: searchRange)
            if foundRange.location == NSNotFound { break }
            ranges.append(foundRange)
            if !replaceAll { break }
            let nextStart = foundRange.location + max(foundRange.length, 1)
            if nextStart >= text.length { break }
            searchRange = NSRange(location: nextStart, length: text.length - nextStart)
        }

        if ranges.isEmpty { return NSNumber(value: 0) }

        // 後方から置換（インデックスずれ防止）
        textStorage.beginEditing()
        for range in ranges.reversed() {
            if useRegex {
                let nsText = textStorage.string as NSString
                let matched = nsText.substring(with: range)
                do {
                    var regexOptions: NSRegularExpression.Options = []
                    if !caseSensitive { regexOptions.insert(.caseInsensitive) }
                    let regex = try NSRegularExpression(pattern: searchText, options: regexOptions)
                    if let match = regex.firstMatch(in: matched, range: NSRange(location: 0, length: (matched as NSString).length)) {
                        let replacement = regex.replacementString(for: match, in: matched, offset: 0, template: replacementText)
                        textStorage.replaceCharacters(in: range, with: replacement)
                    } else {
                        textStorage.replaceCharacters(in: range, with: replacementText)
                    }
                } catch {
                    textStorage.replaceCharacters(in: range, with: replacementText)
                }
            } else {
                textStorage.replaceCharacters(in: range, with: replacementText)
            }
        }
        textStorage.endEditing()

        return NSNumber(value: ranges.count)
    }

    override func performDefaultImplementation() -> Any? {
        let args = evaluatedArguments

        guard let _ = args?["forText"] as? String else {
            scriptErrorNumber = -1708
            scriptErrorString = "Missing search text."
            return nil
        }
        guard let _ = args?["byText"] as? String else {
            scriptErrorNumber = -1708
            scriptErrorString = "Missing replacement text."
            return nil
        }

        guard let document = resolveDocument() else { return nil }

        return ReplaceCommand.performReplace(document: document, args: args)
    }
}
