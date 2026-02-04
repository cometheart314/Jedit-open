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
        let width = pageWidth - leftMargin - rightMargin
        let height = pageHeight - topMargin - bottomMargin
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

    /// HeaderFooterParser用のコンテキストを作成
    private func createParserContext(forPageNumber pageNumber: Int) -> HeaderFooterParser.Context {
        return HeaderFooterParser.Context(
            pageNumber: pageNumber,
            totalPages: numPages,
            documentName: documentName,
            filePath: filePath,
            dateModified: dateModified,
            properties: documentProperties
        )
    }

    private func drawHeader(forPageNumber pageNumber: Int, in pageRect: NSRect, docRect: NSRect) {
        // ヘッダーAttributedStringがある場合はパースして使用
        if let headerAttrString = headerAttributedString, headerAttrString.length > 0 {
            let context = createParserContext(forPageNumber: pageNumber)
            let parsedHeader = HeaderFooterParser.parse(headerAttrString, with: context)

            // ヘッダー色を適用（設定されている場合）
            if let color = headerColor {
                parsedHeader.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: parsedHeader.length))
            }

            // ヘッダーはページ上部マージン内に描画
            let headerY = pageRect.minY + 20  // ページ上端から20ポイント下

            // パラグラフスタイルからアラインメントを取得
            let alignment: NSTextAlignment
            if parsedHeader.length > 0,
               let paragraphStyle = parsedHeader.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
                alignment = paragraphStyle.alignment
            } else {
                alignment = .left
            }

            // アラインメントに応じてX位置を計算
            let headerSize = parsedHeader.size()
            let headerX: CGFloat
            switch alignment {
            case .center:
                headerX = pageRect.midX - headerSize.width / 2
            case .right:
                headerX = docRect.maxX - headerSize.width
            default:
                headerX = docRect.minX
            }

            parsedHeader.draw(at: NSPoint(x: headerX, y: headerY))
        } else {
            // 従来の単純な描画（後方互換性）
            let attributes: [NSAttributedString.Key: Any] = [
                .font: headerFooterFont,
                .foregroundColor: headerColor ?? defaultHeaderFooterColor
            ]

            let headerString = documentName as NSString

            // ヘッダーはページ上部マージン内に左寄せ
            let headerY = pageRect.minY + 20  // ページ上端から20ポイント下
            let headerX = docRect.minX  // ドキュメント領域の左端に合わせる

            headerString.draw(at: NSPoint(x: headerX, y: headerY), withAttributes: attributes)
        }
    }

    private func drawFooter(forPageNumber pageNumber: Int, in pageRect: NSRect, docRect: NSRect) {
        // フッターAttributedStringがある場合はパースして使用
        if let footerAttrString = footerAttributedString, footerAttrString.length > 0 {
            let context = createParserContext(forPageNumber: pageNumber)
            let parsedFooter = HeaderFooterParser.parse(footerAttrString, with: context)

            // フッター色を適用（設定されている場合）
            if let color = footerColor {
                parsedFooter.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: parsedFooter.length))
            }

            // パラグラフスタイルからアラインメントを取得
            let alignment: NSTextAlignment
            if parsedFooter.length > 0,
               let paragraphStyle = parsedFooter.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
                alignment = paragraphStyle.alignment
            } else {
                alignment = .center
            }

            // フッターサイズを計算
            let footerSize = parsedFooter.size()

            // フッターはページ下部マージン内に描画
            let footerY = pageRect.maxY - footerSize.height - 20  // ページ下端から20ポイント上

            // アラインメントに応じてX位置を計算
            let footerX: CGFloat
            switch alignment {
            case .left:
                footerX = docRect.minX
            case .right:
                footerX = docRect.maxX - footerSize.width
            default:
                footerX = pageRect.midX - footerSize.width / 2
            }

            parsedFooter.draw(at: NSPoint(x: footerX, y: footerY))
        } else {
            // 従来の単純な描画（後方互換性）
            let attributes: [NSAttributedString.Key: Any] = [
                .font: headerFooterFont,
                .foregroundColor: footerColor ?? defaultHeaderFooterColor
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
    }

    // MARK: - Line Number Drawing

    private let lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    /// 行番号文字色（Document Colorsから設定可能）
    var lineNumberTextColor: NSColor? {
        didSet {
            needsDisplay = true
        }
    }

    private var lineNumberColor: NSColor {
        lineNumberTextColor ?? .secondaryLabelColor
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
                let nsRange = NSRange(substringRange, in: textStorage.string)
                let paragraphGlyphRange = layoutManager.glyphRange(forCharacterRange: nsRange, actualCharacterRange: nil)

                // 最初の行フラグメントの位置を取得
                var firstLineRect = NSRect.zero
                layoutManager.enumerateLineFragments(forGlyphRange: paragraphGlyphRange) { rect, _, _, _, stop in
                    firstLineRect = rect
                    stop.pointee = true
                }

                if !firstLineRect.isEmpty && !drawnParagraphs.contains(currentParagraphNumber) {
                    if self.isVerticalLayout {
                        // 縦書き：上マージン内に描画
                        self.drawVerticalNumber(currentParagraphNumber, rect: firstLineRect, pageRect: pageRect, docRect: docRect, attributes: attributes)
                    } else {
                        // 横書き：左マージン内に右寄せで描画
                        let numberString = "\(currentParagraphNumber)" as NSString
                        let size = numberString.size(withAttributes: attributes)
                        let xPosition = docRect.minX - self.lineNumberRightMargin - size.width
                        let yPosition = docRect.minY + firstLineRect.minY
                        numberString.draw(at: NSPoint(x: xPosition, y: yPosition), withAttributes: attributes)
                    }
                    drawnParagraphs.insert(currentParagraphNumber)
                }

                currentParagraphNumber += 1
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
            if self.isVerticalLayout {
                // 縦書き：上マージン内に描画
                self.drawVerticalNumber(rowNumber, rect: rect, pageRect: pageRect, docRect: docRect, attributes: attributes)
            } else {
                // 横書き：左マージン内に右寄せで描画
                let numberString = "\(rowNumber)" as NSString
                let size = numberString.size(withAttributes: attributes)
                let xPosition = docRect.minX - self.lineNumberRightMargin - size.width
                let yPosition = docRect.minY + rect.minY
                numberString.draw(at: NSPoint(x: xPosition, y: yPosition), withAttributes: attributes)
            }
            rowNumber += 1
        }
    }

    /// 縦書きの行番号を描画（上マージン内に90度回転）
    private func drawVerticalNumber(_ number: Int, rect: NSRect, pageRect: NSRect, docRect: NSRect, attributes: [NSAttributedString.Key: Any]) {
        let numberString = "\(number)" as NSString
        let font = attributes[.font] as? NSFont ?? lineNumberFont
        let charAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: attributes[.foregroundColor] ?? lineNumberColor
        ]

        let stringSize = numberString.size(withAttributes: charAttributes)

        // 回転後：幅と高さが入れ替わる
        let rotatedWidth = stringSize.height
        let rotatedHeight = stringSize.width

        // 縦書き：列のX位置を計算
        // rect.origin.yが列の論理位置（0が最初の列=右端）
        // rect.heightが列幅
        // docRect.width（コンテナの幅）から相対位置を計算
        let containerWidth = docRect.width
        let columnX = docRect.minX + (containerWidth - rect.origin.y - rect.height)

        // 上マージン内に配置（ページ上端とdocRect上端の間）
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
