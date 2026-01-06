//
//  MultiplePageView.swift
//  Jedit-open
//
//  ページモード用のコンテナビュー
//  TextEditのMultiplePageViewを参考に、効率的な描画を実装
//

import Cocoa

class MultiplePageView: NSView {

    // MARK: - Properties

    private(set) var numberOfPages: Int = 0

    var pageWidth: CGFloat = 595.0  // A4
    var pageHeight: CGFloat = 842.0 // A4
    var pageMargin: CGFloat = 72.0  // 1インチ
    var pageSeparatorHeight: CGFloat = 20.0

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

    // 色はプレーンテキストの場合のみダークモード対応
    var lineColor: NSColor {
        isPlainText ? .separatorColor : .gray
    }
    var marginColor: NSColor {
        isPlainText ? .textBackgroundColor : .white
    }
    var backgroundColor: NSColor {
        isPlainText ? .underPageBackgroundColor : .lightGray
    }

    // ヘッダー・フッター
    var documentName: String = ""
    var showHeader: Bool = true
    var showFooter: Bool = true
    private let headerFooterFont = NSFont.systemFont(ofSize: 10)
    private var headerFooterColor: NSColor {
        isPlainText ? .secondaryLabelColor : .darkGray
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
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
        if newFrame.size.height > oldFrame.size.height {
            setNeedsDisplay(NSRect(
                x: oldFrame.origin.x,
                y: oldFrame.maxY,
                width: oldFrame.size.width,
                height: newFrame.maxY - oldFrame.maxY
            ))
        }
    }

    private var numPages: Int {
        return numberOfPages
    }

    private func updateFrame() {
        guard superview != nil else { return }

        var rect = NSRect.zero
        rect.size = NSSize(width: pageWidth, height: pageHeight)
        rect.size.height = rect.size.height * CGFloat(numPages)
        if numPages > 1 {
            rect.size.height += pageSeparatorHeight * CGFloat(numPages - 1)
        }

        frame = rect
    }

    // MARK: - Page Geometry

    /// ページの表示領域（マージン含む）
    func pageRect(forPageNumber pageNumber: Int) -> NSRect {
        var rect = NSRect.zero
        rect.size = NSSize(width: pageWidth, height: pageHeight)
        // originは(0, 0)から開始（frame.originを使わない）
        rect.origin.y = (rect.size.height + pageSeparatorHeight) * CGFloat(pageNumber)
        return rect
    }

    /// ページ内のテキスト表示領域
    func documentRect(forPageNumber pageNumber: Int) -> NSRect {
        var rect = pageRect(forPageNumber: pageNumber)
        rect.origin.x += pageMargin
        rect.origin.y += pageMargin
        rect.size.width -= pageMargin * 2
        rect.size.height -= pageMargin * 2
        return rect
    }

    /// テキストコンテナのサイズ
    var documentSizeInPage: NSSize {
        return NSSize(
            width: pageWidth - pageMargin * 2,
            height: pageHeight - pageMargin * 2
        )
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard NSGraphicsContext.current?.isDrawingToScreen == true else { return }

        // 表示領域に含まれるページのみ描画
        let firstPage = max(0, Int(dirtyRect.minY / (pageHeight + pageSeparatorHeight)))
        let lastPage = min(Int(dirtyRect.maxY / (pageHeight + pageSeparatorHeight)), numPages - 1)

        guard firstPage <= lastPage && numPages > 0 else {
            // 背景色で塗りつぶし
            backgroundColor.setFill()
            dirtyRect.fill()
            return
        }

        // 背景色で塗りつぶし（ページ間のセパレーターとして見える）
        backgroundColor.setFill()
        dirtyRect.fill()

        // 各ページを描画
        for pageNum in firstPage...lastPage {
            let pageRect = self.pageRect(forPageNumber: pageNum)
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

            // ヘッダーを描画（ファイル名）
            if showHeader && !documentName.isEmpty {
                drawHeader(forPageNumber: pageNum, in: pageRect, docRect: docRect)
            }

            // フッターを描画（ページ番号/総ページ数）
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

    private func drawHeader(forPageNumber pageNumber: Int, in pageRect: NSRect, docRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: headerFooterFont,
            .foregroundColor: headerFooterColor
        ]

        let headerString = documentName as NSString
        let headerSize = headerString.size(withAttributes: attributes)

        // ヘッダーはページ上部マージン内に左寄せ
        let headerY = pageRect.minY + 20  // ページ上端から20ポイント下
        let headerX = docRect.minX  // ドキュメント領域の左端に合わせる

        headerString.draw(at: NSPoint(x: headerX, y: headerY), withAttributes: attributes)
    }

    private func drawFooter(forPageNumber pageNumber: Int, in pageRect: NSRect, docRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: headerFooterFont,
            .foregroundColor: headerFooterColor
        ]

        // "ページ番号 / 総ページ数" 形式
        let footerText = "\(pageNumber + 1) / \(numPages)"
        let footerString = footerText as NSString
        let footerSize = footerString.size(withAttributes: attributes)

        // フッターはページ下部マージン内に中央配置
        let footerY = pageRect.maxY - footerSize.height - 20  // ページ下端から20ポイント上
        let footerX = pageRect.midX - footerSize.width / 2

        footerString.draw(at: NSPoint(x: footerX, y: footerY), withAttributes: attributes)
    }

    // MARK: - Line Number Drawing

    private let lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    private var lineNumberColor: NSColor {
        isPlainText ? .secondaryLabelColor : .darkGray
    }
    private let lineNumberRightMargin: CGFloat = 8.0

    private func drawLineNumbers(forPageNumber pageNumber: Int, in pageRect: NSRect, docRect: NSRect) {
        guard let layoutManager = layoutManager,
              pageNumber < layoutManager.textContainers.count else { return }

        let textContainer = layoutManager.textContainers[pageNumber]
        let glyphRange = layoutManager.glyphRange(for: textContainer)

        guard glyphRange.length > 0 else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: lineNumberFont,
            .foregroundColor: lineNumberColor
        ]

        // 前のページまでの行数/パラグラフ数をカウント
        var startingNumber = 1

        switch lineNumberMode {
        case .none:
            return

        case .paragraph:
            // 前のページまでのパラグラフ数をカウント
            if pageNumber > 0, let textStorage = layoutManager.textStorage {
                var paragraphCount = 0
                for i in 0..<pageNumber {
                    let container = layoutManager.textContainers[i]
                    let containerGlyphRange = layoutManager.glyphRange(for: container)
                    if containerGlyphRange.length > 0 {
                        let charRange = layoutManager.characterRange(forGlyphRange: containerGlyphRange, actualGlyphRange: nil)
                        if charRange.length > 0 {
                            let rangeEnd = min(charRange.location + charRange.length, textStorage.length)
                            let searchRange = NSRange(location: 0, length: rangeEnd)
                            if let stringRange = Range(searchRange, in: textStorage.string) {
                                textStorage.string.enumerateSubstrings(in: stringRange, options: .byParagraphs) { _, _, _, _ in
                                    paragraphCount += 1
                                }
                            }
                        }
                    }
                }
                startingNumber = paragraphCount + 1
            }

            // このページのパラグラフ番号を描画
            drawParagraphNumbers(for: textContainer, layoutManager: layoutManager,
                                 startingNumber: startingNumber, pageRect: pageRect,
                                 docRect: docRect, attributes: attributes)

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

            // このページの行番号を描画
            drawRowNumbers(for: textContainer, layoutManager: layoutManager,
                          startingNumber: startingNumber, pageRect: pageRect,
                          docRect: docRect, attributes: attributes)
        }
    }

    private func drawParagraphNumbers(for textContainer: NSTextContainer, layoutManager: NSLayoutManager,
                                       startingNumber: Int, pageRect: NSRect, docRect: NSRect,
                                       attributes: [NSAttributedString.Key: Any]) {
        guard let textStorage = layoutManager.textStorage else { return }

        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        guard charRange.length > 0 else { return }

        // このページの最初の文字位置からパラグラフ番号を計算
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
            textStorage.string.enumerateSubstrings(in: stringRange, options: .byParagraphs) { (_, substringRange, _, _) in
                currentParagraphNumber += 1

                let nsRange = NSRange(substringRange, in: textStorage.string)
                let paragraphGlyphRange = layoutManager.glyphRange(forCharacterRange: nsRange, actualCharacterRange: nil)

                // 最初の行フラグメントの位置を取得
                var firstLineRect = NSRect.zero
                layoutManager.enumerateLineFragments(forGlyphRange: paragraphGlyphRange) { rect, _, _, _, stop in
                    firstLineRect = rect
                    stop.pointee = true
                }

                if !firstLineRect.isEmpty && !drawnParagraphs.contains(currentParagraphNumber) {
                    let numberString = "\(currentParagraphNumber)" as NSString
                    let size = numberString.size(withAttributes: attributes)

                    // 左マージン内に右寄せで描画
                    let xPosition = docRect.minX - self.lineNumberRightMargin - size.width
                    let yPosition = docRect.minY + firstLineRect.minY

                    numberString.draw(at: NSPoint(x: xPosition, y: yPosition), withAttributes: attributes)
                    drawnParagraphs.insert(currentParagraphNumber)
                }
            }
        }
    }

    private func drawRowNumbers(for textContainer: NSTextContainer, layoutManager: NSLayoutManager,
                                startingNumber: Int, pageRect: NSRect, docRect: NSRect,
                                attributes: [NSAttributedString.Key: Any]) {
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0 else { return }

        var rowNumber = startingNumber

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { (rect, usedRect, container, glyphRange, stop) in
            let numberString = "\(rowNumber)" as NSString
            let size = numberString.size(withAttributes: attributes)

            // 左マージン内に右寄せで描画
            let xPosition = docRect.minX - self.lineNumberRightMargin - size.width
            let yPosition = docRect.minY + rect.minY

            numberString.draw(at: NSPoint(x: xPosition, y: yPosition), withAttributes: attributes)
            rowNumber += 1
        }
    }
}
