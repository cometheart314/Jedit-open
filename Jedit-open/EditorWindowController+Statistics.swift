//
//  EditorWindowController+Statistics.swift
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

extension EditorWindowController {

    // MARK: - Document Statistics Calculation

    /// 統計計算をスケジュール（短時間の連続イベントを合体）
    func scheduleStatisticsUpdate() {
        statisticsWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.calculateStatistics()
        }
        statisticsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    /// 統計情報を計算して Document に設定
    internal func calculateStatistics() {
        guard let document = textDocument else { return }

        // 最初のテキストビューを取得（Split時も常に最初のView）
        let primaryTextView: NSTextView?
        if displayMode == .page {
            primaryTextView = textViews1.first
        } else {
            primaryTextView = scrollView1?.documentView as? NSTextView
        }
        guard let textView = primaryTextView else { return }

        // メインスレッドで取得する情報
        let fullText = document.textStorage.string
        let textLength = document.textStorage.length
        let selectedRange: NSRange
        if let firstRange = textView.selectedRanges.first {
            selectedRange = firstRange.rangeValue
        } else {
            selectedRange = NSRange(location: 0, length: 0)
        }

        let showRows = (lineNumberMode != .none)
        let showPages = (displayMode == .page)

        // Rows 計算（メインスレッドで — layoutManager 依存）
        var totalRows = 0
        var locationRows = 0
        var selectionRows = 0
        if showRows, let layoutManager = textView.layoutManager {
            // 全体の表示行数 + 選択開始位置の行番号
            var lineCount = 0
            var index = 0
            let numberOfGlyphs = layoutManager.numberOfGlyphs
            let selGlyphStart = (selectedRange.location < textLength)
                ? layoutManager.glyphIndexForCharacter(at: selectedRange.location)
                : numberOfGlyphs
            var locationRowFound = false

            while index < numberOfGlyphs {
                var lineRange = NSRange()
                layoutManager.lineFragmentRect(forGlyphAt: index, effectiveRange: &lineRange, withoutAdditionalLayout: true)
                lineCount += 1

                // 選択開始位置の行番号を記録
                if !locationRowFound && NSMaxRange(lineRange) > selGlyphStart {
                    locationRows = lineCount
                    locationRowFound = true
                }

                index = NSMaxRange(lineRange)
            }
            if !locationRowFound {
                locationRows = lineCount + 1
            }
            // テキストが空でない場合、最後が改行なら+1
            if textLength > 0 {
                let lastChar = (fullText as NSString).character(at: textLength - 1)
                if lastChar == 0x0A || lastChar == 0x0D {
                    lineCount += 1
                }
            }
            totalRows = max(lineCount, 1)

            // 選択範囲の行数
            if selectedRange.length > 0 {
                let selEnd = min(selectedRange.location + selectedRange.length, textLength)
                let selGlyphEnd = (selEnd < textLength)
                    ? layoutManager.glyphIndexForCharacter(at: selEnd)
                    : numberOfGlyphs
                var selLineCount = 0
                var gi = selGlyphStart
                while gi < selGlyphEnd {
                    var lineRange = NSRange()
                    layoutManager.lineFragmentRect(forGlyphAt: gi, effectiveRange: &lineRange, withoutAdditionalLayout: false)
                    selLineCount += 1
                    gi = NSMaxRange(lineRange)
                }
                selectionRows = selLineCount
            }
        }

        // Pages 計算（メインスレッドで）
        var totalPages = 0
        var locationPages = 0
        var selectionPages = 0
        if showPages, let pagesView = pagesView1, let layoutManager = textView.layoutManager {
            totalPages = pagesView.numberOfPages

            let selGlyph = (selectedRange.location < textLength)
                ? layoutManager.glyphIndexForCharacter(at: selectedRange.location)
                : layoutManager.numberOfGlyphs

            // 選択開始位置のページ番号
            for (pageIndex, tc) in textContainers1.enumerated() {
                let tcGlyphRange = layoutManager.glyphRange(for: tc)
                if NSLocationInRange(selGlyph, tcGlyphRange) || selGlyph < tcGlyphRange.location {
                    locationPages = pageIndex + 1
                    break
                }
                locationPages = pageIndex + 1  // 最後のページの末尾を超えた場合
            }

            // 選択範囲のページ数
            if selectedRange.length > 0 {
                let endChar = min(selectedRange.location + selectedRange.length, textLength)
                let endGlyph = (endChar < textLength)
                    ? layoutManager.glyphIndexForCharacter(at: endChar)
                    : layoutManager.numberOfGlyphs

                var startPage = -1
                var endPage = -1
                for (pageIndex, tc) in textContainers1.enumerated() {
                    let tcGlyphRange = layoutManager.glyphRange(for: tc)
                    if startPage < 0 && NSLocationInRange(selGlyph, tcGlyphRange) {
                        startPage = pageIndex
                    }
                    if NSLocationInRange(max(endGlyph - 1, 0), tcGlyphRange) {
                        endPage = pageIndex
                        break
                    }
                }
                if startPage >= 0 && endPage >= 0 {
                    selectionPages = endPage - startPage + 1
                }
            }
        }

        // Char. Code（メインスレッドで）
        let charCodeLocation = selectedRange.location
        var charCode = ""
        if charCodeLocation < textLength {
            let charIndex = fullText.index(fullText.startIndex, offsetBy: charCodeLocation, limitedBy: fullText.endIndex) ?? fullText.endIndex
            if charIndex < fullText.endIndex {
                let char = fullText[charIndex]
                let scalars = char.unicodeScalars
                let codePoint = scalars.first!.value
                let displayChar = Self.displayName(for: codePoint) ?? "'\(char)'"
                let codeStr = codePoint < 0x10000
                    ? String(format: "\\u%04x", codePoint)
                    : String(format: "\\u%05x", codePoint)
                charCode = "\(displayChar) : \(codeStr)"
            }
        }

        // テキストのコピーをバックグラウンドに渡す
        let textCopy = fullText
        let selLoc = selectedRange.location
        let selLen = selectedRange.length
        let countHalfAs05 = DocumentInfoPanelController.shared.countHalfWidthAs05

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let nsText = textCopy as NSString

            // Whole document の統計（バックグラウンド）
            let totalCharacters = nsText.length
            let totalVisibleChars = Self.countVisibleChars(in: textCopy, countHalfAs05: countHalfAs05)
            let totalWords = Self.countWords(in: textCopy)
            let totalParagraphs = Self.countParagraphs(in: textCopy)

            // Selection 開始位置までの統計（location 計算、1始まり）
            var locationWords = 1
            var locationParagraphs = 1
            if selLoc > 0 {
                let prefixText = nsText.substring(to: selLoc)
                locationWords = Self.countWords(in: prefixText) + 1
                locationParagraphs = Self.countParagraphs(in: prefixText) + 1
            }

            // Selection の統計（バックグラウンド）
            var selCharacters = 0
            var selVisibleChars: Double = 0
            var selWords = 0
            var selParagraphs = 0
            if selLen > 0 {
                let safeRange = NSRange(location: selLoc, length: min(selLen, nsText.length - selLoc))
                let selectedText = nsText.substring(with: safeRange)
                selCharacters = (selectedText as NSString).length
                selVisibleChars = Self.countVisibleChars(in: selectedText, countHalfAs05: countHalfAs05)
                selWords = Self.countWords(in: selectedText)
                selParagraphs = Self.countParagraphs(in: selectedText)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self, let document = self.textDocument else { return }

                var stats = DocumentStatistics()
                stats.totalCharacters = totalCharacters
                stats.totalVisibleChars = totalVisibleChars
                stats.totalWords = totalWords
                stats.totalParagraphs = totalParagraphs
                stats.totalRows = totalRows
                stats.totalPages = totalPages
                stats.selectionLocation = selLoc
                stats.selectionLength = selLen
                stats.locationWords = locationWords
                stats.locationParagraphs = locationParagraphs
                stats.locationRows = locationRows
                stats.locationPages = locationPages
                stats.selectionCharacters = selCharacters
                stats.selectionVisibleChars = selVisibleChars
                stats.selectionWords = selWords
                stats.selectionParagraphs = selParagraphs
                stats.selectionRows = selectionRows
                stats.selectionPages = selectionPages
                stats.charCode = charCode
                stats.showRows = showRows
                stats.showPages = showPages

                document.statistics = stats
                NotificationCenter.default.post(
                    name: Document.statisticsDidChangeNotification,
                    object: document
                )

                // 執筆進捗ツールバーアイテムを更新
                self.updateWritingProgressDisplay()
            }
        }
    }

    // MARK: - Statistics Counting Helpers

    /// 可視文字数をカウント（制御文字＝タブ・改行を除く）
    internal static func countVisibleChars(in text: String, countHalfAs05: Bool) -> Double {
        var count: Double = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x09, 0x0A, 0x0D:  // tab, LF, CR
                break
            default:
                if countHalfAs05 && isHalfWidth(scalar) {
                    count += 0.5
                } else {
                    count += 1
                }
            }
        }
        return count
    }

    /// 半角文字かどうかを判定
    /// ASCII 印字可能文字（0x21-0x7E）および半角カナ（0xFF61-0xFF9F）を半角とみなす
    internal static func isHalfWidth(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        // ASCII 印字可能文字（スペースは除外、制御文字は既に除外済み）
        if v >= 0x21 && v <= 0x7E { return true }
        // 半角カナ
        if v >= 0xFF61 && v <= 0xFF9F { return true }
        return false
    }

    /// 単語数をカウント
    internal static func countWords(in text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { _, _, _, _ in
            count += 1
        }
        return count
    }

    /// 段落数をカウント（改行区切り）
    internal static func countParagraphs(in text: String) -> Int {
        if text.isEmpty { return 0 }
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byParagraphs) { _, _, _, _ in
            count += 1
        }
        return count
    }

    /// Unicode コードポイントが制御文字の場合に表示名を返す
    /// 表示可能な文字の場合は nil を返す
    internal static func displayName(for codePoint: UInt32) -> String? {
        switch codePoint {
        case 0x00: return "NUL"
        case 0x01: return "SOH"
        case 0x02: return "STX"
        case 0x03: return "ETX"
        case 0x04: return "EOT"
        case 0x05: return "ENQ"
        case 0x06: return "ACK"
        case 0x07: return "BEL"
        case 0x08: return "BS"
        case 0x09: return "TAB"
        case 0x0A: return "LF"
        case 0x0B: return "VT"
        case 0x0C: return "FF"
        case 0x0D: return "CR"
        case 0x0E: return "SO"
        case 0x0F: return "SI"
        case 0x10: return "DLE"
        case 0x11: return "DC1"
        case 0x12: return "DC2"
        case 0x13: return "DC3"
        case 0x14: return "DC4"
        case 0x15: return "NAK"
        case 0x16: return "SYN"
        case 0x17: return "ETB"
        case 0x18: return "CAN"
        case 0x19: return "EM"
        case 0x1A: return "SUB"
        case 0x1B: return "ESC"
        case 0x1C: return "FS"
        case 0x1D: return "GS"
        case 0x1E: return "RS"
        case 0x1F: return "US"
        case 0x20: return "SP"
        case 0x7F: return "DEL"
        case 0x85: return "NEL"
        case 0xA0: return "NBSP"
        case 0x2028: return "LS"     // Line Separator
        case 0x2029: return "PS"     // Paragraph Separator
        case 0x200B: return "ZWSP"   // Zero Width Space
        case 0x200C: return "ZWNJ"   // Zero Width Non-Joiner
        case 0x200D: return "ZWJ"    // Zero Width Joiner
        case 0xFEFF: return "BOM"    // Byte Order Mark
        case 0xFFFC: return "OBJ"    // Object Replacement Character
        case 0xFFFD: return "REP"    // Replacement Character
        default: return nil
        }
    }
}
