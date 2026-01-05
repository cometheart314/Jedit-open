//
//  EditorWindowController.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/26.
//

import Cocoa

// MARK: - Display Mode

enum DisplayMode {
    case continuous  // 通常モード（連続スクロール）
    case page        // ページモード（ページネーション）
}

class EditorWindowController: NSWindowController, NSLayoutManagerDelegate, NSSplitViewDelegate, NSWindowDelegate, NSMenuItemValidation {

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
    private var isInspectorBarVisible: Bool = false  // Inspector Barの表示状態
    private var isInspectorBarInitialized: Bool = false  // Inspector Bar初期化済みフラグ

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
    private var pagesView1: MultiplePageView?
    private var pagesView2: MultiplePageView?

    // ページ設定
    private let pageWidth: CGFloat = 595.0  // A4サイズ相当（ポイント）
    private let pageHeight: CGFloat = 842.0 // A4サイズ相当（ポイント）
    private let pageMargin: CGFloat = 72.0  // 1インチ（72ポイント）のマージン
    private let pageSpacing: CGFloat = 20.0 // ページ間のスペース

    // NotificationCenter observers
    private var textViewObservers: [Any] = []

    deinit {
        // KVO observerを解除
        if let contentView = self.window?.contentView {
            contentView.removeObserver(self, forKeyPath: "effectiveAppearance")
        }
        // NotificationCenter observerを解除
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Window Lifecycle

    override func windowDidLoad() {
        super.windowDidLoad()

        // WindowDelegateを設定
        self.window?.delegate = self

        // SplitViewのデリゲートを設定
        splitView?.delegate = self

        // 初期状態では2つ目のペインを非表示にする
        if let splitView = splitView, splitView.subviews.count > 1 {
            splitView.subviews[1].isHidden = true
            isSplitViewCollapsed = true
        }

        // ルーラー幅変更通知を監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rulerThicknessDidChange(_:)),
            name: LineNumberRulerView.rulerThicknessDidChangeNotification,
            object: nil
        )

        // ドキュメントタイプ変更通知を監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentTypeDidChange(_:)),
            name: Document.documentTypeDidChangeNotification,
            object: nil
        )

        // アピアランス変更を監視
        if let window = self.window {
            window.contentView?.addObserver(self, forKeyPath: "effectiveAppearance", options: [.new], context: nil)
        }

        // TextStorageを設定
        setupTextStorage()
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "effectiveAppearance" {
            // メインスレッドで即座に実行
            if Thread.isMainThread {
                updateTextColorForAppearance()
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.updateTextColorForAppearance()
                }
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    private func updateTextColorForAppearance() {
        let isPlainText = textDocument?.documentType == .plain

        // プレーンテキストの場合のみ文字色を変更
        if isPlainText, let textStorage = textDocument?.textStorage {
            let fullRange = NSRange(location: 0, length: textStorage.length)
            if fullRange.length > 0 {
                textStorage.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)
            }
        }

        // 背景色を更新（プレーンテキストはシステムカラー、リッチテキストは白固定）
        switch displayMode {
        case .continuous:
            if let scrollView = scrollView1,
               let textView = scrollView.documentView as? NSTextView {
                if isPlainText {
                    textView.backgroundColor = .textBackgroundColor
                    textView.textColor = .textColor
                    scrollView.backgroundColor = .textBackgroundColor
                } else {
                    textView.backgroundColor = .white
                    scrollView.backgroundColor = .white
                }
            }
            if let scrollView = scrollView2,
               !scrollView.isHidden,
               let textView = scrollView.documentView as? NSTextView {
                if isPlainText {
                    textView.backgroundColor = .textBackgroundColor
                    textView.textColor = .textColor
                    scrollView.backgroundColor = .textBackgroundColor
                } else {
                    textView.backgroundColor = .white
                    scrollView.backgroundColor = .white
                }
            }
        case .page:
            for textView in textViews1 {
                if isPlainText {
                    textView.backgroundColor = .textBackgroundColor
                    textView.textColor = .textColor
                } else {
                    textView.backgroundColor = .white
                }
            }
            for textView in textViews2 {
                if isPlainText {
                    textView.backgroundColor = .textBackgroundColor
                    textView.textColor = .textColor
                } else {
                    textView.backgroundColor = .white
                }
            }
        }
    }

    @objc private func documentTypeDidChange(_ notification: Notification) {
        // 自分のドキュメントからの通知かを確認
        guard let document = notification.object as? Document,
              document === textDocument else { return }

        // 初期化済みでない場合のみ、ドキュメントタイプに基づいて設定
        if !isInspectorBarInitialized {
            isInspectorBarInitialized = true
            isInspectorBarVisible = (document.documentType != .plain)
            updateInspectorBarVisibility()
        }

        // ドキュメント読み込み後にアピアランスに応じた色を適用
        // （プレーンテキストをダークモードで開いた場合に文字色を設定）
        updateTextColorForAppearance()
    }

    @objc private func rulerThicknessDidChange(_ notification: Notification) {
        // ルーラー幅が変更されたらテキストビューのサイズを更新
        guard displayMode == .continuous else { return }

        if let scrollView = scrollView1 {
            updateTextViewSize(for: scrollView)
        }

        if let scrollView = scrollView2, !scrollView.isHidden {
            updateTextViewSize(for: scrollView)
        }
    }

    // MARK: - Setup Methods

    func setupTextStorage() {
        guard let textDocument = self.textDocument else {
            return
        }

        setupTextViews(with: textDocument.textStorage)
    }

    func setupTextViews(with textStorage: NSTextStorage) {
        // 既存のtextViewのインスペクターバーを閉じる
        if let scrollView = scrollView1,
           let textView = scrollView.documentView as? NSTextView {
            textView.usesInspectorBar = false
        }
        if let scrollView = scrollView2,
           let textView = scrollView.documentView as? NSTextView {
            textView.usesInspectorBar = false
        }
        for textView in textViews1 {
            textView.usesInspectorBar = false
        }
        for textView in textViews2 {
            textView.usesInspectorBar = false
        }

        // 既存のobserverを削除
        for observer in textViewObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        textViewObservers.removeAll()

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
        pagesView1 = nil
        pagesView2 = nil

        // 表示モードに応じてセットアップ
        switch displayMode {
        case .continuous:
            setupContinuousMode(with: textStorage)
        case .page:
            setupPageMode(with: textStorage)
        }

        // モード切り替え後にInspector barの状態を確実に反映
        updateInspectorBarVisibility()
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
            let containerInset = textDocument!.containerInset

            // 行番号ルーラーを先に設定（テキストビュー作成前にcontentSizeを確定させる）
            if lineNumberMode != .none {
                let rulerView = LineNumberRulerView(scrollView: scrollView, textView: nil)
                rulerView.lineNumberMode = lineNumberMode
                scrollView.verticalRulerView = rulerView
                scrollView.hasVerticalRuler = true
                scrollView.rulersVisible = true
                rulerView1 = rulerView
                scrollView.tile()
            } else {
                scrollView.hasVerticalRuler = false
                scrollView.rulersVisible = false
                scrollView.verticalRulerView = nil
                rulerView1 = nil
                scrollView.tile()
            }

            // scrollViewのフレーム幅を基準にして利用可能な幅を計算
            var availableWidth = scrollView.frame.width

            // ルーラーの幅を引く
            if scrollView.hasVerticalRuler, scrollView.rulersVisible, let rulerView = scrollView.verticalRulerView {
                availableWidth -= rulerView.ruleThickness
            }

            // 垂直スクローラーの幅を引く（表示されている場合）
            if scrollView.hasVerticalScroller, let scroller = scrollView.verticalScroller, !scroller.isHidden {
                availableWidth -= scroller.frame.width
            }

            let containerWidth = availableWidth - (containerInset.width * 2)

            // TextContainerを作成
            // widthTracksTextView = false で手動制御（scrollViewのリサイズ時に自動で幅が変わらないようにする）
            let textContainer = NSTextContainer(containerSize: NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude))
            textContainer.widthTracksTextView = false
            textContainer.heightTracksTextView = false
            // デフォルトのlineFragmentPaddingを使用（5.0）
            textContainer.lineFragmentPadding = 5.0

            // LayoutManagerにTextContainerを追加
            let layoutManager = layoutManagers[0]
            layoutManager.addTextContainer(textContainer)

            // TextViewを作成
            let textViewFrame = NSRect(x: 0, y: 0, width: availableWidth, height: scrollView.contentSize.height)
            let textView = NSTextView(frame: textViewFrame, textContainer: textContainer)
            textView.isEditable = true
            textView.isSelectable = true
            textView.allowsUndo = true
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = true
            textView.autoresizingMask = []
            textView.usesInspectorBar = isInspectorBarVisible
            // textContainerInsetで左右と上下のインセットを設定
            textView.textContainerInset = containerInset
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            // ダークモード対応（プレーンテキストのみ）
            // リッチテキストは白背景固定（文字色はユーザー設定を保持）
            if textDocument?.documentType == .plain {
                textView.backgroundColor = .textBackgroundColor
                textView.textColor = .textColor
                scrollView.backgroundColor = .textBackgroundColor
            } else {
                textView.backgroundColor = .white
                scrollView.backgroundColor = .white
            }

            // ScrollViewに設定
            scrollView.documentView = textView
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = true
            scrollView.autohidesScrollers = false

            // rulerViewにtextViewを設定
            if let rulerView = rulerView1 {
                rulerView.textView = textView
                rulerView.clientView = textView

                // テキスト変更時とスクロール時にrulerViewを更新
                let observer1 = NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: textView, queue: .main) { [weak rulerView] _ in
                    rulerView?.needsDisplay = true
                }
                let observer2 = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak rulerView] _ in
                    rulerView?.needsDisplay = true
                }
                textViewObservers.append(contentsOf: [observer1, observer2])
            }
        }

        // TextView2の設定（サブビューが2つ以上の場合のみ）
        if numberOfViews >= 2, let scrollView = scrollView2 {
            let containerInset = textDocument!.containerInset

            // 行番号ルーラーを先に設定（テキストビュー作成前にcontentSizeを確定させる）
            if lineNumberMode != .none {
                let rulerView = LineNumberRulerView(scrollView: scrollView, textView: nil)
                rulerView.lineNumberMode = lineNumberMode
                scrollView.verticalRulerView = rulerView
                scrollView.hasVerticalRuler = true
                scrollView.rulersVisible = true
                rulerView2 = rulerView
                scrollView.tile()
            } else {
                scrollView.hasVerticalRuler = false
                scrollView.rulersVisible = false
                scrollView.verticalRulerView = nil
                rulerView2 = nil
                scrollView.tile()
            }

            // scrollViewのフレーム幅を基準にして利用可能な幅を計算
            var availableWidth = scrollView.frame.width

            // ルーラーの幅を引く
            if scrollView.hasVerticalRuler, scrollView.rulersVisible, let rulerView = scrollView.verticalRulerView {
                availableWidth -= rulerView.ruleThickness
            }

            // 垂直スクローラーの幅を引く（表示されている場合）
            if scrollView.hasVerticalScroller, let scroller = scrollView.verticalScroller, !scroller.isHidden {
                availableWidth -= scroller.frame.width
            }

            let containerWidth = availableWidth - (containerInset.width * 2)

            // TextContainerを作成（widthTracksTextView = false で手動制御）
            let textContainer = NSTextContainer(containerSize: NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude))
            textContainer.widthTracksTextView = false
            textContainer.heightTracksTextView = false
            // デフォルトのlineFragmentPaddingを使用（5.0）
            textContainer.lineFragmentPadding = 5.0

            // LayoutManagerにTextContainerを追加
            let layoutManager = layoutManagers[1]
            layoutManager.addTextContainer(textContainer)

            // TextViewを作成
            let textViewFrame = NSRect(x: 0, y: 0, width: availableWidth, height: scrollView.contentSize.height)
            let textView = NSTextView(frame: textViewFrame, textContainer: textContainer)
            textView.isEditable = true
            textView.isSelectable = true
            textView.allowsUndo = true
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = true
            textView.autoresizingMask = []
            textView.usesInspectorBar = isInspectorBarVisible
            // textContainerInsetで左右と上下のインセットを設定
            textView.textContainerInset = containerInset
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            // ダークモード対応（プレーンテキストのみ）
            // リッチテキストは白背景固定（文字色はユーザー設定を保持）
            if textDocument?.documentType == .plain {
                textView.backgroundColor = .textBackgroundColor
                textView.textColor = .textColor
                scrollView.backgroundColor = .textBackgroundColor
            } else {
                textView.backgroundColor = .white
                scrollView.backgroundColor = .white
            }

            // ScrollViewに設定
            scrollView.documentView = textView
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = true
            scrollView.autohidesScrollers = false

            // rulerViewにtextViewを設定
            if let rulerView = rulerView2 {
                rulerView.textView = textView
                rulerView.clientView = textView

                // テキスト変更時とスクロール時にrulerViewを更新
                let observer1 = NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: textView, queue: .main) { [weak rulerView] _ in
                    rulerView?.needsDisplay = true
                }
                let observer2 = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak rulerView] _ in
                    rulerView?.needsDisplay = true
                }
                textViewObservers.append(contentsOf: [observer1, observer2])
            }
        }

        // レイアウト完了後にサイズを更新（初期化時はフレームが確定していない場合があるため）
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let scrollView = self.scrollView1 {
                self.updateTextViewSize(for: scrollView)
            }
            if let scrollView = self.scrollView2, !scrollView.isHidden {
                self.updateTextViewSize(for: scrollView)
            }
        }
    }

    private func setupPageMode(with textStorage: NSTextStorage) {
        // splitViewの表示されているサブビューの数を取得
        guard let splitView = splitView else { return }
        let visibleSubviews = splitView.subviews.filter { !$0.isHidden }
        let numberOfViews = visibleSubviews.count

        // 推定ページ数を計算（1ページあたりの文字数を概算）
        let charsPerPage = 1000
        let estimatedPages = max(1, (textStorage.length + charsPerPage - 1) / charsPerPage)

        // 必要な数のLayoutManagerを作成
        var layoutManagers: [NSLayoutManager] = []
        for _ in 0..<numberOfViews {
            let layoutManager = NSLayoutManager()
            // 非連続レイアウトを有効にしてパフォーマンス向上
            layoutManager.allowsNonContiguousLayout = true
            layoutManagers.append(layoutManager)
        }

        // TextView1の設定（常に設定）
        if numberOfViews >= 1, let scrollView = scrollView1 {
            let layoutManager = layoutManagers[0]
            layoutManager1 = layoutManager

            // MultiplePageViewを作成
            let initialFrame = NSRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
            let pagesView = MultiplePageView(frame: initialFrame)
            pagesView.pageWidth = pageWidth
            pagesView.pageHeight = pageHeight
            pagesView.pageMargin = pageMargin
            pagesView.pageSeparatorHeight = pageSpacing
            pagesView.documentName = textDocument?.displayName ?? ""
            pagesView.isPlainText = textDocument?.documentType == .plain
            scrollView.documentView = pagesView
            pagesView1 = pagesView

            // ScrollViewの設定
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = true
            scrollView.autohidesScrollers = false

            // 推定ページ数分のTextContainerを一度に作成
            createAllPages(count: estimatedPages, for: layoutManager, in: scrollView, target: .scrollView1)

            // デリゲートを設定（追加ページが必要な場合のみ使用）
            layoutManager.delegate = self
        }

        // TextView2の設定（サブビューが2つ以上の場合のみ）
        if numberOfViews >= 2, let scrollView = scrollView2 {
            let layoutManager = layoutManagers[1]
            layoutManager2 = layoutManager

            // MultiplePageViewを作成
            let initialFrame = NSRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
            let pagesView = MultiplePageView(frame: initialFrame)
            pagesView.pageWidth = pageWidth
            pagesView.pageHeight = pageHeight
            pagesView.pageMargin = pageMargin
            pagesView.pageSeparatorHeight = pageSpacing
            pagesView.documentName = textDocument?.displayName ?? ""
            pagesView.isPlainText = textDocument?.documentType == .plain
            scrollView.documentView = pagesView
            pagesView2 = pagesView

            // ScrollViewの設定
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = true
            scrollView.autohidesScrollers = false

            // 推定ページ数分のTextContainerを一度に作成
            createAllPages(count: estimatedPages, for: layoutManager, in: scrollView, target: .scrollView2)

            // デリゲートを設定（追加ページが必要な場合のみ使用）
            layoutManager.delegate = self
        }

        // scrollViewとpagesViewを即座に表示
        if let scrollView = scrollView1, let pagesView = pagesView1 {
            scrollView.needsLayout = true
            scrollView.layoutSubtreeIfNeeded()
            pagesView.needsDisplay = true
            pagesView.displayIfNeeded()
        }
        if let scrollView = scrollView2, let pagesView = pagesView2 {
            scrollView.needsLayout = true
            scrollView.layoutSubtreeIfNeeded()
            pagesView.needsDisplay = true
            pagesView.displayIfNeeded()
        }

        // ウィンドウを更新
        self.window?.displayIfNeeded()

        // UIを更新してから、レイアウトを開始（遅延実行）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }

            // layoutManager1にTextStorageを追加
            if let layoutManager = self.layoutManager1 {
                textStorage.addLayoutManager(layoutManager)

                // 最初のページのレイアウトを即座に実行
                if let firstContainer = self.textContainers1.first {
                    layoutManager.ensureLayout(for: firstContainer)
                }
            }

            // layoutManager2にTextStorageを追加（スプリット時のみ）
            if let layoutManager = self.layoutManager2 {
                textStorage.addLayoutManager(layoutManager)

                // 最初のページのレイアウトを即座に実行
                if let firstContainer = self.textContainers2.first {
                    layoutManager.ensureLayout(for: firstContainer)
                }
            }
        }
    }

    /// 指定された数のページを一度に作成
    private func createAllPages(count: Int, for layoutManager: NSLayoutManager, in scrollView: NSScrollView, target: ScrollViewTarget) {
        var textContainers: [NSTextContainer] = []
        var textViews: [NSTextView] = []
        let pagesView: MultiplePageView?

        switch target {
        case .scrollView1:
            pagesView = pagesView1
        case .scrollView2:
            pagesView = pagesView2
        }

        guard let pagesView = pagesView else { return }

        let textContainerSize = pagesView.documentSizeInPage

        // すべてのページを一度に作成
        for pageIndex in 0..<count {
            // TextContainerを作成
            let textContainer = NSTextContainer(containerSize: textContainerSize)
            textContainer.widthTracksTextView = false
            textContainer.heightTracksTextView = false

            // LayoutManagerにTextContainerを追加
            layoutManager.addTextContainer(textContainer)

            // TextViewを作成
            let documentRect = pagesView.documentRect(forPageNumber: pageIndex)
            let textView = NSTextView(frame: documentRect, textContainer: textContainer)
            textView.isEditable = true
            textView.isSelectable = true
            textView.allowsUndo = true
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = false
            textView.autoresizingMask = []
            textView.textContainerInset = NSSize(width: 0, height: 0)
            // ダークモード対応（プレーンテキストのみ）
            // リッチテキストは白背景固定（文字色はユーザー設定を保持）
            if textDocument?.documentType == .plain {
                textView.backgroundColor = .textBackgroundColor
                textView.textColor = .textColor
            } else {
                textView.backgroundColor = .white
            }
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.usesInspectorBar = isInspectorBarVisible

            textContainers.append(textContainer)
            textViews.append(textView)
            pagesView.addSubview(textView)
        }

        // ページ数を設定
        pagesView.setNumberOfPages(count)

        // 配列をプロパティに保存
        switch target {
        case .scrollView1:
            textContainers1 = textContainers
            textViews1 = textViews
        case .scrollView2:
            textContainers2 = textContainers
            textViews2 = textViews
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
            // ページモードへの切り替え時は警告チェック
            switchToPageModeWithWarning()
            return
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
        switchToPageModeWithWarning()
    }

    private func switchToPageModeWithWarning() {
        guard let textDocument = self.textDocument else { return }
        displayMode = .page
        setupTextViews(with: textDocument.textStorage)
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
        guard lineNumberMode != .none else { return }
        lineNumberMode = .none
        updateLineNumberDisplay()
    }

    @IBAction func showParagraphNumbers(_ sender: Any?) {
        guard lineNumberMode != .paragraph else { return }
        lineNumberMode = .paragraph
        updateLineNumberDisplay()
    }

    @IBAction func showRowNumbers(_ sender: Any?) {
        guard lineNumberMode != .row else { return }
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
            if rulerRef != nil {
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

            // レイアウトを更新（ScalingScrollView.tile()でautoresizesSubviews=falseが設定される）
            scrollView.tile()

            // サイズを更新（inoutパラメータへのアクセス競合を避けるため非同期で実行）
            DispatchQueue.main.async { [weak self] in
                self?.updateTextViewSize(for: scrollView)
            }

            // テキスト変更時とスクロール時にrulerViewを更新
            let observer1 = NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: textView, queue: .main) { [weak rulerView] _ in
                rulerView?.needsDisplay = true
            }
            let observer2 = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak rulerView] _ in
                rulerView?.needsDisplay = true
            }
            textViewObservers.append(contentsOf: [observer1, observer2])
        } else {
            // rulerViewを削除
            scrollView.hasVerticalRuler = false
            scrollView.rulersVisible = false
            scrollView.verticalRulerView = nil
            rulerRef = nil

            // レイアウトを更新（ScalingScrollView.tile()でautoresizesSubviews=falseが設定される）
            scrollView.tile()

            // サイズを更新（inoutパラメータへのアクセス競合を避けるため非同期で実行）
            DispatchQueue.main.async { [weak self] in
                self?.updateTextViewSize(for: scrollView)
            }
        }
    }

    // MARK: - Inspector Bar Actions

    @IBAction func toggleInspectorBar(_ sender: Any?) {
        isInspectorBarVisible = !isInspectorBarVisible
        updateInspectorBarVisibility()
    }

    private func updateInspectorBarVisibility() {
        switch displayMode {
        case .continuous:
            // scrollView1のtextViewを更新
            if let scrollView = scrollView1,
               let textView = scrollView.documentView as? NSTextView {
                textView.usesInspectorBar = isInspectorBarVisible
            }

            // scrollView2のtextViewを更新（splitViewが表示されている場合）
            if let scrollView = scrollView2,
               !scrollView.isHidden,
               let textView = scrollView.documentView as? NSTextView {
                textView.usesInspectorBar = isInspectorBarVisible
            }

        case .page:
            // ページモード時は全てのtextViewを更新
            for textView in textViews1 {
                textView.usesInspectorBar = isInspectorBarVisible
            }
            for textView in textViews2 {
                textView.usesInspectorBar = isInspectorBarVisible
            }
        }
    }

    // MARK: - Pagination Methods

    private enum ScrollViewTarget {
        case scrollView1
        case scrollView2
    }

    private func addPage(to layoutManager: NSLayoutManager, in scrollView: NSScrollView, for target: ScrollViewTarget) {

        var textContainers: [NSTextContainer]
        var textViews: [NSTextView]
        var pagesView: MultiplePageView?

        switch target {
        case .scrollView1:
            textContainers = textContainers1
            textViews = textViews1
            pagesView = pagesView1
        case .scrollView2:
            textContainers = textContainers2
            textViews = textViews2
            pagesView = pagesView2
        }

        guard let pagesView = pagesView else { return }

        let textContainerSize = pagesView.documentSizeInPage

        // 新しいTextContainerを作成
        let textContainer = NSTextContainer(containerSize: textContainerSize)
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false

        // LayoutManagerにTextContainerを追加
        layoutManager.addTextContainer(textContainer)

        // 新しいTextViewを作成
        let pageIndex = textContainers.count
        let documentRect = pagesView.documentRect(forPageNumber: pageIndex)

        let textView = NSTextView(frame: documentRect, textContainer: textContainer)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.autoresizingMask = []
        textView.textContainerInset = NSSize(width: 0, height: 0)
        // ダークモード対応（プレーンテキストのみ）
        // リッチテキストは白背景固定（文字色はユーザー設定を保持）
        if textDocument?.documentType == .plain {
            textView.backgroundColor = .textBackgroundColor
            textView.textColor = .textColor
        } else {
            textView.backgroundColor = .white
        }
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.usesInspectorBar = isInspectorBarVisible

        // 配列に追加
        textContainers.append(textContainer)
        textViews.append(textView)

        // pagesViewにTextViewを追加
        pagesView.addSubview(textView)

        // ページ数を更新（これでpagesViewのフレームも更新される）
        pagesView.setNumberOfPages(textContainers.count)

        // 配列をプロパティに戻す
        switch target {
        case .scrollView1:
            textContainers1 = textContainers
            textViews1 = textViews
        case .scrollView2:
            textContainers2 = textContainers
            textViews2 = textViews
        }
    }

    private func removeExcessPages(from layoutManager: NSLayoutManager, in scrollView: NSScrollView, for target: ScrollViewTarget) {
        var textContainers: [NSTextContainer]
        var textViews: [NSTextView]
        var pagesView: MultiplePageView?

        switch target {
        case .scrollView1:
            textContainers = textContainers1
            textViews = textViews1
            pagesView = pagesView1
        case .scrollView2:
            textContainers = textContainers2
            textViews = textViews2
            pagesView = pagesView2
        }

        guard let pagesView = pagesView else { return }

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
            let textView = textViews[index]

            // TextViewをpagesViewから削除
            textView.removeFromSuperview()

            // layoutManagerから削除（layoutManager内のインデックスを見つける）
            if let layoutManagerIndex = layoutManager.textContainers.firstIndex(of: container) {
                layoutManager.removeTextContainer(at: layoutManagerIndex)
            }

            // 配列から削除
            textContainers.remove(at: index)
            textViews.remove(at: index)
        }

        // ページ数を更新
        if !indicesToRemove.isEmpty {
            pagesView.setNumberOfPages(textContainers.count)
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
    }


    // MARK: - Text View Size Management

    private func updateTextViewSize(for scrollView: NSScrollView) {
        guard let textView = scrollView.documentView as? NSTextView,
              let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager,
              let containerInset = textDocument?.containerInset else { return }

        // scrollViewのフレーム幅を基準にして利用可能な幅を計算
        var availableWidth = scrollView.frame.width

        // ルーラーの幅を引く
        if scrollView.hasVerticalRuler, scrollView.rulersVisible, let rulerView = scrollView.verticalRulerView {
            availableWidth -= rulerView.ruleThickness
        }

        // 垂直スクローラーの幅を引く
        if scrollView.hasVerticalScroller, let scroller = scrollView.verticalScroller, !scroller.isHidden {
            availableWidth -= scroller.frame.width
        }

        let containerWidth = availableWidth - (containerInset.width * 2)

        // テキストビューのフレームを更新
        textView.setFrameSize(NSSize(width: availableWidth, height: textView.frame.height))

        // テキストコンテナのサイズを更新
        textContainer.size = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)

        // textContainerInsetを設定
        textView.textContainerInset = containerInset

        // レイアウトを強制的に再計算
        layoutManager.ensureLayout(for: textContainer)

        // テキストビューを再描画
        textView.needsDisplay = true
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, shouldHideDividerAt dividerIndex: Int) -> Bool {
        // 2つ目のビューが非表示の場合、スプリットバーを非表示にする
        if splitView.subviews.count > 1 {
            return splitView.subviews[1].isHidden
        }
        return false
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        // 通常モードの場合、テキストビューのサイズを更新
        guard displayMode == .continuous else { return }

        if let scrollView = scrollView1 {
            updateTextViewSize(for: scrollView)
        }

        if let scrollView = scrollView2, !scrollView.isHidden {
            updateTextViewSize(for: scrollView)
        }
    }

    // MARK: - Menu Validation

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleInspectorBar(_:)) {
            menuItem.title = isInspectorBarVisible ? "Hide Inspector Bar" : "Show Inspector Bar"
        }
        if menuItem.action == #selector(toggleDisplayMode(_:)) {
            menuItem.title = displayMode == .continuous ? "Wrap to Page" : "Wrap to Window"
        }
        if menuItem.action == #selector(toggleSplitView(_:)) {
            let isSplitViewVisible = splitView?.subviews.count ?? 0 > 1 && !(splitView?.subviews[1].isHidden ?? true)
            menuItem.title = isSplitViewVisible ? "Collapse Views" : "Split View"
        }
        return true
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        // スプリットバー操作時はsplitViewDidResizeSubviewsで処理されるため、
        // ウィンドウ全体のリサイズのみ処理する
        guard displayMode == .continuous else { return }
        guard let window = self.window, !window.inLiveResize else { return }

        // scrollView1を更新
        if let scrollView = scrollView1 {
            updateTextViewSize(for: scrollView)
        }

        // scrollView2を更新（表示されている場合）
        if let scrollView = scrollView2, !scrollView.isHidden {
            updateTextViewSize(for: scrollView)
        }
    }

    // MARK: - NSLayoutManagerDelegate

    // ページ追加中の再入防止フラグ
    private var isAddingPage1: Bool = false
    private var isAddingPage2: Bool = false

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

        // 再入防止チェック
        let isAddingPage = target == .scrollView1 ? isAddingPage1 : isAddingPage2
        guard !isAddingPage else { return }

        // 現在のコンテナ数を取得（毎回最新の値を参照）
        let currentContainers = target == .scrollView1 ? textContainers1 : textContainers2

        // textContainerがnilでない場合のみ処理
        if let textContainer = textContainer {
            let isLastContainer = currentContainers.isEmpty || textContainer == currentContainers.last

            // 最後のコンテナでレイアウトが完了していない場合、新しいページを追加
            // （事前に推定ページ数を作成しているので、ここに来るのは稀）
            if isLastContainer && !layoutFinishedFlag {
                // 再入防止フラグをセット
                if target == .scrollView1 {
                    isAddingPage1 = true
                } else {
                    isAddingPage2 = true
                }

                // 追加ページが必要（推定が少なかった場合）
                addPage(to: layoutManager, in: scrollView, for: target)

                // 再入防止フラグをクリア
                if target == .scrollView1 {
                    isAddingPage1 = false
                } else {
                    isAddingPage2 = false
                }
            }
        }

        // レイアウトが完了した場合、余分なページを削除
        if layoutFinishedFlag {
            removeExcessPages(from: layoutManager, in: scrollView, for: target)
        }
    }
}

