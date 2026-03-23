//
//  LineNumberDrawer.swift
//  Jedit-open
//
//  行番号描画の共通ユーティリティ
//  MultiplePageViewとPrintPageViewで共有される
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

/// 行番号描画の共通ユーティリティ
class LineNumberDrawer {

    // MARK: - Drawing Info

    /// 行番号描画に必要な情報
    struct DrawingInfo {
        let layoutManager: NSLayoutManager
        let lineNumberMode: LineNumberMode
        let isVerticalLayout: Bool
        let lineNumberFont: NSFont
        let lineNumberColor: NSColor
        let lineNumberRightMargin: CGFloat
        /// テキストコンテナのlineFragmentPaddingに対応するオフセット（印刷時は5.0）
        var textContainerPadding: CGFloat = 0.0
    }

    // MARK: - Constants

    static let defaultFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    static let defaultRightMargin: CGFloat = 8.0

    // MARK: - Drawing

    /// 行番号を描画
    /// - Parameters:
    ///   - info: 描画情報
    ///   - pageNumber: ページ番号（0始まり）
    ///   - pageRect: ページ全体の矩形
    ///   - docRect: ドキュメント領域の矩形（マージン内）
    static func drawLineNumbers(info: DrawingInfo, forPageNumber pageNumber: Int, in pageRect: NSRect, docRect: NSRect) {
        let layoutManager = info.layoutManager
        guard pageNumber < layoutManager.textContainers.count else { return }

        let textContainer = layoutManager.textContainers[pageNumber]
        let glyphRange = layoutManager.glyphRange(for: textContainer)

        guard glyphRange.length > 0 else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: info.lineNumberFont,
            .foregroundColor: info.lineNumberColor
        ]

        // 前のページまでの行数/パラグラフ数をカウント
        var startingNumber = 1

        switch info.lineNumberMode {
        case .none:
            return

        case .paragraph:
            // 前のページまでのパラグラフ数をカウント
            if pageNumber > 0, let textStorage = layoutManager.textStorage {
                let firstContainer = layoutManager.textContainers[0]
                let firstGlyphRange = layoutManager.glyphRange(for: firstContainer)
                let firstCharRange = layoutManager.characterRange(forGlyphRange: firstGlyphRange, actualGlyphRange: nil)

                let prevContainer = layoutManager.textContainers[pageNumber - 1]
                let prevGlyphRange = layoutManager.glyphRange(for: prevContainer)
                let prevCharRange = layoutManager.characterRange(forGlyphRange: prevGlyphRange, actualGlyphRange: nil)

                let rangeStart = firstCharRange.location
                let rangeEnd = min(prevCharRange.location + prevCharRange.length, textStorage.length)

                if rangeEnd > rangeStart {
                    let searchRange = NSRange(location: rangeStart, length: rangeEnd - rangeStart)
                    if let stringRange = Range(searchRange, in: textStorage.string) {
                        var paragraphCount = 0
                        textStorage.string.enumerateSubstrings(in: stringRange, options: .byParagraphs) { _, _, _, _ in
                            paragraphCount += 1
                        }
                        startingNumber = paragraphCount + 1
                    }
                }
            }

            drawParagraphNumbers(for: textContainer, layoutManager: layoutManager,
                                 startingNumber: startingNumber, isVerticalLayout: info.isVerticalLayout,
                                 pageRect: pageRect, docRect: docRect, attributes: attributes,
                                 lineNumberRightMargin: info.lineNumberRightMargin,
                                 textContainerPadding: info.textContainerPadding)

        case .row:
            // 前のページまでの行数をカウント
            if pageNumber > 0 {
                for i in 0..<pageNumber {
                    let container = layoutManager.textContainers[i]
                    let containerGlyphRange = layoutManager.glyphRange(for: container)
                    layoutManager.enumerateLineFragments(forGlyphRange: containerGlyphRange) { _, _, _, _, _ in
                        startingNumber += 1
                    }
                }
            }

            drawRowNumbers(for: textContainer, layoutManager: layoutManager,
                          startingNumber: startingNumber, isVerticalLayout: info.isVerticalLayout,
                          pageRect: pageRect, docRect: docRect, attributes: attributes,
                          lineNumberRightMargin: info.lineNumberRightMargin,
                          textContainerPadding: info.textContainerPadding)
        }
    }

    // MARK: - Private Drawing Methods

    private static func drawParagraphNumbers(for textContainer: NSTextContainer, layoutManager: NSLayoutManager,
                                              startingNumber: Int, isVerticalLayout: Bool,
                                              pageRect: NSRect, docRect: NSRect,
                                              attributes: [NSAttributedString.Key: Any],
                                              lineNumberRightMargin: CGFloat,
                                              textContainerPadding: CGFloat) {
        guard let textStorage = layoutManager.textStorage else { return }

        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        guard charRange.length > 0 else { return }

        var currentParagraphNumber = startingNumber

        // 前のパラグラフと同じパラグラフから始まっているかチェック
        if charRange.location > 0 {
            let prevCharIndex = charRange.location - 1
            let prevChar = (textStorage.string as NSString).character(at: prevCharIndex)
            if prevChar != 0x0A && prevChar != 0x0D {  // 改行でない場合、前のパラグラフの続き
                currentParagraphNumber -= 1
            }
        }

        var drawnParagraphs = Set<Int>()
        let searchRange = NSRange(location: charRange.location, length: charRange.length)

        if let stringRange = Range(searchRange, in: textStorage.string) {
            textStorage.string.enumerateSubstrings(in: stringRange, options: .byParagraphs) { (_, _, enclosingRange, _) in
                // enclosingRangeを使用（改行文字を含む）。substringRangeは空行の場合に
                // 長さ0になり、グリフが見つからずに行番号が描画されない問題を防ぐ。
                let nsRange = NSRange(enclosingRange, in: textStorage.string)
                let paragraphGlyphRange = layoutManager.glyphRange(forCharacterRange: nsRange, actualCharacterRange: nil)

                // 最初の行フラグメントの位置を取得
                var firstLineRect = NSRect.zero
                layoutManager.enumerateLineFragments(forGlyphRange: paragraphGlyphRange) { rect, _, _, _, stop in
                    firstLineRect = rect
                    stop.pointee = true
                }

                if !firstLineRect.isEmpty && !drawnParagraphs.contains(currentParagraphNumber) {
                    if isVerticalLayout {
                        drawVerticalNumber(currentParagraphNumber, rect: firstLineRect, pageRect: pageRect,
                                          docRect: docRect, attributes: attributes, lineNumberRightMargin: lineNumberRightMargin,
                                          textContainerPadding: textContainerPadding)
                    } else {
                        let numberString = "\(currentParagraphNumber)" as NSString
                        let size = numberString.size(withAttributes: attributes)
                        let xPosition = docRect.minX - lineNumberRightMargin - size.width
                        let yPosition = docRect.minY - textContainerPadding + firstLineRect.minY
                        numberString.draw(at: NSPoint(x: xPosition, y: yPosition), withAttributes: attributes)
                    }
                    drawnParagraphs.insert(currentParagraphNumber)
                }

                currentParagraphNumber += 1
            }
        }
    }

    private static func drawRowNumbers(for textContainer: NSTextContainer, layoutManager: NSLayoutManager,
                                        startingNumber: Int, isVerticalLayout: Bool,
                                        pageRect: NSRect, docRect: NSRect,
                                        attributes: [NSAttributedString.Key: Any],
                                        lineNumberRightMargin: CGFloat,
                                        textContainerPadding: CGFloat) {
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0 else { return }

        var rowNumber = startingNumber

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { (rect, usedRect, container, glyphRange, stop) in
            if isVerticalLayout {
                drawVerticalNumber(rowNumber, rect: rect, pageRect: pageRect,
                                  docRect: docRect, attributes: attributes, lineNumberRightMargin: lineNumberRightMargin,
                                  textContainerPadding: textContainerPadding)
            } else {
                let numberString = "\(rowNumber)" as NSString
                let size = numberString.size(withAttributes: attributes)
                let xPosition = docRect.minX - lineNumberRightMargin - size.width
                let yPosition = docRect.minY - textContainerPadding + rect.minY
                numberString.draw(at: NSPoint(x: xPosition, y: yPosition), withAttributes: attributes)
            }
            rowNumber += 1
        }
    }

    /// 縦書きの行番号を描画（上マージン内に90度回転）
    private static func drawVerticalNumber(_ number: Int, rect: NSRect, pageRect: NSRect, docRect: NSRect,
                                            attributes: [NSAttributedString.Key: Any],
                                            lineNumberRightMargin: CGFloat,
                                            textContainerPadding: CGFloat = 0.0) {
        let numberString = "\(number)" as NSString
        let font = attributes[.font] as? NSFont ?? defaultFont
        let charAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: attributes[.foregroundColor] ?? NSColor.secondaryLabelColor
        ]

        let stringSize = numberString.size(withAttributes: charAttributes)

        // 回転後：幅と高さが入れ替わる
        let rotatedWidth = stringSize.height
        let rotatedHeight = stringSize.width

        // 縦書き：列のX位置を計算
        // rect.origin.yはテキストコンテナ座標系での列位置
        // textContainerPaddingは印刷時のlineFragmentPaddingオフセット補正
        let containerWidth = docRect.width
        let columnX = docRect.minX + (containerWidth - (rect.origin.y - textContainerPadding) - rect.height)

        // 上マージン内に配置
        let yPosition = docRect.minY - lineNumberRightMargin - rotatedHeight

        // 列の中央にX位置を配置
        let xCenter = columnX + (rect.height - rotatedWidth) / 2

        // グラフィックスコンテキストを保存
        NSGraphicsContext.current?.saveGraphicsState()

        // 回転の中心点に移動して90度回転
        let transform = NSAffineTransform()
        transform.translateX(by: xCenter + rotatedWidth / 2, yBy: yPosition + rotatedHeight / 2)
        transform.rotate(byDegrees: 90)
        transform.translateX(by: -stringSize.width / 2, yBy: -stringSize.height / 2)
        transform.concat()

        // 文字列を描画
        numberString.draw(at: NSPoint.zero, withAttributes: charAttributes)

        // グラフィックスコンテキストを復元
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
