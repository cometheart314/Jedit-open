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

// MARK: - Split Mode

enum SplitMode {
    case none        // スプリットなし
    case horizontal  // 水平スプリット（上下に分割）
    case vertical    // 垂直スプリット（左右に分割）
}

// MARK: - Line Wrap Mode (for Continuous mode)

enum LineWrapMode {
    case paperWidth   // 用紙幅に合わせる
    case windowWidth  // ウィンドウ幅に合わせる（デフォルト）
    case noWrap       // 行を折り返さない
    case fixedWidth   // 固定幅に合わせる
}

class EditorWindowController: NSWindowController, NSLayoutManagerDelegate, NSSplitViewDelegate, NSWindowDelegate, NSMenuItemValidation {

    // MARK: - IBOutlets

    @IBOutlet weak var splitView: NSSplitView!
    @IBOutlet weak var scrollView2: ScalingScrollView!
    @IBOutlet weak var scrollView1: ScalingScrollView!

    // MARK: - Image Resize

    private var imageResizeController: ImageResizeController?

    // MARK: - Properties

    var textDocument: Document? {
        return document as? Document
    }

    private var splitMode: SplitMode = .none

    // 表示モード
    private var displayMode: DisplayMode = .continuous
    private var lineNumberMode: LineNumberMode = .none
    private var isInspectorBarVisible: Bool = false  // Inspector Barの表示状態
    private var isInspectorBarInitialized: Bool = false  // Inspector Bar初期化済みフラグ
    private var isRulerVisible: Bool = false  // ルーラーの表示状態
    private var rulerType: NewDocData.ViewData.RulerType = .character  // ルーラーの単位タイプ
    private var invisibleCharacterOptions: InvisibleCharacterOptions = .none  // 不可視文字の表示オプション
    private var isVerticalLayout: Bool = false  // 縦書きレイアウト
    private var lineWrapMode: LineWrapMode = .windowWidth  // 行折り返しモード（Continuousモード用）
    private var fixedWrapWidthInChars: Int = 80  // 固定幅（fixedWidthモード用、文字数）

    // 行番号ビュー
    private var lineNumberView1: LineNumberView?
    private var lineNumberView2: LineNumberView?
    private var lineNumberWidthConstraint1: NSLayoutConstraint?
    private var lineNumberWidthConstraint2: NSLayoutConstraint?

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
    private var contentViewObservers: [Any] = []

    deinit {
        // KVO observerを解除
        if let contentView = self.window?.contentView {
            contentView.removeObserver(self, forKeyPath: "effectiveAppearance")
        }
        // NotificationCenter observerを解除
        NotificationCenter.default.removeObserver(self)
        // contentViewObserversを解除
        for observer in contentViewObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        contentViewObservers.removeAll()
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
            splitMode = .none
        }

        // 行番号ビュー幅変更通知を監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(lineNumberSizeDidChange(_:)),
            name: LineNumberView.widthDidChangeNotification,
            object: nil
        )
        // 行番号ビュー高さ変更通知を監視（縦書き時）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(lineNumberSizeDidChange(_:)),
            name: LineNumberView.heightDidChangeNotification,
            object: nil
        )

        // ドキュメントタイプ変更通知を監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentTypeDidChange(_:)),
            name: Document.documentTypeDidChangeNotification,
            object: nil
        )

        // ズーム変更通知を監視（ルーラーのキャレット位置更新用）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(magnificationDidChange(_:)),
            name: ScalingScrollView.magnificationDidChangeNotification,
            object: nil
        )

        // アピアランス変更を監視
        if let window = self.window {
            window.contentView?.addObserver(self, forKeyPath: "effectiveAppearance", options: [.new], context: nil)
        }

        // ツールバー可視性変更を監視（KVO）
        if let toolbar = self.window?.toolbar {
            toolbar.addObserver(self, forKeyPath: "visible", options: [.new], context: nil)
        }

        // TextStorageを設定
        setupTextStorage()

        // プリセットデータがあれば適用
        // Note: windowDidLoadの時点ではdocumentがまだ関連付けられていない場合があるため、
        //       Document.windowControllerDidLoadNibからも呼び出される
        applyPresetData()

        // リッチテキストのLightモード設定を適用
        applyRichTextLightModeAppearance()

        // テキスト編集設定の変更を監視
        observeTextEditingPreferences()

        // リッチテキストLightモード設定の変更を監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(richTextLightModeSettingChanged(_:)),
            name: NSNotification.Name("RichTextLightModeSettingChanged"),
            object: nil
        )
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
        } else if keyPath == "visible" {
            // ツールバー可視性変更を presetData に反映
            if let toolbar = object as? NSToolbar {
                textDocument?.presetData?.view.showToolBar = toolbar.isVisible
                textDocument?.presetDataEdited = true
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

        // リッチテキストでDynamic Colors（システムカラー）を使用している場合は再適用
        if !isPlainText, let colors = textDocument?.presetData?.fontAndColors.colors {
            // 背景色または文字色がDynamicカラーの場合は色を再適用
            if colors.background.isDynamic || colors.character.isDynamic {
                applyColorsToTextViews(colors)
                return
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

    /// リッチテキストのLightモード設定を適用
    private func applyRichTextLightModeAppearance() {
        let isRichText = textDocument?.documentType != .plain
        let alwaysUseLightMode = UserDefaults.standard.bool(forKey: UserDefaults.Keys.richTextAlwaysUsesLightMode)

        // リッチテキストでLightモード設定がオンの場合、スクロールビューにLightアピアランスを設定
        let appearance: NSAppearance? = (isRichText && alwaysUseLightMode) ? NSAppearance(named: .aqua) : nil

        scrollView1?.appearance = appearance
        scrollView2?.appearance = appearance
        pagesView1?.appearance = appearance
        pagesView2?.appearance = appearance
    }

    @objc private func richTextLightModeSettingChanged(_ notification: Notification) {
        applyRichTextLightModeAppearance()
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

        // リッチテキストのLightモード設定を適用
        applyRichTextLightModeAppearance()

        // ドキュメント読み込み後にアピアランスに応じた色を適用
        // （プレーンテキストをダークモードで開いた場合に文字色を設定）
        updateTextColorForAppearance()

        // ドキュメントタイプ変更時にテキスト編集設定を再適用
        // （richTextSubstitutionsEnabled の設定に応じて置換オプションを切り替え）
        applyTextEditingPreferences()
    }

    /// プリセットデータがあれば適用する（ウィンドウ生成時に一度だけ呼ばれる）
    /// Note: プリセットデータはドキュメント作成時にコピーされ、以降Preferencesの変更とは同期しない
    /// Document.windowControllerDidLoadNibからも呼び出される
    func applyPresetData() {
        guard let presetData = textDocument?.presetData else { return }

        // 表示モードを適用
        let viewData = presetData.view
        displayMode = viewData.pageMode ? .page : .continuous

        // 行番号モードを適用
        switch viewData.lineNumberType {
        case .none:
            lineNumberMode = .none
        case .logical:
            lineNumberMode = .paragraph
        case .physical:
            lineNumberMode = .row
        }

        // ドキュメント幅モードを適用
        switch viewData.docWidthType {
        case .paperWidth:
            lineWrapMode = .paperWidth
        case .windowWidth:
            lineWrapMode = .windowWidth
        case .noWrap:
            lineWrapMode = .noWrap
        case .fixedWidth:
            lineWrapMode = .fixedWidth
            fixedWrapWidthInChars = viewData.fixedDocWidth
        }

        // Inspector Barの表示状態を適用
        isInspectorBarVisible = viewData.showInspectorBar
        isInspectorBarInitialized = true

        // ルーラータイプを適用
        rulerType = viewData.rulerType
        // rulerType.noneでなければルーラーを表示
        isRulerVisible = (viewData.rulerType != .none)

        // 不可視文字の表示設定を適用
        invisibleCharacterOptions = viewData.showInvisibles.toInvisibleCharacterOptions()

        // ツールバーの表示状態を適用
        if let window = self.window, let toolbar = window.toolbar {
            toolbar.isVisible = viewData.showToolBar
        }

        // スケールを適用
        if let scrollView = scrollView1 {
            scrollView.magnification = viewData.scale
        }

        // Editing Direction（縦書き/横書き）を適用
        let formatData = presetData.format
        isVerticalLayout = (formatData.editingDirection == .rightToLeft)

        // フォント設定を適用
        let fontData = presetData.fontAndColors
        if let font = NSFont(name: fontData.baseFontName, size: fontData.baseFontSize) {
            applyFontToTextViews(font)
        }

        // テキストビューを再セットアップ（上記の設定を反映）
        if let textStorage = textDocument?.textStorage {
            setupTextViews(with: textStorage)
        }

        // 色設定を適用（setupTextViews後に適用）
        // プレーンテキストでも色設定を適用する
        applyColorsToTextViews(fontData.colors)

        // setupTextViews後にパラグラフスタイル（タブ幅、行間、段落間隔）を適用
        // スペースモードではタブ幅はデフォルト値を使用
        let tabWidthPoints = formatData.tabWidthUnit == .points ? formatData.tabWidthPoints : 28.0
        applyParagraphStyle(
            tabWidthPoints: tabWidthPoints,
            interLineSpacing: formatData.interLineSpacing,
            paragraphSpacingBefore: formatData.paragraphSpacingBefore,
            paragraphSpacingAfter: formatData.paragraphSpacingAfter,
            lineHeightMultiple: formatData.lineHeightMultiple,
            lineHeightMinimum: formatData.lineHeightMinimum,
            lineHeightMaximum: formatData.lineHeightMaximum
        )

        // setupTextViews後にルーラー設定を適用（単位設定を含む）
        updateRulerVisibility()

        // setupTextViews後に行番号表示を適用
        updateLineNumberDisplay()

        // setupTextViews後にスケールを再適用（setupTextViewsで上書きされる可能性があるため）
        if let scrollView = scrollView1 {
            scrollView.magnification = viewData.scale
        }

        // ウィンドウサイズと位置を適用
        // プリセットから生成したドキュメントではウィンドウ復元機能を無効にして、
        // プリセットで指定されたフレームを使用する
        if let window = self.window {
            // ウィンドウフレームの自動保存を無効化（プリセットのフレームを優先）
            window.setFrameAutosaveName("")

            let newFrame = NSRect(
                x: viewData.windowX,
                y: viewData.windowY,
                width: viewData.windowWidth,
                height: viewData.windowHeight
            )
            window.setFrame(newFrame, display: true)

            // 次のランループで再適用（システムによる上書き対策）
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window else { return }
                if window.frame != newFrame {
                    window.setFrame(newFrame, display: true)
                }
            }
        }

        // 選択範囲とスクロール位置の復元（レイアウト完了後に実行）
        DispatchQueue.main.async { [weak self] in
            self?.restoreSelectionAndScrollPosition()
        }
    }

    /// 保存された選択範囲とスクロール位置を復元
    private func restoreSelectionAndScrollPosition() {
        guard let presetData = textDocument?.presetData else { return }
        let viewData = presetData.view

        // 選択範囲を先に復元（スクロール位置より先に行う）
        if let location = viewData.selectedRangeLocation,
           let length = viewData.selectedRangeLength,
           let textStorage = textDocument?.textStorage {
            // テキストの長さを取得
            let textLength = textStorage.length
            // テキストの長さを超えないように調整
            let safeLocation = min(location, textLength)
            let safeLength = min(length, textLength - safeLocation)
            let selectedRange = NSRange(location: safeLocation, length: safeLength)

            // Continuousモードの場合
            if displayMode == .continuous,
               let textView = scrollView1?.documentView as? NSTextView {
                textView.setSelectedRange(selectedRange)
            }
            // Pageモードの場合（textViews1配列の最初のテキストビューを使用）
            else if displayMode == .page,
                    let textView = textViews1.first {
                textView.setSelectedRange(selectedRange)
            }
        }

        // スクロール位置を復元（レイアウト完了後に実行するため遅延させる）
        // 縦書きページモードはレイアウトに時間がかかるため、より長い遅延が必要
        let isVerticalPageMode = (displayMode == .page && isVerticalLayout)
        let delay: TimeInterval = isVerticalPageMode ? 0.5 : 0.1

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            if let scrollPositionX = viewData.scrollPositionX,
               let scrollPositionY = viewData.scrollPositionY,
               let scrollView = self.scrollView1,
               let clipView = scrollView.contentView as? NSClipView {
                let scrollPosition = NSPoint(x: scrollPositionX, y: scrollPositionY)
                clipView.scroll(to: scrollPosition)
                scrollView.reflectScrolledClipView(clipView)
            }
        }
    }

    /// 現在の選択範囲を取得
    private func getCurrentSelectedRange() -> NSRange? {
        if displayMode == .continuous,
           let textView = scrollView1?.documentView as? NSTextView {
            return textView.selectedRange()
        } else if displayMode == .page,
                  let textView = textViews1.first {
            return textView.selectedRange()
        }
        return nil
    }

    /// 選択範囲を設定し、選択範囲の先頭が表示されるようにスクロール
    private func restoreSelectionAndScrollToVisible(_ range: NSRange, delay: TimeInterval = 0.1) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            guard let textStorage = self.textDocument?.textStorage else { return }

            // テキストの長さを超えないように調整
            let textLength = textStorage.length
            let safeLocation = min(range.location, textLength)
            let safeLength = min(range.length, textLength - safeLocation)
            let safeRange = NSRange(location: safeLocation, length: safeLength)

            // Continuousモードの場合
            if self.displayMode == .continuous,
               let textView = self.scrollView1?.documentView as? NSTextView {
                textView.setSelectedRange(safeRange)
                textView.scrollRangeToVisible(safeRange)
            }
            // Pageモードの場合
            else if self.displayMode == .page,
                    let textView = self.textViews1.first {
                textView.setSelectedRange(safeRange)
                textView.scrollRangeToVisible(safeRange)
            }
        }
    }

    /// プリセットのウィンドウフレームのみを適用（showWindows後に呼び出される）
    func applyWindowFrameFromPreset() {
        guard let presetData = textDocument?.presetData else { return }
        guard let window = self.window else { return }

        let viewData = presetData.view
        window.setFrameAutosaveName("")

        let newFrame = NSRect(
            x: viewData.windowX,
            y: viewData.windowY,
            width: viewData.windowWidth,
            height: viewData.windowHeight
        )

        // ランループの次のサイクルで実行して、システムのウィンドウ配置処理の後に適用
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            window.setFrame(newFrame, display: true, animate: false)
        }
    }

    /// フォントをテキストビューに適用
    private func applyFontToTextViews(_ font: NSFont) {
        // Continuous モードの場合
        if let scrollView = scrollView1,
           let textView = scrollView.documentView as? NSTextView {
            textView.font = font
        }
        if let scrollView = scrollView2,
           !scrollView.isHidden,
           let textView = scrollView.documentView as? NSTextView {
            textView.font = font
        }

        // Page モードの場合
        for textView in textViews1 {
            textView.font = font
        }
        for textView in textViews2 {
            textView.font = font
        }
    }

    /// タブ幅をテキストビューに適用
    private func applyTabWidth(_ tabWidthPoints: CGFloat) {
        // presetDataから行間・段落間隔を取得してapplyParagraphStyleを呼び出す
        let format = textDocument?.presetData?.format
        let interLineSpacing = format?.interLineSpacing ?? 0
        let paragraphSpacingBefore = format?.paragraphSpacingBefore ?? 0
        let paragraphSpacingAfter = format?.paragraphSpacingAfter ?? 0
        let lineHeightMultiple = format?.lineHeightMultiple ?? 1.0
        let lineHeightMinimum = format?.lineHeightMinimum ?? 0
        let lineHeightMaximum = format?.lineHeightMaximum ?? 0
        applyParagraphStyle(
            tabWidthPoints: tabWidthPoints,
            interLineSpacing: interLineSpacing,
            paragraphSpacingBefore: paragraphSpacingBefore,
            paragraphSpacingAfter: paragraphSpacingAfter,
            lineHeightMultiple: lineHeightMultiple,
            lineHeightMinimum: lineHeightMinimum,
            lineHeightMaximum: lineHeightMaximum
        )
    }

    /// パラグラフスタイル（タブ幅、行間、段落間隔）をテキストビューに適用
    /// applyToExistingText: 既存テキストにも適用するかどうか（Line Spacingパネルからの変更時はfalse）
    private func applyParagraphStyle(
        tabWidthPoints: CGFloat,
        interLineSpacing: CGFloat,
        paragraphSpacingBefore: CGFloat,
        paragraphSpacingAfter: CGFloat,
        lineHeightMultiple: CGFloat = 1.0,
        lineHeightMinimum: CGFloat = 0,
        lineHeightMaximum: CGFloat = 0,
        applyToExistingText: Bool = true
    ) {
        // デフォルトのパラグラフスタイルを作成
        let defaultParagraphStyle = NSMutableParagraphStyle()
        defaultParagraphStyle.defaultTabInterval = tabWidthPoints
        // タブストップをクリア（defaultTabIntervalを使用するため）
        defaultParagraphStyle.tabStops = []
        // 行の高さの倍率
        defaultParagraphStyle.lineHeightMultiple = lineHeightMultiple
        // 最小・最大行高
        defaultParagraphStyle.minimumLineHeight = lineHeightMinimum
        defaultParagraphStyle.maximumLineHeight = lineHeightMaximum
        // 行間（行の高さの倍率ではなく、追加の間隔）
        defaultParagraphStyle.lineSpacing = interLineSpacing
        // 段落前後の間隔
        defaultParagraphStyle.paragraphSpacingBefore = paragraphSpacingBefore
        defaultParagraphStyle.paragraphSpacing = paragraphSpacingAfter

        // Continuous モードの場合
        if let scrollView = scrollView1,
           let textView = scrollView.documentView as? NSTextView {
            textView.defaultParagraphStyle = defaultParagraphStyle
            // typingAttributesにもパラグラフスタイルを設定
            var typingAttrs = textView.typingAttributes
            typingAttrs[.paragraphStyle] = defaultParagraphStyle
            textView.typingAttributes = typingAttrs
        }
        if let scrollView = scrollView2,
           !scrollView.isHidden,
           let textView = scrollView.documentView as? NSTextView {
            textView.defaultParagraphStyle = defaultParagraphStyle
            var typingAttrs = textView.typingAttributes
            typingAttrs[.paragraphStyle] = defaultParagraphStyle
            textView.typingAttributes = typingAttrs
        }

        // Page モードの場合
        for textView in textViews1 {
            textView.defaultParagraphStyle = defaultParagraphStyle
            var typingAttrs = textView.typingAttributes
            typingAttrs[.paragraphStyle] = defaultParagraphStyle
            textView.typingAttributes = typingAttrs
        }
        for textView in textViews2 {
            textView.defaultParagraphStyle = defaultParagraphStyle
            var typingAttrs = textView.typingAttributes
            typingAttrs[.paragraphStyle] = defaultParagraphStyle
            textView.typingAttributes = typingAttrs
        }

        // 既存のテキストにもパラグラフスタイルを適用（既存のスタイルを保持しつつ設定を更新）
        // applyToExistingTextがfalseの場合はスキップ（Undo対応の別メソッドで適用する）
        if applyToExistingText, let textStorage = textDocument?.textStorage, textStorage.length > 0 {
            textStorage.beginEditing()
            textStorage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, _ in
                let newStyle: NSMutableParagraphStyle
                if let existingStyle = value as? NSParagraphStyle {
                    newStyle = existingStyle.mutableCopy() as! NSMutableParagraphStyle
                } else {
                    newStyle = NSMutableParagraphStyle()
                }
                newStyle.defaultTabInterval = tabWidthPoints
                newStyle.tabStops = []
                newStyle.lineHeightMultiple = lineHeightMultiple
                newStyle.minimumLineHeight = lineHeightMinimum
                newStyle.maximumLineHeight = lineHeightMaximum
                newStyle.lineSpacing = interLineSpacing
                newStyle.paragraphSpacingBefore = paragraphSpacingBefore
                newStyle.paragraphSpacing = paragraphSpacingAfter
                textStorage.addAttribute(.paragraphStyle, value: newStyle, range: range)
            }
            textStorage.endEditing()
        }
    }

    /// 色設定をテキストビューに適用
    private func applyColorsToTextViews(_ colors: NewDocData.FontAndColorsData.Colors) {
        // テキストビューの色を適用するヘルパー
        func applyTextViewColors(_ textView: NSTextView, scrollView: NSScrollView? = nil) {
            textView.backgroundColor = colors.background.nsColor
            textView.textColor = colors.character.nsColor
            textView.insertionPointColor = colors.caret.nsColor
            var newAttributes = textView.selectedTextAttributes
            newAttributes[.backgroundColor] = colors.highlight.nsColor
            textView.selectedTextAttributes = newAttributes

            // 不可視文字の色を適用
            if let layoutManager = textView.layoutManager as? InvisibleCharacterLayoutManager {
                layoutManager.invisibleCharacterColor = colors.invisible.nsColor
            }

            // ScrollViewの背景色も設定（Continuousモード用）
            scrollView?.backgroundColor = colors.background.nsColor
        }

        // Continuous モードの場合
        if let scrollView = scrollView1,
           let textView = scrollView.documentView as? NSTextView {
            applyTextViewColors(textView, scrollView: scrollView)
        }
        if let scrollView = scrollView2,
           !scrollView.isHidden,
           let textView = scrollView.documentView as? NSTextView {
            applyTextViewColors(textView, scrollView: scrollView)
        }

        // Page モードの場合
        for textView in textViews1 {
            applyTextViewColors(textView)
        }
        for textView in textViews2 {
            applyTextViewColors(textView)
        }

        // 行番号ビューの色を適用（Continuousモード）
        lineNumberView1?.lineNumberColor = colors.lineNumber.nsColor
        lineNumberView1?.lineNumberBackgroundColor = colors.lineNumberBackground.nsColor
        lineNumberView2?.lineNumberColor = colors.lineNumber.nsColor
        lineNumberView2?.lineNumberBackgroundColor = colors.lineNumberBackground.nsColor

        // ページモードのヘッダー・フッター・行番号色を適用
        pagesView1?.headerColor = colors.header.nsColor
        pagesView1?.footerColor = colors.footer.nsColor
        pagesView1?.lineNumberTextColor = colors.lineNumber.nsColor
        pagesView2?.headerColor = colors.header.nsColor
        pagesView2?.footerColor = colors.footer.nsColor
        pagesView2?.lineNumberTextColor = colors.lineNumber.nsColor
    }

    @objc private func lineNumberSizeDidChange(_ notification: Notification) {
        // 行番号ビューのサイズが変更されたら制約を更新
        guard displayMode == .continuous else { return }

        if let lineNumberView = notification.object as? LineNumberView {
            if lineNumberView === lineNumberView1 {
                if isVerticalLayout {
                    lineNumberWidthConstraint1?.constant = lineNumberView.currentHeight
                } else {
                    lineNumberWidthConstraint1?.constant = lineNumberView.currentWidth
                }
            } else if lineNumberView === lineNumberView2 {
                if isVerticalLayout {
                    lineNumberWidthConstraint2?.constant = lineNumberView.currentHeight
                } else {
                    lineNumberWidthConstraint2?.constant = lineNumberView.currentWidth
                }
            }
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

        // contentViewObserversを削除
        for observer in contentViewObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        contentViewObservers.removeAll()

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

        // 既存の行番号ビューをクリアし、ScrollViewの制約を復元
        if lineNumberView1 != nil, let scrollView = scrollView1, let parentView = scrollView.superview {
            lineNumberView1?.removeFromSuperview()
            lineNumberView1 = nil
            lineNumberWidthConstraint1 = nil
            // ScrollViewの制約を復元
            let scrollViewConstraints = parentView.constraints.filter { constraint in
                (constraint.firstItem as? NSView) === scrollView || (constraint.secondItem as? NSView) === scrollView
            }
            NSLayoutConstraint.deactivate(scrollViewConstraints)
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                scrollView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
                scrollView.topAnchor.constraint(equalTo: parentView.topAnchor),
                scrollView.bottomAnchor.constraint(equalTo: parentView.bottomAnchor)
            ])
        }
        if lineNumberView2 != nil, let scrollView = scrollView2, let parentView = scrollView.superview {
            lineNumberView2?.removeFromSuperview()
            lineNumberView2 = nil
            lineNumberWidthConstraint2 = nil
            // ScrollViewの制約を復元
            let scrollViewConstraints = parentView.constraints.filter { constraint in
                (constraint.firstItem as? NSView) === scrollView || (constraint.secondItem as? NSView) === scrollView
            }
            NSLayoutConstraint.deactivate(scrollViewConstraints)
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                scrollView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
                scrollView.topAnchor.constraint(equalTo: parentView.topAnchor),
                scrollView.bottomAnchor.constraint(equalTo: parentView.bottomAnchor)
            ])
        }

        // 表示モードに応じてセットアップ
        switch displayMode {
        case .continuous:
            setupContinuousMode(with: textStorage)
            // lineWrapModeに応じたサイズ設定を適用（setupContinuousModeは常にウィンドウ幅で初期化するため）
            // 初期化時はpresetDataを更新しない（読み込んだ設定を保持するため）
            applyLineWrapMode(updatePresetData: false)
        case .page:
            setupPageMode(with: textStorage)
        }

        // モード切り替え後にInspector barとルーラーの状態を確実に反映
        updateInspectorBarVisibility()
        updateRulerVisibility()

        // テキスト編集設定を適用
        applyTextEditingPreferences()
    }

    private func setupContinuousMode(with textStorage: NSTextStorage) {
        // splitViewの表示されているサブビューの数を取得
        guard let splitView = splitView else { return }
        let visibleSubviews = splitView.subviews.filter { !$0.isHidden }
        let numberOfViews = visibleSubviews.count

        // 必要な数のLayoutManagerを作成（不可視文字表示対応）
        var layoutManagers: [InvisibleCharacterLayoutManager] = []
        for _ in 0..<numberOfViews {
            let layoutManager = InvisibleCharacterLayoutManager()
            layoutManager.invisibleCharacterOptions = invisibleCharacterOptions
            textStorage.addLayoutManager(layoutManager)
            layoutManagers.append(layoutManager)
        }

        // TextView1の設定（常に設定）
        if numberOfViews >= 1, let scrollView = scrollView1 {
            let containerInset = textDocument!.containerInset

            // 行番号ビューを設定
            setupLineNumberView(for: scrollView, lineNumberViewRef: &lineNumberView1, constraintRef: &lineNumberWidthConstraint1)

            // TextContainerを作成
            // widthTracksTextView = false で手動でサイズ管理
            let textContainerSize: NSSize
            if isVerticalLayout {
                // 縦書き: 高さ（行の長さ）をウィンドウ高さに合わせる
                let availableHeight = scrollView.contentView.frame.height
                let containerHeight = availableHeight - (containerInset.height * 2)
                textContainerSize = NSSize(width: containerHeight > 0 ? containerHeight : availableHeight, height: CGFloat.greatestFiniteMagnitude)
            } else {
                // 横書き: 幅（行の長さ）をウィンドウ幅に合わせる
                let availableWidth = scrollView.contentView.frame.width
                let containerWidth = availableWidth - (containerInset.width * 2)
                textContainerSize = NSSize(width: containerWidth > 0 ? containerWidth : availableWidth, height: CGFloat.greatestFiniteMagnitude)
            }
            let textContainer = NSTextContainer(containerSize: textContainerSize)
            textContainer.widthTracksTextView = false
            textContainer.heightTracksTextView = false
            textContainer.lineFragmentPadding = 5.0

            // LayoutManagerにTextContainerを追加
            let layoutManager = layoutManagers[0]
            layoutManager.addTextContainer(textContainer)

            // TextViewを作成（画像クリック対応）
            let availableWidth = scrollView.contentView.frame.width
            let availableHeight = scrollView.contentView.frame.height
            let textViewFrame = NSRect(x: 0, y: 0, width: availableWidth, height: availableHeight)
            let textView = ImageClickableTextView(frame: textViewFrame, textContainer: textContainer)
            textView.isEditable = true
            textView.isSelectable = true
            textView.allowsUndo = true
            // 縦書き/横書きに応じてリサイズ方向を設定
            textView.isHorizontallyResizable = isVerticalLayout
            textView.isVerticallyResizable = !isVerticalLayout
            textView.autoresizingMask = []
            textView.usesInspectorBar = isInspectorBarVisible
            textView.usesRuler = true
            // textContainerInsetで左右と上下のインセットを設定
            textView.textContainerInset = containerInset
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            // Document Colorsが設定されている場合はそれを使用、なければデフォルト
            if let colors = textDocument?.presetData?.fontAndColors.colors {
                textView.backgroundColor = colors.background.nsColor
                textView.textColor = colors.character.nsColor
                scrollView.backgroundColor = colors.background.nsColor
            } else if textDocument?.documentType == .plain {
                // ダークモード対応（プレーンテキストのみ）
                textView.backgroundColor = .textBackgroundColor
                textView.textColor = .textColor
                scrollView.backgroundColor = .textBackgroundColor
            } else {
                // リッチテキストは白背景固定（文字色はユーザー設定を保持）
                textView.backgroundColor = .white
                scrollView.backgroundColor = .white
            }

            // ImageResizeControllerを設定
            if imageResizeController == nil {
                imageResizeController = ImageResizeController(textStorage: textStorage, undoManager: textDocument?.undoManager)
            }
            textView.imageResizeController = imageResizeController

            // ScrollViewに設定
            scrollView.documentView = textView
            // スクロールバーを両方とも常に表示
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = true
            scrollView.autohidesScrollers = false
            // 縦書き時は縦ルーラー、横書き時は横ルーラーを使用
            scrollView.hasHorizontalRuler = !isVerticalLayout
            scrollView.hasVerticalRuler = isVerticalLayout
            // カスタムルーラーを設定
            setupLabeledRuler(for: scrollView)
            scrollView.rulersVisible = isRulerVisible

            // 縦書き/横書きレイアウトを適用
            textView.setLayoutOrientation(isVerticalLayout ? .vertical : .horizontal)

            // lineNumberViewにtextViewを設定
            lineNumberView1?.textView = textView

            // contentViewのフレーム変更を監視
            scrollView.contentView.postsFrameChangedNotifications = true
            let observer = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let self = self, let scrollView = scrollView else { return }
                self.updateTextViewSize(for: scrollView)
            }
            contentViewObservers.append(observer)

            // 選択範囲変更を監視してルーラーのキャレット位置を更新
            let selectionObserver = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: textView,
                queue: .main
            ) { [weak self] notification in
                self?.textViewSelectionDidChange(notification)
            }
            textViewObservers.append(selectionObserver)
        }

        // TextView2の設定（サブビューが2つ以上の場合のみ）
        if numberOfViews >= 2, let scrollView = scrollView2 {
            let containerInset = textDocument!.containerInset

            // 行番号ビューを設定
            setupLineNumberView(for: scrollView, lineNumberViewRef: &lineNumberView2, constraintRef: &lineNumberWidthConstraint2)

            // TextContainerを作成
            // widthTracksTextView = false で手動でサイズ管理
            let textContainerSize: NSSize
            if isVerticalLayout {
                // 縦書き: 高さ（行の長さ）をウィンドウ高さに合わせる
                let availableHeight = scrollView.contentView.frame.height
                let containerHeight = availableHeight - (containerInset.height * 2)
                textContainerSize = NSSize(width: containerHeight > 0 ? containerHeight : availableHeight, height: CGFloat.greatestFiniteMagnitude)
            } else {
                // 横書き: 幅（行の長さ）をウィンドウ幅に合わせる
                let availableWidth = scrollView.contentView.frame.width
                let containerWidth = availableWidth - (containerInset.width * 2)
                textContainerSize = NSSize(width: containerWidth > 0 ? containerWidth : availableWidth, height: CGFloat.greatestFiniteMagnitude)
            }
            let textContainer = NSTextContainer(containerSize: textContainerSize)
            textContainer.widthTracksTextView = false
            textContainer.heightTracksTextView = false
            textContainer.lineFragmentPadding = 5.0

            // LayoutManagerにTextContainerを追加
            let layoutManager = layoutManagers[1]
            layoutManager.addTextContainer(textContainer)

            // TextViewを作成（画像クリック対応）
            let availableWidth = scrollView.contentView.frame.width
            let availableHeight = scrollView.contentView.frame.height
            let textViewFrame = NSRect(x: 0, y: 0, width: availableWidth, height: availableHeight)
            let textView = ImageClickableTextView(frame: textViewFrame, textContainer: textContainer)
            textView.isEditable = true
            textView.isSelectable = true
            textView.allowsUndo = true
            // 縦書き/横書きに応じてリサイズ方向を設定
            textView.isHorizontallyResizable = isVerticalLayout
            textView.isVerticallyResizable = !isVerticalLayout
            textView.autoresizingMask = []
            textView.usesInspectorBar = isInspectorBarVisible
            textView.usesRuler = true
            // textContainerInsetで左右と上下のインセットを設定
            textView.textContainerInset = containerInset
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            // Document Colorsが設定されている場合はそれを使用、なければデフォルト
            if let colors = textDocument?.presetData?.fontAndColors.colors {
                textView.backgroundColor = colors.background.nsColor
                textView.textColor = colors.character.nsColor
                scrollView.backgroundColor = colors.background.nsColor
            } else if textDocument?.documentType == .plain {
                // ダークモード対応（プレーンテキストのみ）
                textView.backgroundColor = .textBackgroundColor
                textView.textColor = .textColor
                scrollView.backgroundColor = .textBackgroundColor
            } else {
                // リッチテキストは白背景固定（文字色はユーザー設定を保持）
                textView.backgroundColor = .white
                scrollView.backgroundColor = .white
            }

            // ImageResizeControllerを設定
            if imageResizeController == nil {
                imageResizeController = ImageResizeController(textStorage: textStorage, undoManager: textDocument?.undoManager)
            }
            textView.imageResizeController = imageResizeController

            // ScrollViewに設定
            scrollView.documentView = textView
            // スクロールバーを両方とも常に表示
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = true
            scrollView.autohidesScrollers = false
            // 縦書き時は縦ルーラー、横書き時は横ルーラーを使用
            scrollView.hasHorizontalRuler = !isVerticalLayout
            scrollView.hasVerticalRuler = isVerticalLayout
            // カスタムルーラーを設定
            setupLabeledRuler(for: scrollView)
            scrollView.rulersVisible = isRulerVisible

            // 縦書き/横書きレイアウトを適用
            textView.setLayoutOrientation(isVerticalLayout ? .vertical : .horizontal)

            // lineNumberViewにtextViewを設定
            lineNumberView2?.textView = textView

            // contentViewのフレーム変更を監視
            scrollView.contentView.postsFrameChangedNotifications = true
            let observer = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let self = self, let scrollView = scrollView else { return }
                self.updateTextViewSize(for: scrollView)
            }
            contentViewObservers.append(observer)

            // 選択範囲変更を監視してルーラーのキャレット位置を更新
            let selectionObserver = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: textView,
                queue: .main
            ) { [weak self] notification in
                self?.textViewSelectionDidChange(notification)
            }
            textViewObservers.append(selectionObserver)
        }
    }

    /// 行番号ビューをセットアップ
    private func setupLineNumberView(for scrollView: NSScrollView, lineNumberViewRef: inout LineNumberView?, constraintRef: inout NSLayoutConstraint?) {
        // 既存の行番号ビューを削除
        lineNumberViewRef?.removeFromSuperview()
        lineNumberViewRef = nil
        constraintRef = nil

        guard lineNumberMode != .none,
              let parentView = scrollView.superview else { return }

        // ScrollViewの既存の制約を削除
        let scrollViewConstraints = parentView.constraints.filter { constraint in
            (constraint.firstItem as? NSView) === scrollView || (constraint.secondItem as? NSView) === scrollView
        }
        NSLayoutConstraint.deactivate(scrollViewConstraints)

        // 行番号ビューを作成
        let lineNumberView = LineNumberView(frame: .zero)
        lineNumberView.lineNumberMode = lineNumberMode
        lineNumberView.isVerticalLayout = isVerticalLayout
        lineNumberView.translatesAutoresizingMaskIntoConstraints = false
        parentView.addSubview(lineNumberView)

        // ScrollViewのAuto Layout制約を再設定
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        if isVerticalLayout {
            // 縦書き時は行番号ビューを上部に配置
            let heightConstraint = lineNumberView.heightAnchor.constraint(equalToConstant: lineNumberView.currentHeight)
            NSLayoutConstraint.activate([
                lineNumberView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
                lineNumberView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
                lineNumberView.topAnchor.constraint(equalTo: parentView.topAnchor),
                heightConstraint
            ])

            // ScrollViewの制約を更新（行番号ビューの下側に配置）
            NSLayoutConstraint.activate([
                scrollView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
                scrollView.topAnchor.constraint(equalTo: lineNumberView.bottomAnchor),
                scrollView.bottomAnchor.constraint(equalTo: parentView.bottomAnchor)
            ])

            constraintRef = heightConstraint
        } else {
            // 横書き時は行番号ビューを左側に配置
            let widthConstraint = lineNumberView.widthAnchor.constraint(equalToConstant: lineNumberView.currentWidth)
            NSLayoutConstraint.activate([
                lineNumberView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
                lineNumberView.topAnchor.constraint(equalTo: parentView.topAnchor),
                lineNumberView.bottomAnchor.constraint(equalTo: parentView.bottomAnchor),
                widthConstraint
            ])

            // ScrollViewの制約を更新（行番号ビューの右側に配置）
            NSLayoutConstraint.activate([
                scrollView.leadingAnchor.constraint(equalTo: lineNumberView.trailingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
                scrollView.topAnchor.constraint(equalTo: parentView.topAnchor),
                scrollView.bottomAnchor.constraint(equalTo: parentView.bottomAnchor)
            ])

            constraintRef = widthConstraint
        }

        lineNumberViewRef = lineNumberView
    }

    private func setupPageMode(with textStorage: NSTextStorage) {
        // splitViewの表示されているサブビューの数を取得
        guard let splitView = splitView else { return }
        let visibleSubviews = splitView.subviews.filter { !$0.isHidden }
        let numberOfViews = visibleSubviews.count

        // 推定ページ数を計算（1ページあたりの文字数を概算）
        let charsPerPage = 1000
        let estimatedPages = max(1, (textStorage.length + charsPerPage - 1) / charsPerPage)

        // 必要な数のLayoutManagerを作成（不可視文字表示対応）
        var layoutManagers: [InvisibleCharacterLayoutManager] = []
        for _ in 0..<numberOfViews {
            let layoutManager = InvisibleCharacterLayoutManager()
            layoutManager.invisibleCharacterOptions = invisibleCharacterOptions
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
            pagesView.isVerticalLayout = isVerticalLayout
            pagesView.documentName = textDocument?.displayName ?? ""
            pagesView.isPlainText = textDocument?.documentType == .plain
            pagesView.lineNumberMode = lineNumberMode
            pagesView.layoutManager = layoutManager
            scrollView.documentView = pagesView
            pagesView1 = pagesView

            // ScrollViewの設定
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = true
            // 縦書き時は縦ルーラー、横書き時は横ルーラーを使用
            scrollView.hasHorizontalRuler = !isVerticalLayout
            scrollView.hasVerticalRuler = isVerticalLayout
            // カスタムルーラーを設定
            setupLabeledRuler(for: scrollView)
            scrollView.rulersVisible = isRulerVisible
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
            pagesView.isVerticalLayout = isVerticalLayout
            pagesView.documentName = textDocument?.displayName ?? ""
            pagesView.isPlainText = textDocument?.documentType == .plain
            pagesView.lineNumberMode = lineNumberMode
            pagesView.layoutManager = layoutManager
            scrollView.documentView = pagesView
            pagesView2 = pagesView

            // ScrollViewの設定
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = true
            // 縦書き時は縦ルーラー、横書き時は横ルーラーを使用
            scrollView.hasHorizontalRuler = !isVerticalLayout
            scrollView.hasVerticalRuler = isVerticalLayout
            // カスタムルーラーを設定
            setupLabeledRuler(for: scrollView)
            scrollView.rulersVisible = isRulerVisible
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

                // 行番号表示のため再描画
                self.pagesView1?.needsDisplay = true
            }

            // layoutManager2にTextStorageを追加（スプリット時のみ）
            if let layoutManager = self.layoutManager2 {
                textStorage.addLayoutManager(layoutManager)

                // 最初のページのレイアウトを即座に実行
                if let firstContainer = self.textContainers2.first {
                    layoutManager.ensureLayout(for: firstContainer)
                }

                // 行番号表示のため再描画
                self.pagesView2?.needsDisplay = true
            }

            // 縦書き時は右端（1ページ目）にスクロール（レイアウト完了後に実行）
            if self.isVerticalLayout {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self = self else { return }
                    self.scrollToFirstPageForVerticalLayout()
                }
            }
        }
    }

    /// 縦書き時に1ページ目（右端）にスクロール
    private func scrollToFirstPageForVerticalLayout() {
        if let scrollView = scrollView1, let pagesView = pagesView1 {
            let maxX = max(0, pagesView.frame.width - scrollView.contentView.bounds.width)
            scrollView.contentView.scroll(to: NSPoint(x: maxX, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        if let scrollView = scrollView2, let pagesView = pagesView2, !scrollView.isHidden {
            let maxX = max(0, pagesView.frame.width - scrollView.contentView.bounds.width)
            scrollView.contentView.scroll(to: NSPoint(x: maxX, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
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

        // 縦書き時の右から左配置のために、先にページ数を設定
        pagesView.setNumberOfPages(count)

        let textContainerSize = pagesView.documentSizeInPage

        // ImageResizeControllerを確保
        if imageResizeController == nil, let textStorage = layoutManager.textStorage {
            imageResizeController = ImageResizeController(textStorage: textStorage, undoManager: textDocument?.undoManager)
        }

        // すべてのページを一度に作成
        for pageIndex in 0..<count {
            // TextContainerを作成
            let textContainer = NSTextContainer(containerSize: textContainerSize)
            textContainer.widthTracksTextView = false
            textContainer.heightTracksTextView = false

            // LayoutManagerにTextContainerを追加
            layoutManager.addTextContainer(textContainer)

            // TextViewを作成（画像クリック対応）
            let documentRect = pagesView.documentRect(forPageNumber: pageIndex)
            let textView = ImageClickableTextView(frame: documentRect, textContainer: textContainer)
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
            textView.usesRuler = true
            // 縦書き/横書きレイアウトを適用
            textView.setLayoutOrientation(isVerticalLayout ? .vertical : .horizontal)
            // ImageResizeControllerを設定
            textView.imageResizeController = imageResizeController

            textContainers.append(textContainer)
            textViews.append(textView)
            pagesView.addSubview(textView)
        }

        // 配列をプロパティに保存
        switch target {
        case .scrollView1:
            textContainers1 = textContainers
            textViews1 = textViews
        case .scrollView2:
            textContainers2 = textContainers
            textViews2 = textViews
        }

        // 各テキストビューの選択範囲変更を監視
        for textView in textViews {
            let selectionObserver = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: textView,
                queue: .main
            ) { [weak self] notification in
                self?.textViewSelectionDidChange(notification)
            }
            textViewObservers.append(selectionObserver)
        }
    }

    // MARK: - Zoom Actions

    @IBAction func zoomIn(_ sender: Any?) {
        scrollView1?.zoomIn()
        scrollView2?.zoomIn()
        updatePresetDataScale()
    }

    @IBAction func zoomOut(_ sender: Any?) {
        scrollView1?.zoomOut()
        scrollView2?.zoomOut()
        updatePresetDataScale()
    }

    @IBAction func resetZoom(_ sender: Any?) {
        scrollView1?.resetZoom()
        scrollView2?.resetZoom()
        updatePresetDataScale()
    }

    /// presetData のスケールを更新
    private func updatePresetDataScale() {
        if let scale = scrollView1?.magnification {
            textDocument?.presetData?.view.scale = scale
            markDocumentAsEdited()
        }
    }

    // MARK: - Split View Actions

    @IBAction func toggleSplitView(_ sender: Any?) {
        // 現在のモードに応じてトグル
        if splitMode == .none {
            setSplitMode(.vertical)
        } else {
            setSplitMode(.none)
        }
    }

    @IBAction func setNoSplit(_ sender: Any?) {
        setSplitMode(.none)
    }

    @IBAction func setHorizontalSplit(_ sender: Any?) {
        setSplitMode(.horizontal)
    }

    @IBAction func setVerticalSplit(_ sender: Any?) {
        setSplitMode(.vertical)
    }

    /// スプリットボタンから呼び出す: 単一ビューに戻す
    @objc func collapseViews(_ sender: Any?) {
        setSplitMode(.none)
    }

    /// スプリットボタンから呼び出す: 水平分割
    @objc func splitHorizontally(_ sender: Any?) {
        setSplitMode(.horizontal)
    }

    /// スプリットボタンから呼び出す: 垂直分割
    @objc func splitVertically(_ sender: Any?) {
        setSplitMode(.vertical)
    }

    private func setSplitMode(_ mode: SplitMode) {
        guard let splitView = splitView else { return }

        splitMode = mode

        switch mode {
        case .none:
            // 2つ目のペインを折りたたむ
            if splitView.subviews.count > 1 {
                splitView.subviews[1].isHidden = true
            }
        case .horizontal:
            // 水平スプリット（上下に分割）
            splitView.isVertical = false
            if splitView.subviews.count > 1 {
                splitView.subviews[1].isHidden = false
            }
        case .vertical:
            // 垂直スプリット（左右に分割）
            splitView.isVertical = true
            if splitView.subviews.count > 1 {
                splitView.subviews[1].isHidden = false
            }
        }

        splitView.adjustSubviews()

        // splitViewの状態に合わせてtextViewsを再設定
        if let textDocument = self.textDocument {
            setupTextViews(with: textDocument.textStorage)
        }

        // ルーラーの表示状態を更新（updateContinuousModeRuler内でtile()とupdateTextViewSizeが呼ばれる）
        updateRulerVisibility()

        // スプリット直後はcontentViewのフレームがまだ更新されていない場合があるため、
        // 次のランループでもう一度ルーラーとテキストビューサイズを更新
        DispatchQueue.main.async { [weak self] in
            self?.updateRulerVisibility()
        }
    }

    // MARK: - Display Mode Actions

    @IBAction func toggleDisplayMode(_ sender: Any?) {
        // 現在の選択範囲を保存
        let savedRange = getCurrentSelectedRange()

        // モードを切り替え
        switch displayMode {
        case .continuous:
            // ページモードへの切り替え時は警告チェック
            switchToPageModeWithWarning(savedRange: savedRange)
            return
        case .page:
            displayMode = .continuous
        }

        // TextViewsを再設定
        if let textDocument = self.textDocument {
            setupTextViews(with: textDocument.textStorage)
            // Document Colorsを再適用
            if let colors = textDocument.presetData?.fontAndColors.colors {
                applyColorsToTextViews(colors)
            }
        }
        // ルーラー表示状態を引き継ぐ（レイアウト完了後に実行）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updateRulerVisibility()
        }

        // 選択範囲を復元してスクロール
        if let range = savedRange {
            restoreSelectionAndScrollToVisible(range, delay: 0.2)
        }

        // presetData に反映
        textDocument?.presetData?.view.pageMode = (displayMode == .page)
        markDocumentAsEdited()
    }

    @IBAction func switchToContinuousMode(_ sender: Any?) {
        // 現在の選択範囲を保存
        let savedRange = getCurrentSelectedRange()

        displayMode = .continuous
        if let textDocument = self.textDocument {
            setupTextViews(with: textDocument.textStorage)
            // Document Colorsを再適用
            if let colors = textDocument.presetData?.fontAndColors.colors {
                applyColorsToTextViews(colors)
            }
        }
        // ルーラー表示状態を引き継ぐ（レイアウト完了後に実行）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.updateRulerVisibility()
        }

        // 選択範囲を復元してスクロール
        if let range = savedRange {
            restoreSelectionAndScrollToVisible(range, delay: 0.2)
        }

        // presetData に反映
        textDocument?.presetData?.view.pageMode = false
        markDocumentAsEdited()
    }

    @IBAction func switchToPageMode(_ sender: Any?) {
        switchToPageModeWithWarning(savedRange: getCurrentSelectedRange())
    }

    private func switchToPageModeWithWarning(savedRange: NSRange? = nil) {
        guard let textDocument = self.textDocument else { return }
        displayMode = .page
        setupTextViews(with: textDocument.textStorage)
        // Document Colorsを再適用
        if let colors = textDocument.presetData?.fontAndColors.colors {
            applyColorsToTextViews(colors)
        }
        // ルーラー表示状態を引き継ぐ（レイアウト完了後に実行）
        // レイアウト処理が完了するまで待つ必要があるため、遅延を長めに設定
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updateRulerVisibility()
        }

        // 選択範囲を復元してスクロール
        if let range = savedRange {
            restoreSelectionAndScrollToVisible(range, delay: 0.3)
        }

        // presetData に反映
        textDocument.presetData?.view.pageMode = true
        markDocumentAsEdited()
    }

    // MARK: - Line Wrap Mode Actions (for Continuous mode)

    @IBAction func setLineWrapPaperWidth(_ sender: Any?) {
        lineWrapMode = .paperWidth
        applyLineWrapMode()
    }

    @IBAction func setLineWrapWindowWidth(_ sender: Any?) {
        lineWrapMode = .windowWidth
        applyLineWrapMode()
    }

    @IBAction func setLineWrapNoWrap(_ sender: Any?) {
        lineWrapMode = .noWrap
        applyLineWrapMode()
    }

    @IBAction func setLineWrapFixedWidth(_ sender: Any?) {
        // 固定幅を文字数で入力するダイアログを表示
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Fixed Width", comment: "")
        alert.informativeText = NSLocalizedString("Enter the document width in characters:", comment: "")
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        // アクセサリビュー（テキストフィールド + ラベル）
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        textField.integerValue = fixedWrapWidthInChars
        textField.alignment = .right
        // NumberFormatterを設定
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 10
        formatter.maximum = 9999
        formatter.allowsFloats = false
        textField.formatter = formatter
        containerView.addSubview(textField)

        let label = NSTextField(labelWithString: NSLocalizedString("chars.", comment: ""))
        label.frame = NSRect(x: 85, y: 4, width: 50, height: 17)
        containerView.addSubview(label)

        alert.accessoryView = containerView

        guard let window = self.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                let chars = textField.integerValue
                if chars >= 10 && chars <= 9999 {
                    self?.fixedWrapWidthInChars = chars
                    self?.lineWrapMode = .fixedWidth
                    self?.applyLineWrapMode()
                }
            }
        }
    }

    /// 固定幅をポイント値で取得（文字数 × 基本文字幅）
    private func getFixedWrapWidthInPoints() -> CGFloat {
        let charWidth: CGFloat
        if let presetData = textDocument?.presetData {
            let fontData = presetData.fontAndColors
            if let basicFont = NSFont(name: fontData.baseFontName, size: fontData.baseFontSize) {
                charWidth = basicCharWidth(from: basicFont)
            } else {
                charWidth = 8.0  // フォントが見つからない場合のデフォルト
            }
        } else {
            // presetDataがない場合はシステムフォントを使用
            let systemFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            charWidth = basicCharWidth(from: systemFont)
        }
        return CGFloat(fixedWrapWidthInChars) * charWidth
    }

    private func applyLineWrapMode(updatePresetData: Bool = true) {
        // presetData に反映（メニューからの変更時のみ更新、初期化時は更新しない）
        if updatePresetData {
            updatePresetDataDocWidth()
        }

        guard displayMode == .continuous else { return }

        // ScalingScrollViewのautoAdjustsContainerSizeOnFrameChangeを設定
        // 横書きのwindowWidthモードのみScalingScrollViewにコンテナサイズ調整を任せる
        // 縦書きでは常にfalse（textViewの幅が縮小されるのを防ぐため）
        let autoAdjust = !isVerticalLayout && (lineWrapMode == .windowWidth)
        if let scalingScrollView = scrollView1 as? ScalingScrollView {
            scalingScrollView.autoAdjustsContainerSizeOnFrameChange = autoAdjust
        }
        if let scalingScrollView = scrollView2 as? ScalingScrollView {
            scalingScrollView.autoAdjustsContainerSizeOnFrameChange = autoAdjust
        }

        if let scrollView = scrollView1 {
            updateTextViewSize(for: scrollView)
        }
        if let scrollView = scrollView2, !scrollView.isHidden {
            updateTextViewSize(for: scrollView)
        }
    }

    /// presetData の Document Width 設定を更新
    private func updatePresetDataDocWidth() {
        syncDocWidthToPresetData()
        markDocumentAsEdited()
    }

    /// 現在の Document Width 設定を presetData に同期
    private func syncDocWidthToPresetData() {
        switch lineWrapMode {
        case .paperWidth:
            textDocument?.presetData?.view.docWidthType = .paperWidth
        case .windowWidth:
            textDocument?.presetData?.view.docWidthType = .windowWidth
        case .noWrap:
            textDocument?.presetData?.view.docWidthType = .noWrap
        case .fixedWidth:
            textDocument?.presetData?.view.docWidthType = .fixedWidth
            textDocument?.presetData?.view.fixedDocWidth = fixedWrapWidthInChars
        }
    }

    /// presetData の変更をマーク（保存時に拡張属性が更新される）
    /// ウィンドウタイトルに「Edited」は表示されない
    private func markDocumentAsEdited() {
        textDocument?.presetDataEdited = true
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
        switch displayMode {
        case .continuous:
            // scrollView1の行番号を更新
            if let scrollView = scrollView1,
               let textView = scrollView.documentView as? NSTextView {
                updateLineNumberView(for: scrollView, textView: textView, lineNumberViewRef: &lineNumberView1, constraintRef: &lineNumberWidthConstraint1)
            }

            // scrollView2の行番号を更新（splitViewが表示されている場合）
            if let scrollView = scrollView2,
               !scrollView.isHidden,
               let textView = scrollView.documentView as? NSTextView {
                updateLineNumberView(for: scrollView, textView: textView, lineNumberViewRef: &lineNumberView2, constraintRef: &lineNumberWidthConstraint2)
            }

        case .page:
            // ページモードではpagesViewの行番号モードを更新
            pagesView1?.lineNumberMode = lineNumberMode
            pagesView2?.lineNumberMode = lineNumberMode
        }

        // presetData に反映
        switch lineNumberMode {
        case .none:
            textDocument?.presetData?.view.lineNumberType = .none
        case .paragraph:
            textDocument?.presetData?.view.lineNumberType = .logical
        case .row:
            textDocument?.presetData?.view.lineNumberType = .physical
        }
        markDocumentAsEdited()
    }

    private func updateLineNumberView(for scrollView: NSScrollView, textView: NSTextView, lineNumberViewRef: inout LineNumberView?, constraintRef: inout NSLayoutConstraint?) {
        if lineNumberMode != .none {
            if let existingView = lineNumberViewRef {
                // 既存の行番号ビューがある場合はモードを更新
                existingView.lineNumberMode = lineNumberMode
            } else {
                // 新しい行番号ビューを作成
                setupLineNumberView(for: scrollView, lineNumberViewRef: &lineNumberViewRef, constraintRef: &constraintRef)
                lineNumberViewRef?.textView = textView
            }
        } else {
            // 行番号ビューを削除
            lineNumberViewRef?.removeFromSuperview()
            lineNumberViewRef = nil
            constraintRef = nil

            // ScrollViewの制約をリセット（親ビューいっぱいに広げる）
            if let parentView = scrollView.superview {
                // ScrollViewの既存の制約を削除
                let scrollViewConstraints = parentView.constraints.filter { constraint in
                    (constraint.firstItem as? NSView) === scrollView || (constraint.secondItem as? NSView) === scrollView
                }
                NSLayoutConstraint.deactivate(scrollViewConstraints)

                scrollView.translatesAutoresizingMaskIntoConstraints = false
                // 新しい制約を追加
                NSLayoutConstraint.activate([
                    scrollView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
                    scrollView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
                    scrollView.topAnchor.constraint(equalTo: parentView.topAnchor),
                    scrollView.bottomAnchor.constraint(equalTo: parentView.bottomAnchor)
                ])
            }
        }
    }

    // MARK: - Ruler Actions

    @IBAction func showHideTextRuler(_ sender: Any?) {
        isRulerVisible = !isRulerVisible
        updateRulerVisibility()
        updatePresetDataRulerType()
    }

    @IBAction func setRulerHide(_ sender: Any?) {
        rulerType = .none
        isRulerVisible = false
        updateRulerVisibility()
        updatePresetDataRulerType()
    }

    @IBAction func setRulerPoints(_ sender: Any?) {
        rulerType = .point
        isRulerVisible = true
        updateRulerVisibility()
        updatePresetDataRulerType()
    }

    @IBAction func setRulerCentimeters(_ sender: Any?) {
        rulerType = .centimeter
        isRulerVisible = true
        updateRulerVisibility()
        updatePresetDataRulerType()
    }

    @IBAction func setRulerInches(_ sender: Any?) {
        rulerType = .inch
        isRulerVisible = true
        updateRulerVisibility()
        updatePresetDataRulerType()
    }

    @IBAction func setRulerCharacters(_ sender: Any?) {
        rulerType = .character
        isRulerVisible = true
        updateRulerVisibility()
        updatePresetDataRulerType()
    }

    /// presetData のルーラータイプを更新
    private func updatePresetDataRulerType() {
        if isRulerVisible {
            textDocument?.presetData?.view.rulerType = rulerType
        } else {
            textDocument?.presetData?.view.rulerType = .none
        }
        markDocumentAsEdited()
    }

    private func updateRulerVisibility() {
        switch displayMode {
        case .continuous:
            updateContinuousModeRuler(scrollView: scrollView1, isFirstResponder: true)
            if let scrollView = scrollView2, !scrollView.isHidden {
                updateContinuousModeRuler(scrollView: scrollView, isFirstResponder: false)
            }
        case .page:
            updatePageModeRuler(scrollView: scrollView1, textViews: textViews1, isFirstResponder: true)
            if let scrollView = scrollView2, !scrollView.isHidden {
                updatePageModeRuler(scrollView: scrollView, textViews: textViews2, isFirstResponder: false)
            }
        }
    }

    /// 連続モードのルーラー設定
    private func updateContinuousModeRuler(scrollView: NSScrollView?, isFirstResponder: Bool) {
        guard let scrollView = scrollView,
              let textView = scrollView.documentView as? NSTextView else { return }

        // ルーラーの種類を切り替え（縦書き/横書き対応）
        let needsHorizontalRuler = !isVerticalLayout
        let needsVerticalRuler = isVerticalLayout
        let currentRuler = isVerticalLayout ? scrollView.verticalRulerView : scrollView.horizontalRulerView
        let needsRulerSetup = scrollView.hasHorizontalRuler != needsHorizontalRuler ||
                              scrollView.hasVerticalRuler != needsVerticalRuler ||
                              !(currentRuler is LabeledRulerView)

        // ルーラーを一度非表示にしてから再表示することで、レイアウトを強制的に再計算
        scrollView.rulersVisible = false

        if needsRulerSetup {
            scrollView.hasHorizontalRuler = needsHorizontalRuler
            scrollView.hasVerticalRuler = needsVerticalRuler
            // カスタムルーラーを再設定
            setupLabeledRuler(for: scrollView)
        }

        // tileを呼んでレイアウトを更新
        scrollView.tile()

        // ScrollViewのルーラー表示状態を更新
        scrollView.rulersVisible = isRulerVisible
        textView.isRulerVisible = isRulerVisible

        if isRulerVisible {
            let ruler = isVerticalLayout ? scrollView.verticalRulerView : scrollView.horizontalRulerView
            if let ruler = ruler {
                ruler.originOffset = textDocument?.containerInset.width ?? 0
                ruler.clientView = textView
                // ルーラーの単位を設定
                configureRulerUnit(ruler)
                if isFirstResponder {
                    window?.makeFirstResponder(textView)
                }
                textView.updateRuler()
            }
        }
        updateTextViewSize(for: scrollView)
    }

    /// ページモードのルーラー設定
    private func updatePageModeRuler(scrollView: NSScrollView?, textViews: [NSTextView], isFirstResponder: Bool) {
        guard let scrollView = scrollView else { return }

        // ルーラーの種類を切り替え
        scrollView.rulersVisible = false
        scrollView.hasHorizontalRuler = !isVerticalLayout
        scrollView.hasVerticalRuler = isVerticalLayout
        // カスタムルーラーを再設定
        setupLabeledRuler(for: scrollView)
        scrollView.tile()
        scrollView.rulersVisible = isRulerVisible

        // ルーラーの設定
        if let firstTextView = textViews.first {
            let ruler = isVerticalLayout ? scrollView.verticalRulerView : scrollView.horizontalRulerView
            if let ruler = ruler {
                ruler.clientView = firstTextView
                // ページモードでは、ルーラーの0地点をテキストの開始位置に合わせる
                // pageMargin + lineFragmentPadding（テキストコンテナのデフォルト値は5.0）
                let lineFragmentPadding = firstTextView.textContainer?.lineFragmentPadding ?? 5.0
                ruler.originOffset = pageMargin + lineFragmentPadding
                // ルーラーの単位を設定
                configureRulerUnit(ruler)
            }
            if isFirstResponder {
                window?.makeFirstResponder(firstTextView)
            }
            firstTextView.updateRuler()
        }
    }

    /// ScrollViewにカスタムルーラーを設定
    private func setupLabeledRuler(for scrollView: NSScrollView) {
        // 横ルーラーを設定
        if scrollView.hasHorizontalRuler {
            let horizontalRuler = LabeledRulerView(
                scrollView: scrollView,
                orientation: .horizontalRuler
            )
            // マーカーとアクセサリビュー用の予約スペースを0にして、
            // 縦ルーラーがある場合でもヘッダー領域を表示しない
            horizontalRuler.reservedThicknessForMarkers = 0
            horizontalRuler.reservedThicknessForAccessoryView = 0
            scrollView.horizontalRulerView = horizontalRuler
        } else {
            // 横ルーラーが不要な場合は明示的にnilを設定して、
            // 上部のスペースが確保されないようにする
            scrollView.horizontalRulerView = nil
        }

        // 縦ルーラーを設定
        if scrollView.hasVerticalRuler {
            let verticalRuler = LabeledRulerView(
                scrollView: scrollView,
                orientation: .verticalRuler
            )
            // マーカーとアクセサリビュー用の予約スペースを0にして、
            // 横ルーラーがある場合でもヘッダー領域を表示しない
            verticalRuler.reservedThicknessForMarkers = 0
            verticalRuler.reservedThicknessForAccessoryView = 0
            scrollView.verticalRulerView = verticalRuler
        } else {
            // 縦ルーラーが不要な場合は明示的にnilを設定して、
            // 左側のスペースが確保されないようにする
            scrollView.verticalRulerView = nil
        }
    }

    /// ルーラーの単位を設定
    private func configureRulerUnit(_ ruler: NSRulerView) {
        var labelText = ""

        switch rulerType {
        case .none:
            // noneの場合は表示しないため、ここには来ないはず
            break
        case .point:
            ruler.measurementUnits = .points
            labelText = "Points"
        case .centimeter:
            ruler.measurementUnits = .centimeters
            labelText = "cm"
        case .inch:
            ruler.measurementUnits = .inches
            labelText = "Inches"
        case .character:
            // 基本フォントから文字幅を計算してカスタム単位を登録
            if let presetData = textDocument?.presetData {
                let fontData = presetData.fontAndColors
                if let basicFont = NSFont(name: fontData.baseFontName, size: fontData.baseFontSize) {
                    let charWidth = basicCharWidth(from: basicFont)
                    registerCharacterRulerUnit(charWidth: charWidth)
                    ruler.measurementUnits = .characters
                    // フォント名とサイズを簡潔に表示
                    let shortName = basicFont.displayName ?? basicFont.fontName
                    labelText = "\(shortName) \(Int(fontData.baseFontSize))pt"
                }
            } else {
                // presetDataがない場合はシステムフォントを使用
                let systemFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
                let charWidth = basicCharWidth(from: systemFont)
                registerCharacterRulerUnit(charWidth: charWidth)
                ruler.measurementUnits = .characters
                labelText = "System \(Int(NSFont.systemFontSize))pt"
            }
        }

        // LabeledRulerViewの場合はラベルを設定
        if let labeledRuler = ruler as? LabeledRulerView {
            labeledRuler.typeLabel = labelText
        }
    }

    // MARK: - Caret Position Indicator

    /// テキストビューの選択範囲変更を監視してルーラーのキャレット位置を更新
    @objc private func textViewSelectionDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        updateRulerCaretPosition(for: textView)
    }

    /// ルーラー上のキャレット位置インジケータを更新
    private func updateRulerCaretPosition(for textView: NSTextView) {
        guard isRulerVisible else { return }
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        // キャレット位置（挿入点）を取得
        let selectedRange = textView.selectedRange()
        let insertionPoint = selectedRange.location

        // 挿入点のグリフインデックスを取得
        let glyphIndex: Int
        let useEndPosition: Bool
        if insertionPoint < layoutManager.numberOfGlyphs {
            glyphIndex = layoutManager.glyphIndexForCharacter(at: insertionPoint)
            useEndPosition = false
        } else if layoutManager.numberOfGlyphs > 0 {
            // 文書末尾の場合は最後のグリフの末尾を使用
            glyphIndex = layoutManager.numberOfGlyphs - 1
            useEndPosition = true
        } else {
            // 空の文書の場合
            glyphIndex = 0
            useEndPosition = false
        }

        // 対応するScrollViewを見つけてルーラーを更新
        if let scrollView = textView.enclosingScrollView {
            let lineFragmentPadding = textContainer.lineFragmentPadding
            let isPageMode = (displayMode == .page)

            if isVerticalLayout {
                // 縦書きモード：縦ルーラーを使用
                // 縦書きでは画面上は文字が上から下に流れるが、
                // NSLayoutManagerは内部的に横書きと同じ座標系を使用している
                // つまり location.x が文字の進行方向（縦ルーラーのY位置）に対応する
                if let verticalRuler = scrollView.verticalRulerView as? LabeledRulerView {
                    var caretY: CGFloat = 0

                    if layoutManager.numberOfGlyphs > 0 {
                        let safeGlyphIndex = max(0, min(glyphIndex, layoutManager.numberOfGlyphs - 1))

                        // lineFragmentRectを取得
                        var effectiveRange = NSRange()
                        let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: safeGlyphIndex, effectiveRange: &effectiveRange)

                        // グリフの位置を取得
                        let location = layoutManager.location(forGlyphAt: safeGlyphIndex)

                        // 縦書きでは location.x が縦方向の位置を示す
                        // lineFragmentRect.origin.x + location.x が縦ルーラー上のY位置になる
                        if useEndPosition {
                            // 文書末尾の場合、グリフの下端（右端）を使用
                            let glyphRange = NSRange(location: safeGlyphIndex, length: 1)
                            let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                            caretY = lineFragmentRect.origin.x + location.x + boundingRect.width
                        } else {
                            // 通常はグリフの上端（左端）を使用
                            caretY = lineFragmentRect.origin.x + location.x
                        }
                    }

                    // lineFragmentPaddingを引いてルーラーの0地点と一致させる
                    var adjustedCaretY = caretY - lineFragmentPadding

                    if isPageMode {
                        // ページモードでの調整
                        adjustedCaretY += textView.frame.origin.y - pageMargin
                    }

                    verticalRuler.caretPosition = adjustedCaretY
                }
            } else {
                // 横書きモード：横ルーラーを使用
                // lineFragmentRectとlocationを使用して正確な位置を計算
                var effectiveRange = NSRange()
                let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: max(0, min(glyphIndex, layoutManager.numberOfGlyphs - 1)), effectiveRange: &effectiveRange)

                // グリフの行フラグメント内での位置を取得
                let locationInLineFragment: NSPoint
                if layoutManager.numberOfGlyphs > 0 {
                    locationInLineFragment = layoutManager.location(forGlyphAt: glyphIndex)
                } else {
                    locationInLineFragment = .zero
                }

                // テキストコンテナ座標でのキャレットX位置を計算
                let caretX: CGFloat
                if useEndPosition {
                    // 文書末尾の場合、グリフの右端を使用
                    let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
                    caretX = glyphRect.maxX
                } else {
                    caretX = lineFragmentRect.origin.x + locationInLineFragment.x
                }

                if let horizontalRuler = scrollView.horizontalRulerView as? LabeledRulerView {
                    var adjustedCaretX = caretX - lineFragmentPadding
                    if isPageMode {
                        // ページモードでの調整
                        adjustedCaretX += textView.frame.origin.x - pageMargin
                    }
                    horizontalRuler.caretPosition = adjustedCaretX
                }
            }
        }
    }

    /// 全てのテキストビューのルーラーキャレット位置を更新
    private func updateAllRulerCaretPositions() {
        if let scrollView = scrollView1,
           let textView = scrollView.documentView as? NSTextView {
            updateRulerCaretPosition(for: textView)
        }
        if let scrollView = scrollView2, !scrollView.isHidden,
           let textView = scrollView.documentView as? NSTextView {
            updateRulerCaretPosition(for: textView)
        }
        for textView in textViews1 {
            updateRulerCaretPosition(for: textView)
        }
        for textView in textViews2 {
            updateRulerCaretPosition(for: textView)
        }
    }

    /// ズーム変更時にルーラーのキャレット位置を更新
    @objc private func magnificationDidChange(_ notification: Notification) {
        // このウィンドウのScrollViewからの通知かチェック
        guard let scrollView = notification.object as? ScalingScrollView,
              scrollView === scrollView1 || scrollView === scrollView2 else { return }

        // ルーラーを再描画してキャレット位置を更新
        if let horizontalRuler = scrollView.horizontalRulerView as? LabeledRulerView {
            horizontalRuler.needsDisplay = true
        }
        if let verticalRuler = scrollView.verticalRulerView as? LabeledRulerView {
            verticalRuler.needsDisplay = true
        }
    }

    // MARK: - Invisible Character Actions

    @IBAction func toggleAllInvisibleCharacters(_ sender: Any?) {
        if invisibleCharacterOptions == .none {
            // 1つもvisibleでない場合は全てオン
            invisibleCharacterOptions = .all
        } else {
            // 1つでもvisibleの場合は全てオフ
            invisibleCharacterOptions = .none
        }
        updateInvisibleCharacterDisplay()
    }

    @IBAction func toggleShowReturnCharacter(_ sender: Any?) {
        if invisibleCharacterOptions.contains(.returnCharacter) {
            invisibleCharacterOptions.remove(.returnCharacter)
        } else {
            invisibleCharacterOptions.insert(.returnCharacter)
        }
        updateInvisibleCharacterDisplay()
    }

    @IBAction func toggleShowTabCharacter(_ sender: Any?) {
        if invisibleCharacterOptions.contains(.tabCharacter) {
            invisibleCharacterOptions.remove(.tabCharacter)
        } else {
            invisibleCharacterOptions.insert(.tabCharacter)
        }
        updateInvisibleCharacterDisplay()
    }

    @IBAction func toggleShowSpaceCharacter(_ sender: Any?) {
        if invisibleCharacterOptions.contains(.spaceCharacter) {
            invisibleCharacterOptions.remove(.spaceCharacter)
        } else {
            invisibleCharacterOptions.insert(.spaceCharacter)
        }
        updateInvisibleCharacterDisplay()
    }

    @IBAction func toggleShowFullWidthSpaceCharacter(_ sender: Any?) {
        if invisibleCharacterOptions.contains(.fullWidthSpaceCharacter) {
            invisibleCharacterOptions.remove(.fullWidthSpaceCharacter)
        } else {
            invisibleCharacterOptions.insert(.fullWidthSpaceCharacter)
        }
        updateInvisibleCharacterDisplay()
    }

    @IBAction func toggleShowLineSeparator(_ sender: Any?) {
        if invisibleCharacterOptions.contains(.lineSeparator) {
            invisibleCharacterOptions.remove(.lineSeparator)
        } else {
            invisibleCharacterOptions.insert(.lineSeparator)
        }
        updateInvisibleCharacterDisplay()
    }

    @IBAction func toggleShowNonBreakingSpace(_ sender: Any?) {
        if invisibleCharacterOptions.contains(.nonBreakingSpace) {
            invisibleCharacterOptions.remove(.nonBreakingSpace)
        } else {
            invisibleCharacterOptions.insert(.nonBreakingSpace)
        }
        updateInvisibleCharacterDisplay()
    }

    @IBAction func toggleShowPageBreak(_ sender: Any?) {
        if invisibleCharacterOptions.contains(.pageBreak) {
            invisibleCharacterOptions.remove(.pageBreak)
        } else {
            invisibleCharacterOptions.insert(.pageBreak)
        }
        updateInvisibleCharacterDisplay()
    }

    @IBAction func toggleShowVerticalTab(_ sender: Any?) {
        if invisibleCharacterOptions.contains(.verticalTab) {
            invisibleCharacterOptions.remove(.verticalTab)
        } else {
            invisibleCharacterOptions.insert(.verticalTab)
        }
        updateInvisibleCharacterDisplay()
    }

    private func updateInvisibleCharacterDisplay() {
        // textStorageに関連付けられた全てのLayoutManagerを更新
        guard let textStorage = textDocument?.textStorage else { return }

        for layoutManager in textStorage.layoutManagers {
            if let invisibleLayoutManager = layoutManager as? InvisibleCharacterLayoutManager {
                invisibleLayoutManager.invisibleCharacterOptions = invisibleCharacterOptions
            }
        }

        // presetData に反映
        textDocument?.presetData?.view.showInvisibles = NewDocData.ViewData.ShowInvisibles(from: invisibleCharacterOptions)
        markDocumentAsEdited()
    }

    // MARK: - Layout Orientation Actions

    @IBAction func toggleLayoutOrientation(_ sender: Any?) {
        // 現在の選択範囲を保存
        let savedRange = getCurrentSelectedRange()

        isVerticalLayout = !isVerticalLayout
        applyLayoutOrientation(savedRange: savedRange)

        // presetData に反映
        textDocument?.presetData?.format.editingDirection = isVerticalLayout ? .rightToLeft : .leftToRight
        markDocumentAsEdited()
    }

    private func applyLayoutOrientation(savedRange: NSRange? = nil) {
        let orientation: NSLayoutManager.TextLayoutOrientation = isVerticalLayout ? .vertical : .horizontal

        // ページモードの場合はTextViewを再構築（setLayoutOrientationは大量テキストでフリーズするため）
        if displayMode == .page {
            guard let textDocument = self.textDocument else { return }
            setupTextViews(with: textDocument.textStorage)
            // ルーラー表示状態を引き継ぐ
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.updateRulerVisibility()
            }
            // Document Colorsを再適用
            if let colors = textDocument.presetData?.fontAndColors.colors {
                applyColorsToTextViews(colors)
            }
            // 選択範囲を復元してスクロール
            if let range = savedRange {
                restoreSelectionAndScrollToVisible(range, delay: 0.3)
            }
            return
        }

        // Continuous modeのテキストビュー
        if let scrollView = scrollView1,
           let textView = scrollView.documentView as? NSTextView {
            textView.setLayoutOrientation(orientation)
            // サイズとスクロールバーを更新（updateTextViewSize内でスクロールバー設定も行う）
            updateTextViewSize(for: scrollView)
        }
        if let scrollView = scrollView2,
           !scrollView.isHidden,
           let textView = scrollView.documentView as? NSTextView {
            textView.setLayoutOrientation(orientation)
            updateTextViewSize(for: scrollView)
        }

        for textView in textViews1 {
            textView.setLayoutOrientation(orientation)
        }
        for textView in textViews2 {
            textView.setLayoutOrientation(orientation)
        }

        // ルーラーの向きを更新
        updateRulerVisibility()

        // 行番号ビューを再構築（縦書き/横書きで位置が変わるため）
        if lineNumberMode != .none {
            if let scrollView = scrollView1 {
                setupLineNumberView(for: scrollView, lineNumberViewRef: &lineNumberView1, constraintRef: &lineNumberWidthConstraint1)
                lineNumberView1?.textView = scrollView.documentView as? NSTextView
            }
            if let scrollView = scrollView2, !scrollView.isHidden {
                setupLineNumberView(for: scrollView, lineNumberViewRef: &lineNumberView2, constraintRef: &lineNumberWidthConstraint2)
                lineNumberView2?.textView = scrollView.documentView as? NSTextView
            }
        }

        // Document Colorsを再適用（行番号ビューの色など）
        if let colors = textDocument?.presetData?.fontAndColors.colors {
            applyColorsToTextViews(colors)
        }

        // 選択範囲を復元してスクロール
        if let range = savedRange {
            restoreSelectionAndScrollToVisible(range, delay: 0.2)
        }
    }

    // MARK: - Inspector Bar Actions

    @IBAction func toggleInspectorBar(_ sender: Any?) {
        isInspectorBarVisible = !isInspectorBarVisible
        updateInspectorBarVisibility()

        // presetData に反映
        textDocument?.presetData?.view.showInspectorBar = isInspectorBarVisible
        markDocumentAsEdited()
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
        // 再入防止
        guard !isAddingPage else { return }
        isAddingPage = true
        defer { isAddingPage = false }

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

        // 一時的なフレームでTextViewを作成（後でupdateAllTextViewFramesで更新される、画像クリック対応）
        let tempFrame = NSRect(x: 0, y: 0, width: textContainerSize.width, height: textContainerSize.height)
        let textView = ImageClickableTextView(frame: tempFrame, textContainer: textContainer)
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
        textView.usesRuler = true
        // ImageResizeControllerを設定
        textView.imageResizeController = imageResizeController

        // レイアウト方向を即座に設定（テキストがレイアウトされるために必要）
        let orientation: NSLayoutManager.TextLayoutOrientation = isVerticalLayout ? .vertical : .horizontal
        textView.setLayoutOrientation(orientation)

        // 一時的に非表示（フレームはupdateAllTextViewFramesで更新される）
        textView.isHidden = true

        // 配列に追加
        textContainers.append(textContainer)
        textViews.append(textView)

        // pagesViewにTextViewを追加（まだ表示位置は未設定）
        pagesView.addSubview(textView)

        // 配列をプロパティに戻す
        switch target {
        case .scrollView1:
            textContainers1 = textContainers
            textViews1 = textViews
        case .scrollView2:
            textContainers2 = textContainers
            textViews2 = textViews
        }

        // ページ追加をマーク（レイアウト完了後にフレームを更新するため）
        needsPageFrameUpdate = true
    }

    // ページフレーム更新が必要かどうか
    private var needsPageFrameUpdate: Bool = false

    private func removeExcessPages(from layoutManager: NSLayoutManager, in scrollView: NSScrollView, for target: ScrollViewTarget) {
        var textContainers: [NSTextContainer]
        var textViews: [NSTextView]

        switch target {
        case .scrollView1:
            textContainers = textContainers1
            textViews = textViews1
            guard pagesView1 != nil else { return }
        case .scrollView2:
            textContainers = textContainers2
            textViews = textViews2
            guard pagesView2 != nil else { return }
        }

        // テキストストレージの長さを取得
        guard let textStorage = layoutManager.textStorage else { return }
        let textLength = textStorage.length

        // 最初の空のコンテナを見つける（それ以降はすべて削除対象）
        var firstEmptyIndex = textContainers.count  // デフォルトは削除なし

        // 前方から探索して、最初の空または無効なコンテナを見つける
        let totalGlyphs = layoutManager.numberOfGlyphs
        let validContainers = Set(layoutManager.textContainers)
        for index in 0..<textContainers.count {
            let container = textContainers[index]
            // コンテナがレイアウトマネージャに存在しない場合は無効として削除対象
            guard validContainers.contains(container) else {
                firstEmptyIndex = index
                break
            }
            let glyphRange = layoutManager.glyphRange(for: container)

            if glyphRange.length == 0 {
                // グリフがない - このコンテナ以降を削除
                firstEmptyIndex = index
                break
            } else {
                // グリフがある場合、文字範囲とグリフ範囲が有効かチェック
                let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
                // 文字範囲の終端がテキスト長を超えている場合は無効（古いデータ）
                if NSMaxRange(charRange) > textLength {
                    firstEmptyIndex = index
                    break
                }
                // グリフ範囲の開始位置が総グリフ数以上の場合は無効（古いデータ）
                if glyphRange.location >= totalGlyphs {
                    firstEmptyIndex = index
                    break
                }
            }
        }

        // 最初の空コンテナ以降を削除対象にする（ただし最低1ページは残す）
        var indicesToRemove: [Int] = []
        let startIndex = max(1, firstEmptyIndex)  // 最初のページは残す
        for index in startIndex..<textContainers.count {
            indicesToRemove.append(index)
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

    /// レイアウト完了後の遅延チェック：問題があれば修正
    private func checkForLayoutIssues(layoutManager: NSLayoutManager, scrollView: NSScrollView, target: ScrollViewTarget, retryCount: Int = 0) {
        // 更新中なら少し待ってから再試行（最大5回）
        if isUpdatingPages {
            if retryCount < 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.checkForLayoutIssues(layoutManager: layoutManager, scrollView: scrollView, target: target, retryCount: retryCount + 1)
                }
            } else {
                isUpdatingPages = false
                // 再帰呼び出しせず、直接実行
            }
            if retryCount < 5 { return }
        }

        let currentContainers = target == .scrollView1 ? textContainers1 : textContainers2
        guard let textStorage = layoutManager.textStorage else { return }
        let textLength = textStorage.length

        // レイアウトマネージャに実際に存在するコンテナのセットを取得
        let validContainers = Set(layoutManager.textContainers)

        // 全コンテナの文字範囲を確認
        var totalLayoutedChars = 0
        var emptyContainerCount = 0
        for container in currentContainers {
            // コンテナがレイアウトマネージャに存在するか確認
            guard validContainers.contains(container) else { continue }

            let glyphRange = layoutManager.glyphRange(for: container)
            if glyphRange.length > 0 {
                let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
                totalLayoutedChars += charRange.length
            } else {
                emptyContainerCount += 1
            }
        }

        // 問題があれば対処
        if totalLayoutedChars > textLength {
            // 古いデータがある場合は再構築
            isUpdatingPages = true
            defer { isUpdatingPages = false }
            rebuildAllPages(for: layoutManager, in: scrollView, target: target)
        } else if emptyContainerCount > 0 {
            // 空のコンテナがある場合は削除
            isUpdatingPages = true
            defer { isUpdatingPages = false }
            removeExcessPages(from: layoutManager, in: scrollView, for: target)

            // ページ数を更新
            let newCount = target == .scrollView1 ? textContainers1.count : textContainers2.count
            if let pagesView = (target == .scrollView1 ? pagesView1 : pagesView2) {
                pagesView.setNumberOfPages(newCount)
                // 強制的に再描画
                pagesView.needsDisplay = true
                pagesView.needsLayout = true
            }
            updateAllTextViewFrames(for: target)

            // すべてのテキストビューを再描画
            let textViews = target == .scrollView1 ? textViews1 : textViews2
            for textView in textViews {
                textView.needsDisplay = true
            }
        }
    }

    /// テキスト長が減少した場合に全ページを再構築
    private func rebuildAllPages(for layoutManager: NSLayoutManager, in scrollView: NSScrollView, target: ScrollViewTarget) {
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

        // 全てのテキストビューを削除
        for textView in textViews {
            textView.removeFromSuperview()
        }

        // 全てのテキストコンテナをレイアウトマネージャーから削除
        while layoutManager.textContainers.count > 0 {
            layoutManager.removeTextContainer(at: 0)
        }

        // 配列をクリア
        textContainers.removeAll()
        textViews.removeAll()

        // 配列をプロパティに戻す
        switch target {
        case .scrollView1:
            textContainers1 = textContainers
            textViews1 = textViews
        case .scrollView2:
            textContainers2 = textContainers
            textViews2 = textViews
        }

        // 必要なページ数を推定（1ページあたりの文字数を概算）
        guard let textStorage = layoutManager.textStorage else { return }
        let charsPerPage = 1000
        let estimatedPages = max(1, (textStorage.length + charsPerPage - 1) / charsPerPage)

        // ページを再作成
        createAllPages(count: estimatedPages, for: layoutManager, in: scrollView, target: target)

        // ページ数を設定
        let newPageCount = target == .scrollView1 ? textContainers1.count : textContainers2.count
        pagesView.setNumberOfPages(newPageCount)

        // フレームを更新
        updateAllTextViewFrames(for: target)

        // ビューの再描画を強制
        pagesView.needsDisplay = true
        pagesView.needsLayout = true
    }


    // MARK: - Text View Size Management

    private func updateTextViewSize(for scrollView: NSScrollView) {
        guard let textView = scrollView.documentView as? NSTextView,
              let textContainer = textView.textContainer else { return }

        let containerInset = textView.textContainerInset

        // ルーラーの厚さを考慮してavailableサイズを計算
        // contentView.frameはルーラー表示直後に更新されていない場合があるため、
        // scrollViewのフレームからルーラーの厚さとスクローラーの幅を引いて計算
        var availableWidth = scrollView.contentView.frame.width
        var availableHeight = scrollView.contentView.frame.height

        // ルーラー表示時は、ルーラーの厚さ分を引く
        if isRulerVisible {
            if !isVerticalLayout {
                // 横書き時は水平ルーラーの厚さを引く
                if let horizontalRuler = scrollView.horizontalRulerView {
                    let rulerThickness = horizontalRuler.ruleThickness
                    // contentViewの高さがルーラー分を含んでいる場合は引く
                    if scrollView.contentView.frame.height > scrollView.frame.height - rulerThickness - NSScroller.scrollerWidth(for: .regular, scrollerStyle: scrollView.scrollerStyle) {
                        availableHeight -= rulerThickness
                    }
                }
            } else {
                // 縦書き時は垂直ルーラーの厚さを引く
                if let verticalRuler = scrollView.verticalRulerView {
                    let rulerThickness = verticalRuler.ruleThickness
                    // contentViewの幅がルーラー分を含んでいる場合は引く
                    if scrollView.contentView.frame.width > scrollView.frame.width - rulerThickness - NSScroller.scrollerWidth(for: .regular, scrollerStyle: scrollView.scrollerStyle) {
                        availableWidth -= rulerThickness
                    }
                }
            }
        }

        if isVerticalLayout {
            // 縦書きの場合
            let lineHeight: CGFloat
            let padding = textContainer.lineFragmentPadding
            switch lineWrapMode {
            case .paperWidth:
                // 用紙高さ（マージンを除く）を1行の高さとする
                // lineFragmentPadding分を加算して正確な用紙幅位置で折り返す
                lineHeight = pageHeight - (pageMargin * 2) + (padding * 2)
            case .windowWidth:
                // ウィンドウ高さを1行の高さとする
                // lineFragmentPaddingが上下に追加されるので、その分を引いて正確にウィンドウ高さに収める
                var adjustedHeight = availableHeight - (containerInset.height * 2) - (padding * 2)
                // macOS 26: ルーラー表示時はシステムがスクロールバー幅を追加するため、その分を補正
                if scrollView.rulersVisible {
                    let scrollerWidth = NSScroller.scrollerWidth(for: .regular, scrollerStyle: scrollView.scrollerStyle)
                    adjustedHeight -= scrollerWidth
                }
                lineHeight = adjustedHeight
            case .noWrap:
                // 折り返さない（十分大きな値を使用）
                lineHeight = 100000
            case .fixedWidth:
                // 固定幅を1行の高さとする（文字数から計算）
                // fixedWidthモードではlineFragmentPaddingを0にして正確な文字数で折り返す
                textContainer.lineFragmentPadding = 0
                // containerInset.height分を加算してルーラー上で正確に指定文字数位置で折り返す
                lineHeight = getFixedWrapWidthInPoints() + containerInset.height
            }

            if lineHeight > 0 {
                textContainer.containerSize = NSSize(width: lineHeight, height: CGFloat.greatestFiniteMagnitude)
            }

            // テキストビューは横に拡張可能（縦書きでは水平方向がスクロール方向）
            textView.isHorizontallyResizable = true
            textView.isVerticallyResizable = lineWrapMode != .windowWidth
            // テキストビューの高さを設定
            // macOS 26: windowWidthモードでルーラー表示時はcontentViewが広がるため、スクロールバー幅分を引いて補正
            let textViewHeight: CGFloat
            if lineWrapMode == .windowWidth && scrollView.rulersVisible {
                let scrollerWidth = NSScroller.scrollerWidth(for: .regular, scrollerStyle: scrollView.scrollerStyle)
                textViewHeight = availableHeight - scrollerWidth
            } else {
                textViewHeight = availableHeight
            }
            // maxSizeは幅・高さとも無制限にして、テキストが水平方向に自由に拡張できるようにする
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.minSize = NSSize(width: 0, height: textViewHeight)

            // テキストビューの現在の幅を保持しつつ、高さだけ更新
            // レイアウトを強制的に更新してからフレームサイズを設定
            textView.layoutManager?.ensureLayout(for: textContainer)
            let currentWidth = max(textView.frame.width, availableWidth)
            textView.setFrameSize(NSSize(width: currentWidth, height: textViewHeight))

            // スクロールバーの設定（両方とも常に表示）
            scrollView.hasHorizontalScroller = true
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = false

            // 縦書きモードではScalingScrollViewの自動サイズ調整を無効にする
            // （EditorWindowControllerがサイズを管理するため）
            if let scalingScrollView = scrollView as? ScalingScrollView {
                scalingScrollView.autoAdjustsContainerSizeOnFrameChange = false
            }
        } else {
            // 横書きの場合
            let lineWidth: CGFloat
            let padding = textContainer.lineFragmentPadding
            switch lineWrapMode {
            case .paperWidth:
                // 用紙幅（マージンを除く）
                // lineFragmentPadding分を加算して正確な用紙幅位置で折り返す
                lineWidth = pageWidth - (pageMargin * 2) + (padding * 2)
            case .windowWidth:
                // ウィンドウ幅に収める
                // lineFragmentPaddingが左右に追加されるので、その分を引いて正確にウィンドウ幅に収める
                var adjustedWidth = availableWidth - (containerInset.width * 2) - (padding * 2)
                // macOS 26: ルーラー表示時はシステムがスクロールバー幅を追加するため、その分を補正
                if scrollView.rulersVisible {
                    let scrollerWidth = NSScroller.scrollerWidth(for: .regular, scrollerStyle: scrollView.scrollerStyle)
                    adjustedWidth -= scrollerWidth
                }
                lineWidth = adjustedWidth
            case .noWrap:
                // 折り返さない（十分大きな値を使用）
                lineWidth = 100000
            case .fixedWidth:
                // 固定幅（文字数から計算）
                // fixedWidthモードではlineFragmentPaddingを0にして正確な文字数で折り返す
                textContainer.lineFragmentPadding = 0
                // containerInset.width分を加算してルーラー上で正確に指定文字数位置で折り返す
                lineWidth = getFixedWrapWidthInPoints() + containerInset.width
            }

            if lineWidth > 0 {
                textContainer.containerSize = NSSize(width: lineWidth, height: CGFloat.greatestFiniteMagnitude)
            }

            // テキストビューのサイズ設定
            let textViewWidth: CGFloat
            if lineWrapMode == .windowWidth {
                // windowWidthモードではテキストビューの幅をcontentViewの幅に正確に合わせてスクロールを防ぐ
                // macOS 26: ルーラー表示時はcontentViewが広がるため、スクロールバー幅分を引いて補正
                if scrollView.rulersVisible {
                    let scrollerWidth = NSScroller.scrollerWidth(for: .regular, scrollerStyle: scrollView.scrollerStyle)
                    textViewWidth = availableWidth - scrollerWidth
                } else {
                    textViewWidth = availableWidth
                }
                textView.maxSize = NSSize(width: textViewWidth, height: CGFloat.greatestFiniteMagnitude)
            } else {
                textViewWidth = max(lineWidth + (containerInset.width * 2), availableWidth)
                // 他のモードではmaxSizeを無制限に
                textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            }
            textView.isHorizontallyResizable = lineWrapMode != .windowWidth
            textView.isVerticallyResizable = true
            textView.setFrameSize(NSSize(width: textViewWidth, height: textView.frame.height))

            // スクロールバーの設定（両方とも常に表示）
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = true
            scrollView.autohidesScrollers = false

            // 横書きモードではwindowWidthの時のみScalingScrollViewの自動サイズ調整を有効にする
            if let scalingScrollView = scrollView as? ScalingScrollView {
                scalingScrollView.autoAdjustsContainerSizeOnFrameChange = (lineWrapMode == .windowWidth)
            }
        }

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

        // ルーラーの表示状態を更新
        updateRulerVisibility()

        // ルーラー更新後にテキストビューのサイズを更新
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
            menuItem.title = splitMode != .none ? "Collapse Views" : "Split View"
        }

        // Split mode menu items validation
        if menuItem.action == #selector(setNoSplit(_:)) {
            menuItem.state = splitMode == .none ? .on : .off
        }
        if menuItem.action == #selector(setHorizontalSplit(_:)) {
            menuItem.state = splitMode == .horizontal ? .on : .off
        }
        if menuItem.action == #selector(setVerticalSplit(_:)) {
            menuItem.state = splitMode == .vertical ? .on : .off
        }

        // Line number menu items validation
        if menuItem.action == #selector(hideLineNumbers(_:)) {
            menuItem.state = lineNumberMode == .none ? .on : .off
        }
        if menuItem.action == #selector(showParagraphNumbers(_:)) {
            menuItem.state = lineNumberMode == .paragraph ? .on : .off
        }
        if menuItem.action == #selector(showRowNumbers(_:)) {
            menuItem.state = lineNumberMode == .row ? .on : .off
        }
        if menuItem.action == #selector(toggleLineNumberMode(_:)) {
            menuItem.title = lineNumberMode == .none ? "Show Line Numbers" : "Hide Line Numbers"
        }
        if menuItem.action == #selector(showHideTextRuler(_:)) {
            menuItem.title = isRulerVisible ? "Hide Ruler" : "Show Ruler"
            menuItem.state = .off
        }

        // Ruler submenu items validation
        if menuItem.action == #selector(setRulerHide(_:)) {
            menuItem.state = rulerType == .none ? .on : .off
        }
        if menuItem.action == #selector(setRulerPoints(_:)) {
            menuItem.state = rulerType == .point ? .on : .off
        }
        if menuItem.action == #selector(setRulerCentimeters(_:)) {
            menuItem.state = rulerType == .centimeter ? .on : .off
        }
        if menuItem.action == #selector(setRulerInches(_:)) {
            menuItem.state = rulerType == .inch ? .on : .off
        }
        if menuItem.action == #selector(setRulerCharacters(_:)) {
            menuItem.state = rulerType == .character ? .on : .off
        }

        // Invisible character menu items validation
        if menuItem.action == #selector(toggleAllInvisibleCharacters(_:)) {
            menuItem.title = invisibleCharacterOptions == .none ? "Show All" : "Hide All"
        }
        if menuItem.action == #selector(toggleShowReturnCharacter(_:)) {
            menuItem.state = invisibleCharacterOptions.contains(.returnCharacter) ? .on : .off
        }
        if menuItem.action == #selector(toggleShowTabCharacter(_:)) {
            menuItem.state = invisibleCharacterOptions.contains(.tabCharacter) ? .on : .off
        }
        if menuItem.action == #selector(toggleShowSpaceCharacter(_:)) {
            menuItem.state = invisibleCharacterOptions.contains(.spaceCharacter) ? .on : .off
        }
        if menuItem.action == #selector(toggleShowFullWidthSpaceCharacter(_:)) {
            menuItem.state = invisibleCharacterOptions.contains(.fullWidthSpaceCharacter) ? .on : .off
        }
        if menuItem.action == #selector(toggleShowLineSeparator(_:)) {
            menuItem.state = invisibleCharacterOptions.contains(.lineSeparator) ? .on : .off
        }
        if menuItem.action == #selector(toggleShowNonBreakingSpace(_:)) {
            menuItem.state = invisibleCharacterOptions.contains(.nonBreakingSpace) ? .on : .off
        }
        if menuItem.action == #selector(toggleShowPageBreak(_:)) {
            menuItem.state = invisibleCharacterOptions.contains(.pageBreak) ? .on : .off
        }
        if menuItem.action == #selector(toggleShowVerticalTab(_:)) {
            menuItem.state = invisibleCharacterOptions.contains(.verticalTab) ? .on : .off
        }

        // Layout orientation menu item validation
        if menuItem.action == #selector(toggleLayoutOrientation(_:)) {
            menuItem.title = isVerticalLayout ? "Make Horizontal Layout" : "Make Vertical Layout"
        }

        // Line wrap mode menu items validation
        if menuItem.action == #selector(setLineWrapPaperWidth(_:)) {
            menuItem.state = lineWrapMode == .paperWidth ? .on : .off
        }
        if menuItem.action == #selector(setLineWrapWindowWidth(_:)) {
            menuItem.state = lineWrapMode == .windowWidth ? .on : .off
        }
        if menuItem.action == #selector(setLineWrapNoWrap(_:)) {
            menuItem.state = lineWrapMode == .noWrap ? .on : .off
        }
        if menuItem.action == #selector(setLineWrapFixedWidth(_:)) {
            menuItem.state = lineWrapMode == .fixedWidth ? .on : .off
            // メニュータイトルに現在の文字数を表示
            menuItem.title = String(format: NSLocalizedString("Fixed Width (%dchars.)...", comment: ""), fixedWrapWidthInChars)
        }

        // Auto Indent menu item validation
        if menuItem.action == #selector(toggleAutoIndent(_:)) {
            if let presetData = textDocument?.presetData {
                menuItem.state = presetData.format.autoIndent ? .on : .off
            } else {
                menuItem.state = .off
            }
        }

        // Wrapped Line Indent menu item validation (Plain Text only)
        if menuItem.action == #selector(showWrappedLineIndentPanel(_:)) {
            // プレーンテキストの時だけ有効
            let isPlainText = textDocument?.documentType == .plain
            return isPlainText
        }

        return true
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // ウィンドウが閉じる前にプリセットデータを保存
        guard let document = textDocument,
              let url = document.fileURL,
              document.presetData != nil else { return }

        // 現在のウィンドウフレームを取得してプリセットデータに反映
        if let window = self.window {
            let frame = window.frame
            document.presetData?.view.windowX = frame.origin.x
            document.presetData?.view.windowY = frame.origin.y
            document.presetData?.view.windowWidth = frame.size.width
            document.presetData?.view.windowHeight = frame.size.height
        }

        // 選択範囲を保存
        // Continuousモードの場合
        if displayMode == .continuous,
           let textView = scrollView1?.documentView as? NSTextView {
            let selectedRange = textView.selectedRange()
            document.presetData?.view.selectedRangeLocation = selectedRange.location
            document.presetData?.view.selectedRangeLength = selectedRange.length
        }
        // Pageモードの場合（textViews1配列の最初のテキストビューから選択範囲を取得）
        else if displayMode == .page,
                let textView = textViews1.first {
            let selectedRange = textView.selectedRange()
            document.presetData?.view.selectedRangeLocation = selectedRange.location
            document.presetData?.view.selectedRangeLength = selectedRange.length
        }

        // スクロール位置を保存
        if let scrollView = scrollView1,
           let clipView = scrollView.contentView as? NSClipView {
            let scrollPosition = clipView.bounds.origin
            document.presetData?.view.scrollPositionX = scrollPosition.x
            document.presetData?.view.scrollPositionY = scrollPosition.y
        }

        // プリセットデータを拡張属性に保存（修正日付を保持）
        document.savePresetDataToExtendedAttribute(at: url)
    }

    func windowDidResize(_ notification: Notification) {
        // ウィンドウモードの場合のみテキストビューのサイズを更新
        // （ページモードは固定サイズのページなので更新不要）
        guard displayMode == .continuous else { return }
        guard let window = self.window, !window.inLiveResize else { return }

        if let scrollView = scrollView1 {
            updateTextViewSize(for: scrollView)
        }
        if let scrollView = scrollView2, !scrollView.isHidden {
            updateTextViewSize(for: scrollView)
        }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        // ウィンドウモードの場合、ライブリサイズ終了時にレイアウトを更新
        guard displayMode == .continuous else { return }

        if let scrollView = scrollView1 {
            updateTextViewSize(for: scrollView)
        }
        if let scrollView = scrollView2, !scrollView.isHidden {
            updateTextViewSize(for: scrollView)
        }
    }

    // MARK: - NSLayoutManagerDelegate

    // ページ操作中の再入防止フラグ（より広範囲に適用）
    private var isUpdatingPages: Bool = false
    private var isAddingPage: Bool = false
    private var previousTextLength1: Int = 0
    private var previousTextLength2: Int = 0
    // レイアウト方向切り替え中フラグ（ページ追加を抑制）
    private var isChangingLayoutOrientation: Bool = false
    // 遅延削除中フラグ
    private var isDelayedRemoveScheduled: Bool = false
    // レイアウトチェックのワークアイテム（デバウンス用）
    private var layoutCheckWorkItem: DispatchWorkItem?
    // レイアウト完了後のクールダウン期間終了時刻
    private var layoutCooldownUntil: Date?

    func layoutManager(_ layoutManager: NSLayoutManager, didCompleteLayoutFor textContainer: NSTextContainer?, atEnd layoutFinishedFlag: Bool) {
        // デバッグ出力（必要時のみ有効化）
        // print("didCompleteLayoutFor: layoutFinishedFlag=\(layoutFinishedFlag), isUpdatingPages=\(isUpdatingPages)")

        // レイアウト方向切り替え中はスキップ
        guard !isChangingLayoutOrientation else { return }

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

        // textContainerがnilでない場合のみ処理
        if let textContainer = textContainer {
            // レイアウトマネージャのコンテナを直接使用（キャッシュ配列との同期ずれを防ぐ）
            let lmContainers = layoutManager.textContainers
            let isLastContainerInLM = lmContainers.last === textContainer
            let containerIndexInLM = lmContainers.firstIndex(of: textContainer) ?? -1

            // 最後のコンテナでレイアウトが完了していない場合、新しいページを追加
            if isLastContainerInLM && !layoutFinishedFlag {
                // クールダウン期間中はページ追加をスキップ
                if let cooldownUntil = layoutCooldownUntil, Date() < cooldownUntil {
                    return
                }

                // まだレイアウトされていない文字があるかチェック
                if let textStorage = layoutManager.textStorage {
                    let totalCharacters = textStorage.length
                    if totalCharacters > 0 {
                        // 全コンテナでレイアウトされた最後の文字位置を取得
                        var lastLayoutedChar = 0
                        for container in lmContainers {
                            let glyphRange = layoutManager.glyphRange(for: container)
                            if glyphRange.length > 0 {
                                let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
                                lastLayoutedChar = max(lastLayoutedChar, NSMaxRange(charRange))
                            }
                        }

                        // すべてのテキストがレイアウト済みならクールダウンを設定
                        if lastLayoutedChar >= totalCharacters {
                            layoutCooldownUntil = Date().addingTimeInterval(0.5)
                            return
                        }

                        // まだレイアウトされていない文字がある場合のみページを追加
                        addPage(to: layoutManager, in: scrollView, for: target)
                    }
                }
                return
            } else if !layoutFinishedFlag {
                // 最後のコンテナではないが、レイアウトが完了していない（デバッグ用）
                // print("didCompleteLayoutFor: containerIndex=\(containerIndexInLM)/\(lmContainers.count-1)")
            }
        }

        // レイアウトが完了した場合、ページ数を確定し、フレームを更新
        if layoutFinishedFlag {
            // 再入防止（ここに到達した場合は isUpdatingPages は false）
            isUpdatingPages = true
            defer {
                isUpdatingPages = false
                // 処理完了後、遅延チェックをスケジュール（デバウンス：毎回リセット）
                layoutCheckWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    self?.layoutCheckWorkItem = nil
                    self?.layoutCooldownUntil = nil  // クールダウンをクリア
                    self?.checkForLayoutIssues(layoutManager: layoutManager, scrollView: scrollView, target: target)
                }
                layoutCheckWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
            }

            // すべてのテキストがレイアウト済みか確認
            let textLength = layoutManager.textStorage?.length ?? 0
            var totalLayoutedChars = 0
            for container in layoutManager.textContainers {
                let glyphRange = layoutManager.glyphRange(for: container)
                if glyphRange.length > 0 {
                    let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
                    totalLayoutedChars = max(totalLayoutedChars, NSMaxRange(charRange))
                }
            }
            // すべてレイアウト済みならクールダウンを設定
            if totalLayoutedChars >= textLength {
                layoutCooldownUntil = Date().addingTimeInterval(0.5)
            }

            // ページ数を確定
            let currentContainers = target == .scrollView1 ? textContainers1 : textContainers2
            let finalPageCount = currentContainers.count
            if let pagesView = (target == .scrollView1 ? pagesView1 : pagesView2) {
                pagesView.setNumberOfPages(finalPageCount)
            }

            // 全テキストビューのフレームとレイアウト方向を更新
            updateAllTextViewFrames(for: target)

            // 余分なページの削除は遅延チェック（checkForLayoutIssues）でのみ行う
            // レイアウト中にremoveExcessPagesを呼ぶと同期ずれが発生する

            // フレーム更新完了
            needsPageFrameUpdate = false
        }
    }

    /// 全テキストビューのフレームとレイアウト方向を更新
    private func updateAllTextViewFrames(for target: ScrollViewTarget) {
        let textViews: [NSTextView]
        let pagesView: MultiplePageView?

        switch target {
        case .scrollView1:
            textViews = textViews1
            pagesView = pagesView1
        case .scrollView2:
            textViews = textViews2
            pagesView = pagesView2
        }

        guard let pagesView = pagesView else { return }

        let orientation: NSLayoutManager.TextLayoutOrientation = isVerticalLayout ? .vertical : .horizontal

        for (index, tv) in textViews.enumerated() {
            tv.frame = pagesView.documentRect(forPageNumber: index)
            // レイアウト方向が異なる場合のみ設定（不要な再レイアウトを避ける）
            if tv.layoutOrientation != orientation {
                tv.setLayoutOrientation(orientation)
            }
            // 非表示だったテキストビューを表示
            if tv.isHidden {
                tv.isHidden = false
            }
        }
    }

    // MARK: - Text Editing Preferences

    /// テキスト編集設定の変更通知を監視開始
    func observeTextEditingPreferences() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textEditingPreferencesDidChange(_:)),
            name: .textEditingPreferencesDidChange,
            object: nil
        )
    }

    @objc private func textEditingPreferencesDidChange(_ notification: Notification) {
        applyTextEditingPreferences()
    }

    /// テキスト編集設定をすべてのテキストビューに適用
    func applyTextEditingPreferences() {
        let defaults = UserDefaults.standard

        // 設定値を取得
        let checkSpelling = defaults.bool(forKey: UserDefaults.Keys.checkSpellingAsYouType)
        let checkGrammar = defaults.bool(forKey: UserDefaults.Keys.checkGrammarWithSpelling)
        let dataDetectors = defaults.bool(forKey: UserDefaults.Keys.dataDetectors)
        let smartLinks = defaults.bool(forKey: UserDefaults.Keys.smartLinks)
        let smartCopyPaste = defaults.bool(forKey: UserDefaults.Keys.smartCopyPaste)

        // Rich Text Substitutions の設定
        let richTextSubstitutionsOnly = defaults.bool(forKey: UserDefaults.Keys.richTextSubstitutionsEnabled)
        let isPlainText = textDocument?.documentType == .plain

        // richTextSubstitutionsOnly が true で、かつプレーンテキストの場合は置換を無効にする
        let shouldApplySubstitutions = !richTextSubstitutionsOnly || !isPlainText
        let textReplacements = shouldApplySubstitutions && defaults.bool(forKey: UserDefaults.Keys.textReplacements)
        let smartQuotes = shouldApplySubstitutions && defaults.bool(forKey: UserDefaults.Keys.smartQuotes)
        let smartDashes = shouldApplySubstitutions && defaults.bool(forKey: UserDefaults.Keys.smartDashes)
        let correctSpelling = shouldApplySubstitutions && defaults.bool(forKey: UserDefaults.Keys.correctSpellingAutomatically)

        // Continuousモードのテキストビュー
        if let scrollView = scrollView1,
           let textView = scrollView.documentView as? NSTextView {
            applyTextEditingSettings(to: textView,
                                     checkSpelling: checkSpelling,
                                     checkGrammar: checkGrammar,
                                     dataDetectors: dataDetectors,
                                     smartLinks: smartLinks,
                                     smartCopyPaste: smartCopyPaste,
                                     textReplacements: textReplacements,
                                     smartQuotes: smartQuotes,
                                     smartDashes: smartDashes,
                                     correctSpelling: correctSpelling)
        }

        if let scrollView = scrollView2,
           let textView = scrollView.documentView as? NSTextView {
            applyTextEditingSettings(to: textView,
                                     checkSpelling: checkSpelling,
                                     checkGrammar: checkGrammar,
                                     dataDetectors: dataDetectors,
                                     smartLinks: smartLinks,
                                     smartCopyPaste: smartCopyPaste,
                                     textReplacements: textReplacements,
                                     smartQuotes: smartQuotes,
                                     smartDashes: smartDashes,
                                     correctSpelling: correctSpelling)
        }

        // Pageモードのテキストビュー
        for textView in textViews1 {
            applyTextEditingSettings(to: textView,
                                     checkSpelling: checkSpelling,
                                     checkGrammar: checkGrammar,
                                     dataDetectors: dataDetectors,
                                     smartLinks: smartLinks,
                                     smartCopyPaste: smartCopyPaste,
                                     textReplacements: textReplacements,
                                     smartQuotes: smartQuotes,
                                     smartDashes: smartDashes,
                                     correctSpelling: correctSpelling)
        }

        for textView in textViews2 {
            applyTextEditingSettings(to: textView,
                                     checkSpelling: checkSpelling,
                                     checkGrammar: checkGrammar,
                                     dataDetectors: dataDetectors,
                                     smartLinks: smartLinks,
                                     smartCopyPaste: smartCopyPaste,
                                     textReplacements: textReplacements,
                                     smartQuotes: smartQuotes,
                                     smartDashes: smartDashes,
                                     correctSpelling: correctSpelling)
        }
    }

    /// 個別のテキストビューに設定を適用
    private func applyTextEditingSettings(to textView: NSTextView,
                                          checkSpelling: Bool,
                                          checkGrammar: Bool,
                                          dataDetectors: Bool,
                                          smartLinks: Bool,
                                          smartCopyPaste: Bool,
                                          textReplacements: Bool,
                                          smartQuotes: Bool,
                                          smartDashes: Bool,
                                          correctSpelling: Bool) {
        textView.isContinuousSpellCheckingEnabled = checkSpelling
        textView.isGrammarCheckingEnabled = checkGrammar
        textView.isAutomaticDataDetectionEnabled = dataDetectors
        textView.isAutomaticLinkDetectionEnabled = smartLinks
        textView.smartInsertDeleteEnabled = smartCopyPaste
        textView.isAutomaticTextReplacementEnabled = textReplacements
        textView.isAutomaticQuoteSubstitutionEnabled = smartQuotes
        textView.isAutomaticDashSubstitutionEnabled = smartDashes
        textView.isAutomaticSpellingCorrectionEnabled = correctSpelling
    }

    // MARK: - Basic Font

    /// Format > Font > Basic Font... メニューアクション
    @IBAction func showBasicFont(_ sender: Any?) {
        BasicFontPanelController.shared.showBasicFontInfo(for: self)
    }

    /// Basic Font が変更された時に呼び出される
    /// ルーラーの文字幅目盛りとドキュメント幅（文字幅指定時）を更新する
    func basicFontDidChange(_ font: NSFont) {
        // 文字幅を再計算
        let charWidth = basicCharWidth(from: font)

        // プレーンテキストの場合、全文にBasic Fontを適用
        if textDocument?.documentType == .plain {
            if let textStorage = textDocument?.textStorage {
                let range = NSRange(location: 0, length: textStorage.length)
                textStorage.addAttribute(.font, value: font, range: range)
            }
        }

        // ルーラーの単位を更新（character単位の場合）
        if rulerType == .character {
            registerCharacterRulerUnit(charWidth: charWidth)

            // ルーラーを再設定
            updateRulerVisibility()
        }

        // 固定幅モードの場合、ドキュメントレイアウトを更新
        // （フォント変更によるレイアウト更新なので、presetDataは更新しない）
        if lineWrapMode == .fixedWidth && displayMode == .continuous {
            applyLineWrapMode(updatePresetData: false)
        }

        // ドキュメントに変更をマーク
        textDocument?.updateChangeCount(.changeDone)
    }

    /// 現在の Basic Font を取得
    func currentBasicFont() -> NSFont {
        if let presetData = textDocument?.presetData {
            let fontData = presetData.fontAndColors
            if let font = NSFont(name: fontData.baseFontName, size: fontData.baseFontSize) {
                return font
            }
        }
        return NSFont.systemFont(ofSize: 14)
    }

    /// 現在の Basic Character Width を取得
    func currentBasicCharWidth() -> CGFloat {
        return basicCharWidth(from: currentBasicFont())
    }

    // MARK: - Tab Width

    /// Tab Widthパネルのインスタンス
    private lazy var tabWidthPanel = TabWidthPanel()

    /// Format > Text > Tab Width... メニューアクション
    @IBAction func showTabWidthPanel(_ sender: Any?) {
        guard let window = self.window,
              let presetData = textDocument?.presetData else { return }

        let currentValue = presetData.format.tabWidthPoints
        let currentUnit = presetData.format.tabWidthUnit

        tabWidthPanel.beginSheet(
            for: window,
            currentValue: currentValue,
            currentUnit: currentUnit
        ) { [weak self] newValue, newUnit in
            guard let self = self,
                  let newValue = newValue,
                  let newUnit = newUnit else { return }

            // presetDataを更新
            self.textDocument?.presetData?.format.tabWidthPoints = newValue
            self.textDocument?.presetData?.format.tabWidthUnit = newUnit

            // ポイントモードの場合のみタブ幅を適用
            // スペースモードではタブキー押下時にスペース文字を挿入するため、タブ幅は変更しない
            if newUnit == .points {
                self.applyTabWidth(newValue)

                // プレーンテキストの場合、全文にタブ幅を適用
                if self.textDocument?.documentType == .plain {
                    self.applyTabWidthToAllText(newValue)
                }
            }

            // presetDataの変更をマーク
            self.textDocument?.presetDataEdited = true
        }
    }

    /// 全文にタブ幅を適用（プレーンテキスト用）
    private func applyTabWidthToAllText(_ tabWidthPoints: CGFloat) {
        guard let textStorage = textDocument?.textStorage, textStorage.length > 0 else { return }

        textStorage.beginEditing()
        textStorage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, _ in
            let newStyle: NSMutableParagraphStyle
            if let existingStyle = value as? NSParagraphStyle {
                newStyle = existingStyle.mutableCopy() as! NSMutableParagraphStyle
            } else {
                newStyle = NSMutableParagraphStyle()
            }
            newStyle.defaultTabInterval = tabWidthPoints
            newStyle.tabStops = []
            textStorage.addAttribute(.paragraphStyle, value: newStyle, range: range)
        }
        textStorage.endEditing()
    }

    // MARK: - Line Spacing

    /// Line Spacingパネルのインスタンス
    private lazy var lineSpacingPanel = LineSpacingPanel()

    /// Format > Text > Line Spacing... メニューアクション
    @IBAction func showLineSpacingPanel(_ sender: Any?) {
        guard let window = self.window,
              let presetData = textDocument?.presetData else { return }

        // 現在の値を取得（選択範囲があればその範囲の値を使用）
        var currentData = LineSpacingPanel.LineSpacingData(
            lineHeightMultiple: presetData.format.lineHeightMultiple,
            lineHeightMinimum: presetData.format.lineHeightMinimum,
            lineHeightMaximum: presetData.format.lineHeightMaximum,
            interLineSpacing: presetData.format.interLineSpacing,
            paragraphSpacingBefore: presetData.format.paragraphSpacingBefore,
            paragraphSpacingAfter: presetData.format.paragraphSpacingAfter
        )

        // RTFで選択範囲がある場合、選択範囲のパラグラフスタイルから値を取得
        let isPlainText = textDocument?.documentType == .plain
        if !isPlainText,
           let textView = currentTextView(),
           let textStorage = textDocument?.textStorage,
           textStorage.length > 0 {
            let selectedRange = textView.selectedRange()
            if selectedRange.length > 0 {
                // 選択範囲の先頭のパラグラフスタイルを取得
                let checkLocation = min(selectedRange.location, textStorage.length - 1)
                if let paragraphStyle = textStorage.attribute(.paragraphStyle, at: checkLocation, effectiveRange: nil) as? NSParagraphStyle {
                    currentData = LineSpacingPanel.LineSpacingData(
                        lineHeightMultiple: paragraphStyle.lineHeightMultiple,
                        lineHeightMinimum: paragraphStyle.minimumLineHeight,
                        lineHeightMaximum: paragraphStyle.maximumLineHeight,
                        interLineSpacing: paragraphStyle.lineSpacing,
                        paragraphSpacingBefore: paragraphStyle.paragraphSpacingBefore,
                        paragraphSpacingAfter: paragraphStyle.paragraphSpacing
                    )
                }
            }
        }

        lineSpacingPanel.beginSheet(
            for: window,
            currentData: currentData
        ) { [weak self] newData in
            guard let self = self,
                  let newData = newData else { return }

            let isPlainText = self.textDocument?.documentType == .plain

            if isPlainText {
                // プレーンテキストの場合：presetDataを更新し、全文に適用
                self.textDocument?.presetData?.format.lineHeightMultiple = newData.lineHeightMultiple
                self.textDocument?.presetData?.format.lineHeightMinimum = newData.lineHeightMinimum
                self.textDocument?.presetData?.format.lineHeightMaximum = newData.lineHeightMaximum
                self.textDocument?.presetData?.format.interLineSpacing = newData.interLineSpacing
                self.textDocument?.presetData?.format.paragraphSpacingBefore = newData.paragraphSpacingBefore
                self.textDocument?.presetData?.format.paragraphSpacingAfter = newData.paragraphSpacingAfter

                // デフォルトのパラグラフスタイルを適用（新規入力用のみ、既存テキストはapplyLineSpacingToRangeで適用）
                let tabWidthPoints = self.textDocument?.presetData?.format.tabWidthPoints ?? 28.0
                self.applyParagraphStyle(
                    tabWidthPoints: tabWidthPoints,
                    interLineSpacing: newData.interLineSpacing,
                    paragraphSpacingBefore: newData.paragraphSpacingBefore,
                    paragraphSpacingAfter: newData.paragraphSpacingAfter,
                    lineHeightMultiple: newData.lineHeightMultiple,
                    lineHeightMinimum: newData.lineHeightMinimum,
                    lineHeightMaximum: newData.lineHeightMaximum,
                    applyToExistingText: false  // 既存テキストへの適用はapplyLineSpacingToRangeで行う（Undo対応）
                )

                // 全文にも適用（Undo対応）
                self.applyLineSpacingToRange(newData, range: nil)
            } else {
                // RTFの場合：選択範囲に適用（選択がなければ全文に適用）
                if let textView = self.currentTextView() {
                    let selectedRange = textView.selectedRange()
                    if selectedRange.length > 0 {
                        // 選択範囲に適用
                        self.applyLineSpacingToRange(newData, range: selectedRange)
                    } else {
                        // 選択がない場合は全文に適用し、presetDataも更新
                        self.textDocument?.presetData?.format.lineHeightMultiple = newData.lineHeightMultiple
                        self.textDocument?.presetData?.format.lineHeightMinimum = newData.lineHeightMinimum
                        self.textDocument?.presetData?.format.lineHeightMaximum = newData.lineHeightMaximum
                        self.textDocument?.presetData?.format.interLineSpacing = newData.interLineSpacing
                        self.textDocument?.presetData?.format.paragraphSpacingBefore = newData.paragraphSpacingBefore
                        self.textDocument?.presetData?.format.paragraphSpacingAfter = newData.paragraphSpacingAfter

                        let tabWidthPoints = self.textDocument?.presetData?.format.tabWidthPoints ?? 28.0
                        self.applyParagraphStyle(
                            tabWidthPoints: tabWidthPoints,
                            interLineSpacing: newData.interLineSpacing,
                            paragraphSpacingBefore: newData.paragraphSpacingBefore,
                            paragraphSpacingAfter: newData.paragraphSpacingAfter,
                            lineHeightMultiple: newData.lineHeightMultiple,
                            lineHeightMinimum: newData.lineHeightMinimum,
                            lineHeightMaximum: newData.lineHeightMaximum,
                            applyToExistingText: false  // 既存テキストへの適用はapplyLineSpacingToRangeで行う（Undo対応）
                        )

                        self.applyLineSpacingToRange(newData, range: nil)
                    }
                }
            }

            // presetDataの変更をマーク
            self.textDocument?.presetDataEdited = true
        }
    }

    /// 現在アクティブなテキストビューを取得
    private func currentTextView() -> NSTextView? {
        // Continuous モードの場合
        if let scrollView = scrollView1,
           let textView = scrollView.documentView as? NSTextView,
           textView.window?.firstResponder === textView {
            return textView
        }
        if let scrollView = scrollView2,
           !scrollView.isHidden,
           let textView = scrollView.documentView as? NSTextView,
           textView.window?.firstResponder === textView {
            return textView
        }

        // Page モードの場合
        for textView in textViews1 {
            if textView.window?.firstResponder === textView {
                return textView
            }
        }
        for textView in textViews2 {
            if textView.window?.firstResponder === textView {
                return textView
            }
        }

        // どれもfirstResponderでない場合、最初のテキストビューを返す
        if let scrollView = scrollView1,
           let textView = scrollView.documentView as? NSTextView {
            return textView
        }
        if !textViews1.isEmpty {
            return textViews1[0]
        }

        return nil
    }

    /// 指定範囲（またはnilで全文）に行間設定を適用（Undo/Redo対応）
    private func applyLineSpacingToRange(_ data: LineSpacingPanel.LineSpacingData, range: NSRange?) {
        guard let textStorage = textDocument?.textStorage, textStorage.length > 0 else { return }
        guard let textView = currentTextView() else { return }
        guard let undoManager = textView.undoManager else { return }

        let targetRange = range ?? NSRange(location: 0, length: textStorage.length)

        // Undo登録のため、変更前の属性を保存
        var oldAttributes: [(range: NSRange, style: NSParagraphStyle)] = []
        textStorage.enumerateAttribute(.paragraphStyle, in: targetRange, options: []) { value, attrRange, _ in
            let style: NSParagraphStyle
            if let existingStyle = value as? NSParagraphStyle {
                style = existingStyle.copy() as! NSParagraphStyle
            } else {
                style = NSParagraphStyle.default
            }
            oldAttributes.append((range: attrRange, style: style))
        }

        // Undoアクションを登録（Undo時にRedoも登録される）
        undoManager.registerUndo(withTarget: self) { [weak self, oldAttributes, data, targetRange] target in
            self?.restoreLineSpacing(oldAttributes: oldAttributes, newData: data, range: targetRange)
        }

        if !undoManager.isUndoing && !undoManager.isRedoing {
            undoManager.setActionName(NSLocalizedString("Line Spacing", comment: "Undo action name"))
        }

        // 新しい行間設定を適用
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.paragraphStyle, in: targetRange, options: []) { value, attrRange, _ in
            let newStyle: NSMutableParagraphStyle
            if let existingStyle = value as? NSParagraphStyle {
                newStyle = existingStyle.mutableCopy() as! NSMutableParagraphStyle
            } else {
                newStyle = NSMutableParagraphStyle()
            }
            newStyle.lineHeightMultiple = data.lineHeightMultiple
            newStyle.minimumLineHeight = data.lineHeightMinimum
            newStyle.maximumLineHeight = data.lineHeightMaximum
            newStyle.lineSpacing = data.interLineSpacing
            newStyle.paragraphSpacingBefore = data.paragraphSpacingBefore
            newStyle.paragraphSpacing = data.paragraphSpacingAfter
            textStorage.addAttribute(.paragraphStyle, value: newStyle, range: attrRange)
        }
        textStorage.endEditing()
    }

    /// 行間設定を復元（Undo/Redo用）
    private func restoreLineSpacing(
        oldAttributes: [(range: NSRange, style: NSParagraphStyle)],
        newData: LineSpacingPanel.LineSpacingData,
        range: NSRange
    ) {
        guard let textStorage = textDocument?.textStorage, textStorage.length > 0 else { return }
        guard let textView = currentTextView() else { return }
        guard let undoManager = textView.undoManager else { return }

        // 現在の属性を保存（Redo用）
        var currentAttributes: [(range: NSRange, style: NSParagraphStyle)] = []
        let targetRange = NSRange(location: 0, length: min(range.location + range.length, textStorage.length))
        if targetRange.length > 0 {
            textStorage.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, attrRange, _ in
                let style: NSParagraphStyle
                if let existingStyle = value as? NSParagraphStyle {
                    style = existingStyle.copy() as! NSParagraphStyle
                } else {
                    style = NSParagraphStyle.default
                }
                currentAttributes.append((range: attrRange, style: style))
            }
        }

        // Redo用のUndoアクションを登録
        undoManager.registerUndo(withTarget: self) { [weak self, currentAttributes, newData, range] target in
            self?.restoreLineSpacing(oldAttributes: currentAttributes, newData: newData, range: range)
        }

        if !undoManager.isUndoing && !undoManager.isRedoing {
            undoManager.setActionName(NSLocalizedString("Line Spacing", comment: "Undo action name"))
        }

        // 古い属性を復元
        textStorage.beginEditing()
        for attr in oldAttributes {
            // 範囲がtextStorageの範囲内にあることを確認
            let safeRange = NSRange(
                location: attr.range.location,
                length: min(attr.range.length, textStorage.length - attr.range.location)
            )
            if safeRange.length > 0 {
                textStorage.addAttribute(.paragraphStyle, value: attr.style, range: safeRange)
            }
        }
        textStorage.endEditing()
    }

    // MARK: - Plain Text Font Change

    /// プレーンテキスト全文にフォントを適用（Undo/Redo対応）
    /// - Parameter font: 適用するフォント
    func applyFontToEntireDocument(_ font: NSFont) {
        guard let textStorage = textDocument?.textStorage, textStorage.length > 0 else { return }
        guard let textView = currentTextView() as? ImageClickableTextView else { return }

        let targetRange = NSRange(location: 0, length: textStorage.length)

        // 全文のテキストを取得してフォントを適用
        let currentAttributedString = textStorage.attributedSubstring(from: targetRange)
        let mutableString = NSMutableAttributedString(attributedString: currentAttributedString)
        mutableString.addAttribute(.font, value: font, range: NSRange(location: 0, length: mutableString.length))

        // replaceStringを使って置換（Undo対応）
        textView.replaceString(in: targetRange, with: mutableString)

        // presetData を更新
        textDocument?.presetData?.fontAndColors.baseFontName = font.fontName
        textDocument?.presetData?.fontAndColors.baseFontSize = font.pointSize
        textDocument?.presetDataEdited = true

        // ルーラーの更新などを行う
        basicFontDidChange(font)
    }

    /// プレーンテキスト全文に下線をトグル適用（Undo/Redo対応）
    func applyUnderlineToEntireDocument() {
        guard let textStorage = textDocument?.textStorage, textStorage.length > 0 else { return }
        guard let textView = currentTextView() as? ImageClickableTextView else { return }

        let targetRange = NSRange(location: 0, length: textStorage.length)

        // 現在の下線状態を確認（最初の文字で判定）
        let currentUnderline = textStorage.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int ?? 0
        let hasUnderline = currentUnderline != 0

        // 全文のテキストを取得して下線を適用/削除
        let currentAttributedString = textStorage.attributedSubstring(from: targetRange)
        let mutableString = NSMutableAttributedString(attributedString: currentAttributedString)
        let fullRange = NSRange(location: 0, length: mutableString.length)

        if hasUnderline {
            mutableString.removeAttribute(.underlineStyle, range: fullRange)
        } else {
            mutableString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: fullRange)
        }

        // replaceStringを使って置換（Undo対応）
        textView.replaceString(in: targetRange, with: mutableString)
    }

    // MARK: - Kern Support

    /// プレーンテキスト全文にカーニングを適用（Undo/Redo対応）
    func applyKernToEntireDocument(value: Float?) {
        guard let textStorage = textDocument?.textStorage, textStorage.length > 0 else { return }
        guard let textView = currentTextView() as? ImageClickableTextView else { return }

        let targetRange = NSRange(location: 0, length: textStorage.length)

        // 全文のテキストを取得してカーニングを適用/削除
        let currentAttributedString = textStorage.attributedSubstring(from: targetRange)
        let mutableString = NSMutableAttributedString(attributedString: currentAttributedString)
        let fullRange = NSRange(location: 0, length: mutableString.length)

        if let kernValue = value {
            mutableString.addAttribute(.kern, value: kernValue, range: fullRange)
        } else {
            mutableString.removeAttribute(.kern, range: fullRange)
        }

        // replaceStringを使って置換（Undo対応）
        textView.replaceString(in: targetRange, with: mutableString)
    }

    /// プレーンテキスト全文のカーニングを調整（Undo/Redo対応）
    func adjustKernToEntireDocument(delta: Float) {
        guard let textStorage = textDocument?.textStorage, textStorage.length > 0 else { return }
        guard let textView = currentTextView() as? ImageClickableTextView else { return }

        let targetRange = NSRange(location: 0, length: textStorage.length)

        // 現在のカーニング値を取得
        let currentKern = textStorage.attribute(.kern, at: 0, effectiveRange: nil) as? Float ?? 0
        let newKern = currentKern + delta

        // 全文のテキストを取得してカーニングを適用
        let currentAttributedString = textStorage.attributedSubstring(from: targetRange)
        let mutableString = NSMutableAttributedString(attributedString: currentAttributedString)
        mutableString.addAttribute(.kern, value: newKern, range: NSRange(location: 0, length: mutableString.length))

        // replaceStringを使って置換（Undo対応）
        textView.replaceString(in: targetRange, with: mutableString)
    }

    // MARK: - Ligature Support

    /// プレーンテキスト全文に合字設定を適用（Undo/Redo対応）
    func applyLigatureToEntireDocument(value: Int) {
        guard let textStorage = textDocument?.textStorage, textStorage.length > 0 else { return }
        guard let textView = currentTextView() as? ImageClickableTextView else { return }

        let targetRange = NSRange(location: 0, length: textStorage.length)

        // 全文のテキストを取得して合字設定を適用
        let currentAttributedString = textStorage.attributedSubstring(from: targetRange)
        let mutableString = NSMutableAttributedString(attributedString: currentAttributedString)
        mutableString.addAttribute(.ligature, value: value, range: NSRange(location: 0, length: mutableString.length))

        // replaceStringを使って置換（Undo対応）
        textView.replaceString(in: targetRange, with: mutableString)
    }

    // MARK: - Text Alignment Support

    /// プレーンテキスト全文にアラインメントを適用（Undo/Redo対応）
    func applyAlignmentToEntireDocument(_ alignment: NSTextAlignment) {
        guard let textStorage = textDocument?.textStorage, textStorage.length > 0 else { return }
        guard let textView = currentTextView() as? ImageClickableTextView else { return }

        let targetRange = NSRange(location: 0, length: textStorage.length)

        // 全文のテキストを取得してアラインメントを適用
        let currentAttributedString = textStorage.attributedSubstring(from: targetRange)
        let mutableString = NSMutableAttributedString(attributedString: currentAttributedString)
        let fullRange = NSRange(location: 0, length: mutableString.length)

        // 既存のパラグラフスタイルを取得または新規作成
        let existingStyle = mutableString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let mutableStyle = (existingStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        mutableStyle.alignment = alignment
        mutableString.addAttribute(.paragraphStyle, value: mutableStyle, range: fullRange)

        // replaceStringを使って置換（Undo対応）
        textView.replaceString(in: targetRange, with: mutableString)
    }

    // MARK: - Character Color Support

    /// プレーンテキスト全文に前景色を適用（Undo/Redo対応）
    func applyForeColorToEntireDocument(_ color: NSColor) {
        guard let textStorage = textDocument?.textStorage, textStorage.length > 0 else { return }
        guard let textView = currentTextView() as? ImageClickableTextView else { return }

        let targetRange = NSRange(location: 0, length: textStorage.length)

        // 全文のテキストを取得して前景色を適用
        let currentAttributedString = textStorage.attributedSubstring(from: targetRange)
        let mutableString = NSMutableAttributedString(attributedString: currentAttributedString)
        mutableString.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: mutableString.length))

        // replaceStringを使って置換（Undo対応）
        textView.replaceString(in: targetRange, with: mutableString)
    }

    /// プレーンテキスト全文に背景色を適用（Undo/Redo対応）
    func applyBackColorToEntireDocument(_ color: NSColor?) {
        guard let textStorage = textDocument?.textStorage, textStorage.length > 0 else { return }
        guard let textView = currentTextView() as? ImageClickableTextView else { return }

        let targetRange = NSRange(location: 0, length: textStorage.length)

        // 全文のテキストを取得して背景色を適用/削除
        let currentAttributedString = textStorage.attributedSubstring(from: targetRange)
        let mutableString = NSMutableAttributedString(attributedString: currentAttributedString)
        let fullRange = NSRange(location: 0, length: mutableString.length)

        if let color = color {
            mutableString.addAttribute(.backgroundColor, value: color, range: fullRange)
        } else {
            mutableString.removeAttribute(.backgroundColor, range: fullRange)
        }

        // replaceStringを使って置換（Undo対応）
        textView.replaceString(in: targetRange, with: mutableString)
    }

    // MARK: - Auto Indent

    /// Format > Auto Indent メニューアクション
    @IBAction func toggleAutoIndent(_ sender: Any?) {
        guard let presetData = textDocument?.presetData else { return }

        // トグル
        let newValue = !presetData.format.autoIndent
        textDocument?.presetData?.format.autoIndent = newValue

        // presetDataの変更をマーク
        textDocument?.presetDataEdited = true

        // 設定との同期
        syncAutoIndentToPreferences(newValue)
    }

    /// Auto Indent メニューの状態を検証
    func validateAutoIndentMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let presetData = textDocument?.presetData else { return false }
        menuItem.state = presetData.format.autoIndent ? .on : .off
        return true
    }

    /// Auto Indent 設定をプリファレンスに同期
    private func syncAutoIndentToPreferences(_ enabled: Bool) {
        // 現在選択されているプリセットの autoIndent を更新
        let presetManager = DocumentPresetManager.shared
        if let selectedID = presetManager.selectedPresetID,
           let index = presetManager.presets.firstIndex(where: { $0.id == selectedID }) {
            var preset = presetManager.presets[index]
            preset.data.format.autoIndent = enabled
            presetManager.updatePreset(preset)
        }
    }

    // MARK: - Wrapped Line Indent

    /// Wrapped Line Indent パネルのインスタンス
    private lazy var wrappedLineIndentPanel = WrappedLineIndentPanel()

    /// Format > Wrapped Line Indent... メニューアクション
    @IBAction func showWrappedLineIndentPanel(_ sender: Any?) {
        guard let window = self.window,
              let presetData = textDocument?.presetData else { return }

        let currentEnabled = presetData.format.indentWrappedLines
        let currentValue = presetData.format.wrappedLineIndent

        wrappedLineIndentPanel.beginSheet(
            for: window,
            enabled: currentEnabled,
            indentValue: currentValue
        ) { [weak self] newEnabled, newValue in
            guard let self = self else { return }

            // presetData を更新
            self.textDocument?.presetData?.format.indentWrappedLines = newEnabled
            self.textDocument?.presetData?.format.wrappedLineIndent = newValue

            // wrapped line indent を適用
            self.applyWrappedLineIndent(enabled: newEnabled, indent: newValue)

            // presetData の変更をマーク
            self.textDocument?.presetDataEdited = true

            // 設定との同期
            self.syncWrappedLineIndentToPreferences(enabled: newEnabled, indent: newValue)
        }
    }

    /// Wrapped Line Indent を適用
    private func applyWrappedLineIndent(enabled: Bool, indent: CGFloat) {
        guard let textStorage = textDocument?.textStorage else { return }

        let headIndent: CGFloat = enabled ? indent : 0

        // 全てのテキストビューに適用
        func applyToTextView(_ textView: NSTextView) {
            textView.defaultParagraphStyle = {
                let style = (textView.defaultParagraphStyle?.mutableCopy() as? NSMutableParagraphStyle)
                    ?? NSMutableParagraphStyle()
                style.headIndent = headIndent
                return style
            }()
        }

        // Continuous モードのテキストビュー
        if let scrollView = scrollView1,
           let textView = scrollView.documentView as? NSTextView {
            applyToTextView(textView)
        }
        if let scrollView = scrollView2,
           let textView = scrollView.documentView as? NSTextView {
            applyToTextView(textView)
        }

        // Page モードのテキストビュー
        for textView in textViews1 {
            applyToTextView(textView)
        }
        for textView in textViews2 {
            applyToTextView(textView)
        }

        // 既存のテキストにも適用
        if textStorage.length > 0 {
            textStorage.beginEditing()
            textStorage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, _ in
                let newStyle: NSMutableParagraphStyle
                if let existingStyle = value as? NSParagraphStyle {
                    newStyle = existingStyle.mutableCopy() as! NSMutableParagraphStyle
                } else {
                    newStyle = NSMutableParagraphStyle()
                }
                newStyle.headIndent = headIndent
                textStorage.addAttribute(.paragraphStyle, value: newStyle, range: range)
            }
            textStorage.endEditing()
        }
    }

    /// Wrapped Line Indent 設定をプリファレンスに同期
    private func syncWrappedLineIndentToPreferences(enabled: Bool, indent: CGFloat) {
        // 現在選択されているプリセットの wrappedLineIndent を更新
        let presetManager = DocumentPresetManager.shared
        if let selectedID = presetManager.selectedPresetID,
           let index = presetManager.presets.firstIndex(where: { $0.id == selectedID }) {
            var preset = presetManager.presets[index]
            preset.data.format.indentWrappedLines = enabled
            preset.data.format.wrappedLineIndent = indent
            presetManager.updatePreset(preset)
        }
    }

    // MARK: - Document Colors

    /// Document Colorsパネルのインスタンス
    private lazy var documentColorsPanel: DocumentColorsPanel? = DocumentColorsPanel.loadFromNib()

    /// View > Document Colors... メニューアクション
    @IBAction func showDocumentColorsPanel(_ sender: Any?) {
        guard let window = self.window,
              let presetData = textDocument?.presetData,
              let panel = documentColorsPanel else { return }

        let currentColors = presetData.fontAndColors.colors

        panel.beginSheet(
            for: window,
            currentColors: currentColors
        ) { [weak self] newColors in
            guard let self = self else { return }

            // Setボタンが押された場合のみ色を適用
            if let colors = newColors {
                self.textDocument?.presetData?.fontAndColors.colors = colors
                self.applyColorsToTextViews(colors)
            }
            // Cancelの場合は何もしない（元の色のまま）
        }
    }
}

