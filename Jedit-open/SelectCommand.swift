//
//  SelectCommand.swift
//  Jedit-open
//
//  AppleScript select command handler.
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

/// AppleScript "select" コマンドの実装
/// select in document 1 location 0 length 5
/// select paragraph 10 in document 1
/// select word 5 in document 1
/// select character 3 in document 1
/// select paragraph 3 through paragraph 7 in document 1
/// tell document 1 / select location 0 length 5
/// tell document 1 / select paragraph 10
class SelectCommand: NSScriptCommand {

    override func performDefaultImplementation() -> Any? {
        let args = evaluatedArguments

        guard let document = resolveDocument() else { return nil }

        let textStorage = document.textStorage
        let text = textStorage.string as NSString

        // paragraph / word / character パラメータの処理
        if let paragraphNum = args?["selParagraph"] as? Int {
            guard let range = SelectCommand.paragraphRange(paragraphNum, in: text) else {
                scriptErrorNumber = -1728
                scriptErrorString = "Paragraph \(paragraphNum) not found."
                return nil
            }
            if let throughNum = args?["selThroughParagraph"] as? Int {
                guard let throughRange = SelectCommand.paragraphRange(throughNum, in: text) else {
                    scriptErrorNumber = -1728
                    scriptErrorString = "Paragraph \(throughNum) not found."
                    return nil
                }
                let unionRange = NSUnionRange(range, throughRange)
                document.setSelectionRange(unionRange)
            } else {
                document.setSelectionRange(range)
            }
            return nil
        }

        if let wordNum = args?["selWord"] as? Int {
            guard let range = SelectCommand.wordRange(wordNum, in: text) else {
                scriptErrorNumber = -1728
                scriptErrorString = "Word \(wordNum) not found."
                return nil
            }
            if let throughNum = args?["selThroughWord"] as? Int {
                guard let throughRange = SelectCommand.wordRange(throughNum, in: text) else {
                    scriptErrorNumber = -1728
                    scriptErrorString = "Word \(throughNum) not found."
                    return nil
                }
                let unionRange = NSUnionRange(range, throughRange)
                document.setSelectionRange(unionRange)
            } else {
                document.setSelectionRange(range)
            }
            return nil
        }

        if let charNum = args?["selCharacter"] as? Int {
            guard let range = SelectCommand.characterRange(charNum, in: text) else {
                scriptErrorNumber = -1728
                scriptErrorString = "Character \(charNum) not found."
                return nil
            }
            if let throughNum = args?["selThroughCharacter"] as? Int {
                guard let throughRange = SelectCommand.characterRange(throughNum, in: text) else {
                    scriptErrorNumber = -1728
                    scriptErrorString = "Character \(throughNum) not found."
                    return nil
                }
                let unionRange = NSUnionRange(range, throughRange)
                document.setSelectionRange(unionRange)
            } else {
                document.setSelectionRange(range)
            }
            return nil
        }

        // location パラメータによる選択（従来の動作）
        guard let loc = args?["selLocation"] as? Int else {
            scriptErrorNumber = -1708
            scriptErrorString = "Missing location or paragraph/word/character parameter."
            return nil
        }

        let len = args?["selLength"] as? Int ?? 0
        let maxLen = textStorage.length
        let safeLoc = min(max(loc, 0), maxLen)
        let safeLen = min(max(len, 0), maxLen - safeLoc)
        let range = NSRange(location: safeLoc, length: safeLen)

        document.setSelectionRange(range)

        return nil
    }

    // MARK: - Text Element Range Helpers

    /// N番目のパラグラフ（1-based）の NSRange を返す
    static func paragraphRange(_ n: Int, in text: NSString) -> NSRange? {
        guard n >= 1 else { return nil }
        var count = 0
        var searchStart = 0
        while searchStart <= text.length {
            let lineRange = text.paragraphRange(for: NSRange(location: searchStart, length: 0))
            count += 1
            if count == n {
                return lineRange
            }
            let nextStart = NSMaxRange(lineRange)
            if nextStart == searchStart { break }   // 無限ループ防止
            searchStart = nextStart
        }
        return nil
    }

    /// N番目のワード（1-based）の NSRange を返す
    static func wordRange(_ n: Int, in text: NSString) -> NSRange? {
        guard n >= 1, text.length > 0 else { return nil }
        var count = 0
        var pos = 0
        while pos < text.length {
            let wordRange = text.range(of: "\\S+", options: .regularExpression,
                                       range: NSRange(location: pos, length: text.length - pos))
            if wordRange.location == NSNotFound { break }
            count += 1
            if count == n {
                return wordRange
            }
            pos = NSMaxRange(wordRange)
        }
        return nil
    }

    /// N番目のキャラクタ（1-based）の NSRange を返す
    static func characterRange(_ n: Int, in text: NSString) -> NSRange? {
        guard n >= 1, n <= text.length else { return nil }
        // composed character sequence（結合文字、サロゲートペア等）に対応
        let range = text.rangeOfComposedCharacterSequence(at: n - 1)
        return range
    }
}
