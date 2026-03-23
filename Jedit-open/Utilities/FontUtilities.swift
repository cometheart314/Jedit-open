//
//  FontUtilities.swift
//  Jedit-open
//
//  Created by Claude on 2026/01/22.
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
import CoreText

// MARK: - Font Utilities

/// フォントが日本語をサポートしているかどうかをチェック
/// - Parameter font: チェック対象のフォント
/// - Returns: 日本語をサポートしていればtrue
func fontSupportsJapanese(_ font: NSFont) -> Bool {
    let ctFont = font as CTFont

    // 代表的な日本語文字（ひらがな・カタカナ・漢字）
    let testChars: [UniChar] = ["あ", "ア", "漢"].map { UniChar($0.utf16.first!) }

    var glyphs = Array(repeating: CGGlyph(0), count: testChars.count)
    let ok = CTFontGetGlyphsForCharacters(ctFont, testChars, &glyphs, testChars.count)

    // ok=true でも glyph=0 が混じる場合があるので両方見る
    if !ok { return false }
    return glyphs.allSatisfy { $0 != 0 }
}

/// 日本語フォント用の全角文字幅を計算
/// - Parameter font: 計算対象のフォント
/// - Returns: 全角文字の幅（ポイント）
func fullWidthCharWidth(font: NSFont) -> CGFloat {
    // 日本語テキストエディタでは「全角文字」を基準にする
    // 代表的な全角文字で幅を計算（ひらがな・カタカナ・漢字は同じ幅）
    let sample = "あ"
    let attr: [NSAttributedString.Key: Any] = [.font: font]
    return (sample as NSString).size(withAttributes: attr).width
}

/// 半角文字幅を計算（英数字フォント用）
/// - Parameter font: 計算対象のフォント
/// - Returns: 半角文字の平均幅（ポイント）
func halfWidthCharWidth(font: NSFont) -> CGFloat {
    // 英数字の代表サンプル
    let sample = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    let attr: [NSAttributedString.Key: Any] = [.font: font]
    let width = (sample as NSString).size(withAttributes: attr).width
    return width / CGFloat(sample.count)
}

/// フォントの平均文字幅を計算
/// 日本語フォントの場合は全角文字幅、それ以外は半角文字幅を返す
/// - Parameter font: 計算対象のフォント
/// - Returns: 平均文字幅（ポイント）
func averageCharWidth(font: NSFont) -> CGFloat {
    if fontSupportsJapanese(font) {
        return fullWidthCharWidth(font: font)
    } else {
        return halfWidthCharWidth(font: font)
    }
}

/// 基本フォントから基本文字幅を計算
/// - Parameter basicFont: 基本フォント
/// - Returns: 基本文字幅（ポイント）
func basicCharWidth(from basicFont: NSFont) -> CGFloat {
    return averageCharWidth(font: basicFont)
}

// MARK: - Latin Character Detection

/// 文字がLatin文字（欧文）かどうかを判定
/// Basic Latin (U+0000-U+007F) と Latin-1 Supplement (U+0080-U+00FF) を含む
/// - Parameter character: 判定対象の文字
/// - Returns: Latin文字の場合true
func isLatinCharacter(_ character: Character) -> Bool {
    guard let scalar = character.unicodeScalars.first else { return false }
    // Basic Latin + Latin-1 Supplement
    return scalar.value <= 0x00FF
}

/// 文字列がすべてLatin文字かどうかを判定
/// - Parameter string: 判定対象の文字列
/// - Returns: すべてLatin文字の場合true、空文字列の場合もtrue
func isAllLatinCharacters(_ string: String) -> Bool {
    guard !string.isEmpty else { return true }
    return string.allSatisfy { isLatinCharacter($0) }
}

/// フォントが指定した文字をネイティブにサポートしているか（フォールバックなしで）判定
/// - Parameters:
///   - font: 判定対象のフォント
///   - character: テスト対象の文字
/// - Returns: フォントがその文字のグリフを持っていればtrue
func fontSupportsCharacter(_ font: NSFont, character: Character) -> Bool {
    let ctFont = font as CTFont
    let utf16 = Array(String(character).utf16)
    var glyphs = Array(repeating: CGGlyph(0), count: utf16.count)
    let hasGlyphs = CTFontGetGlyphsForCharacters(ctFont, utf16, &glyphs, utf16.count)
    return hasGlyphs && glyphs.allSatisfy { $0 != 0 }
}

/// フォントがLatin文字をサポートしているかどうかをチェック
/// - Parameter font: チェック対象のフォント
/// - Returns: Latin文字をサポートしていればtrue
func fontSupportsLatin(_ font: NSFont) -> Bool {
    // 代表的なLatin文字でテスト
    return fontSupportsCharacter(font, character: "A") &&
           fontSupportsCharacter(font, character: "a") &&
           fontSupportsCharacter(font, character: "0")
}

// MARK: - Custom Ruler Unit

/// カスタムルーラー単位名
extension NSRulerView.UnitName {
    static let characters = NSRulerView.UnitName("characters")
}

/// カスタム文字単位をNSRulerViewに登録
/// - Parameter charWidth: 1文字の幅（ポイント）
func registerCharacterRulerUnit(charWidth: CGFloat) {
    // 既存の登録を上書き（同じ名前で再登録可能）
    // stepUpCycle: 値は1.0より大きくなければならない（Appleの制約）
    // stepDownCycle: 値は1.0より小さくなければならない
    NSRulerView.registerUnit(
        withName: .characters,
        abbreviation: "ch",
        unitToPointsConversionFactor: charWidth,
        stepUpCycle: [2, 5, 10],   // 2, 5, 10文字ごとに目盛り
        stepDownCycle: [0.5, 0.2]  // 0.5文字、0.2文字の細分化
    )
}
