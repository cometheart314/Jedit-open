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

class EditorWindowController: NSWindowController, NSLayoutManagerDelegate, NSSplitViewDelegate, NSWindowDelegate, NSMenuItemValidation, NSToolbarDelegate {

    // MARK: - Toolbar Item Identifiers

    private static let findToolbarItemIdentifier = NSToolbarItem.Identifier("FindItem")
    private static let encodingToolbarItemIdentifier = NSToolbarItem.Identifier("EncodingItem")
    private static let lineEndingToolbarItemIdentifier = NSToolbarItem.Identifier("LineEndingItem")
    private static let writingProgressToolbarItemIdentifier = NSToolbarItem.Identifier("WritingProgressItem")
    private static let bookmarkToolbarItemIdentifier = NSToolbarItem.Identifier("BookmarkItem")

    // MARK: - IBOutlets

    @IBOutlet weak var splitView: NSSplitView!
    @IBOutlet weak var scrollView2: ScalingScrollView!
    @IBOutlet weak var scrollView1: ScalingScrollView!

    // MARK: - Toolbar

    private var encodingToolbarItem: NSToolbarItem?
    private var lineEndingToolbarItem: NSToolbarItem?
    private var writingProgressToolbarItem: NSToolbarItem?
    private lazy var writingGoalPanel = WritingGoalPanel()

    // MARK: - Image Resize

    private var imageResizeController: ImageResizeController?

    // MARK: - Find Bar

    private var findBarViewController: FindBarViewController?
    private var splitViewTopConstraint: NSLayoutConstraint?

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

    // スクロール位置復元用（レイアウト完了待ち）
    private var pendingScrollPosition: NSPoint?

    // ページ設定（document.printInfo から取得）
    // Note: NSPrintInfo.paperSize は orientation に応じて既に調整されている
    // （landscape の場合は width > height となっている）
    private var pageWidth: CGFloat {
        guard let printInfo = textDocument?.printInfo else {
            return 595.0  // デフォルト: A4サイズ相当（ポイント）
        }
        return printInfo.paperSize.width
    }

    private var pageHeight: CGFloat {
        guard let printInfo = textDocument?.printInfo else {
            return 842.0  // デフォルト: A4サイズ相当（ポイント）
        }
        return printInfo.paperSize.height
    }

    private var pageMargin: CGFloat {
        // printInfo のマージンの平均値を使用（簡略化）
        // より正確には、各マージンを個別に使用すべきだが、
        // 現在の MultiplePageView は均一マージンを想定している
        guard let printInfo = textDocument?.printInfo else {
            return 72.0  // デフォルト: 1インチ（72ポイント）
        }
        // 左右マージンの平均を使用（横書きの場合）
        return (printInfo.leftMargin + printInfo.rightMargin) / 2.0
    }

    private var pageTopMargin: CGFloat {
        textDocument?.printInfo.topMargin ?? 72.0
    }

    private var pageBottomMargin: CGFloat {
        textDocument?.printInfo.bottomMargin ?? 72.0
    }

    private var pageLeftMargin: CGFloat {
        textDocument?.printInfo.leftMargin ?? 72.0
    }

    private var pageRightMargin: CGFloat {
        textDocument?.printInfo.rightMargin ?? 72.0
    }

    private let pageSpacing: CGFloat = 20.0 // ページ間のスペース

    // NotificationCenter observers
    private var textViewObservers: [Any] = []
    private var contentViewObservers: [Any] = []

    deinit {
        // 保留中の統計計算をキャンセル
        statisticsWorkItem?.cancel()
        statisticsWorkItem = nil
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

        // 行番号モード変更通知を監視（行番号ビューからのクリックメニュー）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(lineNumberModeDidChange(_:)),
            name: LineNumberView.lineNumberModeDidChangeNotification,
            object: nil
        )

        // ドキュメントタイプ変更通知を監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentTypeDidChange(_:)),
            name: Document.documentTypeDidChangeNotification,
            object: nil
        )

        // printInfo変更通知を監視（Page Setupダイアログからの変更）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(printInfoDidChange(_:)),
            name: Document.printInfoDidChangeNotification,
            object: nil
        )

        // ズーム変更通知を監視（ルーラーのキャレット位置更新用）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(magnificationDidChange(_:)),
            name: ScalingScrollView.magnificationDidChangeNotification,
            object: nil
        )

        // エンコーディングリスト変更通知を監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(encodingsListDidChange(_:)),
            name: .encodingsListChanged,
            object: nil
        )

        // アピアランス変更を監視
        if let window = self.window {
            window.contentView?.addObserver(self, forKeyPath: "effectiveAppearance", options: [.new], context: nil)
        }

        // splitView の上端制約を保存（Find Bar 挿入用）
        if let contentView = window?.contentView, let splitView = self.splitView {
            for constraint in contentView.constraints {
                if let firstItem = constraint.firstItem as? NSView,
                   firstItem === splitView,
                   constraint.firstAttribute == .top {
                    splitViewTopConstraint = constraint
                    break
                }
            }
        }

        // ツールバーのセットアップ（コードで作成）
        setupEncodingToolbarItem()

        // ツールバー可視性変更を監視（KVO）- setupEncodingToolbarItem後に実行
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

        // テキストタイプボタンの初期化
        updateTextTypeButtons()

        // 編集ロックボタンの初期化
        updateEditLockButtons()

        // テキスト編集設定の変更を監視
        observeTextEditingPreferences()

        // リッチテキストLightモード設定の変更を監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(richTextLightModeSettingChanged(_:)),
            name: NSNotification.Name("RichTextLightModeSettingChanged"),
            object: nil
        )

        // ファイル読み込み〜applyPresetData() の過程で textStorage が変更され、
        // UndoManager にアクションが記録される。RunLoop 終了時に
        // _endTopLevelGroupings 経由で changeDone が発火して "Edited" マークがつくため、
        // 次のイベントループで UndoManager をクリアし、変更カウントもリセットする。
        (document as? Document)?.scheduleFinishInitialLoading()
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
            // ページモードではMultiplePageViewが背景を描画するため、
            // TextViewの背景色更新は不要（パフォーマンス最適化）
            // MultiplePageViewは自動的にneedsDisplay=trueになる

            // プレーンテキストの場合のみテキスト色を更新（textStorageで一括更新済み）
            // リッチテキストの場合は何もしない（背景は.clearのまま）
            break
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

    /// テキストタイプボタンを更新
    private func updateTextTypeButtons() {
        let typeName = textTypeShortName()
        scrollView1?.updateTextTypeButton(typeName: typeName)
        scrollView2?.updateTextTypeButton(typeName: typeName)
    }

    /// ステータスバー用の書類タイプ略称を返す
    private func textTypeShortName() -> String {
        guard let document = textDocument else { return "Plain" }

        // Markdown
        if document.isMarkdownDocument {
            return "MD"
        }

        // インポートされた Word/ODT ドキュメント
        if document.isImportedDocument, let fileURL = document.fileURL {
            switch fileURL.pathExtension.lowercased() {
            case "doc":
                return "DOC"
            case "docx":
                return "DOCX"
            case "xml":
                return "XML"
            case "odt":
                return "ODT"
            default:
                break
            }
        }

        switch document.documentType {
        case .plain:
            return "Plain"
        case .rtf:
            return "Rich"
        case .rtfd:
            return "RTFD"
        case .docFormat:
            return "DOC"
        case .officeOpenXML:
            return "DOCX"
        case .wordML:
            return "XML"
        default:
            return "Rich"
        }
    }

    /// 編集ロックボタンを更新
    private func updateEditLockButtons() {
        let isEditable = currentTextView()?.isEditable ?? true
        scrollView1?.updateEditLockButton(isEditable: isEditable)
        scrollView2?.updateEditLockButton(isEditable: isEditable)
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

        // ツールバーアイテムを更新
        updateEncodingToolbarItem()
        updateLineEndingToolbarItem()

        // テキストタイプボタンを更新
        updateTextTypeButtons()

        // 編集ロックボタンを更新
        updateEditLockButtons()
    }

    @objc private func printInfoDidChange(_ notification: Notification) {
        // 自分のドキュメントからの通知かを確認
        guard let document = notification.object as? Document,
              document === textDocument else { return }

        #if DEBUG
        Swift.print("=== printInfoDidChange notification received ===")
        Swift.print("orientation: \(document.printInfo.orientation.rawValue)")
        Swift.print("paperSize: \(document.printInfo.paperSize)")
        #endif

        // ページモードの場合のみ、ページサイズを更新
        if displayMode == .page {
            // ページモードを再設定（用紙サイズ、向き、マージンが変更された可能性がある）
            guard let textStorage = textDocument?.textStorage else { return }
            setupPageMode(with: textStorage)
        }
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
        scrollView1?.setZoomLevel(viewData.scale)

        // Editing Direction（縦書き/横書き）を適用
        let formatData = presetData.format
        isVerticalLayout = (formatData.editingDirection == .rightToLeft)

        // TextStorageに行折り返しタイプを設定（setupTextViewsの前に設定する必要がある）
        if let textStorage = textDocument?.textStorage {
            textStorage.setLineBreakingType(presetData.format.wordWrappingType.rawValue)
        }

        // テキストビューを再セットアップ（上記の設定を反映）
        if let textStorage = textDocument?.textStorage {
            setupTextViews(with: textStorage)
        }

        // フォント設定を適用（setupTextViews後に適用、新しいTextViewに反映するため）
        let fontData = presetData.fontAndColors
        if let font = NSFont(name: fontData.baseFontName, size: fontData.baseFontSize) {
            applyFontToTextViews(font)
        }

        // 色設定を適用（setupTextViews後に適用）
        // プレーンテキストでも色設定を適用する
        applyColorsToTextViews(fontData.colors)

        // setupTextViews後にパラグラフスタイル（タブ幅、行間、段落間隔）を適用
        // スペースモードではタブ幅はデフォルト値を使用
        let tabWidthPoints = formatData.tabWidthUnit == .points ? formatData.tabWidthPoints : 28.0
        // リッチテキストの既存ファイルの場合、RTFに保存されたパラグラフごとの行間設定を保持する。
        // presetData の行間値で上書きすると、個別に設定した行間が失われてしまうため。
        let isExistingRichTextFile = textDocument?.fileURL != nil
            && textDocument?.documentType != .plain
        applyParagraphStyle(
            tabWidthPoints: tabWidthPoints,
            interLineSpacing: formatData.interLineSpacing,
            paragraphSpacingBefore: formatData.paragraphSpacingBefore,
            paragraphSpacingAfter: formatData.paragraphSpacingAfter,
            lineHeightMultiple: formatData.lineHeightMultiple,
            lineHeightMinimum: formatData.lineHeightMinimum,
            lineHeightMaximum: formatData.lineHeightMaximum,
            preserveExistingLineSpacing: isExistingRichTextFile,
            preserveExistingTabStops: isExistingRichTextFile
        )

        // setupTextViews後にルーラー設定を適用（単位設定を含む）
        updateRulerVisibility()

        // setupTextViews後に行番号表示を適用
        updateLineNumberDisplay()

        // setupTextViews後にスケールを再適用（setupTextViewsで上書きされる可能性があるため）
        scrollView1?.setZoomLevel(viewData.scale)

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

        // スクロール位置を復元
        // allowsNonContiguousLayout が有効な場合、documentView のサイズは推定値であり、
        // スクロール先のコンテンツがレイアウトされていないと真っ白になる。
        // ensureLayout で全テキストのレイアウトを完了させ、documentView のサイズを
        // 正確に更新してから、次のランループでスクロール位置を適用する。
        if let scrollPositionX = viewData.scrollPositionX,
           let scrollPositionY = viewData.scrollPositionY {
            pendingScrollPosition = NSPoint(x: scrollPositionX, y: scrollPositionY)

            // Continuousモード: 全テキストのレイアウトを完了させ、
            // documentView (NSTextView) のサイズを正確に更新する。
            // layoutManager1 は Page モード専用なので、
            // NSTextView の layoutManager プロパティを直接使用する。
            if displayMode == .continuous,
               let textView = scrollView1?.documentView as? NSTextView,
               let layoutManager = textView.layoutManager,
               let textContainer = textView.textContainer {
                let textLength = textView.textStorage?.length ?? 0
                if textLength > 0 {
                    let fullRange = NSRange(location: 0, length: textLength)
                    layoutManager.ensureLayout(forCharacterRange: fullRange)
                    // allowsNonContiguousLayout=true だと ensureLayout 後も
                    // NSTextView の frame が自動更新されないため、
                    // usedRect から正確なサイズを取得して手動で更新する
                    let usedRect = layoutManager.usedRect(for: textContainer)
                    let inset = textView.textContainerInset
                    let newHeight = usedRect.height + inset.height * 2
                    if textView.frame.height < newHeight {
                        textView.setFrameSize(NSSize(width: textView.frame.width, height: newHeight))
                    }
                }
            }

            // ensureLayout によるスクロールリセットが完了した後にスクロール位置を適用
            DispatchQueue.main.async { [weak self] in
                self?.applyPendingScrollPosition()
            }
        }
    }

    /// ペンディング中のスクロール位置を適用する
    private func applyPendingScrollPosition() {
        guard let scrollPosition = pendingScrollPosition else { return }
        guard let scrollView = self.scrollView1 else { return }
        let clipView = scrollView.contentView

        pendingScrollPosition = nil
        clipView.scroll(to: scrollPosition)
        scrollView.reflectScrolledClipView(clipView)
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
        let isPlainText = textDocument?.documentType == .plain

        // Continuous モードの場合
        if let scrollView = scrollView1,
           let textView = scrollView.documentView as? NSTextView {
            if isPlainText {
                // プレーンテキスト: textStorage全体のフォントを設定
                textView.font = font
            } else {
                // リッチテキスト: typingAttributesのみ更新（既存の属性を保持）
                var attrs = textView.typingAttributes
                attrs[.font] = font
                textView.typingAttributes = attrs
            }
        }
        if let scrollView = scrollView2,
           !scrollView.isHidden,
           let textView = scrollView.documentView as? NSTextView {
            if isPlainText {
                textView.font = font
            } else {
                var attrs = textView.typingAttributes
                attrs[.font] = font
                textView.typingAttributes = attrs
            }
        }

        // Page モードの場合
        for textView in textViews1 {
            if isPlainText {
                textView.font = font
            } else {
                var attrs = textView.typingAttributes
                attrs[.font] = font
                textView.typingAttributes = attrs
            }
        }
        for textView in textViews2 {
            if isPlainText {
                textView.font = font
            } else {
                var attrs = textView.typingAttributes
                attrs[.font] = font
                textView.typingAttributes = attrs
            }
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
        applyToExistingText: Bool = true,
        preserveExistingLineSpacing: Bool = false,
        preserveExistingTabStops: Bool = false
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
            let fullRange = NSRange(location: 0, length: textStorage.length)
            let isPlainText = textDocument?.documentType == .plain

            textStorage.beginEditing()
            if isPlainText {
                // プレーンテキストの場合は全範囲に一括で設定（enumerateAttribute不要）
                textStorage.addAttribute(.paragraphStyle, value: defaultParagraphStyle, range: fullRange)
            } else {
                // リッチテキストの場合は既存のスタイルを保持しつつ設定を更新
                textStorage.enumerateAttribute(.paragraphStyle, in: fullRange, options: []) { value, range, _ in
                    let newStyle: NSMutableParagraphStyle
                    if let existingStyle = value as? NSParagraphStyle {
                        newStyle = existingStyle.mutableCopy() as! NSMutableParagraphStyle
                    } else {
                        newStyle = NSMutableParagraphStyle()
                    }
                    // タブ幅を適用
                    newStyle.defaultTabInterval = tabWidthPoints
                    // preserveExistingTabStops が true の場合、
                    // RTFから読み込んだパラグラフごとのタブストップ設定を保持する。
                    if !preserveExistingTabStops || value == nil {
                        newStyle.tabStops = []
                    }
                    // preserveExistingLineSpacing が true の場合、
                    // RTFから読み込んだパラグラフごとの行間設定を保持する。
                    // 既存のスタイルがない場合のみ presetData の値を適用する。
                    if !preserveExistingLineSpacing || value == nil {
                        newStyle.lineHeightMultiple = lineHeightMultiple
                        newStyle.minimumLineHeight = lineHeightMinimum
                        newStyle.maximumLineHeight = lineHeightMaximum
                        newStyle.lineSpacing = interLineSpacing
                        newStyle.paragraphSpacingBefore = paragraphSpacingBefore
                        newStyle.paragraphSpacing = paragraphSpacingAfter
                    }
                    textStorage.addAttribute(.paragraphStyle, value: newStyle, range: range)
                }
            }
            textStorage.endEditing()
        }
    }

    /// 色設定をテキストビューに適用
    private func applyColorsToTextViews(_ colors: NewDocData.FontAndColorsData.Colors) {
        let isPlainText = textDocument?.documentType == .plain

        // テキストビューの色を適用するヘルパー
        func applyTextViewColors(_ textView: NSTextView, scrollView: NSScrollView? = nil) {
            textView.backgroundColor = colors.background.nsColor
            textView.insertionPointColor = colors.caret.nsColor
            var newAttributes = textView.selectedTextAttributes
            newAttributes[.backgroundColor] = colors.highlight.nsColor
            textView.selectedTextAttributes = newAttributes

            // プレーンテキストの場合のみtextColorを設定
            // リッチテキストでは既存の色属性を保持するため、textColorは設定しない
            if isPlainText {
                textView.textColor = colors.character.nsColor
            }

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

        // ページモードのヘッダー・フッター・行番号色・背景色を適用
        pagesView1?.headerColor = colors.header.nsColor
        pagesView1?.footerColor = colors.footer.nsColor
        pagesView1?.lineNumberTextColor = colors.lineNumber.nsColor
        pagesView1?.documentBackgroundColor = colors.background.nsColor
        pagesView2?.headerColor = colors.header.nsColor
        pagesView2?.footerColor = colors.footer.nsColor
        pagesView2?.lineNumberTextColor = colors.lineNumber.nsColor
        pagesView2?.documentBackgroundColor = colors.background.nsColor
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

    @objc private func lineNumberModeDidChange(_ notification: Notification) {
        // 自分のドキュメントの行番号ビューからの通知かを確認
        guard let lineNumberView = notification.object as? LineNumberView,
              (lineNumberView === lineNumberView1 || lineNumberView === lineNumberView2) else {
            return
        }

        guard let modeValue = notification.userInfo?["mode"] as? LineNumberMode else {
            return
        }

        // lineNumberModeを更新して表示を更新
        lineNumberMode = modeValue
        updateLineNumberDisplay()
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

        // レイアウト関連の状態をリセット（ページ追加クールダウン等）
        layoutCooldownUntil = nil
        layoutCheckWorkItem?.cancel()
        layoutCheckWorkItem = nil
        isUpdatingPages = false
        isAddingPage = false

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
            layoutManager.allowsNonContiguousLayout = true
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
            let textView = JeditTextView(frame: textViewFrame, textContainer: textContainer)
            textView.isEditable = !(textDocument?.presetData?.view.preventEditing ?? false)
            textView.isSelectable = true
            textView.allowsUndo = true
            // 縦書き/横書きに応じてリサイズ方向を設定
            textView.isHorizontallyResizable = isVerticalLayout
            textView.isVerticallyResizable = !isVerticalLayout
            textView.autoresizingMask = []
            textView.usesInspectorBar = isInspectorBarVisible
            textView.usesRuler = true
            textView.usesFindBar = false
            textView.isIncrementalSearchingEnabled = true
            // textContainerInsetで左右と上下のインセットを設定
            textView.textContainerInset = containerInset
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            // Document Colorsが設定されている場合はそれを使用、なければデフォルト
            let isPlainTextDoc = textDocument?.documentType == .plain
            // リッチテキスト書類の場合はisRichTextとimportsGraphicsを設定
            textView.isRichText = !isPlainTextDoc
            textView.importsGraphics = !isPlainTextDoc
            if let colors = textDocument?.presetData?.fontAndColors.colors {
                textView.backgroundColor = colors.background.nsColor
                // リッチテキストでは既存の色属性を保持するため、textColorは設定しない
                if isPlainTextDoc {
                    textView.textColor = colors.character.nsColor
                }
                scrollView.backgroundColor = colors.background.nsColor
            } else if isPlainTextDoc {
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
            let textView = JeditTextView(frame: textViewFrame, textContainer: textContainer)
            textView.isEditable = !(textDocument?.presetData?.view.preventEditing ?? false)
            textView.isSelectable = true
            textView.allowsUndo = true
            // 縦書き/横書きに応じてリサイズ方向を設定
            textView.isHorizontallyResizable = isVerticalLayout
            textView.isVerticallyResizable = !isVerticalLayout
            textView.autoresizingMask = []
            textView.usesInspectorBar = isInspectorBarVisible
            textView.usesRuler = true
            textView.usesFindBar = false
            textView.isIncrementalSearchingEnabled = true
            // textContainerInsetで左右と上下のインセットを設定
            textView.textContainerInset = containerInset
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            // Document Colorsが設定されている場合はそれを使用、なければデフォルト
            let isPlainTextDoc = textDocument?.documentType == .plain
            // リッチテキスト書類の場合はisRichTextとimportsGraphicsを設定
            textView.isRichText = !isPlainTextDoc
            textView.importsGraphics = !isPlainTextDoc
            if let colors = textDocument?.presetData?.fontAndColors.colors {
                textView.backgroundColor = colors.background.nsColor
                // リッチテキストでは既存の色属性を保持するため、textColorは設定しない
                if isPlainTextDoc {
                    textView.textColor = colors.character.nsColor
                }
                scrollView.backgroundColor = colors.background.nsColor
            } else if isPlainTextDoc {
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

        // TextKit 1 リスト表示バグの回避策を適用
        // RTFD の場合、画像データの serialize/deserialize が重いため、
        // ウィンドウ表示後に非同期で実行する
        DispatchQueue.main.async { [weak self] in
            self?.fixTextListRenderingIfNeeded(in: textStorage)
        }
    }

    // MARK: - TextKit 1 List Rendering Workaround

    /// TextKit 1 の NSLayoutManager が RTF/RTFD 読み込み後に NSTextList 属性を
    /// 正しくレンダリングしないバグを回避する。
    /// RTF ラウンドトリップで再適用することでリスト表示を修復する。
    func fixTextListRenderingIfNeeded(in textStorage: NSTextStorage) {
        // RTF/RTFD ドキュメントのみ対象
        guard let docType = textDocument?.documentType,
              (docType == .rtf || docType == .rtfd) else { return }
        guard textStorage.length > 0 else { return }

        // textStorage にリスト属性が含まれているか確認
        var hasTextLists = false
        textStorage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: textStorage.length), options: [.longestEffectiveRangeNotRequired]) { value, _, stop in
            if let style = value as? NSParagraphStyle, !style.textLists.isEmpty {
                hasTextLists = true
                stop.pointee = true
            }
        }
        guard hasTextLists else { return }

        // 新しく作成された textView に対して RTF/RTFD ラウンドトリップを適用
        if let textView = scrollView1?.documentView as? NSTextView {
            // RTFD の場合、ラウンドトリップで添付ファイルの bounds 情報が失われるため保存
            let savedBoundsInfo: [AttachmentBoundsInfo]?
            if docType == .rtfd {
                savedBoundsInfo = textDocument?.collectAttachmentBoundsMetadata()
            } else {
                savedBoundsInfo = nil
            }

            let fullRange = NSRange(location: 0, length: textStorage.length)

            // RTF ラウンドトリップではカスタム属性 (.anchor) が失われるため、
            // ラウンドトリップ前に保存し、後で復元する
            var savedAnchors: [(range: NSRange, uuid: String)] = []
            textStorage.enumerateAttribute(.anchor, in: fullRange, options: []) { value, attrRange, _ in
                if let uuid = value as? String {
                    savedAnchors.append((attrRange, uuid))
                }
            }

            do {
                if docType == .rtfd {
                    // RTFD: 添付ファイル（画像・図形）を保持するため RTFD フォーマットを使用
                    let rtfdData = try textStorage.data(from: fullRange, documentAttributes: [
                        .documentType: NSAttributedString.DocumentType.rtfd
                    ])
                    textView.replaceCharacters(in: fullRange, withRTFD: rtfdData)
                } else {
                    // RTF: 添付ファイルなしの場合は RTF フォーマットを使用
                    let rtfData = try textStorage.data(from: fullRange, documentAttributes: [
                        .documentType: NSAttributedString.DocumentType.rtf
                    ])
                    textView.replaceCharacters(in: fullRange, withRTF: rtfData)
                }
            } catch {
                #if DEBUG
                Swift.print("fixTextListRenderingIfNeeded: RTF/RTFD round-trip failed: \(error)")
                #endif
            }

            // RTFD ラウンドトリップで失われた添付ファイルの bounds 情報を復元
            if let boundsInfo = savedBoundsInfo, !boundsInfo.isEmpty {
                textDocument?.applyAttachmentBoundsMetadata(boundsInfo)
            }

            // RTF ラウンドトリップで失われたアンカー属性を復元
            if !savedAnchors.isEmpty {
                textStorage.beginEditing()
                for (range, uuid) in savedAnchors {
                    if range.location + range.length <= textStorage.length {
                        textStorage.addAttribute(.anchor, value: uuid, range: range)
                    }
                }
                textStorage.endEditing()
            }
        }
        // scrollView2 は同じ textStorage を共有しているため、
        // textStorage への修正は自動的に反映される（追加の処理不要）
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

            // デバッグ: printInfo の値を出力
            #if DEBUG
            if let printInfo = textDocument?.printInfo {
                Swift.print("=== Page Setup Debug ===")
                Swift.print("paperSize: \(printInfo.paperSize)")
                Swift.print("orientation: \(printInfo.orientation.rawValue) (0=portrait, 1=landscape)")
                Swift.print("topMargin: \(printInfo.topMargin)")
                Swift.print("bottomMargin: \(printInfo.bottomMargin)")
                Swift.print("leftMargin: \(printInfo.leftMargin)")
                Swift.print("rightMargin: \(printInfo.rightMargin)")
                Swift.print("Computed pageWidth: \(pageWidth)")
                Swift.print("Computed pageHeight: \(pageHeight)")
                Swift.print("========================")
            }
            #endif

            // MultiplePageViewを作成
            let initialFrame = NSRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
            let pagesView = MultiplePageView(frame: initialFrame)
            pagesView.pageWidth = pageWidth
            pagesView.pageHeight = pageHeight
            pagesView.pageMargin = pageMargin
            // 個別マージンを設定（printInfoから取得）
            pagesView.topMargin = pageTopMargin
            pagesView.bottomMargin = pageBottomMargin
            pagesView.leftMargin = pageLeftMargin
            pagesView.rightMargin = pageRightMargin
            pagesView.pageSeparatorHeight = pageSpacing
            pagesView.isVerticalLayout = isVerticalLayout
            pagesView.documentName = textDocument?.displayName ?? ""
            pagesView.isPlainText = textDocument?.documentType == .plain
            pagesView.lineNumberMode = lineNumberMode
            pagesView.layoutManager = layoutManager
            // ヘッダー・フッターのAttributedStringを設定
            configureHeaderFooter(for: pagesView)
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
            // 個別マージンを設定（printInfoから取得）
            pagesView.topMargin = pageTopMargin
            pagesView.bottomMargin = pageBottomMargin
            pagesView.leftMargin = pageLeftMargin
            pagesView.rightMargin = pageRightMargin
            pagesView.pageSeparatorHeight = pageSpacing
            pagesView.isVerticalLayout = isVerticalLayout
            pagesView.documentName = textDocument?.displayName ?? ""
            pagesView.isPlainText = textDocument?.documentType == .plain
            pagesView.lineNumberMode = lineNumberMode
            pagesView.layoutManager = layoutManager
            // ヘッダー・フッターのAttributedStringを設定
            configureHeaderFooter(for: pagesView)
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

                // 全テキストのレイアウトを強制（動的ページ追加のトリガーに必要）
                let fullRange = NSRange(location: 0, length: textStorage.length)
                layoutManager.ensureLayout(forCharacterRange: fullRange)

                // 行番号表示のため再描画
                self.pagesView1?.needsDisplay = true
            }

            // layoutManager2にTextStorageを追加（スプリット時のみ）
            if let layoutManager = self.layoutManager2 {
                textStorage.addLayoutManager(layoutManager)

                // 全テキストのレイアウトを強制（動的ページ追加のトリガーに必要）
                let fullRange = NSRange(location: 0, length: textStorage.length)
                layoutManager.ensureLayout(forCharacterRange: fullRange)

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

    /// MultiplePageViewにヘッダー・フッターを設定
    private func configureHeaderFooter(for pagesView: MultiplePageView) {
        guard let document = textDocument else { return }

        // ヘッダー・フッターのAttributedStringを取得
        if let headerFooterData = document.presetData?.headerFooter {
            // ヘッダー
            if let headerData = headerFooterData.headerRTFData {
                pagesView.headerAttributedString = NewDocData.HeaderFooterData.attributedString(from: headerData)
            }
            // フッター
            if let footerData = headerFooterData.footerRTFData {
                pagesView.footerAttributedString = NewDocData.HeaderFooterData.attributedString(from: footerData)
            }
        }

        // ヘッダー・フッター用のコンテキスト情報を設定
        pagesView.filePath = document.fileURL?.path
        pagesView.dateModified = document.fileModificationDate
        pagesView.documentProperties = document.presetData?.properties

        // ヘッダー・フッター・背景色を設定
        let colors = document.presetData?.fontAndColors.colors
        pagesView.headerColor = colors?.header.nsColor
        pagesView.footerColor = colors?.footer.nsColor
        // マージン（用紙）の背景色を設定
        pagesView.documentBackgroundColor = colors?.background.nsColor ?? .textBackgroundColor
    }

    /// ヘッダー・フッターの設定を更新
    /// presetDataが変更されたときに呼び出す
    func updateHeaderFooter() {
        if let pagesView = pagesView1 {
            configureHeaderFooter(for: pagesView)
            pagesView.needsDisplay = true
        }
        if let pagesView = pagesView2 {
            configureHeaderFooter(for: pagesView)
            pagesView.needsDisplay = true
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
            let textView = JeditTextView(frame: documentRect, textContainer: textContainer)
            textView.isEditable = !(textDocument?.presetData?.view.preventEditing ?? false)
            textView.isSelectable = true
            textView.allowsUndo = true
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = false
            textView.autoresizingMask = []
            textView.textContainerInset = NSSize(width: 0, height: 0)
            // リッチテキスト書類の場合はisRichTextとimportsGraphicsを設定
            let isPlainTextPage = textDocument?.documentType == .plain
            textView.isRichText = !isPlainTextPage
            textView.importsGraphics = !isPlainTextPage
            // ダークモード対応（プレーンテキストのみ）
            // リッチテキストは白背景固定（文字色はユーザー設定を保持）
            if isPlainTextPage {
                textView.backgroundColor = .textBackgroundColor
                textView.textColor = .textColor
            } else {
                textView.backgroundColor = .white
            }
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.usesInspectorBar = isInspectorBarVisible
            textView.usesRuler = true
            textView.usesFindBar = false
            textView.isIncrementalSearchingEnabled = true
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
        alert.messageText = "Fixed Width".localized
        alert.informativeText = "Enter the document width in characters:".localized
        alert.addButton(withTitle: "OK".localized)
        alert.addButton(withTitle: "Cancel".localized)

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

        let label = NSTextField(labelWithString: "chars.".localized)
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

    // MARK: - Word Wrapping Actions

    @IBAction func setWordWrappingSystemDefault(_ sender: Any?) {
        setWordWrappingType(.systemDefault)
    }

    @IBAction func setWordWrappingJapanese(_ sender: Any?) {
        setWordWrappingType(.japaneseWordwrap)
    }

    @IBAction func setWordWrappingNone(_ sender: Any?) {
        setWordWrappingType(.dontWordwrap)
    }

    private func setWordWrappingType(_ type: NewDocData.FormatData.WordWrappingType) {
        guard textDocument?.presetData != nil else { return }
        textDocument?.presetData?.format.wordWrappingType = type
        textDocument?.presetDataEdited = true

        // JOTextStorageに反映
        if let textStorage = textDocument?.textStorage {
            textStorage.setLineBreakingType(type.rawValue)

            if displayMode == .page {
                // ページ表示モードでは、invalidateLayout が didCompleteLayoutFor デリゲートを
                // 繰り返し呼び出し、ページ追加が無限ループになる問題を防ぐため、
                // デリゲートコールバックを一時的に抑制してから再レイアウトを行う
                isChangingLayoutOrientation = true
                let fullRange = NSRange(location: 0, length: textStorage.length)
                for layoutManager in textStorage.layoutManagers {
                    layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
                }
                isChangingLayoutOrientation = false

                // 遅延してレイアウトを再計算（didCompleteLayoutFor が正常に動作するタイミングで）
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    // クールダウンをリセットして再レイアウトを許可
                    self.layoutCooldownUntil = nil
                    // 各レイアウトマネージャーの最初のコンテナでレイアウトを再実行
                    for layoutManager in textStorage.layoutManagers {
                        if let firstContainer = layoutManager.textContainers.first {
                            layoutManager.ensureLayout(for: firstContainer)
                        }
                    }
                }
            } else {
                // Continuous モードでは直接 invalidateLayout を呼ぶ
                let fullRange = NSRange(location: 0, length: textStorage.length)
                for layoutManager in textStorage.layoutManagers {
                    layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
                }
            }
        }

        // 文書幅を再計算してレイアウトを更新
        applyLineWrapMode(updatePresetData: false)
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

        // 日本語禁則処理（japaneseWordwrap = 1）の場合、ぶら下げ用に+1文字分の幅を追加
        let extraChar: Int
        if let presetData = textDocument?.presetData,
           presetData.format.wordWrappingType == .japaneseWordwrap {
            extraChar = 1
        } else {
            extraChar = 0
        }

        return CGFloat(fixedWrapWidthInChars + extraChar) * charWidth
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
        scrollView1?.autoAdjustsContainerSizeOnFrameChange = autoAdjust
        scrollView2?.autoAdjustsContainerSizeOnFrameChange = autoAdjust

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
        textView.usesRuler = true

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

                // プレーンテキストの場合はルーラーのアクセサリビュー（段落スタイルコントロール）を非表示
                if textDocument?.documentType == .plain {
                    ruler.accessoryView = nil
                    ruler.reservedThicknessForAccessoryView = 0
                }
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
            firstTextView.usesRuler = true
            firstTextView.isRulerVisible = isRulerVisible

            if isRulerVisible {
                let ruler = isVerticalLayout ? scrollView.verticalRulerView : scrollView.horizontalRulerView
                if let ruler = ruler {
                    ruler.clientView = firstTextView
                    // ページモードでは、ルーラーの0地点をテキストの開始位置に合わせる
                    // 縦書き: topMargin、横書き: leftMargin + lineFragmentPadding
                    let lineFragmentPadding = firstTextView.textContainer?.lineFragmentPadding ?? 5.0
                    let marginOffset = isVerticalLayout ? pageTopMargin : pageLeftMargin
                    ruler.originOffset = marginOffset + lineFragmentPadding
                    // ルーラーの単位を設定
                    configureRulerUnit(ruler)

                    // プレーンテキストの場合はルーラーのアクセサリビュー（段落スタイルコントロール）を非表示
                    if textDocument?.documentType == .plain {
                        ruler.accessoryView = nil
                        ruler.reservedThicknessForAccessoryView = 0
                    }
                }
                if isFirstResponder {
                    window?.makeFirstResponder(firstTextView)
                }
                firstTextView.updateRuler()
            }
        }

        // 他のテキストビューにも設定
        for textView in textViews.dropFirst() {
            textView.usesRuler = true
            textView.isRulerVisible = isRulerVisible
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
        scheduleStatisticsUpdate()
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
                        // ページモードでの調整（縦書き: topMarginを使用）
                        adjustedCaretY += textView.frame.origin.y - pageTopMargin
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
                        // ページモードでの調整（横書き: leftMarginを使用）
                        adjustedCaretX += textView.frame.origin.x - pageLeftMargin
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

        // スケール表示を更新
        scrollView.updateScaleDisplay()
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

    // MARK: - Plain/Rich Text Toggle

    @IBAction func toggleRichText(_ sender: Any?) {
        guard let document = textDocument else { return }
        let isRich = document.documentType != .plain

        // Rich → Plain で情報が失われる場合はアラートを表示
        if isRich && toggleRichWillLoseInformation() {
            let alert = NSAlert()
            alert.messageText = "Convert this document to plain text?".localized
            alert.informativeText = "Making a rich text document plain will lose all text styles (such as fonts and colors), and images.".localized
            alert.addButton(withTitle: "OK".localized)
            alert.addButton(withTitle: "Cancel".localized)
            alert.beginSheetModal(for: self.window!) { response in
                if response == .alertFirstButtonReturn {
                    self.performToggleRichText(newFileType: nil)
                }
            }
        } else {
            performToggleRichText(newFileType: nil)
        }
    }

    /// リッチテキスト→プレーンテキストに変換するときに情報が失われるかどうかを判定
    private func toggleRichWillLoseInformation() -> Bool {
        guard let document = textDocument else { return false }
        let textStorage = document.textStorage
        let length = textStorage.length
        guard document.documentType != .plain, length > 0 else { return false }

        // プリセットからデフォルトの属性を構築
        var defaultAttrs: [NSAttributedString.Key: Any] = [:]
        if let fontData = document.presetData?.fontAndColors,
           let font = NSFont(name: fontData.baseFontName, size: fontData.baseFontSize) {
            defaultAttrs[.font] = font
        }
        if let colors = document.presetData?.fontAndColors.colors {
            defaultAttrs[.foregroundColor] = colors.character.nsColor
        }

        var range = NSRange()
        let attrs = textStorage.attributes(at: 0, effectiveRange: &range)

        // 属性が全体に統一されていない場合は情報が失われる
        if range.length < length {
            return true
        }

        // アタッチメントが含まれている場合は情報が失われる
        if textStorage.containsAttachments {
            return true
        }

        // フォントがデフォルトと異なる場合は情報が失われる
        if let defaultFont = defaultAttrs[NSAttributedString.Key.font] as? NSFont,
           let existingFont = attrs[NSAttributedString.Key.font] as? NSFont,
           defaultFont != existingFont {
            return true
        }

        return false
    }

    /// 実際のリッチ/プレーン切り替えを実行する（Undo対応）
    private func performToggleRichText(newFileType: String?) {
        guard let document = textDocument else { return }
        let isRich = document.documentType != .plain
        let textStorage = document.textStorage

        guard let undoManager = document.undoManager else { return }
        undoManager.beginUndoGrouping()

        // Undo用に元のファイルタイプを記録
        let oldFileType: String
        if isRich {
            oldFileType = textStorage.containsAttachments || document.documentType == .rtfd
                ? "com.apple.rtfd" : "public.rtf"
        } else {
            oldFileType = "public.plain-text"
        }
        undoManager.registerUndo(withTarget: self) { [weak self] target in
            self?.performToggleRichText(newFileType: oldFileType)
        }

        // テキストビューのリッチテキスト関連プロパティを更新
        updateForRichTextState(!isRich)

        // テキスト属性を変換
        convertTextForRichTextState(!isRich, removeAttachments: isRich)

        // ドキュメントタイプを切り替え
        if isRich {
            // Rich → Plain
            document.documentType = .plain

            // プレーンテキスト用のエンコーディング・改行コード・BOMをデフォルトに設定
            document.documentEncoding = .utf8
            document.lineEnding = .lf
            document.hasBOM = false

            // presetDataを更新
            document.presetData?.format.richText = false
            document.presetData?.format.fileExtension = "txt"
        } else {
            // Plain → Rich
            let type = newFileType ?? "public.rtf"
            document.documentType = (type == "com.apple.rtfd") ? .rtfd : .rtf

            // presetDataを更新
            document.presetData?.format.richText = true
        }

        // Undoアクション名を設定
        let actionName: String
        if undoManager.isUndoing != isRich {
            // Undo中なら逆のアクション名
            actionName = "Make Plain Text".localized
        } else {
            actionName = "Make Rich Text".localized
        }
        undoManager.setActionName(actionName)

        undoManager.endUndoGrouping()

        // ファイルタイプを更新
        // テキストタイプが変わるため、元のfileURLへのautosaveは行わず
        // fileURLをクリアして新規ドキュメント扱いにする（ユーザーが「名前を付けて保存」で保存する）
        let targetFileType = newFileType ?? (isRich ? "public.plain-text" : "public.rtf")
        if document.fileURL != nil {
            document.fileURL = nil
        }
        document.fileType = targetFileType

        // 通知を発行してUIを更新
        NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: document)

        // テキストビューを再構築してUIを完全に更新
        setupTextViews(with: textStorage)

        document.presetDataEdited = true
    }

    /// テキストビューのリッチテキスト関連プロパティを更新する
    private func updateForRichTextState(_ rich: Bool) {
        // リッチテキストで縦書きの場合はインスペクタバーを強制表示
        if rich && isVerticalLayout && displayMode == .continuous {
            isInspectorBarVisible = true
        }

        // Continuousモード
        if let scrollView = scrollView1,
           let textView = scrollView.documentView as? NSTextView {
            textView.isRichText = rich
            textView.usesRuler = rich
            textView.importsGraphics = rich
        }
        if let scrollView = scrollView2,
           !scrollView.isHidden,
           let textView = scrollView.documentView as? NSTextView {
            textView.isRichText = rich
            textView.usesRuler = rich
            textView.importsGraphics = rich
        }

        // Pageモード
        for textView in textViews1 {
            textView.isRichText = rich
            textView.usesRuler = rich
            textView.importsGraphics = rich
        }
        for textView in textViews2 {
            textView.isRichText = rich
            textView.usesRuler = rich
            textView.importsGraphics = rich
        }
    }

    /// テキスト属性をリッチ/プレーンに合わせて変換する
    private func convertTextForRichTextState(_ rich: Bool, removeAttachments: Bool) {
        guard let document = textDocument else { return }
        let textStorage = document.textStorage
        guard let undoManager = document.undoManager else { return }

        // デフォルトの属性を構築
        var textAttributes: [NSAttributedString.Key: Any] = [:]
        if let fontData = document.presetData?.fontAndColors,
           let font = NSFont(name: fontData.baseFontName, size: fontData.baseFontSize) {
            textAttributes[.font] = font
        } else {
            let fallbackFont: NSFont = NSFont.userFont(ofSize: 0) ?? NSFont.systemFont(ofSize: 13)
            textAttributes[.font] = fallbackFont
        }

        if let colors = document.presetData?.fontAndColors.colors {
            textAttributes[.foregroundColor] = colors.character.nsColor
        } else {
            textAttributes[.foregroundColor] = NSColor.textColor
        }

        // デフォルトのパラグラフスタイルをpresetDataから構築
        let formatData = document.presetData?.format
        let tabWidth: CGFloat = {
            if let fmt = formatData {
                return fmt.tabWidthUnit == .points ? fmt.tabWidthPoints : 28.0
            }
            return 28.0
        }()

        let paraStyle = NSMutableParagraphStyle()
        paraStyle.defaultTabInterval = tabWidth
        paraStyle.tabStops = []
        paraStyle.lineHeightMultiple = formatData?.lineHeightMultiple ?? 1.0
        paraStyle.minimumLineHeight = formatData?.lineHeightMinimum ?? 0
        paraStyle.maximumLineHeight = formatData?.lineHeightMaximum ?? 0
        paraStyle.lineSpacing = formatData?.interLineSpacing ?? 0
        paraStyle.paragraphSpacingBefore = formatData?.paragraphSpacingBefore ?? 0
        paraStyle.paragraphSpacing = formatData?.paragraphSpacingAfter ?? 0
        textAttributes[.paragraphStyle] = paraStyle

        // Undo/Redo時はテキスト変換をスキップ（textView自身がUndo処理を行う）
        if !undoManager.isUndoing && !undoManager.isRedoing {
            // アタッチメントの除去（Rich → Plain）
            if !rich && removeAttachments {
                self.removeAttachments(from: textStorage)
            }

            // 属性を一括適用
            let range = NSRange(location: 0, length: textStorage.length)
            if let textView = currentTextView() ?? (scrollView1?.documentView as? NSTextView) {
                if textView.shouldChangeText(in: range, replacementString: nil) {
                    textStorage.beginEditing()
                    // 書字方向を保持しながら属性を適用
                    textStorage.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, paragraphRange, _ in
                        let writingDirection: NSWritingDirection = (value as? NSParagraphStyle)?.baseWritingDirection ?? .natural
                        textStorage.enumerateAttribute(.writingDirection, in: paragraphRange, options: []) { dirValue, attrRange, _ in
                            textStorage.setAttributes(textAttributes, range: attrRange)
                            if let dirValue = dirValue {
                                textStorage.addAttribute(.writingDirection, value: dirValue, range: attrRange)
                            }
                        }
                        if writingDirection != .natural {
                            textStorage.setBaseWritingDirection(writingDirection, range: paragraphRange)
                        }
                    }
                    textStorage.endEditing()
                    textView.didChangeText()
                }
            }
        }

        // typingAttributesとdefaultParagraphStyleを更新
        let allTextViews: [NSTextView] = {
            var views: [NSTextView] = []
            if let tv = scrollView1?.documentView as? NSTextView { views.append(tv) }
            if let tv = scrollView2?.documentView as? NSTextView { views.append(tv) }
            views.append(contentsOf: textViews1)
            views.append(contentsOf: textViews2)
            return views
        }()

        for textView in allTextViews {
            textView.typingAttributes = textAttributes
            textView.defaultParagraphStyle = paraStyle
        }
    }

    /// テキストストレージからアタッチメント文字を除去する
    private func removeAttachments(from textStorage: NSTextStorage) {
        var loc = 0
        let textView = currentTextView() ?? (scrollView1?.documentView as? NSTextView)

        textStorage.beginEditing()
        while loc < textStorage.length {
            var attachmentRange = NSRange()
            let attachment = textStorage.attribute(.attachment, at: loc, longestEffectiveRange: &attachmentRange, in: NSRange(location: loc, length: textStorage.length - loc))
            if attachment != nil {
                let ch = (textStorage.string as NSString).character(at: loc)
                if ch == unichar(NSTextAttachment.character) {
                    if let textView = textView,
                       textView.shouldChangeText(in: NSRange(location: loc, length: 1), replacementString: "") {
                        textStorage.replaceCharacters(in: NSRange(location: loc, length: 1), with: "")
                        textView.didChangeText()
                    } else {
                        textStorage.replaceCharacters(in: NSRange(location: loc, length: 1), with: "")
                    }
                    // lengthが変わったのでlocは進めない
                } else {
                    loc += 1
                }
            } else {
                loc = NSMaxRange(attachmentRange)
            }
        }
        textStorage.endEditing()
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
        let textView = JeditTextView(frame: tempFrame, textContainer: textContainer)
        textView.isEditable = !(textDocument?.presetData?.view.preventEditing ?? false)
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.autoresizingMask = []
        textView.textContainerInset = NSSize(width: 0, height: 0)
        // リッチテキスト書類の場合はisRichTextとimportsGraphicsを設定
        let isPlainTextNewPage = textDocument?.documentType == .plain
        textView.isRichText = !isPlainTextNewPage
        textView.importsGraphics = !isPlainTextNewPage
        // ダークモード対応（プレーンテキストのみ）
        // リッチテキストは白背景固定（文字色はユーザー設定を保持）
        if isPlainTextNewPage {
            textView.backgroundColor = .textBackgroundColor
            textView.textColor = .textColor
        } else {
            textView.backgroundColor = .white
        }
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.usesInspectorBar = isInspectorBarVisible
        textView.usesRuler = true
        textView.usesFindBar = false
        textView.isIncrementalSearchingEnabled = true
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
                lineHeight = pageHeight - pageTopMargin - pageBottomMargin + (padding * 2)
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
                lineWidth = pageWidth - pageLeftMargin - pageRightMargin + (padding * 2)
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

        // ウィンドウリサイズや折り返しモード変更で行数が変わる可能性がある
        scheduleStatisticsUpdate()
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
            menuItem.title = isInspectorBarVisible ? "Hide Inspector Bar".localized : "Show Inspector Bar".localized
        }
        if menuItem.action == #selector(toggleDisplayMode(_:)) {
            menuItem.title = displayMode == .continuous ? "Wrap to Page".localized : "Wrap to Window".localized
        }
        if menuItem.action == #selector(toggleSplitView(_:)) {
            menuItem.title = splitMode != .none ? "Collapse Views".localized : "Split View".localized
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
            menuItem.title = isRulerVisible ? "Hide Ruler".localized : "Show Ruler".localized
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

        // Plain/Rich text toggle menu item validation
        if menuItem.action == #selector(toggleRichText(_:)) {
            let isPlainText = textDocument?.documentType == .plain
            menuItem.title = isPlainText ? "Make Rich Text".localized : "Make Plain Text".localized
        }

        // Layout orientation menu item validation
        if menuItem.action == #selector(toggleLayoutOrientation(_:)) {
            menuItem.title = isVerticalLayout ? "Make Horizontal Layout".localized : "Make Vertical Layout".localized
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
            menuItem.title = String(format: "Fixed Width (%dchars.)...".localized, fixedWrapWidthInChars)
        }

        // Auto Indent menu item validation
        if menuItem.action == #selector(toggleAutoIndent(_:)) {
            if let presetData = textDocument?.presetData {
                menuItem.state = presetData.format.autoIndent ? .on : .off
            } else {
                menuItem.state = .off
            }
        }

        // Word Wrapping menu items validation
        if menuItem.action == #selector(setWordWrappingSystemDefault(_:)) {
            if let presetData = textDocument?.presetData {
                menuItem.state = presetData.format.wordWrappingType == .systemDefault ? .on : .off
            } else {
                menuItem.state = .off
            }
        }
        if menuItem.action == #selector(setWordWrappingJapanese(_:)) {
            if let presetData = textDocument?.presetData {
                menuItem.state = presetData.format.wordWrappingType == .japaneseWordwrap ? .on : .off
            } else {
                menuItem.state = .off
            }
        }
        if menuItem.action == #selector(setWordWrappingNone(_:)) {
            if let presetData = textDocument?.presetData {
                menuItem.state = presetData.format.wordWrappingType == .dontWordwrap ? .on : .off
            } else {
                menuItem.state = .off
            }
        }

        // Prevent Editing menu item validation
        if menuItem.action == #selector(togglePreventEditing(_:)) {
            let isEditable = currentTextView()?.isEditable ?? true
            menuItem.title = isEditable ? "Prevent Editing".localized : "Allow Editing".localized
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
        if let scrollView = scrollView1 {
            let scrollPosition = scrollView.contentView.bounds.origin
            document.presetData?.view.scrollPositionX = scrollPosition.x
            document.presetData?.view.scrollPositionY = scrollPosition.y
        }

        // ツールバー設定を保存
        saveToolbarConfiguration()

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

            // ペンディング中のスクロール位置があれば適用
            if pendingScrollPosition != nil && target == .scrollView1 {
                DispatchQueue.main.async { [weak self] in
                    self?.applyPendingScrollPosition()
                }
            }
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
        let smartSeparation = defaults.bool(forKey: UserDefaults.Keys.smartSeparationEnglishJapanese)

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
                                     smartSeparation: smartSeparation,
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
                                     smartSeparation: smartSeparation,
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
                                     smartSeparation: smartSeparation,
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
                                     smartSeparation: smartSeparation,
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
                                          smartSeparation: Bool,
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
        if let jeditTextView = textView as? JeditTextView {
            jeditTextView.isSmartSeparationEnglishJapaneseEnabled = smartSeparation
        }
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

        // プレーンテキストの場合、全文にBasic Fontを適用し、typingAttributesも更新
        if textDocument?.documentType == .plain {
            applyFontToTextViews(font)
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
    func currentTextView() -> NSTextView? {
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
            undoManager.setActionName("Line Spacing".localized)
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
            undoManager.setActionName("Line Spacing".localized)
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
        guard let textView = currentTextView() as? JeditTextView else { return }

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
        guard let textView = currentTextView() as? JeditTextView else { return }

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
        guard let textView = currentTextView() as? JeditTextView else { return }

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
        guard let textView = currentTextView() as? JeditTextView else { return }

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
        guard let textView = currentTextView() as? JeditTextView else { return }

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
        guard let textView = currentTextView() as? JeditTextView else { return }

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
        guard let textView = currentTextView() as? JeditTextView else { return }

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
        guard let textView = currentTextView() as? JeditTextView else { return }

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

    // MARK: - Prevent Editing

    /// 編集のロック/アンロックをトグル
    @IBAction func togglePreventEditing(_ sender: Any?) {
        let isCurrentlyEditable = currentTextView()?.isEditable ?? true

        if isCurrentlyEditable {
            // 編集可能 → 読み取り専用にする場合は確認アラートを表示
            guard let window = self.window else { return }
            let alert = NSAlert()
            alert.messageText = "Are you sure?".localized
            alert.informativeText = "Make the current document read-only.".localized
            alert.addButton(withTitle: "OK".localized)
            alert.addButton(withTitle: "Cancel".localized)
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    self?.performSetPreventEditing(editable: false)
                }
            }
        } else {
            // 読み取り専用 → 編集可能にする
            if textDocument?.isImportedDocument == true {
                // Word/ODTからインポートした書類の場合は互換性に関する警告を表示
                guard let window = self.window else { return }
                let alert = NSAlert()
                alert.messageText = "Allow Editing?".localized
                alert.informativeText = "This document was imported from a format with limited compatibility. Some formatting may not be fully preserved when saved.".localized
                alert.addButton(withTitle: "Allow Editing".localized)
                alert.addButton(withTitle: "Cancel".localized)
                alert.beginSheetModal(for: window) { [weak self] response in
                    if response == .alertFirstButtonReturn {
                        self?.performSetPreventEditing(editable: true)
                    }
                }
            } else {
                performSetPreventEditing(editable: true)
            }
        }
    }

    /// 全テキストビューの isEditable を設定する（Finder ロックファイル対応で Document から呼ばれる）
    func setAllTextViewsEditable(_ editable: Bool) {
        var views: [NSTextView] = []
        if let tv = scrollView1?.documentView as? NSTextView { views.append(tv) }
        if let tv = scrollView2?.documentView as? NSTextView { views.append(tv) }
        views.append(contentsOf: textViews1)
        views.append(contentsOf: textViews2)
        for textView in views {
            textView.isEditable = editable
        }
        updateEditLockButtons()
    }

    /// 編集ロック状態を実際に変更する
    private func performSetPreventEditing(editable: Bool) {
        var views: [NSTextView] = []
        if let tv = scrollView1?.documentView as? NSTextView { views.append(tv) }
        if let tv = scrollView2?.documentView as? NSTextView { views.append(tv) }
        views.append(contentsOf: textViews1)
        views.append(contentsOf: textViews2)

        for textView in views {
            textView.isEditable = editable
        }

        // 編集許可時に originalMarkdownText をクリア（編集後は逆変換を使う）
        if editable {
            textDocument?.originalMarkdownText = nil
        }

        // presetDataに状態を保存
        textDocument?.presetData?.view.preventEditing = !editable
        markDocumentAsEdited()

        // 編集ロックボタンを更新
        updateEditLockButtons()
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

    // MARK: - Page Layout

    /// Page Layoutパネルのインスタンス
    private lazy var pageLayoutPanel: PageLayoutPanel? = PageLayoutPanel.loadFromNib()

    /// View > Page Layout... メニューアクション
    @IBAction func showPageLayoutPanel(_ sender: Any?) {
        guard let document = textDocument,
              let panel = pageLayoutPanel else { return }

        panel.showPanel(for: document)
    }

    // MARK: - Print Configuration

    /// 印刷用のPrintPageView設定を作成
    func printPageViewConfiguration() -> PrintPageView.Configuration? {
        guard let document = textDocument else { return nil }

        // ヘッダー・フッターのAttributedStringを取得
        var headerAttrString: NSAttributedString?
        var footerAttrString: NSAttributedString?
        if let headerFooterData = document.presetData?.headerFooter {
            if let headerData = headerFooterData.headerRTFData {
                headerAttrString = NewDocData.HeaderFooterData.attributedString(from: headerData)
            }
            if let footerData = headerFooterData.footerRTFData {
                footerAttrString = NewDocData.HeaderFooterData.attributedString(from: footerData)
            }
        }

        // 色を取得
        let colors = document.presetData?.fontAndColors.colors
        let bgColor: NSColor = colors?.background.nsColor ?? .textBackgroundColor

        // プレーンテキストの場合のデフォルトフォントと色
        let defaultFont: NSFont? = document.documentType == .plain ? currentBasicFont() : nil
        let defaultTextColor: NSColor? = document.documentType == .plain ? (colors?.character.nsColor ?? .textColor) : nil

        // 不可視文字の設定を取得
        let invisibleOptions = invisibleCharacterOptions
        let invisibleColor = colors?.invisible.nsColor ?? .tertiaryLabelColor

        return PrintPageView.Configuration(
            textStorage: document.textStorage,
            printInfo: document.printInfo,
            isVerticalLayout: isVerticalLayout,
            headerAttributedString: headerAttrString,
            footerAttributedString: footerAttrString,
            headerColor: colors?.header.nsColor,
            footerColor: colors?.footer.nsColor,
            documentName: document.displayName ?? "",
            filePath: document.fileURL?.path,
            dateModified: document.fileModificationDate,
            documentProperties: document.presetData?.properties,
            textBackgroundColor: bgColor,
            isPlainText: document.documentType == .plain,
            defaultFont: defaultFont,
            defaultTextColor: defaultTextColor,
            invisibleCharacterOptions: invisibleOptions,
            invisibleCharacterColor: invisibleColor,
            lineBreakingType: Int(document.presetData?.format.wordWrappingType.rawValue ?? 0),
            lineNumberMode: lineNumberMode,
            lineNumberColor: colors?.lineNumber.nsColor ?? .secondaryLabelColor
        )
    }

    // MARK: - Toolbar Encoding Item

    /// ツールバーにエンコーディング表示アイテムをセットアップ
    private func setupEncodingToolbarItem() {
        guard let window = self.window else { return }

        // ウィンドウごとにユニークな識別子を生成
        // NSToolbarは同じ識別子を持つツールバー間で設定を共有するため、
        // ドキュメントごとに異なる設定を保持するにはユニークな識別子が必要
        let uniqueID = UUID().uuidString
        let toolbarIdentifier = NSToolbar.Identifier("JeditDocumentToolbar-\(uniqueID)")
        let toolbar = NSToolbar(identifier: toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        // showsBaselineSeparator is deprecated in macOS 11+; NSWindow.titlebarSeparatorStyle is used instead
        if #available(macOS 11.0, *) {
            // titlebarSeparatorStyle is set on the window, not toolbar
        } else {
            toolbar.showsBaselineSeparator = false
        }
        toolbar.autosavesConfiguration = false  // 書類ごとに保存するため無効化
        toolbar.allowsUserCustomization = true

        // ウィンドウに設定
        window.toolbar = toolbar

        // 保存されたツールバー設定を復元
        restoreToolbarConfiguration()

        // 初期表示を更新
        updateEncodingToolbarItem()
        updateLineEndingToolbarItem()

        // ツールバー変更通知を監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toolbarDidChange(_:)),
            name: NSNotification.Name("NSToolbarWillAddItemNotification"),
            object: toolbar
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toolbarDidChange(_:)),
            name: NSNotification.Name("NSToolbarDidRemoveItemNotification"),
            object: toolbar
        )
    }

    /// ツールバー変更時の通知ハンドラ
    @objc private func toolbarDidChange(_ notification: Notification) {
        // 少し遅延させて、ツールバーの変更が完了してから保存
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.saveToolbarConfiguration()
        }
    }

    /// ツールバー設定を保存
    func saveToolbarConfiguration() {
        guard let toolbar = window?.toolbar else { return }
        let identifiers = toolbar.items.map { $0.itemIdentifier.rawValue }
        textDocument?.presetData?.view.toolbarItemIdentifiers = identifiers
        // displayMode を保存
        textDocument?.presetData?.view.toolbarDisplayMode = Int(toolbar.displayMode.rawValue)
        textDocument?.presetDataEdited = true
    }

    /// ツールバー設定を復元
    private func restoreToolbarConfiguration() {
        guard let toolbar = window?.toolbar else { return }

        // displayMode を復元
        if let displayModeValue = textDocument?.presetData?.view.toolbarDisplayMode,
           let displayMode = NSToolbar.DisplayMode(rawValue: UInt(displayModeValue)) {
            toolbar.displayMode = displayMode
        }

        // ツールバー項目を復元
        guard let savedIdentifiers = textDocument?.presetData?.view.toolbarItemIdentifiers,
              !savedIdentifiers.isEmpty else {
            return
        }

        // 現在のツールバー項目を全て削除
        while toolbar.items.count > 0 {
            toolbar.removeItem(at: 0)
        }

        // 保存された順序で項目を挿入
        for (index, identifierString) in savedIdentifiers.enumerated() {
            let identifier = NSToolbarItem.Identifier(identifierString)
            toolbar.insertItem(withItemIdentifier: identifier, at: index)
        }
    }

    /// エンコーディングツールバーアイテムを作成（delegateから呼ばれる）
    private func createEncodingToolbarItem() -> NSToolbarItem {
        // ポップアップボタン作成（EncodingPopUpButton でメニュー表示時に変換不能チェック）
        let popupButton = EncodingPopUpButton(frame: NSRect(x: 0, y: 0, width: 140, height: 22), pullsDown: false)
        popupButton.font = NSFont.systemFont(ofSize: 11)
        popupButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        populateEncodingPopup(popupButton)
        popupButton.target = self
        popupButton.action = #selector(encodingPopupChanged(_:))

        // ポップアップが開く瞬間に変換不能エンコーディングを disable するクロージャを設定
        popupButton.textForValidation = { [weak self] in
            return self?.textDocument?.textStorage.string
        }

        // リッチテキストの場合は無効化
        let isPlainText = textDocument?.documentType == .plain
        popupButton.isEnabled = isPlainText

        // 制約ベースのサイズ設定
        popupButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            popupButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            popupButton.widthAnchor.constraint(lessThanOrEqualToConstant: 180),
            popupButton.heightAnchor.constraint(equalToConstant: 22)
        ])

        // ツールバーアイテム作成
        let item = NSToolbarItem(itemIdentifier: Self.encodingToolbarItemIdentifier)
        item.label = "Encoding".localized
        item.paletteLabel = "Text Encoding".localized
        item.toolTip = "Document text encoding".localized
        item.view = popupButton

        self.encodingToolbarItem = item

        return item
    }

    /// エンコーディングポップアップメニューを構築
    private func populateEncodingPopup(_ popup: NSPopUpButton) {
        // 現在のドキュメントエンコーディングを取得
        let currentEncoding = textDocument?.documentEncoding ?? .utf8

        // EncodingManagerを使用してポップアップを構築
        // 「自動」項目は不要、「カスタマイズ...」項目を追加
        EncodingManager.shared.setupPopUp(
            popup,
            selectedEncoding: currentEncoding,
            withDefaultEntry: false,
            includeCustomizeItem: true,
            target: self,
            action: #selector(showEncodingCustomizePanel(_:))
        )

    }

    /// エンコーディングカスタマイズパネルを表示
    @objc private func showEncodingCustomizePanel(_ sender: Any?) {
        EncodingManager.shared.showPanel(sender)
        // パネルを閉じた後にポップアップを更新するため、通知を監視
        // EncodingManagerが更新されたら再構築
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.refreshEncodingPopup()
        }
    }

    /// エンコーディングポップアップを再構築
    private func refreshEncodingPopup() {
        guard let popup = getEncodingPopupButton() else { return }
        populateEncodingPopup(popup)
    }

    /// エンコーディングリスト変更通知ハンドラ
    @objc private func encodingsListDidChange(_ notification: Notification) {
        refreshEncodingPopup()
    }

    /// エンコーディングポップアップボタンを取得
    private func getEncodingPopupButton() -> EncodingPopUpButton? {
        // まずキャッシュされたアイテムから取得を試みる
        if let popup = encodingToolbarItem?.view as? EncodingPopUpButton {
            return popup
        }
        // ツールバーから直接検索
        guard let toolbar = self.window?.toolbar else { return nil }
        for item in toolbar.items {
            if item.itemIdentifier == Self.encodingToolbarItemIdentifier,
               let popup = item.view as? EncodingPopUpButton {
                // キャッシュを更新
                self.encodingToolbarItem = item
                return popup
            }
        }
        return nil
    }

    /// エンコーディングツールバーアイテムを更新
    func updateEncodingToolbarItem() {
        guard let popup = getEncodingPopupButton() else { return }

        // リッチテキストの場合はエンコーディングポップアップを無効化
        let isPlainText = textDocument?.documentType == .plain
        popup.isEnabled = isPlainText

        // 現在のドキュメントエンコーディングを取得
        let encoding = textDocument?.documentEncoding ?? .utf8

        // ポップアップを再構築して選択を更新
        EncodingManager.shared.setupPopUp(
            popup,
            selectedEncoding: encoding,
            withDefaultEntry: false,
            includeCustomizeItem: true,
            target: self,
            action: #selector(showEncodingCustomizePanel(_:))
        )
        // 変換不能エンコーディングの disable は EncodingPopUpButton.willOpenMenu で行う
    }

    /// エンコーディングポップアップの変更ハンドラ
    @objc private func encodingPopupChanged(_ sender: NSPopUpButton) {
        // リッチテキストの場合はエンコーディング変更を許可しない
        if textDocument?.documentType != .plain {
            updateEncodingToolbarItem()
            return
        }

        guard let selectedItem = sender.selectedItem else { return }

        // 「カスタマイズ...」が選択された場合
        if selectedItem.tag == EncodingManager.customizeEncodingsTag {
            showEncodingCustomizePanel(sender)
            // 選択を元に戻す
            updateEncodingToolbarItem()
            return
        }

        let newEncoding = String.Encoding(rawValue: UInt(selectedItem.tag))

        guard let document = textDocument else { return }

        // 現在のエンコーディングと同じ場合は何もしない
        if document.documentEncoding == newEncoding {
            return
        }

        // エンコーディングを変更
        changeDocumentEncoding(to: newEncoding)
    }

    /// ドキュメントのエンコーディングを変更
    private func changeDocumentEncoding(to newEncoding: String.Encoding) {
        guard let document = textDocument,
              let window = self.window else { return }

        // 現在のテキストを新しいエンコーディングで再エンコードできるか確認
        let currentText = document.textStorage.string
        guard let data = currentText.data(using: newEncoding) else {
            // 変換できない場合はアラートをシートとして表示
            let alert = NSAlert()
            alert.messageText = "Cannot Convert".localized
            alert.informativeText = String(format: "The document contains characters that cannot be represented in %@.".localized, String.localizedName(of: newEncoding))
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK".localized)
            alert.beginSheetModal(for: window) { [weak self] _ in
                // ポップアップを元に戻す
                self?.updateEncodingToolbarItem()
            }
            return
        }

        // 再変換して確認（ラウンドトリップテスト）
        let reconverted = String(data: data, encoding: newEncoding)
        if reconverted != currentText {
            // ラウンドトリップできない場合はアラートをシートとして表示
            let alert = NSAlert()
            alert.messageText = "Encoding Warning".localized
            alert.informativeText = String(format: "Converting to %@ may result in data loss. Do you want to continue?".localized, String.localizedName(of: newEncoding))
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Convert".localized)
            alert.addButton(withTitle: "Cancel".localized)

            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    // 変換を実行
                    self?.applyEncodingChange(newEncoding, to: document)
                } else {
                    // キャンセル - ポップアップを元に戻す
                    self?.updateEncodingToolbarItem()
                }
            }
            return
        }

        // エンコーディングを変更（ラウンドトリップテストOKの場合）
        applyEncodingChange(newEncoding, to: document)
    }

    /// エンコーディング変更を適用
    private func applyEncodingChange(_ newEncoding: String.Encoding, to document: Document) {
        document.documentEncoding = newEncoding
        document.updateChangeCount(.changeDone)

        #if DEBUG
        Swift.print("Encoding changed to: \(String.localizedName(of: newEncoding))")
        #endif
    }

    // MARK: - Toolbar Line Ending Item

    /// 改行コードツールバーアイテムを作成
    private func createLineEndingToolbarItem() -> NSToolbarItem {
        // ポップアップボタン作成
        let popupButton = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 80, height: 22), pullsDown: false)
        popupButton.font = NSFont.systemFont(ofSize: 11)
        popupButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        populateLineEndingPopup(popupButton)
        popupButton.target = self
        popupButton.action = #selector(lineEndingPopupChanged(_:))

        // リッチテキストの場合は無効化
        let isPlainText = textDocument?.documentType == .plain
        popupButton.isEnabled = isPlainText

        // 制約ベースのサイズ設定
        popupButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            popupButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 70),
            popupButton.widthAnchor.constraint(lessThanOrEqualToConstant: 120),
            popupButton.heightAnchor.constraint(equalToConstant: 22)
        ])

        // ツールバーアイテム作成
        let item = NSToolbarItem(itemIdentifier: Self.lineEndingToolbarItemIdentifier)
        item.label = "Line Ending".localized
        item.paletteLabel = "Line Ending".localized
        item.toolTip = "Document line ending format".localized
        item.view = popupButton

        self.lineEndingToolbarItem = item

        return item
    }

    /// 改行コードポップアップメニューを構築
    private func populateLineEndingPopup(_ popup: NSPopUpButton) {
        popup.removeAllItems()

        // 現在の改行コードを取得
        let currentLineEnding = textDocument?.lineEnding ?? .lf

        // 改行コードの選択肢を追加
        for lineEnding in LineEnding.allCases {
            popup.addItem(withTitle: lineEnding.shortDescription)
            popup.lastItem?.tag = lineEnding.rawValue
        }

        // 現在の改行コードを選択
        popup.selectItem(withTag: currentLineEnding.rawValue)
    }

    /// 改行コードポップアップボタンを取得
    private func getLineEndingPopupButton() -> NSPopUpButton? {
        // まずキャッシュされたアイテムから取得を試みる
        if let popup = lineEndingToolbarItem?.view as? NSPopUpButton {
            return popup
        }
        // ツールバーから直接検索
        guard let toolbar = self.window?.toolbar else { return nil }
        for item in toolbar.items {
            if item.itemIdentifier == Self.lineEndingToolbarItemIdentifier,
               let popup = item.view as? NSPopUpButton {
                // キャッシュを更新
                self.lineEndingToolbarItem = item
                return popup
            }
        }
        return nil
    }

    /// 改行コードツールバーアイテムを更新
    func updateLineEndingToolbarItem() {
        guard let popup = getLineEndingPopupButton() else { return }

        // リッチテキストの場合は改行コードポップアップを無効化
        let isPlainText = textDocument?.documentType == .plain
        popup.isEnabled = isPlainText

        // 現在の改行コードを取得して選択を更新
        let lineEnding = textDocument?.lineEnding ?? .lf
        popup.selectItem(withTag: lineEnding.rawValue)
    }

    /// 改行コードポップアップの変更ハンドラ
    @objc private func lineEndingPopupChanged(_ sender: NSPopUpButton) {
        // リッチテキストの場合は改行コード変更を許可しない
        if textDocument?.documentType != .plain {
            updateLineEndingToolbarItem()
            return
        }

        guard let selectedItem = sender.selectedItem,
              let newLineEnding = LineEnding(rawValue: selectedItem.tag),
              let document = textDocument else { return }

        // 現在の改行コードと同じ場合は何もしない
        if document.lineEnding == newLineEnding {
            return
        }

        // 改行コードを変更
        document.lineEnding = newLineEnding
        document.updateChangeCount(.changeDone)

        #if DEBUG
        Swift.print("Line ending changed to: \(newLineEnding.description)")
        #endif
    }

    // MARK: - Writing Progress Toolbar Item

    /// 執筆進捗ツールバーアイテムを作成
    private func createWritingProgressToolbarItem() -> NSToolbarItem {
        let progressView = WritingProgressView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        progressView.target = self
        progressView.action = #selector(showWritingGoalPanel(_:))

        // 制約ベースのサイズ設定
        progressView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressView.widthAnchor.constraint(equalToConstant: 28),
            progressView.heightAnchor.constraint(equalToConstant: 28)
        ])

        let item = NSToolbarItem(itemIdentifier: Self.writingProgressToolbarItemIdentifier)
        item.label = "Writing Progress".localized
        item.paletteLabel = "Writing Progress".localized
        item.toolTip = "Writing Progress - Click to set goal".localized
        item.view = progressView

        self.writingProgressToolbarItem = item

        // 現在の目標設定で初期化
        updateWritingProgressDisplay()

        return item
    }

    /// 執筆進捗表示を更新
    func updateWritingProgressDisplay() {
        guard let progressView = getWritingProgressView() else { return }
        guard let document = textDocument else { return }

        let goal = document.presetData?.writingGoal
        let targetCount = goal?.targetCount ?? 0
        let countMethod = goal?.countMethod ?? 0

        if targetCount > 0 {
            progressView.isGoalSet = true
            let totalVisibleChars = document.statistics.totalVisibleChars

            let currentCount: Int
            if countMethod == 1 {
                // 原稿用紙換算（400字詰め）
                currentCount = Int(ceil(totalVisibleChars / 400.0))
            } else {
                // 可視文字数
                currentCount = Int(totalVisibleChars)
            }

            progressView.currentCount = currentCount
            progressView.targetCount = targetCount
            progressView.countMethod = countMethod
            progressView.progress = Double(currentCount) / Double(targetCount)
        } else {
            progressView.isGoalSet = false
            progressView.progress = 0
            progressView.currentCount = 0
            progressView.targetCount = 0
            progressView.countMethod = 0
        }
    }

    /// WritingProgressView を取得
    private func getWritingProgressView() -> WritingProgressView? {
        // キャッシュされたアイテムから取得
        if let view = writingProgressToolbarItem?.view as? WritingProgressView {
            return view
        }
        // ツールバーから直接検索
        guard let toolbar = self.window?.toolbar else { return nil }
        for item in toolbar.items {
            if item.itemIdentifier == Self.writingProgressToolbarItemIdentifier,
               let view = item.view as? WritingProgressView {
                self.writingProgressToolbarItem = item
                return view
            }
        }
        return nil
    }

    /// 執筆目標設定パネルを表示
    @IBAction func showWritingGoalPanel(_ sender: Any?) {
        guard let window = self.window,
              let document = textDocument else { return }

        let currentGoal = document.presetData?.writingGoal

        writingGoalPanel.beginSheet(for: window, currentGoal: currentGoal) { [weak self] goalData in
            guard let self = self, let goalData = goalData else { return }

            // presetData に保存
            self.textDocument?.presetData?.writingGoal = goalData
            self.textDocument?.presetDataEdited = true

            // 目標が設定された場合、ツールバーを表示し執筆進捗アイテムを追加
            if goalData.targetCount > 0, let toolbar = self.window?.toolbar {
                // ツールバーが非表示なら表示する
                if !toolbar.isVisible {
                    toolbar.isVisible = true
                    self.textDocument?.presetData?.view.showToolBar = true
                }
                // 執筆進捗アイテムがツールバーにない場合は追加
                let hasWritingProgress = toolbar.items.contains {
                    $0.itemIdentifier == Self.writingProgressToolbarItemIdentifier
                }
                if !hasWritingProgress {
                    toolbar.insertItem(withItemIdentifier: Self.writingProgressToolbarItemIdentifier,
                                       at: toolbar.items.count)
                }
            }

            // 表示を更新
            self.updateWritingProgressDisplay()
        }
    }

    // MARK: - Find Toolbar Item

    /// 検索ツールバーアイテムを作成
    private func createFindToolbarItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: Self.findToolbarItemIdentifier)
        item.label = "Find".localized
        item.paletteLabel = "Find".localized
        item.toolTip = "Show Find Bar".localized
        item.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Find")
        item.target = nil  // レスポンダチェーンを通じて送信
        item.action = #selector(showFindBar(_:))
        return item
    }

    private func createBookmarkToolbarItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: Self.bookmarkToolbarItemIdentifier)
        item.label = "Bookmarks".localized
        item.paletteLabel = "Bookmarks".localized
        item.toolTip = "Show Bookmarks".localized
        item.image = NSImage(systemSymbolName: "bookmark", accessibilityDescription: "Bookmarks")
        item.target = nil  // レスポンダチェーンを通じて送信
        item.action = #selector(Document.showBookmarkPanel(_:))
        return item
    }

    // MARK: - NSToolbarDelegate

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == Self.findToolbarItemIdentifier {
            return createFindToolbarItem()
        }
        if itemIdentifier == Self.encodingToolbarItemIdentifier {
            return createEncodingToolbarItem()
        }
        if itemIdentifier == Self.lineEndingToolbarItemIdentifier {
            return createLineEndingToolbarItem()
        }
        if itemIdentifier == Self.writingProgressToolbarItemIdentifier {
            return createWritingProgressToolbarItem()
        }
        if itemIdentifier == Self.bookmarkToolbarItemIdentifier {
            return createBookmarkToolbarItem()
        }
        return nil
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .flexibleSpace,
            .space,
            .showColors,
            .showFonts,
            .print,
            Self.findToolbarItemIdentifier,
            Self.encodingToolbarItemIdentifier,
            Self.lineEndingToolbarItemIdentifier,
            Self.writingProgressToolbarItemIdentifier,
            Self.bookmarkToolbarItemIdentifier
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .flexibleSpace,
            .print
        ]
    }

    // MARK: - Document Statistics Calculation

    /// 統計計算をスケジュールするための DispatchWorkItem（coalescing 用）
    private var statisticsWorkItem: DispatchWorkItem?

    /// 統計計算をスケジュール（短時間の連続イベントを合体）
    func scheduleStatisticsUpdate() {
        statisticsWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.calculateStatistics()
        }
        statisticsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    /// 統計情報を計算して Document に設定
    private func calculateStatistics() {
        guard let document = textDocument else { return }

        // 最初のテキストビューを取得（Split時も常に最初のView）
        let primaryTextView: NSTextView?
        if displayMode == .page {
            primaryTextView = textViews1.first
        } else {
            primaryTextView = scrollView1?.documentView as? NSTextView
        }
        guard let textView = primaryTextView else { return }

        // メインスレッドで取得する情報
        let fullText = document.textStorage.string
        let textLength = document.textStorage.length
        let selectedRange: NSRange
        if let firstRange = textView.selectedRanges.first {
            selectedRange = firstRange.rangeValue
        } else {
            selectedRange = NSRange(location: 0, length: 0)
        }

        let showRows = (lineNumberMode != .none)
        let showPages = (displayMode == .page)

        // Rows 計算（メインスレッドで — layoutManager 依存）
        var totalRows = 0
        var locationRows = 0
        var selectionRows = 0
        if showRows, let layoutManager = textView.layoutManager {
            // 全体の表示行数 + 選択開始位置の行番号
            var lineCount = 0
            var index = 0
            let numberOfGlyphs = layoutManager.numberOfGlyphs
            let selGlyphStart = (selectedRange.location < textLength)
                ? layoutManager.glyphIndexForCharacter(at: selectedRange.location)
                : numberOfGlyphs
            var locationRowFound = false

            while index < numberOfGlyphs {
                var lineRange = NSRange()
                layoutManager.lineFragmentRect(forGlyphAt: index, effectiveRange: &lineRange, withoutAdditionalLayout: false)
                lineCount += 1

                // 選択開始位置の行番号を記録
                if !locationRowFound && NSMaxRange(lineRange) > selGlyphStart {
                    locationRows = lineCount
                    locationRowFound = true
                }

                index = NSMaxRange(lineRange)
            }
            if !locationRowFound {
                locationRows = lineCount + 1
            }
            // テキストが空でない場合、最後が改行なら+1
            if textLength > 0 {
                let lastChar = (fullText as NSString).character(at: textLength - 1)
                if lastChar == 0x0A || lastChar == 0x0D {
                    lineCount += 1
                }
            }
            totalRows = max(lineCount, 1)

            // 選択範囲の行数
            if selectedRange.length > 0 {
                let selEnd = min(selectedRange.location + selectedRange.length, textLength)
                let selGlyphEnd = (selEnd < textLength)
                    ? layoutManager.glyphIndexForCharacter(at: selEnd)
                    : numberOfGlyphs
                var selLineCount = 0
                var gi = selGlyphStart
                while gi < selGlyphEnd {
                    var lineRange = NSRange()
                    layoutManager.lineFragmentRect(forGlyphAt: gi, effectiveRange: &lineRange, withoutAdditionalLayout: false)
                    selLineCount += 1
                    gi = NSMaxRange(lineRange)
                }
                selectionRows = selLineCount
            }
        }

        // Pages 計算（メインスレッドで）
        var totalPages = 0
        var locationPages = 0
        var selectionPages = 0
        if showPages, let pagesView = pagesView1, let layoutManager = textView.layoutManager {
            totalPages = pagesView.numberOfPages

            let selGlyph = (selectedRange.location < textLength)
                ? layoutManager.glyphIndexForCharacter(at: selectedRange.location)
                : layoutManager.numberOfGlyphs

            // 選択開始位置のページ番号
            for (pageIndex, tc) in textContainers1.enumerated() {
                let tcGlyphRange = layoutManager.glyphRange(for: tc)
                if NSLocationInRange(selGlyph, tcGlyphRange) || selGlyph < tcGlyphRange.location {
                    locationPages = pageIndex + 1
                    break
                }
                locationPages = pageIndex + 1  // 最後のページの末尾を超えた場合
            }

            // 選択範囲のページ数
            if selectedRange.length > 0 {
                let endChar = min(selectedRange.location + selectedRange.length, textLength)
                let endGlyph = (endChar < textLength)
                    ? layoutManager.glyphIndexForCharacter(at: endChar)
                    : layoutManager.numberOfGlyphs

                var startPage = -1
                var endPage = -1
                for (pageIndex, tc) in textContainers1.enumerated() {
                    let tcGlyphRange = layoutManager.glyphRange(for: tc)
                    if startPage < 0 && NSLocationInRange(selGlyph, tcGlyphRange) {
                        startPage = pageIndex
                    }
                    if NSLocationInRange(max(endGlyph - 1, 0), tcGlyphRange) {
                        endPage = pageIndex
                        break
                    }
                }
                if startPage >= 0 && endPage >= 0 {
                    selectionPages = endPage - startPage + 1
                }
            }
        }

        // Char. Code（メインスレッドで）
        let charCodeLocation = selectedRange.location
        var charCode = ""
        if charCodeLocation < textLength {
            let charIndex = fullText.index(fullText.startIndex, offsetBy: charCodeLocation, limitedBy: fullText.endIndex) ?? fullText.endIndex
            if charIndex < fullText.endIndex {
                let char = fullText[charIndex]
                let scalars = char.unicodeScalars
                let codePoint = scalars.first!.value
                let displayChar = Self.displayName(for: codePoint) ?? "'\(char)'"
                let codeStr = codePoint < 0x10000
                    ? String(format: "\\u%04x", codePoint)
                    : String(format: "\\u%05x", codePoint)
                charCode = "\(displayChar) : \(codeStr)"
            }
        }

        // テキストのコピーをバックグラウンドに渡す
        let textCopy = fullText
        let selLoc = selectedRange.location
        let selLen = selectedRange.length
        let countHalfAs05 = DocumentInfoPanelController.shared.countHalfWidthAs05

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let nsText = textCopy as NSString

            // Whole document の統計（バックグラウンド）
            let totalCharacters = nsText.length
            let totalVisibleChars = Self.countVisibleChars(in: textCopy, countHalfAs05: countHalfAs05)
            let totalWords = Self.countWords(in: textCopy)
            let totalParagraphs = Self.countParagraphs(in: textCopy)

            // Selection 開始位置までの統計（location 計算、1始まり）
            var locationWords = 1
            var locationParagraphs = 1
            if selLoc > 0 {
                let prefixText = nsText.substring(to: selLoc)
                locationWords = Self.countWords(in: prefixText) + 1
                locationParagraphs = Self.countParagraphs(in: prefixText) + 1
            }

            // Selection の統計（バックグラウンド）
            var selCharacters = 0
            var selVisibleChars: Double = 0
            var selWords = 0
            var selParagraphs = 0
            if selLen > 0 {
                let safeRange = NSRange(location: selLoc, length: min(selLen, nsText.length - selLoc))
                let selectedText = nsText.substring(with: safeRange)
                selCharacters = (selectedText as NSString).length
                selVisibleChars = Self.countVisibleChars(in: selectedText, countHalfAs05: countHalfAs05)
                selWords = Self.countWords(in: selectedText)
                selParagraphs = Self.countParagraphs(in: selectedText)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self, let document = self.textDocument else { return }

                var stats = DocumentStatistics()
                stats.totalCharacters = totalCharacters
                stats.totalVisibleChars = totalVisibleChars
                stats.totalWords = totalWords
                stats.totalParagraphs = totalParagraphs
                stats.totalRows = totalRows
                stats.totalPages = totalPages
                stats.selectionLocation = selLoc
                stats.selectionLength = selLen
                stats.locationWords = locationWords
                stats.locationParagraphs = locationParagraphs
                stats.locationRows = locationRows
                stats.locationPages = locationPages
                stats.selectionCharacters = selCharacters
                stats.selectionVisibleChars = selVisibleChars
                stats.selectionWords = selWords
                stats.selectionParagraphs = selParagraphs
                stats.selectionRows = selectionRows
                stats.selectionPages = selectionPages
                stats.charCode = charCode
                stats.showRows = showRows
                stats.showPages = showPages

                document.statistics = stats
                NotificationCenter.default.post(
                    name: Document.statisticsDidChangeNotification,
                    object: document
                )

                // 執筆進捗ツールバーアイテムを更新
                self.updateWritingProgressDisplay()
            }
        }
    }

    // MARK: - Statistics Counting Helpers

    /// 可視文字数をカウント（制御文字＝タブ・改行を除く）
    private static func countVisibleChars(in text: String, countHalfAs05: Bool) -> Double {
        var count: Double = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x09, 0x0A, 0x0D:  // tab, LF, CR
                break
            default:
                if countHalfAs05 && isHalfWidth(scalar) {
                    count += 0.5
                } else {
                    count += 1
                }
            }
        }
        return count
    }

    /// 半角文字かどうかを判定
    /// ASCII 印字可能文字（0x21-0x7E）および半角カナ（0xFF61-0xFF9F）を半角とみなす
    private static func isHalfWidth(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        // ASCII 印字可能文字（スペースは除外、制御文字は既に除外済み）
        if v >= 0x21 && v <= 0x7E { return true }
        // 半角カナ
        if v >= 0xFF61 && v <= 0xFF9F { return true }
        return false
    }

    /// 単語数をカウント
    private static func countWords(in text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { _, _, _, _ in
            count += 1
        }
        return count
    }

    /// 段落数をカウント（改行区切り）
    private static func countParagraphs(in text: String) -> Int {
        if text.isEmpty { return 0 }
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byParagraphs) { _, _, _, _ in
            count += 1
        }
        return count
    }

    /// Unicode コードポイントが制御文字の場合に表示名を返す
    /// 表示可能な文字の場合は nil を返す
    private static func displayName(for codePoint: UInt32) -> String? {
        switch codePoint {
        case 0x00: return "NUL"
        case 0x01: return "SOH"
        case 0x02: return "STX"
        case 0x03: return "ETX"
        case 0x04: return "EOT"
        case 0x05: return "ENQ"
        case 0x06: return "ACK"
        case 0x07: return "BEL"
        case 0x08: return "BS"
        case 0x09: return "TAB"
        case 0x0A: return "LF"
        case 0x0B: return "VT"
        case 0x0C: return "FF"
        case 0x0D: return "CR"
        case 0x0E: return "SO"
        case 0x0F: return "SI"
        case 0x10: return "DLE"
        case 0x11: return "DC1"
        case 0x12: return "DC2"
        case 0x13: return "DC3"
        case 0x14: return "DC4"
        case 0x15: return "NAK"
        case 0x16: return "SYN"
        case 0x17: return "ETB"
        case 0x18: return "CAN"
        case 0x19: return "EM"
        case 0x1A: return "SUB"
        case 0x1B: return "ESC"
        case 0x1C: return "FS"
        case 0x1D: return "GS"
        case 0x1E: return "RS"
        case 0x1F: return "US"
        case 0x20: return "SP"
        case 0x7F: return "DEL"
        case 0x85: return "NEL"
        case 0xA0: return "NBSP"
        case 0x2028: return "LS"     // Line Separator
        case 0x2029: return "PS"     // Paragraph Separator
        case 0x200B: return "ZWSP"   // Zero Width Space
        case 0x200C: return "ZWNJ"   // Zero Width Non-Joiner
        case 0x200D: return "ZWJ"    // Zero Width Joiner
        case 0xFEFF: return "BOM"    // Byte Order Mark
        case 0xFFFC: return "OBJ"    // Object Replacement Character
        case 0xFFFD: return "REP"    // Replacement Character
        default: return nil
        }
    }

    // MARK: - Find Bar

    @objc func showFindBar(_ sender: Any?) {
        if findBarViewController?.view.superview != nil {
            dismissFindBar()
        } else {
            presentFindBar(replaceMode: false)
        }
    }

    /// FindBar を表示して指定テキストで検索を実行する（Help 検索用）
    func showFindBarAndSearch(_ searchText: String) {
        presentFindBar(replaceMode: false)
        findBarViewController?.setSearchTextCaseInsensitive(searchText)

        // 新規ドキュメントの場合、ウィンドウ表示とテキストレイアウトの完了を待ってからスクロール
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.findBarViewController?.scrollToCurrentMatch()
        }
    }

    @objc func showFindAndReplaceBar(_ sender: Any?) {
        presentFindBar(replaceMode: true)
    }

    @objc func performFindNext(_ sender: Any?) {
        if let findBar = findBarViewController, findBar.view.superview != nil {
            findBar.findNext()
        } else {
            presentFindBar(replaceMode: false)
        }
    }

    @objc func performFindPrevious(_ sender: Any?) {
        if let findBar = findBarViewController, findBar.view.superview != nil {
            findBar.findPrevious()
        } else {
            presentFindBar(replaceMode: false)
        }
    }

    @objc func useSelectionForFind(_ sender: Any?) {
        guard let textView = currentTextView() else { return }
        let selectedRange = textView.selectedRange()
        guard selectedRange.length > 0 else { return }

        let selectedText = (textView.string as NSString).substring(with: selectedRange)

        // macOS 標準の Find Pasteboard にコピー
        let findPasteboard = NSPasteboard(name: .find)
        findPasteboard.clearContents()
        findPasteboard.setString(selectedText, forType: .string)

        if let findBar = findBarViewController, findBar.view.superview != nil {
            findBar.setSearchText(selectedText)
        }
    }

    private func presentFindBar(replaceMode: Bool) {
        guard let contentView = window?.contentView, let splitView = self.splitView else { return }

        if findBarViewController == nil {
            findBarViewController = FindBarViewController()
            findBarViewController!.delegate = self
        }

        let findBar = findBarViewController!

        if findBar.view.superview == nil {
            let findBarView = findBar.view
            findBarView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(findBarView)

            // 既存の splitView.top = contentView.top 制約を無効化
            splitViewTopConstraint?.isActive = false

            // Find Bar の制約を設定
            NSLayoutConstraint.activate([
                findBarView.topAnchor.constraint(equalTo: contentView.topAnchor),
                findBarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                findBarView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                splitView.topAnchor.constraint(equalTo: findBarView.bottomAnchor),
            ])

            // テキストストレージの変更を監視
            findBar.observeTextStorage(textDocument?.textStorage)
        }

        findBar.setReplaceMode(replaceMode)

        // 選択テキストがあれば検索フィールドにセット
        if let textView = currentTextView() {
            let selectedRange = textView.selectedRange()
            if selectedRange.length > 0 && selectedRange.length < 200 {
                let selectedText = (textView.string as NSString).substring(with: selectedRange)
                if !selectedText.contains("\n") {
                    findBar.setSearchText(selectedText)
                }
            }
        }

        findBar.focusSearchField()
    }

    private func dismissFindBar() {
        guard let findBarView = findBarViewController?.view,
              findBarView.superview != nil,
              let contentView = window?.contentView,
              let splitView = self.splitView else { return }

        // ハイライトをクリア
        findBarViewController?.clearSearch()

        // Find Bar を削除
        findBarView.removeFromSuperview()

        // 元の制約を復元: splitView.top = contentView.top
        let newTopConstraint = splitView.topAnchor.constraint(equalTo: contentView.topAnchor)
        newTopConstraint.isActive = true
        splitViewTopConstraint = newTopConstraint

        // テキストビューにフォーカスを戻す
        if let textView = currentTextView() {
            window?.makeFirstResponder(textView)
        }
    }
}

// MARK: - FindBarDelegate

extension EditorWindowController: FindBarDelegate {

    func findBarCurrentTextView() -> NSTextView? {
        return currentTextView()
    }

    func findBarTextStorage() -> NSTextStorage? {
        return textDocument?.textStorage
    }

    func findBarAllLayoutManagers() -> [NSLayoutManager] {
        return textDocument?.textStorage.layoutManagers ?? []
    }

    func findBarDidClose() {
        dismissFindBar()
    }
}

