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

    var lineColor: NSColor = .gray
    var marginColor: NSColor = .white
    var backgroundColor: NSColor = .lightGray

    // ヘッダー・フッター
    var documentName: String = ""
    var showHeader: Bool = true
    var showFooter: Bool = true
    private let headerFooterFont = NSFont.systemFont(ofSize: 10)
    private let headerFooterColor = NSColor.darkGray

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
            NSColor.darkGray.withAlphaComponent(0.3).setFill()
            shadowRect.fill()

            // ページの白い背景
            marginColor.setFill()
            pageRect.fill()

            // ページの境界線
            NSColor.darkGray.setStroke()
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
}
