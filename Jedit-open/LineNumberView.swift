//
//  LineNumberView.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/26.
//

import Cocoa

// MARK: - Line Number Mode

enum LineNumberMode {
    case none        // 行番号非表示
    case paragraph   // パラグラフ番号
    case row         // 行番号（折り返しを含む）
}

// MARK: - Line Number View

class LineNumberView: NSView {
    var lineNumberMode: LineNumberMode = .none {
        didSet {
            updateSizeAsync()
            needsDisplay = true
            // 縦書きモードでは遅延再描画を行う（スクロール位置が確定するまで待つ）
            if isVerticalLayout {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.needsDisplay = true
                }
            }
        }
    }

    var isVerticalLayout: Bool = false {
        didSet {
            updateSizeAsync()
            needsDisplay = true
            // 遅延再描画を行う（スクロール位置が確定するまで待つ）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.needsDisplay = true
            }
        }
    }

    weak var textView: NSTextView? {
        didSet {
            setupScrollObserver()
        }
    }

    weak var scrollView: NSScrollView?

    private let minimumWidth: CGFloat = 40.0
    private let minimumHeight: CGFloat = 25.0
    private let rightMargin: CGFloat = 5.0
    private let leftMargin: CGFloat = 5.0
    private let topMargin: CGFloat = 3.0
    private let bottomMargin: CGFloat = 3.0
    private var updateWorkItem: DispatchWorkItem?
    private var scrollObserver: Any?
    private var textChangeObserver: Any?
    private var textStorageObserver: Any?

    // サイズ変更通知
    static let widthDidChangeNotification = Notification.Name("LineNumberViewWidthDidChange")
    static let heightDidChangeNotification = Notification.Name("LineNumberViewHeightDidChange")

    // 現在のサイズ
    private(set) var currentWidth: CGFloat = 40.0
    private(set) var currentHeight: CGFloat = 25.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        self.clipsToBounds = true
        self.currentWidth = minimumWidth
        self.currentHeight = minimumHeight
    }

    // 座標系を上から下に設定（NSTextViewと同じ）
    override var isFlipped: Bool {
        return true
    }

    deinit {
        updateWorkItem?.cancel()
        if let observer = scrollObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = textChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = textStorageObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupScrollObserver() {
        // 既存のobserverを削除
        if let observer = scrollObserver {
            NotificationCenter.default.removeObserver(observer)
            scrollObserver = nil
        }
        if let observer = textChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            textChangeObserver = nil
        }
        if let observer = textStorageObserver {
            NotificationCenter.default.removeObserver(observer)
            textStorageObserver = nil
        }

        guard let textView = textView,
              let scrollView = textView.enclosingScrollView else { return }

        self.scrollView = scrollView

        // スクロール時に再描画
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        }

        // テキスト変更時に幅を再計算
        textChangeObserver = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            self?.debounceUpdateSize()
        }

        // テキストストレージの属性変更時（フォントサイズ変更など）に再描画
        if let textStorage = textView.textStorage {
            textStorageObserver = NotificationCenter.default.addObserver(
                forName: NSTextStorage.didProcessEditingNotification,
                object: textStorage,
                queue: .main
            ) { [weak self] _ in
                // 即時再描画
                self?.needsDisplay = true
                // レイアウトが確定するまで待ってから再描画
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.needsDisplay = true
                }
            }
        }

        // 初期サイズを計算
        DispatchQueue.main.async { [weak self] in
            self?.updateSizeAsync()
        }
    }

    private func debounceUpdateSize() {
        updateWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.updateSizeAsync()
        }
        updateWorkItem = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func updateSizeAsync() {
        guard lineNumberMode != .none,
              let textView = textView,
              let layoutManager = textView.layoutManager,
              textView.textContainer != nil else {
            return
        }

        let textStorage = layoutManager.textStorage!
        let mode = lineNumberMode

        switch mode {
        case .none:
            break

        case .paragraph:
            let textString = textStorage.string
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }

                var maxLineNumber = 0
                textString.enumerateSubstrings(in: textString.startIndex..<textString.endIndex, options: .byParagraphs) { _, _, _, _ in
                    maxLineNumber += 1
                }

                DispatchQueue.main.async { [weak self] in
                    self?.applySize(for: maxLineNumber)
                }
            }

        case .row:
            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      let textView = self.textView,
                      let layoutManager = textView.layoutManager,
                      let textContainer = textView.textContainer else {
                    return
                }

                var maxLineNumber = 0
                let glyphRange = layoutManager.glyphRange(for: textContainer)
                layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, _, _ in
                    maxLineNumber += 1
                }

                self.applySize(for: maxLineNumber)
            }
        }
    }

    private func applySize(for maxLineNumber: Int) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10)
        ]
        let numberString = "\(maxLineNumber)"

        if isVerticalLayout {
            // 縦書き時は高さを計算（上に配置）
            // 90度回転するので、文字列の幅が高さになる
            let size = (numberString as NSString).size(withAttributes: attributes)
            let requiredHeight = self.topMargin + size.width + self.bottomMargin
            let newHeight = max(self.minimumHeight, requiredHeight)

            if abs(self.currentHeight - newHeight) > 1.0 {
                self.currentHeight = newHeight
                NotificationCenter.default.post(name: LineNumberView.heightDidChangeNotification, object: self)
            }
        } else {
            // 横書き時は幅を計算（左に配置）
            let size = (numberString as NSString).size(withAttributes: attributes)
            let requiredWidth = self.leftMargin + size.width + self.rightMargin
            let newWidth = max(self.minimumWidth, requiredWidth)

            if abs(self.currentWidth - newWidth) > 1.0 {
                self.currentWidth = newWidth
                NotificationCenter.default.post(name: LineNumberView.widthDidChangeNotification, object: self)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 背景を描画
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()

        // 境界線を描画
        NSColor.separatorColor.setStroke()
        let borderPath = NSBezierPath()
        if isVerticalLayout {
            // 縦書き時は下端に境界線
            borderPath.move(to: NSPoint(x: bounds.minX, y: bounds.maxY - 0.5))
            borderPath.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY - 0.5))
        } else {
            // 横書き時は右端に境界線
            borderPath.move(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY))
            borderPath.line(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        }
        borderPath.lineWidth = 1.0
        borderPath.stroke()

        guard lineNumberMode != .none,
              let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let scrollView = scrollView else {
            return
        }

        let textStorage = layoutManager.textStorage!

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        // スクロールオフセットを取得
        let contentBounds = scrollView.contentView.bounds

        if isVerticalLayout {
            // 縦書き時の描画
            drawVerticalLayoutLineNumbers(
                layoutManager: layoutManager,
                textContainer: textContainer,
                textStorage: textStorage,
                textView: textView,
                contentBounds: contentBounds,
                attributes: attributes
            )
        } else {
            // 横書き時の描画
            let textViewVisibleRect = textView.visibleRect
            let glyphRange = layoutManager.glyphRange(forBoundingRect: textViewVisibleRect, in: textContainer)
            drawHorizontalLayoutLineNumbers(
                glyphRange: glyphRange,
                layoutManager: layoutManager,
                textContainer: textContainer,
                textStorage: textStorage,
                textView: textView,
                contentBounds: contentBounds,
                attributes: attributes,
                dirtyRect: dirtyRect
            )
        }
    }

    private func drawHorizontalLayoutLineNumbers(
        glyphRange: NSRange,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        textStorage: NSTextStorage,
        textView: NSTextView,
        contentBounds: CGRect,
        attributes: [NSAttributedString.Key: Any],
        dirtyRect: NSRect
    ) {
        switch lineNumberMode {
        case .none:
            break

        case .paragraph:
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            var paragraphNumber = 0
            var drawnParagraphs = Set<Int>()

            let searchRange = NSRange(location: 0, length: min(charRange.location + charRange.length, textStorage.length))
            guard let stringRange = Range(searchRange, in: textStorage.string) else { return }

            textStorage.string.enumerateSubstrings(in: stringRange, options: .byParagraphs) { (substring, substringRange, enclosingRange, stop) in
                paragraphNumber += 1

                let nsSubstringRange = NSRange(substringRange, in: textStorage.string)

                if nsSubstringRange.location >= charRange.location {
                    let glyphRange = layoutManager.glyphRange(forCharacterRange: nsSubstringRange, actualCharacterRange: nil)
                    let rectInContainer = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

                    // パラグラフの最初の行のlineFragmentRectを取得して行の高さを得る
                    let firstLineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)

                    let yInTextView = rectInContainer.minY + textView.textContainerInset.height
                    let yInLineNumberView = yInTextView - contentBounds.origin.y

                    if yInLineNumberView >= dirtyRect.minY - 20 && yInLineNumberView <= dirtyRect.maxY + 20 && !drawnParagraphs.contains(paragraphNumber) {
                        let numberString = "\(paragraphNumber)" as NSString
                        let size = numberString.size(withAttributes: attributes)
                        let xPosition = self.currentWidth - size.width - self.rightMargin
                        // 行の中央に配置
                        let yCenter = yInLineNumberView + (firstLineRect.height - size.height) / 2
                        let drawPoint = NSPoint(x: xPosition, y: yCenter)
                        numberString.draw(at: drawPoint, withAttributes: attributes)
                        drawnParagraphs.insert(paragraphNumber)
                    }
                }
            }

        case .row:
            var rowNumber = 0

            layoutManager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: glyphRange.location)) { _, _, _, _, _ in
                rowNumber += 1
            }

            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { (rectInContainer, usedRect, textContainer, glyphRange, stop) in
                rowNumber += 1

                let yInTextView = rectInContainer.minY + textView.textContainerInset.height
                let yInLineNumberView = yInTextView - contentBounds.origin.y

                let numberString = "\(rowNumber)" as NSString
                let size = numberString.size(withAttributes: attributes)
                let xPosition = self.currentWidth - size.width - self.rightMargin
                // 行の中央に配置
                let yCenter = yInLineNumberView + (rectInContainer.height - size.height) / 2
                let drawPoint = NSPoint(x: xPosition, y: yCenter)
                numberString.draw(at: drawPoint, withAttributes: attributes)
            }
        }
    }

    private func drawVerticalLayoutLineNumbers(
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        textStorage: NSTextStorage,
        textView: NSTextView,
        contentBounds: CGRect,
        attributes: [NSAttributedString.Key: Any]
    ) {
        // 縦書きでは列（行）が右から左に並ぶ
        // lineRect.origin.y = 0 が最初の列（右端）

        let fullGlyphRange = layoutManager.glyphRange(for: textContainer)
        let documentWidth = textView.frame.width
        let scrollX = contentBounds.origin.x

        switch lineNumberMode {
        case .none:
            break

        case .paragraph:
            var paragraphNumber = 0
            var drawnParagraphs = Set<Int>()

            let fullRange = textStorage.string.startIndex..<textStorage.string.endIndex

            textStorage.string.enumerateSubstrings(in: fullRange, options: .byParagraphs) { (substring, substringRange, enclosingRange, stop) in
                paragraphNumber += 1

                let nsSubstringRange = NSRange(substringRange, in: textStorage.string)
                let glyphRangeForPara = layoutManager.glyphRange(forCharacterRange: nsSubstringRange, actualCharacterRange: nil)

                if glyphRangeForPara.location < layoutManager.numberOfGlyphs {
                    let glyphIndex = glyphRangeForPara.location
                    let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)

                    // 縦書き：documentWidth - origin.y - height でドキュメント内のX位置（列の左端）を計算
                    let columnXInDocument = documentWidth - lineRect.origin.y - lineRect.height

                    // LineNumberView内の座標に変換（列の中央に合わせるためにheight/2を引く）
                    let xInLineNumberView = columnXInDocument - scrollX - lineRect.height / 2

                    if !drawnParagraphs.contains(paragraphNumber) {
                        self.drawVerticalNumber(paragraphNumber, at: xInLineNumberView, columnWidth: lineRect.height, attributes: attributes)
                        drawnParagraphs.insert(paragraphNumber)
                    }
                }
            }

        case .row:
            var rowNumber = 0

            layoutManager.enumerateLineFragments(forGlyphRange: fullGlyphRange) { [self] (lineRect, usedRect, textContainerParam, glyphRangeInFrag, stop) in
                rowNumber += 1

                // 縦書き：documentWidth - origin.y - height でドキュメント内のX位置（列の左端）を計算
                let columnXInDocument = documentWidth - lineRect.origin.y - lineRect.height

                // LineNumberView内の座標に変換（列の中央に合わせるためにheight/2を引く）
                let xInLineNumberView = columnXInDocument - scrollX - lineRect.height / 2

                self.drawVerticalNumber(rowNumber, at: xInLineNumberView, columnWidth: lineRect.height, attributes: attributes)
            }
        }
    }

    /// 縦書きの行番号を描画（横書き文字を90度回転、中央揃え）
    private func drawVerticalNumber(_ number: Int, at xPosition: CGFloat, columnWidth: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        let numberString = "\(number)" as NSString
        let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 10)
        let charAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: attributes[.foregroundColor] ?? NSColor.secondaryLabelColor
        ]

        // 文字列のサイズを計算
        let stringSize = numberString.size(withAttributes: charAttributes)

        // 回転後：幅と高さが入れ替わる
        let rotatedWidth = stringSize.height
        let rotatedHeight = stringSize.width

        // 中央揃え：ビューの中央に配置
        let yPosition = (self.bounds.height - rotatedHeight) / 2

        // 列の中央にX位置を配置
        let xCenter = xPosition + (columnWidth - rotatedWidth) / 2

        // グラフィックスコンテキストを保存
        NSGraphicsContext.current?.saveGraphicsState()

        // 回転の中心点に移動して90度回転（反時計回り）
        let transform = NSAffineTransform()
        transform.translateX(by: xCenter + rotatedWidth / 2, yBy: yPosition + rotatedHeight / 2)
        transform.rotate(byDegrees: 90)
        transform.translateX(by: -stringSize.width / 2, yBy: -stringSize.height / 2)
        transform.concat()

        // 文字列を描画（原点に）
        numberString.draw(at: NSPoint.zero, withAttributes: charAttributes)

        // グラフィックスコンテキストを復元
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
