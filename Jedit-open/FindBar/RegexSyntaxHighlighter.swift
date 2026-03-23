//
//  RegexSyntaxHighlighter.swift
//  Jedit-open
//
//  正規表現パターンのシンタックスカラーリング。
//  検索フィールドに入力された正規表現をリアルタイムに色分けする。
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

class RegexSyntaxHighlighter {

    // MARK: - Colors

    /// ダークモード / ライトモード両対応
    static var metaCharColor: NSColor {
        NSColor(named: "regexMetaChar") ?? .systemBlue
    }
    static var quantifierColor: NSColor {
        NSColor(named: "regexQuantifier") ?? .systemPurple
    }
    static var groupColor: NSColor {
        NSColor(named: "regexGroup") ?? .systemGreen
    }
    static var charClassColor: NSColor {
        NSColor(named: "regexCharClass") ?? .systemOrange
    }
    static var anchorColor: NSColor {
        NSColor(named: "regexAnchor") ?? .systemRed
    }
    static var escapeColor: NSColor {
        NSColor(named: "regexEscape") ?? .systemGray
    }
    static var errorColor: NSColor {
        NSColor.systemRed.withAlphaComponent(0.15)
    }

    // MARK: - Highlight

    /// 正規表現パターンをシンタックスカラーリングした NSAttributedString を返す
    static func highlight(_ pattern: String, font: NSFont, defaultColor: NSColor) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: pattern,
            attributes: [
                .font: font,
                .foregroundColor: defaultColor
            ]
        )

        let chars = Array(pattern)
        let length = chars.count
        var i = 0

        while i < length {
            let ch = chars[i]

            if ch == "\\" && i + 1 < length {
                // エスケープシーケンス
                let next = chars[i + 1]
                let nsRange = nsRangeFor(pattern, charIndex: i, charLength: 2)

                if isMetaChar(next) {
                    // \d, \w, \s, \b, \B, \D, \W, \S, etc.
                    attributed.addAttribute(.foregroundColor, value: metaCharColor, range: nsRange)
                } else {
                    // \., \\, \(, etc. — エスケープ文字
                    attributed.addAttribute(.foregroundColor, value: escapeColor, range: nsRange)
                }
                i += 2
                continue
            }

            if ch == "(" || ch == ")" {
                // グループ
                let nsRange = nsRangeFor(pattern, charIndex: i, charLength: 1)
                attributed.addAttribute(.foregroundColor, value: groupColor, range: nsRange)

                // (?:, (?=, (?!, (?<= 等の非キャプチャグループ記法
                if ch == "(" && i + 1 < length && chars[i + 1] == "?" {
                    var end = i + 2
                    // ?:, ?=, ?!, ?<=, ?<! まで着色
                    while end < length && end < i + 4 {
                        let c = chars[end]
                        if c == ":" || c == "=" || c == "!" || c == "<" {
                            end += 1
                        } else {
                            break
                        }
                    }
                    let groupLen = end - i
                    let groupRange = nsRangeFor(pattern, charIndex: i, charLength: groupLen)
                    attributed.addAttribute(.foregroundColor, value: groupColor, range: groupRange)
                    i = end
                    continue
                }

                i += 1
                continue
            }

            if ch == "[" {
                // 文字クラス — 対応する ] まで
                let start = i
                i += 1
                // [^ の否定
                if i < length && chars[i] == "^" { i += 1 }
                // ] が最初の文字の場合はリテラル
                if i < length && chars[i] == "]" { i += 1 }

                while i < length && chars[i] != "]" {
                    if chars[i] == "\\" && i + 1 < length {
                        i += 2  // エスケープをスキップ
                    } else {
                        i += 1
                    }
                }
                if i < length { i += 1 } // ] を含む

                let nsRange = nsRangeFor(pattern, charIndex: start, charLength: i - start)
                attributed.addAttribute(.foregroundColor, value: charClassColor, range: nsRange)
                continue
            }

            if ch == "^" || ch == "$" {
                // アンカー
                let nsRange = nsRangeFor(pattern, charIndex: i, charLength: 1)
                attributed.addAttribute(.foregroundColor, value: anchorColor, range: nsRange)
                i += 1
                continue
            }

            if ch == "*" || ch == "+" || ch == "?" {
                // 量指定子
                var len = 1
                // *?, +?, ?? の lazy 修飾子
                if i + 1 < length && chars[i + 1] == "?" { len = 2 }
                // *+, ++, ?+ の possessive 修飾子
                if i + 1 < length && chars[i + 1] == "+" { len = 2 }

                let nsRange = nsRangeFor(pattern, charIndex: i, charLength: len)
                attributed.addAttribute(.foregroundColor, value: quantifierColor, range: nsRange)
                i += len
                continue
            }

            if ch == "{" {
                // {n}, {n,}, {n,m} 量指定子
                let start = i
                i += 1
                while i < length && chars[i] != "}" && i - start < 20 {
                    i += 1
                }
                if i < length && chars[i] == "}" {
                    i += 1
                    // Lazy/possessive
                    if i < length && (chars[i] == "?" || chars[i] == "+") { i += 1 }
                    let nsRange = nsRangeFor(pattern, charIndex: start, charLength: i - start)
                    attributed.addAttribute(.foregroundColor, value: quantifierColor, range: nsRange)
                } else {
                    // { が量指定子でなければリテラルとして戻す
                    i = start + 1
                }
                continue
            }

            if ch == "|" {
                // 選択演算子
                let nsRange = nsRangeFor(pattern, charIndex: i, charLength: 1)
                attributed.addAttribute(.foregroundColor, value: groupColor, range: nsRange)
                i += 1
                continue
            }

            if ch == "." {
                // 任意文字メタキャラクタ
                let nsRange = nsRangeFor(pattern, charIndex: i, charLength: 1)
                attributed.addAttribute(.foregroundColor, value: metaCharColor, range: nsRange)
                i += 1
                continue
            }

            // リテラル文字 — デフォルト色のまま
            i += 1
        }

        return attributed
    }

    // MARK: - Private

    /// Character 単位のインデックスから NSRange（UTF-16 ベース）を計算
    private static func nsRangeFor(_ string: String, charIndex: Int, charLength: Int) -> NSRange {
        let chars = Array(string)
        let startIdx = String(chars[0..<charIndex]).utf16.count
        let len = String(chars[charIndex..<min(charIndex + charLength, chars.count)]).utf16.count
        return NSRange(location: startIdx, length: len)
    }

    /// \d, \w, \s, \b 等のメタ文字判定
    private static func isMetaChar(_ ch: Character) -> Bool {
        let metaChars: Set<Character> = [
            "d", "D", "w", "W", "s", "S", "b", "B",
            "A", "Z", "z", "G",
            "n", "r", "t", "f", "v",
            "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
            "p", "P", "k", "K", "R", "X"
        ]
        return metaChars.contains(ch)
    }
}
