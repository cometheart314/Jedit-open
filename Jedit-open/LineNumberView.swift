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

    /// 行番号の文字色
    var lineNumberColor: NSColor = NSColor.secondaryLabelColor {
        didSet {
            needsDisplay = true
        }
    }

    /// 行番号ビューの背景色
    var lineNumberBackgroundColor: NSColor = NSColor.controlBackgroundColor {
        didSet {
            needsDisplay = true
        }
    }

    /// 現在の拡大率（ScalingScrollViewから取得）
    private var magnification: CGFloat = 1.0

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
    private var magnificationObserver: Any?

    // サイズ変更通知
    static let widthDidChangeNotification = Notification.Name("LineNumberViewWidthDidChange")
    static let heightDidChangeNotification = Notification.Name("LineNumberViewHeightDidChange")

    // 現在のサイズ
    private(set) var currentWidth: CGFloat = 40.0
    private(set) var currentHeight: CGFloat = 25.0

    // MARK: - パラグラフキャッシュ
    // 各パラグラフの開始文字位置を保持する配列（インデックス0 = パラグラフ1の開始位置）
    // テキスト変更時にのみ再構築し、draw()時にはバイナリサーチで高速に番号を特定する
    private var paragraphStartLocations: [Int] = []
    private var paragraphCacheVersion: Int = 0
    private var lastKnownTextLength: Int = -1

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

    // MARK: - パラグラフキャッシュ管理

    /// パラグラフの開始位置キャッシュを再構築する
    /// テキスト変更時にのみ呼び出される（draw()からは呼ばない）
    private func rebuildParagraphCacheIfNeeded() {
        guard lineNumberMode != .none else { return }
        guard let textView = textView,
              let textStorage = textView.textStorage else { return }

        let currentLength = textStorage.length
        if currentLength == lastKnownTextLength { return }
        lastKnownTextLength = currentLength

        let textString = textStorage.string
        // バックグラウンドスレッドで構築（大きなファイル対応）
        let version = paragraphCacheVersion + 1
        paragraphCacheVersion = version

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var locations: [Int] = []
            textString.enumerateSubstrings(
                in: textString.startIndex..<textString.endIndex,
                options: .byParagraphs
            ) { _, substringRange, _, _ in
                let nsRange = NSRange(substringRange, in: textString)
                locations.append(nsRange.location)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // 古いバージョンの結果は捨てる
                if self.paragraphCacheVersion == version {
                    self.paragraphStartLocations = locations
                    self.needsDisplay = true
                }
            }
        }
    }

    /// キャッシュを無効化する
    private func invalidateParagraphCache() {
        lastKnownTextLength = -1
    }

    /// 指定した文字位置が属するパラグラフ番号を返す（1始まり）
    /// バイナリサーチでO(log n)
    private func paragraphNumber(forCharacterAt location: Int) -> Int {
        let locations = paragraphStartLocations
        if locations.isEmpty { return 1 }

        // upperBound: locationより大きい最初の要素のインデックスを探す
        var lo = 0
        var hi = locations.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if locations[mid] <= location {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo  // 1始まりのパラグラフ番号（loは「location以下の要素数」）
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
        if let observer = magnificationObserver {
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
        if let observer = magnificationObserver {
            NotificationCenter.default.removeObserver(observer)
            magnificationObserver = nil
        }

        guard let textView = textView,
              let scrollView = textView.enclosingScrollView else { return }

        self.scrollView = scrollView

        // 初期magnificationを取得
        if let scalingScrollView = scrollView as? ScalingScrollView {
            self.magnification = scalingScrollView.magnification
        }

        // magnification変更通知を監視
        magnificationObserver = NotificationCenter.default.addObserver(
            forName: ScalingScrollView.magnificationDidChangeNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] notification in
            if let mag = notification.userInfo?["magnification"] as? CGFloat {
                self?.magnification = mag
                // magnification変更時にサイズを再計算
                self?.updateSizeAsync()
                self?.needsDisplay = true
            }
        }

        // スクロール時に再描画
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        }

        // テキスト変更時に幅を再計算＋パラグラフキャッシュを再構築
        textChangeObserver = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            self?.invalidateParagraphCache()
            self?.rebuildParagraphCacheIfNeeded()
            self?.debounceUpdateSize()
        }

        // テキストストレージの属性変更時（フォントサイズ変更など）に再描画
        if let textStorage = textView.textStorage {
            textStorageObserver = NotificationCenter.default.addObserver(
                forName: NSTextStorage.didProcessEditingNotification,
                object: textStorage,
                queue: .main
            ) { [weak self] _ in
                self?.invalidateParagraphCache()
                self?.rebuildParagraphCacheIfNeeded()
                // 即時再描画
                self?.needsDisplay = true
                // レイアウトが確定するまで待ってから再描画
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.needsDisplay = true
                }
            }
        }

        // 初期サイズを計算＋パラグラフキャッシュを構築
        DispatchQueue.main.async { [weak self] in
            self?.rebuildParagraphCacheIfNeeded()
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
              let textStorage = layoutManager.textStorage,
              textView.textContainer != nil else {
            return
        }
        let mode = lineNumberMode

        switch mode {
        case .none:
            break

        case .paragraph:
            // キャッシュがあればそこからパラグラフ数を取得（O(1)）
            if !paragraphStartLocations.isEmpty {
                let maxLineNumber = paragraphStartLocations.count
                applySize(for: maxLineNumber)
            } else {
                // キャッシュ未構築時はバックグラウンドでカウント
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
        // magnificationを適用したフォントサイズでサイズを計算
        let scaledFontSize: CGFloat = 10 * magnification
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: scaledFontSize)
        ]
        let numberString = "\(maxLineNumber)"

        if isVerticalLayout {
            // 縦書き時は高さを計算（上に配置）
            // 90度回転するので、文字列の幅が高さになる
            let size = (numberString as NSString).size(withAttributes: attributes)
            let scaledTopMargin = self.topMargin * magnification
            let scaledBottomMargin = self.bottomMargin * magnification
            let requiredHeight = scaledTopMargin + size.width + scaledBottomMargin
            let scaledMinHeight = self.minimumHeight * magnification
            let newHeight = max(scaledMinHeight, requiredHeight)

            if abs(self.currentHeight - newHeight) > 1.0 {
                self.currentHeight = newHeight
                NotificationCenter.default.post(name: LineNumberView.heightDidChangeNotification, object: self)
            }
        } else {
            // 横書き時は幅を計算（左に配置）
            let size = (numberString as NSString).size(withAttributes: attributes)
            let scaledLeftMargin = self.leftMargin * magnification
            let scaledRightMargin = self.rightMargin * magnification
            let requiredWidth = scaledLeftMargin + size.width + scaledRightMargin
            let scaledMinWidth = self.minimumWidth * magnification
            let newWidth = max(scaledMinWidth, requiredWidth)

            if abs(self.currentWidth - newWidth) > 1.0 {
                self.currentWidth = newWidth
                NotificationCenter.default.post(name: LineNumberView.widthDidChangeNotification, object: self)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 背景を描画
        lineNumberBackgroundColor.setFill()
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
              let textStorage = layoutManager.textStorage,
              let textContainer = textView.textContainer,
              let scrollView = scrollView else {
            return
        }

        // magnificationを適用したフォントサイズ
        let scaledFontSize: CGFloat = 10 * magnification
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: scaledFontSize),
            .foregroundColor: lineNumberColor
        ]

        // スクロールオフセットを取得
        let contentBounds = scrollView.contentView.bounds

        // 可視範囲のglyphRangeを計算（横書き・縦書き共通）
        let textViewVisibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: textViewVisibleRect, in: textContainer)

        if isVerticalLayout {
            // 縦書き時の描画
            drawVerticalLayoutLineNumbers(
                glyphRange: glyphRange,
                layoutManager: layoutManager,
                textContainer: textContainer,
                textStorage: textStorage,
                textView: textView,
                contentBounds: contentBounds,
                attributes: attributes
            )
        } else {
            // 横書き時の描画
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
            // キャッシュが未構築の場合は構築を開始して次回描画を待つ
            if paragraphStartLocations.isEmpty {
                rebuildParagraphCacheIfNeeded()
                return
            }

            let mag = self.magnification
            // textContainerInsetはテキストコンテナ座標系の値
            let containerInsetY = textView.textContainerInset.height
            // contentBounds.origin.yはdocumentView座標系（magnification前）の値
            let scrollOffset = contentBounds.origin.y

            // 可視範囲のlineFragmentを列挙し、各行の先頭文字位置からパラグラフ番号を特定する
            var drawnParagraphs = Set<Int>()

            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { (rectInContainer, usedRect, textContainerParam, glyphRangeInFrag, stop) in
                // この行の先頭文字位置を取得
                let charIndex = layoutManager.characterIndexForGlyph(at: glyphRangeInFrag.location)

                // キャッシュからO(log n)でパラグラフ番号を特定
                let paraNum = self.paragraphNumber(forCharacterAt: charIndex)

                // 同じパラグラフ番号は1回だけ描画（折り返し行では2行目以降をスキップ）
                guard !drawnParagraphs.contains(paraNum) else { return }
                drawnParagraphs.insert(paraNum)

                // テキストコンテナ座標をテキストビュー座標に変換
                let yInTextView = rectInContainer.minY + containerInsetY

                // テキストビュー座標からLineNumberView座標に変換
                let yInLineNumberView = (yInTextView - scrollOffset) * mag

                let scaledLineHeight = rectInContainer.height * mag

                if yInLineNumberView >= dirtyRect.minY - 20 * mag && yInLineNumberView <= dirtyRect.maxY + 20 * mag {
                    let numberString = "\(paraNum)" as NSString
                    let size = numberString.size(withAttributes: attributes)
                    let scaledRightMargin = self.rightMargin * mag
                    let xPosition = self.currentWidth - size.width - scaledRightMargin
                    // 行の中央に配置（スケーリングされた行の高さを使用）
                    let yCenter = yInLineNumberView + (scaledLineHeight - size.height) / 2
                    let drawPoint = NSPoint(x: xPosition, y: yCenter)
                    numberString.draw(at: drawPoint, withAttributes: attributes)
                }
            }

        case .row:
            var rowNumber = 0
            let mag = self.magnification
            // textContainerInsetはテキストコンテナ座標系の値
            let containerInsetY = textView.textContainerInset.height

            // contentBounds.origin.yはdocumentView座標系（magnification前）の値
            let scrollOffset = contentBounds.origin.y

            layoutManager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: glyphRange.location)) { _, _, _, _, _ in
                rowNumber += 1
            }

            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { (rectInContainer, usedRect, textContainerParam, glyphRangeParam, stop) in
                rowNumber += 1

                // テキストコンテナ座標をテキストビュー座標に変換
                let yInTextView = rectInContainer.minY + containerInsetY

                // テキストビュー座標からLineNumberView座標に変換
                // scrollOffsetはdocumentView座標なのでそのまま引き、結果にmagnificationを適用
                let yInLineNumberView = (yInTextView - scrollOffset) * mag

                let scaledLineHeight = rectInContainer.height * mag

                let numberString = "\(rowNumber)" as NSString
                let size = numberString.size(withAttributes: attributes)
                let scaledRightMargin = self.rightMargin * mag
                let xPosition = self.currentWidth - size.width - scaledRightMargin
                // 行の中央に配置（スケーリングされた行の高さを使用）
                let yCenter = yInLineNumberView + (scaledLineHeight - size.height) / 2
                let drawPoint = NSPoint(x: xPosition, y: yCenter)
                numberString.draw(at: drawPoint, withAttributes: attributes)
            }
        }
    }

    private func drawVerticalLayoutLineNumbers(
        glyphRange: NSRange,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        textStorage: NSTextStorage,
        textView: NSTextView,
        contentBounds: CGRect,
        attributes: [NSAttributedString.Key: Any]
    ) {
        // 縦書きでは列（行）が右から左に並ぶ
        // lineRect.origin.y = 0 が最初の列（右端）

        let documentWidth = textView.frame.width
        let mag = self.magnification
        // contentBounds.origin.xはdocumentView座標系（magnification前）の値
        let scrollOffsetX = contentBounds.origin.x

        switch lineNumberMode {
        case .none:
            break

        case .paragraph:
            // キャッシュが未構築の場合は構築を開始して次回描画を待つ
            if paragraphStartLocations.isEmpty {
                rebuildParagraphCacheIfNeeded()
                return
            }

            // 可視範囲のlineFragmentのみ列挙し、キャッシュからパラグラフ番号を特定する
            var drawnParagraphs = Set<Int>()

            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { [self] (lineRect, usedRect, textContainerParam, glyphRangeInFrag, stop) in
                let charIndex = layoutManager.characterIndexForGlyph(at: glyphRangeInFrag.location)
                let paraNum = self.paragraphNumber(forCharacterAt: charIndex)

                guard !drawnParagraphs.contains(paraNum) else { return }
                drawnParagraphs.insert(paraNum)

                let scaledColumnWidth = lineRect.height * mag

                // 縦書き：documentWidth - origin.y - height でドキュメント内のX位置（列の左端）を計算
                // textView座標系でのX位置
                let xInTextView = documentWidth - lineRect.origin.y - lineRect.height
                // スクロールオフセットを引いてからmagnificationを適用
                let xInLineNumberView = (xInTextView - scrollOffsetX) * mag - scaledColumnWidth / 2

                self.drawVerticalNumber(paraNum, at: xInLineNumberView, columnWidth: scaledColumnWidth, attributes: attributes)
            }

        case .row:
            // 可視範囲「前」の行数をカウント（横書きと同じアプローチ）
            var rowNumber = 0
            layoutManager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: glyphRange.location)) { _, _, _, _, _ in
                rowNumber += 1
            }

            // 可視範囲のlineFragmentのみ描画
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { [self] (lineRect, usedRect, textContainerParam, glyphRangeInFrag, stop) in
                rowNumber += 1

                let scaledColumnWidth = lineRect.height * mag

                // 縦書き：documentWidth - origin.y - height でドキュメント内のX位置（列の左端）を計算
                // textView座標系でのX位置
                let xInTextView = documentWidth - lineRect.origin.y - lineRect.height
                // スクロールオフセットを引いてからmagnificationを適用
                let xInLineNumberView = (xInTextView - scrollOffsetX) * mag - scaledColumnWidth / 2

                self.drawVerticalNumber(rowNumber, at: xInLineNumberView, columnWidth: scaledColumnWidth, attributes: attributes)
            }
        }
    }

    /// 縦書きの行番号を描画（横書き文字を90度回転、中央揃え）
    private func drawVerticalNumber(_ number: Int, at xPosition: CGFloat, columnWidth: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        let numberString = "\(number)" as NSString
        let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 10)
        let charAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: attributes[.foregroundColor] ?? lineNumberColor
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

    // MARK: - Context Menu

    override func mouseDown(with event: NSEvent) {
        // クリック位置を取得
        let location = convert(event.locationInWindow, from: nil)

        // ビュー内であればメニューを表示
        if bounds.contains(location) {
            showLineNumberMenu(at: location, with: event)
        } else {
            super.mouseDown(with: event)
        }
    }

    /// 行番号表示モードを選択するメニューを表示
    private func showLineNumberMenu(at location: NSPoint, with event: NSEvent) {
        let menu = NSMenu(title: "Line Number")

        // None
        let noneItem = NSMenuItem(
            title: "None".localized,
            action: #selector(setLineNumberModeNone(_:)),
            keyEquivalent: ""
        )
        noneItem.target = self
        noneItem.state = (lineNumberMode == .none) ? .on : .off
        menu.addItem(noneItem)

        // Paragraph Number
        let paragraphItem = NSMenuItem(
            title: "Paragraph Number".localized,
            action: #selector(setLineNumberModeParagraph(_:)),
            keyEquivalent: ""
        )
        paragraphItem.target = self
        paragraphItem.state = (lineNumberMode == .paragraph) ? .on : .off
        menu.addItem(paragraphItem)

        // Row Number
        let rowItem = NSMenuItem(
            title: "Row Number".localized,
            action: #selector(setLineNumberModeRow(_:)),
            keyEquivalent: ""
        )
        rowItem.target = self
        rowItem.state = (lineNumberMode == .row) ? .on : .off
        menu.addItem(rowItem)

        // メニューを表示
        menu.popUp(positioning: nil, at: location, in: self)
    }

    @objc private func setLineNumberModeNone(_ sender: Any?) {
        setLineNumberModeAndNotify(.none)
    }

    @objc private func setLineNumberModeParagraph(_ sender: Any?) {
        setLineNumberModeAndNotify(.paragraph)
    }

    @objc private func setLineNumberModeRow(_ sender: Any?) {
        setLineNumberModeAndNotify(.row)
    }

    /// 行番号モードを設定し、変更を通知
    private func setLineNumberModeAndNotify(_ mode: LineNumberMode) {
        lineNumberMode = mode

        // EditorWindowControllerに変更を通知してpresetDataに保存
        NotificationCenter.default.post(
            name: LineNumberView.lineNumberModeDidChangeNotification,
            object: self,
            userInfo: ["mode": mode]
        )
    }

    // 行番号モード変更通知
    static let lineNumberModeDidChangeNotification = Notification.Name("LineNumberViewLineNumberModeDidChange")
}
