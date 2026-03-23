//
//  MultiplePageView.swift
//  Jedit-open
//
//  ページモード用のコンテナビュー
//  TextEditのMultiplePageViewを参考に、効率的な描画を実装
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

class MultiplePageView: NSView {

    // MARK: - Properties

    private(set) var numberOfPages: Int = 0

    var pageWidth: CGFloat = 595.0  // A4
    var pageHeight: CGFloat = 842.0 // A4
    var pageMargin: CGFloat = 72.0  // 1インチ（後方互換性のため残す）
    var pageSeparatorHeight: CGFloat = 20.0

    // 個別マージン（printInfoから設定）
    var topMargin: CGFloat = 72.0
    var bottomMargin: CGFloat = 72.0
    var leftMargin: CGFloat = 72.0
    var rightMargin: CGFloat = 72.0

    // 縦書きレイアウト
    var isVerticalLayout: Bool = false {
        didSet {
            if oldValue != isVerticalLayout {
                updateFrame()
            }
            needsDisplay = true
        }
    }

    // プレーンテキストかどうか（ダークモード対応の判定用）
    var isPlainText: Bool = true

    // 行番号表示モード
    var lineNumberMode: LineNumberMode = .none {
        didSet {
            needsDisplay = true
        }
    }

    // 行番号描画用のtextViews参照
    weak var layoutManager: NSLayoutManager?

    // ダークモード対応の色（プレーンテキストとリッチテキストで共通）
    var lineColor: NSColor {
        .separatorColor
    }

    /// マージン（用紙）の背景色（Document Colorsから設定可能）
    var documentBackgroundColor: NSColor? {
        didSet {
            needsDisplay = true
        }
    }

    var marginColor: NSColor {
        documentBackgroundColor ?? .textBackgroundColor
    }
    var backgroundColor: NSColor {
        .underPageBackgroundColor
    }

    // ヘッダー・フッター
    var documentName: String = ""
    var showHeader: Bool = true
    var showFooter: Bool = true
    private let headerFooterFont = NSFont.systemFont(ofSize: 10)

    /// ヘッダーのAttributedString（RTFデータから読み込み）
    var headerAttributedString: NSAttributedString? {
        didSet {
            // ヘッダーが設定されている場合は表示する
            showHeader = (headerAttributedString != nil && headerAttributedString!.length > 0)
            needsDisplay = true
        }
    }

    /// フッターのAttributedString（RTFデータから読み込み）
    var footerAttributedString: NSAttributedString? {
        didSet {
            // フッターが設定されている場合は表示する
            showFooter = (footerAttributedString != nil && footerAttributedString!.length > 0)
            needsDisplay = true
        }
    }

    /// ファイルパス（ヘッダー・フッター変数用）
    var filePath: String?

    /// ファイル更新日（ヘッダー・フッター変数用）
    var dateModified: Date?

    /// ドキュメントプロパティ（ヘッダー・フッター変数用）
    var documentProperties: NewDocData.PropertiesData?

    /// ヘッダーの色（プリセットから設定可能）
    var headerColor: NSColor? {
        didSet {
            needsDisplay = true
        }
    }

    /// フッターの色（プリセットから設定可能）
    var footerColor: NSColor? {
        didSet {
            needsDisplay = true
        }
    }

    /// ヘッダー/フッターのデフォルト色
    private var defaultHeaderFooterColor: NSColor {
        .secondaryLabelColor
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - View Properties

    override var isFlipped: Bool {
        return true
    }

    override var isOpaque: Bool {
        return true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // アピアランスが変わったら再描画
        // TextViewの色はEditorWindowControllerで管理（プレーンテキストのみ変更）
        needsDisplay = true
    }

    // MARK: - Page Management

    func setNumberOfPages(_ num: Int) {
        guard numPages != num else { return }

        let oldFrame = frame
        numberOfPages = num
        updateFrame()

        let newFrame = frame
        if isVerticalLayout {
            // 縦書き：横方向に拡張
            if newFrame.size.width > oldFrame.size.width {
                setNeedsDisplay(NSRect(
                    x: 0,
                    y: oldFrame.origin.y,
                    width: newFrame.size.width,
                    height: oldFrame.size.height
                ))
            }
        } else {
            // 横書き：縦方向に拡張
            if newFrame.size.height > oldFrame.size.height {
                setNeedsDisplay(NSRect(
                    x: oldFrame.origin.x,
                    y: oldFrame.maxY,
                    width: oldFrame.size.width,
                    height: newFrame.maxY - oldFrame.maxY
                ))
            }
        }
    }

    private var numPages: Int {
        return numberOfPages
    }

    private func updateFrame() {
        guard superview != nil else { return }

        var rect = NSRect.zero
        rect.size = NSSize(width: pageWidth, height: pageHeight)

        if isVerticalLayout {
            // 縦書き：ページを横に並べる
            rect.size.width = rect.size.width * CGFloat(numPages)
            if numPages > 1 {
                rect.size.width += pageSeparatorHeight * CGFloat(numPages - 1)
            }
        } else {
            // 横書き：ページを縦に並べる（上から下）
            rect.size.height = rect.size.height * CGFloat(numPages)
            if numPages > 1 {
                rect.size.height += pageSeparatorHeight * CGFloat(numPages - 1)
            }
        }

        frame = rect
    }

    // MARK: - Page Geometry

    /// ページの表示領域（マージン含む）
    func pageRect(forPageNumber pageNumber: Int) -> NSRect {
        var rect = NSRect.zero
        rect.size = NSSize(width: pageWidth, height: pageHeight)

        if isVerticalLayout {
            // 縦書き：ページを右から左に配置（1ページ目が右端）
            let reversedIndex = numPages - 1 - pageNumber
            rect.origin.x = (pageWidth + pageSeparatorHeight) * CGFloat(reversedIndex)
        } else {
            // 横書き：ページを上から下に配置
            rect.origin.y = (rect.size.height + pageSeparatorHeight) * CGFloat(pageNumber)
        }
        return rect
    }

    /// ページ内のテキスト表示領域
    func documentRect(forPageNumber pageNumber: Int) -> NSRect {
        var rect = pageRect(forPageNumber: pageNumber)
        rect.origin.x += leftMargin
        rect.origin.y += topMargin
        rect.size.width -= (leftMargin + rightMargin)
        rect.size.height -= (topMargin + bottomMargin)
        return rect
    }

    /// テキストコンテナのサイズ
    /// 縦書き時は幅と高さを入れ替える（テキストの流れる方向が変わるため）
    var documentSizeInPage: NSSize {
        // lineFragmentPadding分を加算して、ContinuousモードのPaper Widthと同じ折り返し幅にする
        // TextContainerはlineFragmentPadding（デフォルト5.0）を内側余白として使用するため、
        // その分をコンテナサイズに加算しないと実質的なテキスト描画幅が狭くなる
        let padding: CGFloat = 5.0  // NSTextContainer.lineFragmentPadding のデフォルト値
        let width = pageWidth - leftMargin - rightMargin + (padding * 2)
        let height = pageHeight - topMargin - bottomMargin + (padding * 2)
        if isVerticalLayout {
            return NSSize(width: height, height: width)
        } else {
            return NSSize(width: width, height: height)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard NSGraphicsContext.current?.isDrawingToScreen == true else { return }

        guard numPages > 0 else {
            // 背景色で塗りつぶし
            backgroundColor.setFill()
            dirtyRect.fill()
            return
        }

        // 背景色で塗りつぶし（ページ間のセパレーターとして見える）
        backgroundColor.setFill()
        dirtyRect.fill()

        // 表示領域と交差するページを描画
        for pageNum in 0..<numPages {
            let pageRect = self.pageRect(forPageNumber: pageNum)
            guard pageRect.intersects(dirtyRect) else { continue }

            let docRect = self.documentRect(forPageNumber: pageNum)

            // ページの影を描画（ページを浮き上がらせて見せる）
            let shadowRect = pageRect.offsetBy(dx: 3, dy: 3)
            NSColor.shadowColor.withAlphaComponent(0.3).setFill()
            shadowRect.fill()

            // ページの背景
            marginColor.setFill()
            pageRect.fill()

            // ページの境界線
            NSColor.separatorColor.setStroke()
            pageRect.frame(withWidth: 0.5)

            // ドキュメント領域の境界線
            lineColor.setStroke()
            let borderRect = docRect.insetBy(dx: -0.5, dy: -0.5)
            borderRect.frame(withWidth: 1.0)

            // ヘッダーを描画
            // headerAttributedStringが設定されている場合、またはdocumentNameがある場合に描画
            if showHeader && (headerAttributedString != nil || !documentName.isEmpty) {
                drawHeader(forPageNumber: pageNum, in: pageRect, docRect: docRect)
            }

            // フッターを描画
            // footerAttributedStringが設定されている場合、または常にページ番号を表示
            if showFooter {
                drawFooter(forPageNumber: pageNum, in: pageRect, docRect: docRect)
            }

            // 行番号を描画
            if lineNumberMode != .none {
                drawLineNumbers(forPageNumber: pageNum, in: pageRect, docRect: docRect)
            }
        }
    }

    // MARK: - Header/Footer Drawing

    /// ヘッダー・フッター描画情報を作成
    private func headerFooterDrawingInfo() -> HeaderFooterParser.DrawingInfo {
        return HeaderFooterParser.DrawingInfo(
            headerAttributedString: headerAttributedString,
            footerAttributedString: footerAttributedString,
            headerColor: headerColor,
            footerColor: footerColor,
            defaultColor: defaultHeaderFooterColor,
            defaultFont: headerFooterFont,
            documentName: documentName,
            filePath: filePath,
            dateModified: dateModified,
            documentProperties: documentProperties,
            totalPages: numPages
        )
    }

    private func drawHeader(forPageNumber pageNumber: Int, in pageRect: NSRect, docRect: NSRect) {
        HeaderFooterParser.drawHeader(info: headerFooterDrawingInfo(), forPageNumber: pageNumber, in: pageRect, docRect: docRect)
    }

    private func drawFooter(forPageNumber pageNumber: Int, in pageRect: NSRect, docRect: NSRect) {
        HeaderFooterParser.drawFooter(info: headerFooterDrawingInfo(), forPageNumber: pageNumber, in: pageRect, docRect: docRect)
    }

    // MARK: - Line Number Drawing

    /// 行番号文字色（Document Colorsから設定可能）
    var lineNumberTextColor: NSColor? {
        didSet {
            needsDisplay = true
        }
    }

    private var lineNumberColor: NSColor {
        lineNumberTextColor ?? .secondaryLabelColor
    }

    private func drawLineNumbers(forPageNumber pageNumber: Int, in pageRect: NSRect, docRect: NSRect) {
        guard let layoutManager = layoutManager else { return }

        let info = LineNumberDrawer.DrawingInfo(
            layoutManager: layoutManager,
            lineNumberMode: lineNumberMode,
            isVerticalLayout: isVerticalLayout,
            lineNumberFont: LineNumberDrawer.defaultFont,
            lineNumberColor: lineNumberColor,
            lineNumberRightMargin: LineNumberDrawer.defaultRightMargin
        )
        LineNumberDrawer.drawLineNumbers(info: info, forPageNumber: pageNumber, in: pageRect, docRect: docRect)
    }
}
