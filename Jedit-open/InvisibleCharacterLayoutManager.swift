//
//  InvisibleCharacterLayoutManager.swift
//  Jedit-open
//
//  Created by Claude on 2026/01/08.
//

import Cocoa

/// 不可視文字の表示オプション
struct InvisibleCharacterOptions: OptionSet {
    let rawValue: Int

    static let returnCharacter = InvisibleCharacterOptions(rawValue: 1 << 0)
    static let tabCharacter = InvisibleCharacterOptions(rawValue: 1 << 1)
    static let spaceCharacter = InvisibleCharacterOptions(rawValue: 1 << 2)
    static let fullWidthSpaceCharacter = InvisibleCharacterOptions(rawValue: 1 << 3)
    static let lineSeparator = InvisibleCharacterOptions(rawValue: 1 << 4)
    static let nonBreakingSpace = InvisibleCharacterOptions(rawValue: 1 << 5)
    static let pageBreak = InvisibleCharacterOptions(rawValue: 1 << 6)
    static let verticalTab = InvisibleCharacterOptions(rawValue: 1 << 7)

    static let all: InvisibleCharacterOptions = [.returnCharacter, .tabCharacter, .spaceCharacter, .fullWidthSpaceCharacter, .lineSeparator, .nonBreakingSpace, .pageBreak, .verticalTab]
    static let none: InvisibleCharacterOptions = []
}

/// 不可視文字を描画するカスタムLayoutManager
class InvisibleCharacterLayoutManager: NSLayoutManager {

    // MARK: - Properties

    /// 表示する不可視文字のオプション
    var invisibleCharacterOptions: InvisibleCharacterOptions = .none {
        didSet {
            if oldValue != invisibleCharacterOptions {
                invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textStorage?.length ?? 0))
            }
        }
    }

    /// 不可視文字の色
    var invisibleCharacterColor: NSColor = NSColor.tertiaryLabelColor

    // MARK: - 不可視文字のシンボル

    private let returnSymbol = "↩"           // U+21A9 改行
    private let tabSymbol = "▸"              // U+25B8 右向き三角（タブ）
    private let spaceSymbol = "·"            // U+00B7 中点（半角スペース）
    private let fullWidthSpaceSymbol = "◯"   // U+25EF 大きな丸（全角スペース）
    private let lineSeparatorSymbol = "↓"    // U+2193 下矢印（行区切り）
    private let nonBreakingSpaceSymbol = "°" // U+00B0 度記号（非改行スペース）
    private let pageBreakSymbol = "╍"        // U+254D 破線（改ページ）
    private let verticalTabSymbol = "⇣"      // U+21E3 下矢印（垂直タブ）

    // MARK: - Drawing

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        // まず通常の描画を行う
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)

        // 不可視文字の描画が無効なら終了
        guard invisibleCharacterOptions != .none,
              let textStorage = textStorage else { return }

        let string = textStorage.string as NSString
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        // 文字範囲をスキャン
        for charIndex in charRange.location..<(charRange.location + charRange.length) {
            guard charIndex < string.length else { break }

            let char = string.character(at: charIndex)
            var symbol: String? = nil

            // 文字種に応じたシンボルを選択
            switch char {
            case 0x0A, 0x0D: // 改行 (LF, CR)
                if invisibleCharacterOptions.contains(.returnCharacter) {
                    symbol = returnSymbol
                }
            case 0x09: // タブ
                if invisibleCharacterOptions.contains(.tabCharacter) {
                    symbol = tabSymbol
                }
            case 0x20: // 半角スペース
                if invisibleCharacterOptions.contains(.spaceCharacter) {
                    symbol = spaceSymbol
                }
            case 0x3000: // 全角スペース
                if invisibleCharacterOptions.contains(.fullWidthSpaceCharacter) {
                    symbol = fullWidthSpaceSymbol
                }
            case 0x2028: // Line Separator
                if invisibleCharacterOptions.contains(.lineSeparator) {
                    symbol = lineSeparatorSymbol
                }
            case 0x00A0: // Non-breaking Space
                if invisibleCharacterOptions.contains(.nonBreakingSpace) {
                    symbol = nonBreakingSpaceSymbol
                }
            case 0x0C: // Form Feed / Page Break
                if invisibleCharacterOptions.contains(.pageBreak) {
                    symbol = pageBreakSymbol
                }
            case 0x0B: // Vertical Tab
                if invisibleCharacterOptions.contains(.verticalTab) {
                    symbol = verticalTabSymbol
                }
            default:
                break
            }

            // シンボルを描画
            if let symbol = symbol {
                let glyphIndex = glyphIndexForCharacter(at: charIndex)

                // グリフの位置を取得
                let location = self.location(forGlyphAt: glyphIndex)
                let lineRect = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)

                // この位置のフォントサイズを取得
                var fontSize: CGFloat = 12.0
                if charIndex < textStorage.length {
                    if let font = textStorage.attribute(.font, at: charIndex, effectiveRange: nil) as? NSFont {
                        fontSize = font.pointSize
                    }
                }

                // 不可視文字用のフォントと属性
                let invisibleFont = NSFont.systemFont(ofSize: fontSize * 0.7)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: invisibleFont,
                    .foregroundColor: invisibleCharacterColor
                ]

                // シンボルのサイズを取得
                let symbolSize = (symbol as NSString).size(withAttributes: attributes)

                // 描画位置を計算（行の中央に配置）
                var baseX = origin.x + lineRect.origin.x + location.x
                let baseY = origin.y + lineRect.origin.y

                // 全角スペースの場合は中央に配置するため右にオフセット
                if char == 0x3000 {
                    // 全角スペースの幅を取得して中央に配置
                    let fullWidthSpaceWidth = fontSize * 1.0  // 全角スペースは約1em幅
                    baseX += (fullWidthSpaceWidth - symbolSize.width) / 2
                }

                // 垂直位置を計算
                let verticalOffset: CGFloat
                if char == 0x0A || char == 0x0D {
                    // 改行マークはベースライン付近に配置（下寄り）
                    verticalOffset = lineRect.height - symbolSize.height - (fontSize * 0.1)
                } else {
                    // その他は行の高さの中央にシンボルを配置
                    verticalOffset = (lineRect.height - symbolSize.height) / 2
                }

                let point = NSPoint(
                    x: baseX,
                    y: baseY + verticalOffset
                )

                // シンボルを描画
                (symbol as NSString).draw(at: point, withAttributes: attributes)
            }
        }
    }
}
