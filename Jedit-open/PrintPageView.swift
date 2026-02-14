//
//  PrintPageView.swift
//  Jedit-open
//
//  印刷用のカスタムビュー
//  Page表示と同様にヘッダー・フッター付きで各ページを描画する
//

import Cocoa

/// 印刷用のカスタムビュー（ヘッダー・フッター付き）
class PrintPageView: NSView {

    // MARK: - Properties

    private let textStorage: NSTextStorage
    private let printInfo: NSPrintInfo
    private let isVerticalLayout: Bool

    // ページ設定
    private let pageWidth: CGFloat
    private let pageHeight: CGFloat
    private let topMargin: CGFloat
    private let bottomMargin: CGFloat
    private let leftMargin: CGFloat
    private let rightMargin: CGFloat

    // ヘッダー・フッター
    private let headerAttributedString: NSAttributedString?
    private let footerAttributedString: NSAttributedString?
    private let headerColor: NSColor?
    private let footerColor: NSColor?
    private let documentName: String
    private let filePath: String?
    private let dateModified: Date?
    private let documentProperties: NewDocData.PropertiesData?

    // テキストの背景色
    private let textBackgroundColor: NSColor
    private let isPlainText: Bool

    // 行番号
    private let lineNumberMode: LineNumberMode
    private let lineNumberColor: NSColor

    // 印刷パネルアクセサリ
    weak var accessoryController: PrintPanelAccessoryController?
    private let originalInvisibleOptions: InvisibleCharacterOptions

    // レイアウト
    private let layoutManager: NSLayoutManager
    private var printTextStorage: NSTextStorage?  // layoutManagerが参照するため保持が必要
    private var textContainers: [NSTextContainer] = []
    private var numberOfPages: Int = 0

    // MARK: - Initialization

    struct Configuration {
        let textStorage: NSTextStorage
        let printInfo: NSPrintInfo
        let isVerticalLayout: Bool
        let headerAttributedString: NSAttributedString?
        let footerAttributedString: NSAttributedString?
        let headerColor: NSColor?
        let footerColor: NSColor?
        let documentName: String
        let filePath: String?
        let dateModified: Date?
        let documentProperties: NewDocData.PropertiesData?
        let textBackgroundColor: NSColor
        let isPlainText: Bool
        let defaultFont: NSFont?
        let defaultTextColor: NSColor?
        let invisibleCharacterOptions: InvisibleCharacterOptions
        let invisibleCharacterColor: NSColor
        let lineBreakingType: Int  // 0: System Default, 1: Japanese (Burasagari), 2: No wordwrap
        let lineNumberMode: LineNumberMode
        let lineNumberColor: NSColor
    }

    init(configuration: Configuration) {
        self.textStorage = configuration.textStorage
        self.printInfo = configuration.printInfo
        self.isVerticalLayout = configuration.isVerticalLayout
        self.headerAttributedString = configuration.headerAttributedString
        self.footerAttributedString = configuration.footerAttributedString
        self.headerColor = configuration.headerColor
        self.footerColor = configuration.footerColor
        self.documentName = configuration.documentName
        self.filePath = configuration.filePath
        self.dateModified = configuration.dateModified
        self.documentProperties = configuration.documentProperties
        self.textBackgroundColor = configuration.textBackgroundColor
        self.isPlainText = configuration.isPlainText
        self.lineNumberMode = configuration.lineNumberMode
        self.lineNumberColor = configuration.lineNumberColor
        self.originalInvisibleOptions = configuration.invisibleCharacterOptions

        // ページサイズ（printInfoから取得）
        self.pageWidth = configuration.printInfo.paperSize.width
        self.pageHeight = configuration.printInfo.paperSize.height
        self.topMargin = configuration.printInfo.topMargin
        self.bottomMargin = configuration.printInfo.bottomMargin
        self.leftMargin = configuration.printInfo.leftMargin
        self.rightMargin = configuration.printInfo.rightMargin

        // レイアウトマネージャーを作成（不可視文字対応）
        let lm = InvisibleCharacterLayoutManager()
        // 印刷用：背景レイアウトを無効化し、画面フォントを使わない
        lm.backgroundLayoutEnabled = false
        lm.usesScreenFonts = false
        // 不可視文字オプションは直接設定（invalidateDisplayを避けるため内部値を使用）
        lm.invisibleCharacterOptions = configuration.invisibleCharacterOptions
        // 印刷時はグレーで出力（画面表示色だとダークモード時に見えない場合がある）
        lm.invisibleCharacterColor = configuration.invisibleCharacterColor
        self.layoutManager = lm

        super.init(frame: NSRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        // テキストのレイアウトを実行
        setupLayout(
            defaultFont: configuration.defaultFont,
            defaultTextColor: configuration.defaultTextColor,
            lineBreakingType: configuration.lineBreakingType
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout Setup

    private func setupLayout(defaultFont: NSFont?, defaultTextColor: NSColor?, lineBreakingType: Int) {
        // 印刷用テキストストレージを作成（禁則処理対応のJOTextStorageを使用）
        // Note: layoutManagerはtextStorageを弱参照で保持するため、インスタンス変数で保持する
        let storage = JOTextStorage()
        storage.append(NSAttributedString(attributedString: textStorage))
        storage.setLineBreakingType(lineBreakingType)
        storage.setKinsokuParamsFromDefaults()
        self.printTextStorage = storage
        let printTextStorage = storage

        // プレーンテキストの場合、フォントと色を適用
        if isPlainText {
            let fullRange = NSRange(location: 0, length: printTextStorage.length)
            if let font = defaultFont {
                printTextStorage.addAttribute(.font, value: font, range: fullRange)
            }
            // 印刷時は常に黒文字を使用
            printTextStorage.addAttribute(.foregroundColor, value: NSColor.black, range: fullRange)
        }

        // LayoutManagerをTextStorageに追加
        printTextStorage.addLayoutManager(layoutManager)

        // テキストコンテナのサイズを計算
        let padding: CGFloat = 5.0  // NSTextContainer.lineFragmentPadding のデフォルト値
        let containerWidth: CGFloat
        let containerHeight: CGFloat
        if isVerticalLayout {
            containerWidth = pageHeight - topMargin - bottomMargin + (padding * 2)
            containerHeight = pageWidth - leftMargin - rightMargin + (padding * 2)
        } else {
            containerWidth = pageWidth - leftMargin - rightMargin + (padding * 2)
            containerHeight = pageHeight - topMargin - bottomMargin + (padding * 2)
        }

        // テキストが空の場合は1ページのみ
        guard printTextStorage.length > 0 else {
            addTextContainer(width: containerWidth, height: containerHeight)
            numberOfPages = 1
            frame = NSRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
            return
        }

        // 最初のテキストコンテナを作成
        addTextContainer(width: containerWidth, height: containerHeight)

        // テキスト全体のレイアウトが完了するまでページを追加
        // NSLayoutManagerは各コンテナが満杯になると次のコンテナにテキストを流す
        let maxPages = 10000  // 安全上限
        while textContainers.count < maxPages {
            // 全レイアウトを実行
            layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: printTextStorage.length))

            // 最後のコンテナのグリフ範囲を確認
            let lastContainer = textContainers.last!
            let glyphRange = layoutManager.glyphRange(for: lastContainer)
            let totalGlyphs = layoutManager.numberOfGlyphs

            // 全グリフがレイアウト済みなら終了
            if totalGlyphs == 0 || NSMaxRange(glyphRange) >= totalGlyphs {
                break
            }

            // まだテキストが残っているので、次のページを追加
            addTextContainer(width: containerWidth, height: containerHeight)
        }

        // 不要なコンテナを削除（空のコンテナ）
        trimEmptyContainers()

        numberOfPages = textContainers.count

        // フレームサイズを更新
        if isVerticalLayout {
            frame = NSRect(x: 0, y: 0, width: pageWidth * CGFloat(numberOfPages), height: pageHeight)
        } else {
            frame = NSRect(x: 0, y: 0, width: pageWidth, height: pageHeight * CGFloat(numberOfPages))
        }
    }

    /// 一時的なNSTextViewの参照を保持（縦書き設定のレイアウト方向を維持するため）
    private var tempTextViews: [NSTextView] = []

    private func addTextContainer(width: CGFloat, height: CGFloat) {
        let textContainer = NSTextContainer(containerSize: NSSize(width: width, height: height))
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 5.0
        layoutManager.addTextContainer(textContainer)

        // 縦書きの場合、NSTextViewを使ってレイアウト方向を設定
        // NSTextContainer.layoutOrientationは読み取り専用のため、
        // NSTextView.setLayoutOrientation経由で内部フラグを設定する必要がある
        // Note: NSTextViewを解放するとレイアウト方向がリセットされるため保持する
        if isVerticalLayout {
            let tv = NSTextView(frame: .zero, textContainer: textContainer)
            tv.setLayoutOrientation(.vertical)
            // setLayoutOrientationがコンテナサイズを変更するので元に戻す
            textContainer.containerSize = NSSize(width: width, height: height)
            tempTextViews.append(tv)
        }

        textContainers.append(textContainer)
    }

    private func trimEmptyContainers() {
        while textContainers.count > 1 {
            let lastContainer = textContainers.last!
            let glyphRange = layoutManager.glyphRange(for: lastContainer)
            if glyphRange.length == 0 {
                layoutManager.removeTextContainer(at: textContainers.count - 1)
                textContainers.removeLast()
            } else {
                break
            }
        }
    }

    // MARK: - NSView Overrides

    override var isFlipped: Bool {
        return true
    }

    // MARK: - Printing Support

    override func beginDocument() {
        // "Black Chars and White Back" の場合、実際の印刷時にテキスト色を黒に強制
        if let ctrl = accessoryController, ctrl.colorOption == 2 {
            forceBlackText()
        }
        super.beginDocument()
    }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: numberOfPages)
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        let pageIndex = page - 1  // 1始まりを0始まりに変換
        guard pageIndex >= 0, pageIndex < numberOfPages else {
            return .zero
        }

        if isVerticalLayout {
            // 縦書き：ページを横に並べる
            return NSRect(x: pageWidth * CGFloat(pageIndex), y: 0, width: pageWidth, height: pageHeight)
        } else {
            // 横書き：ページを縦に並べる
            return NSRect(x: 0, y: pageHeight * CGFloat(pageIndex), width: pageWidth, height: pageHeight)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Note: 印刷プレビュー時にmacOSの内部フレームワークが
        // CGContextClipToRect: invalid context 0x0 をログすることがあるが、
        // これはAppleの既知の問題で無害（描画はno-opとしてスキップされる）
        for pageIndex in 0..<numberOfPages {
            let pageRect = rectForPage(pageIndex + 1)
            guard pageRect.intersects(dirtyRect) else { continue }

            drawPage(at: pageIndex, in: pageRect)
        }
    }

    private func drawPage(at pageIndex: Int, in pageRect: NSRect) {
        guard pageIndex < textContainers.count else { return }

        // ページ背景色を決定（アクセサリコントローラの設定に基づく）
        let bgColor: NSColor
        if let ctrl = accessoryController {
            switch ctrl.colorOption {
            case 1, 2:
                // "Don't Print Background Color" or "Black Chars and White Back" → 白背景
                bgColor = .white
            default:
                // "Same as Editing Window" → エディタの背景色を使用
                bgColor = textBackgroundColor
            }
        } else {
            bgColor = .white
        }
        bgColor.setFill()
        pageRect.fill()

        // ドキュメント領域（マージン内）
        let docRect = NSRect(
            x: pageRect.minX + leftMargin,
            y: pageRect.minY + topMargin,
            width: pageWidth - leftMargin - rightMargin,
            height: pageHeight - topMargin - bottomMargin
        )

        // テキストを描画
        let textContainer = textContainers[pageIndex]
        let glyphRange = layoutManager.glyphRange(for: textContainer)

        if glyphRange.length > 0 {
            let padding: CGFloat = 5.0

            if isVerticalLayout {
                // 縦書き：グラフィックスコンテキストを回転して描画
                // NSLayoutManagerは縦書きテキストコンテナのグリフ位置を
                // 回転した座標系で返す：
                //   コンテナX軸 → 画面の上→下（行の進行方向）
                //   コンテナY軸 → 画面の右→左（列の進行方向）
                //
                // 変換：translate(docRect.maxX, docRect.minY) + rotate(+90°)
                // → コンテナ(x,y) → 画面(docRect.maxX - y, docRect.minY + x)

                // 1. 添付画像を一時的に隠してテキストのみ回転描画
                let hiddenAttachments = hideAttachments(in: glyphRange)

                NSGraphicsContext.current?.saveGraphicsState()

                let transform = NSAffineTransform()
                transform.translateX(by: docRect.maxX, yBy: docRect.minY)
                transform.rotate(byDegrees: 90)
                transform.concat()

                let textOrigin = NSPoint(x: -padding, y: -padding)
                layoutManager.drawBackground(forGlyphRange: glyphRange, at: textOrigin)
                layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: textOrigin)

                NSGraphicsContext.current?.restoreGraphicsState()

                // 2. 添付画像を復元
                restoreAttachments(hiddenAttachments)

                // 3. 添付画像を回転なしで正しい向きに描画
                drawAttachmentsForVerticalLayout(glyphRange: glyphRange, padding: padding, docRect: docRect)
            } else {
                // 横書き：通常の描画
                let textOrigin = NSPoint(x: docRect.minX - padding, y: docRect.minY - padding)
                layoutManager.drawBackground(forGlyphRange: glyphRange, at: textOrigin)
                layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: textOrigin)
            }
        }

        // 行番号の描画を決定（アクセサリコントローラの設定に基づく）
        let effectiveLineNumberMode: LineNumberMode
        if let ctrl = accessoryController {
            switch ctrl.lineNumberOption {
            case 1:
                // "Print Line Numbers" → ウィンドウに行番号がない場合は .paragraph をデフォルトに
                effectiveLineNumberMode = (lineNumberMode != .none) ? lineNumberMode : .paragraph
            case 2:
                // "Don't Print Line Numbers"
                effectiveLineNumberMode = .none
            default:
                // "Same as Editing Window"
                effectiveLineNumberMode = lineNumberMode
            }
        } else {
            effectiveLineNumberMode = lineNumberMode
        }

        if effectiveLineNumberMode != .none {
            let lineNumberInfo = LineNumberDrawer.DrawingInfo(
                layoutManager: layoutManager,
                lineNumberMode: effectiveLineNumberMode,
                isVerticalLayout: isVerticalLayout,
                lineNumberFont: LineNumberDrawer.defaultFont,
                lineNumberColor: lineNumberColor,
                lineNumberRightMargin: LineNumberDrawer.defaultRightMargin,
                textContainerPadding: 5.0  // NSTextContainer.lineFragmentPadding
            )
            LineNumberDrawer.drawLineNumbers(info: lineNumberInfo, forPageNumber: pageIndex, in: pageRect, docRect: docRect)
        }

        // ヘッダーの描画（アクセサリコントローラの設定に基づく）
        let shouldDrawHeader = accessoryController?.printHeader ?? true
        if shouldDrawHeader {
            drawHeader(forPageNumber: pageIndex, in: pageRect, docRect: docRect)
        }

        // フッターの描画（アクセサリコントローラの設定に基づく）
        let shouldDrawFooter = accessoryController?.printFooter ?? true
        if shouldDrawFooter {
            drawFooter(forPageNumber: pageIndex, in: pageRect, docRect: docRect)
        }
    }

    // MARK: - Print Options Support

    /// テキスト全体を黒色に強制（"Black Chars and White Back" 用）
    private func forceBlackText() {
        guard let storage = printTextStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.foregroundColor, value: NSColor.black, range: fullRange)
    }

    /// 不可視文字の表示を更新（アクセサリコントローラから呼ばれる）
    func updateInvisibleCharacterDisplay() {
        guard let lm = layoutManager as? InvisibleCharacterLayoutManager else { return }
        if let ctrl = accessoryController, !ctrl.printInvisibles {
            lm.invisibleCharacterOptions = .none
        } else {
            lm.invisibleCharacterOptions = originalInvisibleOptions
        }
    }

    // MARK: - Header/Footer Drawing

    private static let printDefaultFont = NSFont.systemFont(ofSize: 10)

    /// ヘッダー・フッター描画情報を作成
    private func headerFooterDrawingInfo() -> HeaderFooterParser.DrawingInfo {
        return HeaderFooterParser.DrawingInfo(
            headerAttributedString: headerAttributedString,
            footerAttributedString: footerAttributedString,
            headerColor: headerColor,
            footerColor: footerColor,
            defaultColor: .darkGray,
            defaultFont: PrintPageView.printDefaultFont,
            documentName: documentName,
            filePath: filePath,
            dateModified: dateModified,
            documentProperties: documentProperties,
            totalPages: numberOfPages
        )
    }

    private func drawHeader(forPageNumber pageNumber: Int, in pageRect: NSRect, docRect: NSRect) {
        HeaderFooterParser.drawHeader(info: headerFooterDrawingInfo(), forPageNumber: pageNumber, in: pageRect, docRect: docRect)
    }

    private func drawFooter(forPageNumber pageNumber: Int, in pageRect: NSRect, docRect: NSRect) {
        HeaderFooterParser.drawFooter(info: headerFooterDrawingInfo(), forPageNumber: pageNumber, in: pageRect, docRect: docRect)
    }

    // MARK: - Vertical Attachment Drawing

    /// 添付画像情報の保存用
    private struct HiddenAttachment {
        let charIndex: Int
        let attachment: NSTextAttachment
        let image: NSImage
    }

    /// 添付画像を一時的に隠す（drawGlyphsで描画されないようにする）
    private func hideAttachments(in glyphRange: NSRange) -> [HiddenAttachment] {
        guard let textStorage = layoutManager.textStorage else { return [] }
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard charRange.length > 0 else { return [] }

        var hidden: [HiddenAttachment] = []

        textStorage.enumerateAttribute(.attachment, in: charRange, options: []) { value, range, _ in
            guard let attachment = value as? NSTextAttachment else { return }

            // イメージを取得して保存
            let image: NSImage?
            if let cell = attachment.attachmentCell as? NSCell {
                image = cell.image
            } else {
                image = attachment.image
            }
            guard let attachmentImage = image else { return }

            hidden.append(HiddenAttachment(charIndex: range.location, attachment: attachment, image: attachmentImage))

            // 透明1x1画像に置き換えて非表示にする
            let emptyImage = NSImage(size: attachmentImage.size)
            if let cell = attachment.attachmentCell as? NSCell {
                cell.image = emptyImage
            } else {
                attachment.image = emptyImage
            }
        }

        return hidden
    }

    /// 隠した添付画像を復元する
    private func restoreAttachments(_ hidden: [HiddenAttachment]) {
        for item in hidden {
            if let cell = item.attachment.attachmentCell as? NSCell {
                cell.image = item.image
            } else {
                item.attachment.image = item.image
            }
        }
    }

    /// 縦書き印刷時に添付画像を回転なしで正しい向きに描画する
    /// drawGlyphsの回転コンテキスト外で呼び出される（通常の画面座標系）
    private func drawAttachmentsForVerticalLayout(glyphRange: NSRange, padding: CGFloat, docRect: NSRect) {
        guard let textStorage = layoutManager.textStorage else { return }
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard charRange.length > 0 else { return }

        textStorage.enumerateAttribute(.attachment, in: charRange, options: []) { value, range, _ in
            guard let attachment = value as? NSTextAttachment else { return }

            let image: NSImage?
            if let cell = attachment.attachmentCell as? NSCell {
                image = cell.image
            } else {
                image = attachment.image
            }
            guard let attachmentImage = image else { return }

            // テキストコンテナ座標系でのグリフ位置を取得
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: range.location)
            let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let locationInLine = layoutManager.location(forGlyphAt: glyphIndex)
            let attachmentSize = layoutManager.attachmentSize(forGlyphAt: glyphIndex)

            // テキストコンテナ座標系での画像の配置を計算
            // locationInLine.x = 行方向（コンテナX軸）の先頭位置
            // locationInLine.y = 列方向（コンテナY軸）のベースライン位置（画像の下端）
            // 画像のコンテナY座標上端 = locationInLine.y - attachmentSize.height
            let containerX = lineFragmentRect.minX + locationInLine.x
            let containerY = lineFragmentRect.minY + (locationInLine.y - attachmentSize.height)

            // コンテナ座標から画面座標への変換
            // 回転変換: translate(docRect.maxX, docRect.minY) + rotate(+90°)
            // textOrigin = (-padding, -padding) → コンテナ原点が(-padding,-padding)にオフセット
            //
            // コンテナ座標(x,y) → 描画座標(x-padding, y-padding) → 回転後の画面座標:
            //   画面X = docRect.maxX - (y - padding)   [コンテナY → 画面Xは右から左]
            //   画面Y = docRect.minY + (x - padding)   [コンテナX → 画面Yは上から下]
            let screenX = docRect.maxX - (containerY + attachmentSize.height - padding)
            let screenY = docRect.minY + (containerX - padding)
            // 画面でのサイズ: コンテナのheight→画面のwidth, コンテナのwidth→画面のheight
            let screenWidth = attachmentSize.height
            let screenHeight = attachmentSize.width

            let drawRect = NSRect(
                x: screenX,
                y: screenY,
                width: screenWidth,
                height: screenHeight
            )

            attachmentImage.draw(in: drawRect,
                                 from: NSRect(origin: .zero, size: attachmentImage.size),
                                 operation: .sourceOver,
                                 fraction: 1.0,
                                 respectFlipped: true,
                                 hints: [.interpolation: NSImageInterpolation.high])
        }
    }
}
