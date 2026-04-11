//
//  JeditTextView+Indent.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/26.
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

extension JeditTextView {

    // MARK: - Tab Handling / Indent

    /// インデントに使う文字列を返す（スペースモードならスペース、それ以外はタブ）
    func indentString(for presetData: NewDocData) -> String {
        if presetData.format.tabWidthUnit == .spaces {
            let spaceCount = Int(presetData.format.tabWidthPoints)
            return String(repeating: " ", count: max(1, spaceCount))
        } else {
            return "\t"
        }
    }

    /// 選択範囲が複数行にまたがるかを判定
    func selectionSpansMultipleLines() -> Bool {
        guard let textStorage = textStorage else { return false }
        let range = selectedRange()
        guard range.length > 0 else { return false }
        let text = textStorage.string as NSString
        let lineRange = text.lineRange(for: range)
        // 選択範囲内に改行が含まれていれば複数行
        let selectedText = text.substring(with: range)
        return selectedText.contains("\n") || selectedText.contains("\r")
            || lineRange.length > range.length
    }

    /// タブキーが押されたときの処理
    /// 複数行選択中はインデント、それ以外はタブ/スペース挿入
    override func insertTab(_ sender: Any?) {
        // 複数行選択中の場合はインデント動作
        if selectionSpansMultipleLines() {
            shiftRight(sender)
            return
        }

        guard let windowController = window?.windowController as? EditorWindowController,
              let presetData = windowController.textDocument?.presetData else {
            super.insertTab(sender)
            return
        }

        let indent = indentString(for: presetData)
        insertText(indent, replacementRange: selectedRange())
    }

    /// Shift+Tab が押されたときの処理
    /// 複数行選択中はアンインデント
    override func insertBacktab(_ sender: Any?) {
        shiftLeft(sender)
    }

    /// 選択行をインデント（Shift Right / Cmd+]）
    @IBAction func shiftRight(_ sender: Any?) {
        guard let textStorage = textStorage else { return }
        let windowController = window?.windowController as? EditorWindowController
        let presetData = windowController?.textDocument?.presetData

        let indent: String
        if let presetData = presetData {
            indent = indentString(for: presetData)
        } else {
            indent = "\t"
        }

        let text = textStorage.string as NSString
        let range = selectedRange()
        let lineRange = text.lineRange(for: range)

        // 対象行の各行頭にインデント文字列を挿入
        var newText = ""
        var insertedCount = 0
        text.enumerateSubstrings(in: lineRange, options: .byLines) { substring, substringRange, _, _ in
            guard let substring = substring else { return }
            newText += indent + substring
            insertedCount += 1
            // 元のテキストで行末に改行があれば追加
            let afterSubstring = substringRange.location + substringRange.length
            if afterSubstring < lineRange.location + lineRange.length {
                let nlRange = NSRange(location: afterSubstring, length: 1)
                newText += text.substring(with: nlRange)
            }
        }

        // 最後の改行が lineRange にあるが enumerateSubstrings で処理されない場合を考慮
        let lastChar = lineRange.location + lineRange.length - 1
        if lastChar >= 0 && lastChar < text.length {
            let ch = text.character(at: lastChar)
            if (ch == 0x0A || ch == 0x0D) && !newText.hasSuffix("\n") && !newText.hasSuffix("\r") {
                newText += String(Character(UnicodeScalar(ch)!))
            }
        }

        // Undo 対応で置換
        if shouldChangeText(in: lineRange, replacementString: newText) {
            textStorage.replaceCharacters(in: lineRange, with: newText)
            didChangeText()

            // 選択範囲を更新（インデントされた範囲全体を選択）
            let indentLen = (indent as NSString).length
            let newStart = range.location + indentLen
            let newLength = range.length + indentLen * (insertedCount - 1)
            setSelectedRange(NSRange(location: newStart, length: max(0, newLength)))
        }
    }

    /// 選択行をアンインデント（Shift Left / Cmd+[）
    @IBAction func shiftLeft(_ sender: Any?) {
        guard let textStorage = textStorage else { return }
        let windowController = window?.windowController as? EditorWindowController
        let presetData = windowController?.textDocument?.presetData

        let indent: String
        if let presetData = presetData {
            indent = indentString(for: presetData)
        } else {
            indent = "\t"
        }

        let text = textStorage.string as NSString
        let range = selectedRange()
        let lineRange = text.lineRange(for: range)

        // 各行頭から先頭のインデント文字列を1レベル分除去
        var newText = ""
        var removedFromFirstLine = 0
        var totalRemoved = 0
        var isFirstLine = true

        text.enumerateSubstrings(in: lineRange, options: .byLines) { substring, substringRange, _, _ in
            guard let substring = substring else { return }
            var line = substring

            if indent == "\t" {
                // タブモード: 先頭のタブを1つ除去
                if line.hasPrefix("\t") {
                    line = String(line.dropFirst())
                    if isFirstLine { removedFromFirstLine = 1 }
                    totalRemoved += 1
                }
            } else {
                // スペースモード: 先頭のスペースをインデント幅分除去
                let indentLen = indent.count
                var removeCount = 0
                for ch in line {
                    if ch == " " && removeCount < indentLen {
                        removeCount += 1
                    } else {
                        break
                    }
                }
                if removeCount > 0 {
                    line = String(line.dropFirst(removeCount))
                    if isFirstLine { removedFromFirstLine = removeCount }
                    totalRemoved += removeCount
                }
            }

            isFirstLine = false
            newText += line

            // 行末の改行を追加
            let afterSubstring = substringRange.location + substringRange.length
            if afterSubstring < lineRange.location + lineRange.length {
                let nlRange = NSRange(location: afterSubstring, length: 1)
                newText += text.substring(with: nlRange)
            }
        }

        // 末尾改行の処理
        let lastChar = lineRange.location + lineRange.length - 1
        if lastChar >= 0 && lastChar < text.length {
            let ch = text.character(at: lastChar)
            if (ch == 0x0A || ch == 0x0D) && !newText.hasSuffix("\n") && !newText.hasSuffix("\r") {
                newText += String(Character(UnicodeScalar(ch)!))
            }
        }

        if totalRemoved == 0 { return }

        // Undo 対応で置換
        if shouldChangeText(in: lineRange, replacementString: newText) {
            textStorage.replaceCharacters(in: lineRange, with: newText)
            didChangeText()

            // 選択範囲を更新
            let newStart = max(lineRange.location, range.location - removedFromFirstLine)
            let newLength = max(0, range.length - (totalRemoved - removedFromFirstLine))
            setSelectedRange(NSRange(location: newStart, length: newLength))
        }
    }

    // MARK: - Auto Indent

    /// 改行が挿入されたときの処理
    /// Shift+Return の場合は行セパレータ（U+2028）を挿入する。
    /// Auto Indent が有効な場合、現在の行の先頭の空白文字を新しい行にコピー
    /// プレーンテキストで Wrapped Line Indent が有効な場合、パラグラフスタイルも設定
    override func insertNewline(_ sender: Any?) {
        // Shift+Return の場合は行セパレータ（U+2028 Line Separator）を挿入
        if let event = NSApp.currentEvent, event.type == .keyDown,
           event.modifierFlags.contains(.shift) {
            insertLineBreak(sender)
            return
        }

        guard let windowController = window?.windowController as? EditorWindowController,
              let presetData = windowController.textDocument?.presetData,
              presetData.format.autoIndent else {
            // Auto Indent が無効な場合は通常の改行
            super.insertNewline(sender)
            return
        }

        // リッチテキストでリスト内にいる場合は super に委譲する
        // （NSTextView のデフォルト動作がリストマーカーの継続を処理する。
        //  insertText() を使うと typingAttributes が適用され NSTextList が失われるため）
        if !isPlainText, let textStorage = textStorage {
            let loc = selectedRange().location
            if loc > 0 && loc <= textStorage.length {
                let checkIndex = min(loc, textStorage.length - 1)
                if let style = textStorage.attribute(.paragraphStyle, at: checkIndex, effectiveRange: nil) as? NSParagraphStyle,
                   !style.textLists.isEmpty {
                    super.insertNewline(sender)
                    return
                }
            }
        }

        // 現在のカーソル位置を取得
        let currentRange = selectedRange()

        // 現在の行の先頭のインデント文字列を取得
        let indentString = getLeadingIndent(at: currentRange.location)

        // 改行 + インデント文字列を挿入
        let newlineWithIndent = "\n" + indentString
        insertText(newlineWithIndent, replacementRange: currentRange)

        // プレーンテキストの場合のみ Wrapped Line Indent のパラグラフスタイルを適用
        if isPlainText {
            applyWrappedLineIndentStyle(
                indentString: indentString,
                presetData: presetData
            )
        }
    }

    /// Wrapped Line Indent のパラグラフスタイルを新しい行に適用（プレーンテキスト専用）
    /// - Parameters:
    ///   - indentString: Auto Indent でコピーされた空白文字列
    ///   - presetData: ドキュメントのプリセットデータ
    func applyWrappedLineIndentStyle(indentString: String, presetData: NewDocData) {
        guard let textStorage = textStorage else { return }

        // 現在のカーソル位置（改行 + インデント挿入後）
        let cursorLocation = selectedRange().location

        // 新しい行の開始位置を計算（カーソル位置 - インデント文字列の長さ）
        let newLineStart = cursorLocation - indentString.count

        // 範囲チェック：空のテキストや範囲外の場合は何もしない
        guard newLineStart >= 0, textStorage.length > 0, newLineStart < textStorage.length else { return }

        // 新しい行のパラグラフ範囲を取得
        let paragraphRange = (textStorage.string as NSString).paragraphRange(for: NSRange(location: newLineStart, length: 0))

        // インデント文字列の幅をポイントで計算
        let indentWidth = calculateIndentWidth(indentString: indentString, presetData: presetData)

        // 現在のパラグラフスタイルを取得または新規作成
        let existingStyle = textStorage.attribute(.paragraphStyle, at: newLineStart, effectiveRange: nil) as? NSParagraphStyle
        let newStyle = (existingStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()

        if presetData.format.indentWrappedLines {
            // Wrapped Line Indent がオンの場合
            // firstLineHeadIndent = 0
            // headIndent = インデント幅 + wrappedLineIndent
            newStyle.firstLineHeadIndent = 0
            newStyle.headIndent = indentWidth + presetData.format.wrappedLineIndent
        } else {
            // Wrapped Line Indent がオフの場合
            // firstLineHeadIndent = 0
            // headIndent = 0
            newStyle.firstLineHeadIndent = 0
            newStyle.headIndent = 0
        }

        // パラグラフスタイルを適用
        textStorage.addAttribute(.paragraphStyle, value: newStyle, range: paragraphRange)
    }

    /// インデント文字列の幅をポイントで計算
    /// - Parameters:
    ///   - indentString: 空白文字列（タブ、半角スペース、全角スペース）
    ///   - presetData: ドキュメントのプリセットデータ
    /// - Returns: インデント幅（ポイント）
    func calculateIndentWidth(indentString: String, presetData: NewDocData) -> CGFloat {
        var totalWidth: CGFloat = 0

        // フォントを取得
        let font = NSFont(name: presetData.fontAndColors.baseFontName, size: presetData.fontAndColors.baseFontSize)
            ?? NSFont.systemFont(ofSize: presetData.fontAndColors.baseFontSize)

        // タブ幅を取得
        let tabWidth: CGFloat
        if presetData.format.tabWidthUnit == .spaces {
            // スペースモードの場合、スペースの幅 × スペース数
            let spaceWidth = " ".size(withAttributes: [.font: font]).width
            tabWidth = spaceWidth * presetData.format.tabWidthPoints
        } else {
            // ポイントモードの場合、直接ポイント数を使用
            tabWidth = presetData.format.tabWidthPoints
        }

        // 各文字の幅を計算
        for char in indentString {
            switch char {
            case "\t":
                // タブ文字
                totalWidth += tabWidth
            case " ":
                // 半角スペース
                let spaceWidth = " ".size(withAttributes: [.font: font]).width
                totalWidth += spaceWidth
            case "\u{3000}":
                // 全角スペース
                let fullWidthSpaceWidth = "　".size(withAttributes: [.font: font]).width
                totalWidth += fullWidthSpaceWidth
            default:
                break
            }
        }

        return totalWidth
    }

    /// 指定位置の行の先頭にある空白文字（タブ、半角スペース、全角スペース）を取得
    /// - Parameter location: テキスト内の位置
    /// - Returns: 行の先頭の空白文字列
    func getLeadingIndent(at location: Int) -> String {
        guard let textStorage = textStorage else { return "" }
        let text = textStorage.string as NSString

        // 現在位置から行の先頭を探す
        var lineStart = location
        while lineStart > 0 {
            let prevChar = text.character(at: lineStart - 1)
            // 改行文字（\n, \r）を見つけたらそこで止める
            if prevChar == 0x0A || prevChar == 0x0D {
                break
            }
            lineStart -= 1
        }

        // 行の先頭から空白文字を収集
        var indentString = ""
        var pos = lineStart
        while pos < text.length && pos < location {
            let char = text.character(at: pos)
            // タブ (0x09), 半角スペース (0x20), 全角スペース (0x3000)
            if char == 0x09 || char == 0x20 || char == 0x3000 {
                indentString.append(Character(UnicodeScalar(char)!))
                pos += 1
            } else {
                // 空白以外の文字が出現したら終了
                break
            }
        }

        return indentString
    }
}
