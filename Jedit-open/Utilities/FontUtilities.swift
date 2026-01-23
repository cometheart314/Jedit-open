//
//  FontUtilities.swift
//  Jedit-open
//
//  Created by Claude on 2026/01/22.
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
