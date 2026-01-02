//
//  EditorWindowController.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/26.
//

import Cocoa

// MARK: - Flipped Container View

class FlippedContainerView: NSView {
    override var isFlipped: Bool {
        return true
    }
}

// MARK: - Line Number Ruler View

class LineNumberRulerView: NSRulerView {
    var lineNumberMode: LineNumberMode = .none {
        didSet {
            updateRuleThicknessAsync()
            needsDisplay = true
        }
    }

    weak var textView: NSTextView?
    private let minimumThickness: CGFloat = 40.0
    private let rightMargin: CGFloat = 5.0
    private let leftMargin: CGFloat = 5.0
    private var updateWorkItem: DispatchWorkItem?

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = minimumThickness

        // macOSのNSRulerViewのバグ回避: clipsToBoundsを設定
        self.clipsToBounds = true

        // テキスト変更時にルーラーの幅を再計算
        NotificationCenter.default.addObserver(self, selector: #selector(textDidChange), name: NSText.didChangeNotification, object: textView)

        // 初期表示時にもルーラーの幅を計算
        DispatchQueue.main.async { [weak self] in
            self?.updateRuleThicknessAsync()
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        updateWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func textDidChange(_ notification: Notification) {
        // デバウンス: 連続した変更を防ぐため、前のタスクをキャンセル
        updateWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.updateRuleThicknessAsync()
        }
        updateWorkItem = workItem

        // 0.3秒後に実行（タイピング中の連続更新を防ぐ）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func updateRuleThicknessAsync() {
        guard lineNumberMode != .none,
              let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        let textStorage = layoutManager.textStorage!
        let mode = lineNumberMode

        switch mode {
        case .none:
            break

        case .paragraph:
            // パラグラフ数のカウントはバックグラウンドで実行可能（文字列のみを使用）
            let textString = textStorage.string
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }

                var maxLineNumber = 0
                textString.enumerateSubstrings(in: textString.startIndex..<textString.endIndex, options: .byParagraphs) { _, _, _, _ in
                    maxLineNumber += 1
                }

                // UIの更新はメインスレッドで実行
                DispatchQueue.main.async { [weak self] in
                    self?.applyRuleThickness(for: maxLineNumber)
                }
            }

        case .row:
            // LayoutManagerへのアクセスはメインスレッドでのみ可能
            // 非同期で実行してUIをブロックしないようにする
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

                self.applyRuleThickness(for: maxLineNumber)
            }
        }
    }

    private func applyRuleThickness(for maxLineNumber: Int) {
        // 最大行番号の幅を計算
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10)
        ]
        let numberString = "\(maxLineNumber)" as NSString
        let size = numberString.size(withAttributes: attributes)

        // 必要な幅を計算（左マージン + 数字の幅 + 右マージン）
        let requiredThickness = self.leftMargin + size.width + self.rightMargin
        let newThickness = max(self.minimumThickness, requiredThickness)

        if abs(self.ruleThickness - newThickness) > 1.0 {
            self.ruleThickness = newThickness
            // スクロールビューのレイアウトを更新
            if let scrollView = self.scrollView as? NSScrollView,
               let textView = textView,
               let textContainer = textView.textContainer {
                scrollView.tile()

                // textViewとtextContainerのサイズも更新
                textView.frame = scrollView.contentView.bounds
                textContainer.containerSize = NSSize(width: scrollView.contentView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
            }
        }
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        // 背景を常に描画
        NSColor.controlBackgroundColor.setFill()
        rect.fill()

        guard lineNumberMode != .none,
              let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        let textStorage = layoutManager.textStorage!
        let visibleRect = self.convert(textView.visibleRect, from: textView)

        // 右端に境界線を描画
        NSColor.separatorColor.setStroke()
        let borderPath = NSBezierPath()
        borderPath.move(to: NSPoint(x: rect.maxX - 0.5, y: rect.minY))
        borderPath.line(to: NSPoint(x: rect.maxX - 0.5, y: rect.maxY))
        borderPath.lineWidth = 1.0
        borderPath.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        // textViewの可視範囲内のglyphRangeを取得
        let textViewVisibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: textViewVisibleRect, in: textContainer)

        switch lineNumberMode {
        case .none:
            break

        case .paragraph:
            // パラグラフ番号を表示
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

                    // textContainerの座標をtextViewの座標に変換
                    let rectInTextView = NSRect(
                        x: rectInContainer.minX + textView.textContainerInset.width,
                        y: rectInContainer.minY + textView.textContainerInset.height,
                        width: rectInContainer.width,
                        height: rectInContainer.height
                    )

                    // textViewの座標をrulerViewの座標に変換
                    let rectInRuler = self.convert(rectInTextView, from: textView)

                    if rectInRuler.minY >= rect.minY && rectInRuler.minY <= rect.maxY && !drawnParagraphs.contains(paragraphNumber) {
                        let numberString = "\(paragraphNumber)" as NSString
                        let size = numberString.size(withAttributes: attributes)
                        let xPosition = self.ruleThickness - size.width - self.rightMargin
                        let drawPoint = NSPoint(x: xPosition, y: rectInRuler.minY)
                        numberString.draw(at: drawPoint, withAttributes: attributes)
                        drawnParagraphs.insert(paragraphNumber)
                    }
                }
            }

        case .row:
            // 行番号（折り返しを含む）を表示
            var rowNumber = 0

            // 可視範囲の前の行数を計算
            layoutManager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: glyphRange.location)) { _, _, _, _, _ in
                rowNumber += 1
            }

            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { (rectInContainer, usedRect, textContainer, glyphRange, stop) in
                rowNumber += 1

                // textContainerの座標をtextViewの座標に変換
                let rectInTextView = NSRect(
                    x: rectInContainer.minX + textView.textContainerInset.width,
                    y: rectInContainer.minY + textView.textContainerInset.height,
                    width: rectInContainer.width,
                    height: rectInContainer.height
                )

                // textViewの座標をrulerViewの座標に変換
                let rectInRuler = self.convert(rectInTextView, from: textView)

                let numberString = "\(rowNumber)" as NSString
                let size = numberString.size(withAttributes: attributes)
                let xPosition = self.ruleThickness - size.width - self.rightMargin
                let drawPoint = NSPoint(x: xPosition, y: rectInRuler.minY)
                numberString.draw(at: drawPoint, withAttributes: attributes)
            }
        }
    }
}

// MARK: - Display Mode

enum DisplayMode {
    case continuous  // 通常モード（連続スクロール）
    case page        // ページモード（ページネーション）
}

// MARK: - Line Number Mode

enum LineNumberMode {
    case none        // 行番号非表示
    case paragraph   // パラグラフ番号
    case row         // 行番号（折り返しを含む）
}

class EditorWindowController: NSWindowController, NSLayoutManagerDelegate, NSSplitViewDelegate {

    // MARK: - IBOutlets

    @IBOutlet weak var splitView: NSSplitView!
    @IBOutlet weak var scrollView2: ScalingScrollView!
    @IBOutlet weak var scrollView1: ScalingScrollView!

    // MARK: - Properties

    var textDocument: Document? {
        return document as? Document
    }

    private var isSplitViewCollapsed: Bool = false

    // 表示モード
    private var displayMode: DisplayMode = .continuous
    private var lineNumberMode: LineNumberMode = .none

    // 行番号ルーラー
    private var rulerView1: LineNumberRulerView?
    private var rulerView2: LineNumberRulerView?

    // ページネーション関連
    private var layoutManager1: NSLayoutManager?
    private var layoutManager2: NSLayoutManager?
    private var textContainers1: [NSTextContainer] = []
    private var textViews1: [NSTextView] = []
    private var textContainers2: [NSTextContainer] = []
    private var textViews2: [NSTextView] = []
    private var containerView1: FlippedContainerView?
    private var containerView2: FlippedContainerView?

    // ページ設定
    private let pageWidth: CGFloat = 595.0  // A4サイズ相当（ポイント）
    private let pageHeight: CGFloat = 842.0 // A4サイズ相当（ポイント）
    private let pageMargin: CGFloat = 72.0  // 1インチ（72ポイント）のマージン
    private let pageSpacing: CGFloat = 20.0 // ページ間のスペース
    private let headerHeight: CGFloat = 30.0 // ヘッダーの高さ
    private let footerHeight: CGFloat = 30.0 // フッターの高さ

    // MARK: - Window Lifecycle

    override func windowDidLoad() {
        super.windowDidLoad()

        // SplitViewのデリゲートを設定
        splitView?.delegate = self

        // TextStorageを設定
        setupTextStorage()
    }

    // MARK: - Setup Methods

    func setupTextStorage() {
        guard let textDocument = self.textDocument else {
            return
        }

        setupTextViews(with: textDocument.textStorage)
    }

    func setupTextViews(with textStorage: NSTextStorage) {
        // 既存のLayoutManagerを削除
        if textStorage.layoutManagers.count > 0 {
            for lm in textStorage.layoutManagers {
                textStorage.removeLayoutManager(lm)
            }
        }

        // 既存のページとlayoutManagerをクリア
        layoutManager1 = nil
        layoutManager2 = nil
        textContainers1.removeAll()
        textViews1.removeAll()
        textContainers2.removeAll()
        textViews2.removeAll()
        containerView1 = nil
        containerView2 = nil

        // 表示モードに応じてセットアップ
        switch displayMode {
        case .continuous:
            setupContinuousMode(with: textStorage)
        case .page:
            setupPageMode(with: textStorage)
        }
    }

    private func setupContinuousMode(with textStorage: NSTextStorage) {
        // splitViewの表示されているサブビューの数を取得
        guard let splitView = splitView else { return }
        let visibleSubviews = splitView.subviews.filter { !$0.isHidden }
        let numberOfViews = visibleSubviews.count

        // 必要な数のLayoutManagerを作成
        var layoutManagers: [NSLayoutManager] = []
        for _ in 0..<numberOfViews {
            let layoutManager = NSLayoutManager()
            textStorage.addLayoutManager(layoutManager)
            layoutManagers.append(layoutManager)
        }

        // TextView1の設定（常に設定）
        if numberOfViews >= 1, let scrollView = scrollView1 {
            let width = scrollView.contentSize.width

            // TextContainerを作成
            let textContainer = NSTextContainer(containerSize: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false

            // LayoutManagerにTextContainerを追加
            let layoutManager = layoutManagers[0]
            layoutManager.addTextContainer(textContainer)

            // TextViewを作成
            let textView = NSTextView(frame: scrollView.bounds, textContainer: textContainer)
            textView.isEditable = true
            textView.isSelectable = true
            textView.allowsUndo = true
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = true
            textView.autoresizingMask = [.width]
            textView.textContainerInset = textDocument!.containerInset
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

            // ScrollViewに設定
            scrollView.documentView = textView
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true

            // 行番号ルーラーを設定
            if lineNumberMode != .none {
                let rulerView = LineNumberRulerView(scrollView: scrollView, textView: textView)
                rulerView.lineNumberMode = lineNumberMode
                scrollView.verticalRulerView = rulerView
                scrollView.hasVerticalRuler = true
                scrollView.rulersVisible = true
                rulerView1 = rulerView

                // レイアウトを更新
                scrollView.tile()

                // textViewのframeを更新（autoresizingMaskだけでは不十分な場合がある）
                textView.frame = scrollView.contentView.bounds

                // textContainerのサイズも更新
                textContainer.containerSize = NSSize(width: scrollView.contentView.bounds.width, height: CGFloat.greatestFiniteMagnitude)

                // テキスト変更時とスクロール時にrulerViewを更新
                NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: textView, queue: .main) { [weak rulerView] _ in
                    rulerView?.needsDisplay = true
                }
                NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak rulerView] _ in
                    rulerView?.needsDisplay = true
                }
            } else {
                scrollView.hasVerticalRuler = false
                scrollView.rulersVisible = false
                scrollView.verticalRulerView = nil
                rulerView1 = nil

                // レイアウトを更新
                scrollView.tile()

                // textViewのframeを更新
                textView.frame = scrollView.contentView.bounds

                // textContainerのサイズも更新
                textContainer.containerSize = NSSize(width: scrollView.contentView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
            }
        }

        // TextView2の設定（サブビューが2つ以上の場合のみ）
        if numberOfViews >= 2, let scrollView = scrollView2 {
            let width = scrollView.contentSize.width

            // TextContainerを作成
            let textContainer = NSTextContainer(containerSize: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false

            // LayoutManagerにTextContainerを追加
            let layoutManager = layoutManagers[1]
            layoutManager.addTextContainer(textContainer)

            // TextViewを作成
            let textView = NSTextView(frame: scrollView.bounds, textContainer: textContainer)
            textView.isEditable = true
            textView.isSelectable = true
            textView.allowsUndo = true
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = true
            textView.autoresizingMask = [.width]
            textView.textContainerInset = textDocument!.containerInset
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

            // ScrollViewに設定
            scrollView.documentView = textView
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true

            // 行番号ルーラーを設定
            if lineNumberMode != .none {
                let rulerView = LineNumberRulerView(scrollView: scrollView, textView: textView)
                rulerView.lineNumberMode = lineNumberMode
                scrollView.verticalRulerView = rulerView
                scrollView.hasVerticalRuler = true
                scrollView.rulersVisible = true
                rulerView2 = rulerView

                // レイアウトを更新
                scrollView.tile()

                // textViewのframeを更新（autoresizingMaskだけでは不十分な場合がある）
                textView.frame = scrollView.contentView.bounds

                // textContainerのサイズも更新
                textContainer.containerSize = NSSize(width: scrollView.contentView.bounds.width, height: CGFloat.greatestFiniteMagnitude)

                // テキスト変更時とスクロール時にrulerViewを更新
                NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: textView, queue: .main) { [weak rulerView] _ in
                    rulerView?.needsDisplay = true
                }
                NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak rulerView] _ in
                    rulerView?.needsDisplay = true
                }
            } else {
                scrollView.hasVerticalRuler = false
                scrollView.rulersVisible = false
                scrollView.verticalRulerView = nil
                rulerView2 = nil

                // レイアウトを更新
                scrollView.tile()

                // textViewのframeを更新
                textView.frame = scrollView.contentView.bounds

                // textContainerのサイズも更新
                textContainer.containerSize = NSSize(width: scrollView.contentView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
            }
        }
    }

    private func setupPageMode(with textStorage: NSTextStorage) {
        // splitViewの表示されているサブビューの数を取得
        guard let splitView = splitView else { return }
        let visibleSubviews = splitView.subviews.filter { !$0.isHidden }
        let numberOfViews = visibleSubviews.count

        // 必要な数のLayoutManagerを作成（まだTextStorageには追加しない）
        var layoutManagers: [NSLayoutManager] = []
        for _ in 0..<numberOfViews {
            let layoutManager = NSLayoutManager()
            layoutManagers.append(layoutManager)
        }

        // TextView1の設定（常に設定）
        if numberOfViews >= 1, let scrollView = scrollView1 {
            let layoutManager = layoutManagers[0]
            layoutManager1 = layoutManager  // 保存

            // 初期ページを追加
            addPage(to: layoutManager, in: scrollView, for: .scrollView1)

            // ScrollViewの設定
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true

            // デリゲートを設定してからTextStorageに追加
            layoutManager.delegate = self
            textStorage.addLayoutManager(layoutManager)
        }

        // TextView2の設定（サブビューが2つ以上の場合のみ）
        if numberOfViews >= 2, let scrollView = scrollView2 {
            let layoutManager = layoutManagers[1]
            layoutManager2 = layoutManager  // 保存

            // 初期ページを追加
            addPage(to: layoutManager, in: scrollView, for: .scrollView2)

            // ScrollViewの設定
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true

            // デリゲートを設定してからTextStorageに追加
            layoutManager.delegate = self
            textStorage.addLayoutManager(layoutManager)
        }
    }

    // MARK: - Zoom Actions

    @IBAction func zoomIn(_ sender: Any?) {
        scrollView1?.zoomIn()
        scrollView2?.zoomIn()
    }

    @IBAction func zoomOut(_ sender: Any?) {
        scrollView1?.zoomOut()
        scrollView2?.zoomOut()
    }

    @IBAction func resetZoom(_ sender: Any?) {
        scrollView1?.resetZoom()
        scrollView2?.resetZoom()
    }

    // MARK: - Split View Actions

    @IBAction func toggleSplitView(_ sender: Any?) {
        guard let splitView = splitView else { return }

        isSplitViewCollapsed = !isSplitViewCollapsed

        if isSplitViewCollapsed {
            // 2つ目のペインを折りたたむ
            if splitView.subviews.count > 1 {
                splitView.subviews[1].isHidden = true
            }
        } else {
            // 2つ目のペインを展開
            if splitView.subviews.count > 1 {
                splitView.subviews[1].isHidden = false
            }
        }

        splitView.adjustSubviews()

        // splitViewの状態に合わせてtextViewsを再設定
        if let textDocument = self.textDocument {
            setupTextViews(with: textDocument.textStorage)
        }
    }

    // MARK: - Display Mode Actions

    @IBAction func toggleDisplayMode(_ sender: Any?) {
        // モードを切り替え
        switch displayMode {
        case .continuous:
            displayMode = .page
        case .page:
            displayMode = .continuous
        }

        // TextViewsを再設定
        if let textDocument = self.textDocument {
            setupTextViews(with: textDocument.textStorage)
        }
    }

    @IBAction func switchToContinuousMode(_ sender: Any?) {
        displayMode = .continuous
        if let textDocument = self.textDocument {
            setupTextViews(with: textDocument.textStorage)
        }
    }

    @IBAction func switchToPageMode(_ sender: Any?) {
        displayMode = .page
        if let textDocument = self.textDocument {
            setupTextViews(with: textDocument.textStorage)
        }
    }

    // MARK: - Line Number Actions

    @IBAction func toggleLineNumberMode(_ sender: Any?) {
        // モードを順番に切り替え: none -> paragraph -> row -> none
        switch lineNumberMode {
        case .none:
            lineNumberMode = .paragraph
        case .paragraph:
            lineNumberMode = .row
        case .row:
            lineNumberMode = .none
        }

        updateLineNumberDisplay()
    }

    @IBAction func hideLineNumbers(_ sender: Any?) {
        lineNumberMode = .none
        updateLineNumberDisplay()
    }

    @IBAction func showParagraphNumbers(_ sender: Any?) {
        lineNumberMode = .paragraph
        updateLineNumberDisplay()
    }

    @IBAction func showRowNumbers(_ sender: Any?) {
        lineNumberMode = .row
        updateLineNumberDisplay()
    }

    private func updateLineNumberDisplay() {
        // 通常モードの場合のみ行番号を更新
        guard displayMode == .continuous else { return }

        // scrollView1の行番号を更新
        if let scrollView = scrollView1,
           let textView = scrollView.documentView as? NSTextView {
            updateRulerView(for: scrollView, textView: textView, rulerRef: &rulerView1)
        }

        // scrollView2の行番号を更新（splitViewが表示されている場合）
        if let scrollView = scrollView2,
           !scrollView.isHidden,
           let textView = scrollView.documentView as? NSTextView {
            updateRulerView(for: scrollView, textView: textView, rulerRef: &rulerView2)
        }
    }

    private func updateRulerView(for scrollView: NSScrollView, textView: NSTextView, rulerRef: inout LineNumberRulerView?) {
        if lineNumberMode != .none {
            // 既存のrulerViewがあれば削除
            if let existingRuler = rulerRef {
                scrollView.verticalRulerView = nil
                scrollView.hasVerticalRuler = false
                scrollView.rulersVisible = false
                rulerRef = nil
            }

            // 新しいrulerViewを作成
            let rulerView = LineNumberRulerView(scrollView: scrollView, textView: textView)
            rulerView.lineNumberMode = lineNumberMode
            scrollView.verticalRulerView = rulerView
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
            rulerRef = rulerView

            // レイアウトを更新
            scrollView.tile()

            // textViewのframeを更新
            if let textContainer = textView.textContainer {
                textView.frame = scrollView.contentView.bounds
                textContainer.containerSize = NSSize(width: scrollView.contentView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
            }

            // テキスト変更時とスクロール時にrulerViewを更新
            NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: textView, queue: .main) { [weak rulerView] _ in
                rulerView?.needsDisplay = true
            }
            NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak rulerView] _ in
                rulerView?.needsDisplay = true
            }
        } else {
            // rulerViewを削除
            scrollView.hasVerticalRuler = false
            scrollView.rulersVisible = false
            scrollView.verticalRulerView = nil
            rulerRef = nil

            // レイアウトを更新
            scrollView.tile()

            // textViewのframeを更新
            if let textContainer = textView.textContainer {
                textView.frame = scrollView.contentView.bounds
                textContainer.containerSize = NSSize(width: scrollView.contentView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
            }
        }
    }

    // MARK: - Pagination Methods

    private enum ScrollViewTarget {
        case scrollView1
        case scrollView2
    }

    private func createHeaderView(for pageIndex: Int, yOffset: CGFloat) -> NSView {
        let headerView = NSView(frame: NSRect(x: pageMargin, y: yOffset + 10, width: pageWidth - (pageMargin * 2), height: headerHeight))

        // ファイル名を表示
        let fileName = textDocument?.displayName ?? "Untitled"
        let label = NSTextField(labelWithString: fileName)
        label.frame = NSRect(x: 0, y: 0, width: headerView.bounds.width, height: headerHeight)
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 10)
        label.textColor = .secondaryLabelColor

        headerView.addSubview(label)
        return headerView
    }

    private func createFooterView(for pageIndex: Int, totalPages: Int, yOffset: CGFloat) -> NSView {
        let footerView = NSView(frame: NSRect(x: pageMargin, y: yOffset + pageHeight - footerHeight - 10, width: pageWidth - (pageMargin * 2), height: footerHeight))

        // ページ番号を表示
        let pageNumberText = "\(pageIndex + 1) / \(totalPages)"
        let label = NSTextField(labelWithString: pageNumberText)
        label.frame = NSRect(x: 0, y: 0, width: footerView.bounds.width, height: footerHeight)
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 10)
        label.textColor = .secondaryLabelColor

        footerView.addSubview(label)
        return footerView
    }

    private func addPage(to layoutManager: NSLayoutManager, in scrollView: NSScrollView, for target: ScrollViewTarget) {
        var textContainers: [NSTextContainer]
        var textViews: [NSTextView]
        var containerView: FlippedContainerView?

        switch target {
        case .scrollView1:
            textContainers = textContainers1
            textViews = textViews1
            containerView = containerView1
        case .scrollView2:
            textContainers = textContainers2
            textViews = textViews2
            containerView = containerView2
        }

        let textContainerSize = NSSize(
            width: pageWidth - (pageMargin * 2),
            height: pageHeight - (pageMargin * 2)
        )

        // 新しいTextContainerを作成
        let textContainer = NSTextContainer(containerSize: textContainerSize)
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false

        // LayoutManagerにTextContainerを追加
        layoutManager.addTextContainer(textContainer)

        // 新しいTextViewを作成
        let pageIndex = textContainers.count
        let yOffset = CGFloat(pageIndex) * (pageHeight + pageSpacing)
        let frame = NSRect(
            x: pageMargin,
            y: yOffset + pageMargin,
            width: pageWidth - (pageMargin * 2),
            height: pageHeight - (pageMargin * 2)
        )

        let textView = NSTextView(frame: frame, textContainer: textContainer)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.autoresizingMask = []
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.backgroundColor = .white
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // 配列に追加
        textContainers.append(textContainer)
        textViews.append(textView)

        // 配列をプロパティに戻す
        switch target {
        case .scrollView1:
            textContainers1 = textContainers
            textViews1 = textViews
        case .scrollView2:
            textContainers2 = textContainers
            textViews2 = textViews
        }

        // ContainerViewに新しいページを追加（常に非同期で実行）
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let containerView = containerView {
                // 総ページ数を取得
                let totalPages = textViews.count
                self.addPageToContainerView(containerView, textView: textView, at: pageIndex, totalPages: totalPages)
            } else {
                self.createContainerView(in: scrollView, with: textViews, for: target)
            }
        }
    }

    private func removeExcessPages(from layoutManager: NSLayoutManager, in scrollView: NSScrollView, for target: ScrollViewTarget) {
        var textContainers: [NSTextContainer]
        var textViews: [NSTextView]

        switch target {
        case .scrollView1:
            textContainers = textContainers1
            textViews = textViews1
        case .scrollView2:
            textContainers = textContainers2
            textViews = textViews2
        }

        // 最初のページは保持し、空のページのインデックスを収集（逆順で削除するため）
        var indicesToRemove: [Int] = []

        for (index, container) in textContainers.enumerated() {
            if index > 0 { // 最初のページは残す
                let glyphRange = layoutManager.glyphRange(for: container)
                if glyphRange.length == 0 {
                    indicesToRemove.append(index)
                }
            }
        }

        // 逆順で削除（インデックスのずれを防ぐ）
        for index in indicesToRemove.reversed() {
            let container = textContainers[index]

            // layoutManagerから削除（layoutManager内のインデックスを見つける）
            if let layoutManagerIndex = layoutManager.textContainers.firstIndex(of: container) {
                layoutManager.removeTextContainer(at: layoutManagerIndex)
            }

            // 配列から削除
            textContainers.remove(at: index)
            textViews.remove(at: index)
        }

        // 配列をプロパティに戻す
        switch target {
        case .scrollView1:
            textContainers1 = textContainers
            textViews1 = textViews
        case .scrollView2:
            textContainers2 = textContainers
            textViews2 = textViews
        }

        // DocumentViewを更新（非同期で実行）
        if !indicesToRemove.isEmpty {
            // containerViewを再構築
            let viewsCopy = textViews
            DispatchQueue.main.async { [weak self] in
                self?.createContainerView(in: scrollView, with: viewsCopy, for: target)
            }
        }
    }

    private func addPageToContainerView(_ containerView: FlippedContainerView, textView: NSTextView, at pageIndex: Int, totalPages: Int) {
        // スクロール位置を保存
        let scrollView = containerView.enclosingScrollView
        let savedScrollPosition = scrollView?.documentVisibleRect.origin

        // 既存のサブビューのコピーを作成
        let existingSubviews = Array(containerView.subviews)

        // すべてのサブビューを削除
        for subview in existingSubviews {
            subview.removeFromSuperview()
        }

        let yOffset = CGFloat(pageIndex) * (pageHeight + pageSpacing)

        // ページの背景ビュー
        let pageBackgroundView = NSView(frame: NSRect(x: 0, y: yOffset, width: pageWidth, height: pageHeight))
        pageBackgroundView.wantsLayer = true
        pageBackgroundView.layer?.backgroundColor = NSColor.white.cgColor
        pageBackgroundView.layer?.borderColor = NSColor.gray.cgColor
        pageBackgroundView.layer?.borderWidth = 1.0
        pageBackgroundView.layer?.shadowColor = NSColor.black.cgColor
        pageBackgroundView.layer?.shadowOpacity = 0.3
        pageBackgroundView.layer?.shadowOffset = NSSize(width: 0, height: -2)
        pageBackgroundView.layer?.shadowRadius = 4.0

        // ヘッダーを作成
        let headerView = createHeaderView(for: pageIndex, yOffset: yOffset)

        // フッターを作成
        let footerView = createFooterView(for: pageIndex, totalPages: totalPages, yOffset: yOffset)

        // すべてのサブビューを再追加
        for subview in existingSubviews {
            containerView.addSubview(subview)
        }
        containerView.addSubview(pageBackgroundView)
        containerView.addSubview(headerView)
        containerView.addSubview(footerView)
        containerView.addSubview(textView)

        // containerViewのサイズを更新
        let totalHeight = CGFloat(pageIndex + 1) * (pageHeight + pageSpacing)
        containerView.frame.size.height = totalHeight

        // スクロール位置を復元
        if let savedPosition = savedScrollPosition {
            scrollView?.documentView?.scroll(savedPosition)
        }
    }

    private func createContainerView(in scrollView: NSScrollView, with textViews: [NSTextView], for target: ScrollViewTarget) {
        // スクロール位置を保存
        let savedScrollPosition = scrollView.documentVisibleRect.origin

        // すべてのページを含むコンテナビューを作成
        let totalHeight = CGFloat(textViews.count) * (pageHeight + pageSpacing)
        let containerView = FlippedContainerView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: totalHeight))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.lightGray.cgColor

        // 各ページビューを追加
        for (index, textView) in textViews.enumerated() {
            let yOffset = CGFloat(index) * (pageHeight + pageSpacing)

            // ページの背景ビュー
            let pageBackgroundView = NSView(frame: NSRect(x: 0, y: yOffset, width: pageWidth, height: pageHeight))
            pageBackgroundView.wantsLayer = true
            pageBackgroundView.layer?.backgroundColor = NSColor.white.cgColor
            pageBackgroundView.layer?.borderColor = NSColor.gray.cgColor
            pageBackgroundView.layer?.borderWidth = 1.0
            pageBackgroundView.layer?.shadowColor = NSColor.black.cgColor
            pageBackgroundView.layer?.shadowOpacity = 0.3
            pageBackgroundView.layer?.shadowOffset = NSSize(width: 0, height: -2)
            pageBackgroundView.layer?.shadowRadius = 4.0

            // ヘッダーを作成
            let headerView = createHeaderView(for: index, yOffset: yOffset)

            // フッターを作成
            let footerView = createFooterView(for: index, totalPages: textViews.count, yOffset: yOffset)

            containerView.addSubview(pageBackgroundView)
            containerView.addSubview(headerView)
            containerView.addSubview(footerView)
            containerView.addSubview(textView)
        }

        scrollView.documentView = containerView

        // containerViewをプロパティに保存
        switch target {
        case .scrollView1:
            containerView1 = containerView
        case .scrollView2:
            containerView2 = containerView
        }

        // スクロール位置を復元
        scrollView.documentView?.scroll(savedScrollPosition)
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, shouldHideDividerAt dividerIndex: Int) -> Bool {
        // 2つ目のビューが非表示の場合、スプリットバーを非表示にする
        if splitView.subviews.count > 1 {
            return splitView.subviews[1].isHidden
        }
        return false
    }

    // MARK: - NSLayoutManagerDelegate

    func layoutManager(_ layoutManager: NSLayoutManager, didCompleteLayoutFor textContainer: NSTextContainer?, atEnd layoutFinishedFlag: Bool) {
        // どのscrollViewに対応するlayoutManagerかを判定
        var target: ScrollViewTarget?
        var targetScrollView: NSScrollView?

        if layoutManager === layoutManager1 {
            target = .scrollView1
            targetScrollView = scrollView1
        } else if layoutManager === layoutManager2 {
            target = .scrollView2
            targetScrollView = scrollView2
        }

        guard let target = target,
              let scrollView = targetScrollView else {
            return
        }

        // 現在のコンテナ数を取得（毎回最新の値を参照）
        let currentContainers = target == .scrollView1 ? textContainers1 : textContainers2

        // 処理を非同期で実行
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // textContainerがnilでない場合のみ処理
            if let textContainer = textContainer {
                let isLastContainer = currentContainers.isEmpty || textContainer == currentContainers.last

                // コンテナが空か、最後のコンテナで、レイアウトが完了していない場合
                if isLastContainer && !layoutFinishedFlag {
                    // 新しいページを追加
                    self.addPage(to: layoutManager, in: scrollView, for: target)
                }
            }

            // レイアウトが完了した場合、余分なページを削除
            if layoutFinishedFlag {
                self.removeExcessPages(from: layoutManager, in: scrollView, for: target)
            }
        }
    }
}

