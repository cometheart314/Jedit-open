//
//  JeditTextView+BracketMatch.swift
//  Jedit-open
//
//  括弧マッチング機能。
//  - メニュー「編集 > 対応する括弧」: 選択中/カーソル位置の括弧から対の括弧までを選択
//  - 括弧文字を含むダブルクリック: 同様に対の括弧までを選択
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

    // MARK: - Bracket pairs

    /// 対応する括弧のペア (UTF-16 単一コードユニット表現)。
    /// すべて BMP 内にあるため unichar 1 つで表現可能。
    private static let bracketPairs: [(open: unichar, close: unichar)] = [
        (0x0028, 0x0029),   // ( )
        (0x005B, 0x005D),   // [ ]
        (0x007B, 0x007D),   // { }
        (0x300C, 0x300D),   // 「」
        (0x300E, 0x300F),   // 『』
        (0x3010, 0x3011),   // 【】
        (0x300A, 0x300B),   // 《》
        (0xFF08, 0xFF09),   // （）
        (0xFF3B, 0xFF3D),   // ［］
        (0xFF5B, 0xFF5D),   // ｛｝
    ]

    private static func openPairIndex(for char: unichar) -> Int? {
        return bracketPairs.firstIndex { $0.open == char }
    }

    private static func closePairIndex(for char: unichar) -> Int? {
        return bracketPairs.firstIndex { $0.close == char }
    }

    // MARK: - Search

    /// `openPos` の開き括弧から対応する閉じ括弧の位置を探す。見つからなければ nil。
    private static func findMatchingClose(in nsString: NSString, fromOpenAt openPos: Int) -> Int? {
        let openChar = nsString.character(at: openPos)
        guard let pairIdx = openPairIndex(for: openChar) else { return nil }
        let pair = bracketPairs[pairIdx]
        let length = nsString.length
        var depth = 1
        var i = openPos + 1
        while i < length {
            let c = nsString.character(at: i)
            if c == pair.open { depth += 1 }
            else if c == pair.close {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return nil
    }

    /// `closePos` の閉じ括弧から対応する開き括弧の位置を探す。
    private static func findMatchingOpen(in nsString: NSString, fromCloseAt closePos: Int) -> Int? {
        let closeChar = nsString.character(at: closePos)
        guard let pairIdx = closePairIndex(for: closeChar) else { return nil }
        let pair = bracketPairs[pairIdx]
        var depth = 1
        var i = closePos - 1
        while i >= 0 {
            let c = nsString.character(at: i)
            if c == pair.close { depth += 1 }
            else if c == pair.open {
                depth -= 1
                if depth == 0 { return i }
            }
            i -= 1
        }
        return nil
    }

    /// カーソル位置 (cursorPos) を含む最小の括弧ペアを探す。
    /// 見つかれば (open, close) の位置を返す。
    private static func findEnclosingBrackets(in nsString: NSString,
                                              cursorPos: Int) -> (open: Int, close: Int)? {
        // cursorPos の直前から左方向に走査し、未対応の閉じ括弧をスタックに積みながら
        // 未対応の開き括弧を見つける。見つかったらそこから右へ閉じ括弧を探す。
        var unmatchedClosePairs: [Int] = []   // pairIdx を積む
        var i = cursorPos - 1
        while i >= 0 {
            let c = nsString.character(at: i)
            if let pairIdx = closePairIndex(for: c) {
                unmatchedClosePairs.append(pairIdx)
            } else if let pairIdx = openPairIndex(for: c) {
                if let last = unmatchedClosePairs.last, last == pairIdx {
                    unmatchedClosePairs.removeLast()
                } else {
                    // 未対応の開き括弧を発見
                    if let closePos = findMatchingClose(in: nsString, fromOpenAt: i),
                       closePos >= cursorPos {
                        return (i, closePos)
                    }
                    return nil
                }
            }
            i -= 1
        }
        return nil
    }

    /// 指定位置を括弧として扱い、対のペアまでの範囲を返す。
    /// 該当位置が括弧文字でなければ nil。
    private static func bracketRangeStarting(at pos: Int, in nsString: NSString) -> NSRange? {
        guard pos >= 0, pos < nsString.length else { return nil }
        let c = nsString.character(at: pos)
        if openPairIndex(for: c) != nil {
            if let closePos = findMatchingClose(in: nsString, fromOpenAt: pos) {
                return NSRange(location: pos, length: closePos - pos + 1)
            }
        } else if closePairIndex(for: c) != nil {
            if let openPos = findMatchingOpen(in: nsString, fromCloseAt: pos) {
                return NSRange(location: openPos, length: pos - openPos + 1)
            }
        }
        return nil
    }

    // MARK: - Menu action

    /// 編集 > 対応する括弧 のアクション。
    /// 優先順位:
    ///   1. 選択範囲 / カーソル位置 / カーソル直前 の文字が括弧ならその対までを選択
    ///   2. カーソルが括弧で囲まれた領域内なら最小の囲みペアまでを選択
    ///   3. いずれも該当しなければビープ
    @IBAction func selectMatchingBrackets(_ sender: Any?) {
        guard let textStorage = textStorage else { return }
        let text = textStorage.string as NSString
        guard text.length > 0 else { NSSound.beep(); return }
        let selection = selectedRange()

        var result: NSRange? = nil

        // ケース A: 選択 / カーソル位置の文字が括弧
        result = Self.bracketRangeStarting(at: selection.location, in: text)

        // ケース B: カーソル直前の文字が括弧 (右隣にカーソルがある形)
        if result == nil, selection.location > 0 {
            result = Self.bracketRangeStarting(at: selection.location - 1, in: text)
        }

        // ケース C: カーソルが括弧の中
        if result == nil {
            if let pair = Self.findEnclosingBrackets(in: text, cursorPos: selection.location) {
                result = NSRange(location: pair.open, length: pair.close - pair.open + 1)
            }
        }

        if let range = result {
            setSelectedRange(range)
            scrollRangeToVisible(range)
        } else {
            NSSound.beep()
        }
    }

    // MARK: - Double-click handling

    /// 括弧文字をダブルクリックした場合に、対の括弧までを選択する。
    /// それ以外の場合は標準動作 (単語選択など) を返す。
    override func selectionRange(forProposedRange proposedCharRange: NSRange,
                                  granularity: NSSelectionGranularity) -> NSRange {
        let defaultResult = super.selectionRange(forProposedRange: proposedCharRange,
                                                  granularity: granularity)
        guard granularity == .selectByWord else { return defaultResult }
        guard let textStorage = textStorage else { return defaultResult }
        let text = textStorage.string as NSString
        // proposedCharRange.location の文字が括弧なら対までの範囲を返す。
        // (AppKit は括弧のような非単語文字をダブルクリックすると length=1 の
        //  range を提案してくるので、その位置を起点に対の括弧を探す)
        if let bracketRange = Self.bracketRangeStarting(at: proposedCharRange.location, in: text) {
            return bracketRange
        }
        return defaultResult
    }
}
