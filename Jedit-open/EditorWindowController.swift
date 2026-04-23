//
//  EditorWindowController.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/26.
//

//
//  This file is part of Jedit-open.
//  Copyright (C) 2025 Satoshi Matsumoto
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
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

    static let findToolbarItemIdentifier = NSToolbarItem.Identifier("FindItem")
    static let encodingToolbarItemIdentifier = NSToolbarItem.Identifier("EncodingItem")
    static let lineEndingToolbarItemIdentifier = NSToolbarItem.Identifier("LineEndingItem")
    static let writingProgressToolbarItemIdentifier = NSToolbarItem.Identifier("WritingProgressItem")
    static let bookmarkToolbarItemIdentifier = NSToolbarItem.Identifier("BookmarkItem")

    // MARK: - IBOutlets

    @IBOutlet weak var splitView: NSSplitView!
    @IBOutlet weak var scrollView2: ScalingScrollView!
    @IBOutlet weak var scrollView1: ScalingScrollView!

    // MARK: - Toolbar

    var encodingToolbarItem: NSToolbarItem?
    var lineEndingToolbarItem: NSToolbarItem?
    var writingProgressToolbarItem: NSToolbarItem?
    lazy var writingGoalPanel = WritingGoalPanel()
    /// ツールバー非表示時にインスタンスを保持する（window.toolbar = nil にしても参照を保持）
    var cachedToolbar: NSToolbar?

    // MARK: - Image Resize

    var imageResizeController: ImageResizeController?

    // MARK: - Find Bar

    var findBarViewController: FindBarViewController?
    var splitViewTopConstraint: NSLayoutConstraint?

    /// 現在の検索結果の範囲配列を返す（ブックマークパネルからの参照用）
    var currentFindResultRanges: [NSRange] {
        return findBarViewController?.currentResult.ranges ?? []
    }

    // MARK: - Properties

    var textDocument: Document? {
        return document as? Document
    }

    var splitMode: SplitMode = .none
    var isSettingUpSplit: Bool = false  // setSplitMode リエントランシー防止

    // 表示モード
    var displayMode: DisplayMode = .continuous
    var lineNumberMode: LineNumberMode = .none
    var isInspectorBarVisible: Bool = false  // Inspector Barの表示状態
    private var isInspectorBarInitialized: Bool = false  // Inspector Bar初期化済みフラグ
    var isRulerVisible: Bool = false  // ルーラーの表示状態
    var rulerType: NewDocData.ViewData.RulerType = .character  // ルーラーの単位タイプ
    var invisibleCharacterOptions: InvisibleCharacterOptions = .none  // 不可視文字の表示オプション
    var isVerticalLayout: Bool = false  // 縦書きレイアウト
    var lineWrapMode: LineWrapMode = .windowWidth  // 行折り返しモード（Continuousモード用）
    var fixedWrapWidthInChars: Int = 80  // 固定幅（fixedWidthモード用、文字数）

    // 行番号ビュー
    var lineNumberView1: LineNumberView?
    var lineNumberView2: LineNumberView?
    var lineNumberWidthConstraint1: NSLayoutConstraint?
    var lineNumberWidthConstraint2: NSLayoutConstraint?

    // ページネーション関連
    var layoutManager1: NSLayoutManager?
    var layoutManager2: NSLayoutManager?
    var textContainers1: [NSTextContainer] = []
    var textViews1: [NSTextView] = []
    var textContainers2: [NSTextContainer] = []
    var textViews2: [NSTextView] = []
    var pagesView1: MultiplePageView?
    var pagesView2: MultiplePageView?

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

    var pageTopMargin: CGFloat {
        textDocument?.printInfo.topMargin ?? 72.0
    }

    private var pageBottomMargin: CGFloat {
        textDocument?.printInfo.bottomMargin ?? 72.0
    }

    var pageLeftMargin: CGFloat {
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
    func updateEditLockButtons() {
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

        if displayMode == .page {
            // ページモードを再設定（用紙サイズ、向き、マージンが変更された可能性がある）
            guard let textStorage = textDocument?.textStorage else { return }
            setupPageMode(with: textStorage)
        } else if displayMode == .continuous && lineWrapMode == .paperWidth {
            // 連続モードで「用紙幅に合わせる」の場合、用紙サイズの変更を反映
            applyLineWrapMode(updatePresetData: false)
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
        setToolbarVisible(viewData.showToolBar, updatePreset: false)

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

        // スケールと選択範囲の復元（レイアウト完了後に実行）
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // スケールを再適用（setupTextViewsやウィンドウリサイズでリセットされる場合があるため）
            if viewData.scale != 1.0 {
                self.scrollView1?.setZoomLevel(viewData.scale)
            }
            self.restoreSelectionAndScrollPosition()
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
    func getCurrentSelectedRange() -> NSRange? {
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
    func restoreSelectionAndScrollToVisible(_ range: NSRange, delay: TimeInterval = 0.1) {
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
    func applyFontToTextViews(_ font: NSFont) {
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
    func applyTabWidth(_ tabWidthPoints: CGFloat) {
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
    func applyParagraphStyle(
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
    func applyColorsToTextViews(_ colors: NewDocData.FontAndColorsData.Colors) {
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

        guard let lineNumberView = notification.object as? LineNumberView else { return }

        // 制約更新前にスクロール位置を保存
        // Auto Layout による scroll view リサイズが NSTextView の内部的な
        // scrollRangeToVisible を誘発し、カーソルがセンターにスクロールされる問題を防止
        let savedScrollPosition1 = scrollView1?.contentView.bounds.origin
        let savedScrollPosition2 = scrollView2?.contentView.bounds.origin

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

        // レイアウト後にスクロール位置を復元
        // constraint 変更は次のレイアウトパスで反映されるため、
        // layoutSubtreeIfNeeded で即座にレイアウトを確定させてからスクロール位置を戻す
        window?.contentView?.layoutSubtreeIfNeeded()

        if let savedOrigin = savedScrollPosition1, let clipView = scrollView1?.contentView {
            clipView.setBoundsOrigin(savedOrigin)
        }
        if let savedOrigin = savedScrollPosition2, let clipView = scrollView2?.contentView {
            clipView.setBoundsOrigin(savedOrigin)
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
    func setupLineNumberView(for scrollView: NSScrollView, lineNumberViewRef: inout LineNumberView?, constraintRef: inout NSLayoutConstraint?) {
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
    func createAllPages(count: Int, for layoutManager: NSLayoutManager, in scrollView: NSScrollView, target: ScrollViewTarget) {
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
    func updatePresetDataScale() {
        if let scale = scrollView1?.magnification {
            textDocument?.presetData?.view.scale = scale
            markDocumentAsEdited()
        }
    }

    // MARK: - Split View Actions — see EditorWindowController+SplitView.swift
    // MARK: - Display Mode Actions — see EditorWindowController+DisplayMode.swift
    // MARK: - Line Wrap Mode Actions — see EditorWindowController+DisplayMode.swift
    // MARK: - Word Wrapping Actions — see EditorWindowController+DisplayMode.swift


    // MARK: - Line Number Actions — see EditorWindowController+ViewConfig.swift
    // MARK: - Ruler Actions — see EditorWindowController+ViewConfig.swift
    // MARK: - Caret Position Indicator — see EditorWindowController+ViewConfig.swift
    // MARK: - Invisible Character Actions — see EditorWindowController+ViewConfig.swift
    // MARK: - Plain/Rich Text Toggle — see EditorWindowController+ViewConfig.swift
    // MARK: - Layout Orientation Actions — see EditorWindowController+ViewConfig.swift

    // MARK: - Toolbar Customization — see EditorWindowController+Toolbar.swift
    // MARK: - Inspector Bar Actions — see EditorWindowController+Toolbar.swift

    // MARK: - Pagination Methods — see EditorWindowController+DisplayMode.swift

    // ページフレーム更新が必要かどうか
    var needsPageFrameUpdate: Bool = false

    // MARK: - Text View Size Management

    func updateTextViewSize(for scrollView: NSScrollView) {
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

        // 注: 以前「macOS 26 ルーラー補正」として scrollerWidth を追加減算していたが、
        // contentView.frame は既にスクロールバー/ルーラー分が除外済みの実幅を返すため、
        // 二重減算になり行末とウィンドウ枠の間に余分な隙間が出ていた。削除済み。

        // ズーム時の補正: availableWidth/HeightはcontentViewの座標系（表示座標）だが、
        // テキストビューはmagnification前の座標系で動作するため、magnificationで割って変換する。
        // 全ての折り返しモードで適用する（以前 windowWidth は ScalingScrollView に任せる前提で
        // 除外していたが、縦書き windowWidth では ScalingScrollView 側が走らないため、
        // この updateTextViewSize が text 座標に正規化する必要がある）。
        if let scalingScrollView = scrollView as? ScalingScrollView,
           scalingScrollView.magnification != 1.0 {
            let mag = scalingScrollView.magnification
            availableWidth = availableWidth / mag
            availableHeight = availableHeight / mag
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
                // ウィンドウ高さを1行の高さとする。
                // containerInset 分だけ引けば、lineFragmentPadding 分は
                // コンテナ内部で処理されるため、ウィンドウ枠ぎりぎりまで行が伸びる。
                lineHeight = availableHeight - (containerInset.height * 2)
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
            // ルーラー表示時のスクロールバー幅補正は availableHeight に既に適用済み
            let textViewHeight = availableHeight
            // maxSizeは幅・高さとも無制限にして、テキストが水平方向に自由に拡張できるようにする
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.minSize = NSSize(width: 0, height: textViewHeight)

            // テキストビューの現在の幅を保持しつつ、高さだけ更新
            // レイアウトを強制的に更新してからフレームサイズを設定
            textView.layoutManager?.ensureLayout(for: textContainer)
            let currentWidth = max(textView.frame.width, availableWidth)
            if lineWrapMode == .windowWidth {
                // windowWidthモード: テキストビューの高さをウインドウに合わせる（垂直スクロール不要）
                textView.setFrameSize(NSSize(width: currentWidth, height: textViewHeight))
            } else {
                // paperWidth/fixedWidth/noWrap: コンテンツ高さがウインドウより大きい場合は
                // テキストビューをコンテンツに合わせて拡張し、垂直スクロールを可能にする
                let contentHeight = lineHeight + (containerInset.height * 2)
                textView.setFrameSize(NSSize(width: currentWidth, height: max(textViewHeight, contentHeight)))
            }

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
                // ウィンドウ幅に収める。
                // containerInset 分だけ引けば、lineFragmentPadding 分は
                // コンテナ内部で処理されるため、ウィンドウ枠ぎりぎりまで行が伸びる。
                lineWidth = availableWidth - (containerInset.width * 2)
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
            // ルーラー表示時のスクロールバー幅補正は availableWidth に既に適用済み
            let textViewWidth: CGFloat
            if lineWrapMode == .windowWidth {
                // windowWidthモードではテキストビューの幅をcontentViewの幅に正確に合わせてスクロールを防ぐ
                textViewWidth = availableWidth
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

    // MARK: - NSSplitViewDelegate — see EditorWindowController+SplitView.swift
    // MARK: - Menu Validation

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleToolbarVisibility(_:)) {
            menuItem.title = isToolbarVisible ? "Hide Toolbar".localized : "Show Toolbar".localized
        }
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
            menuItem.title = invisibleCharacterOptions == .none ? "Show All".localized : "Hide All".localized
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
        // ページ表示モードでは実際の動作は常に「用紙幅に合わせる」固定なので、
        // 他の折り返しモードは選択不可にする（見かけ上選択できても動作しないのを防ぐ）。
        if menuItem.action == #selector(setLineWrapPaperWidth(_:)) {
            if displayMode == .page {
                menuItem.state = .on
            } else {
                menuItem.state = lineWrapMode == .paperWidth ? .on : .off
            }
        }
        if menuItem.action == #selector(setLineWrapWindowWidth(_:)) {
            if displayMode == .page {
                menuItem.state = .off
                return false
            }
            menuItem.state = lineWrapMode == .windowWidth ? .on : .off
        }
        if menuItem.action == #selector(setLineWrapNoWrap(_:)) {
            if displayMode == .page {
                menuItem.state = .off
                return false
            }
            menuItem.state = lineWrapMode == .noWrap ? .on : .off
        }
        if menuItem.action == #selector(setLineWrapFixedWidth(_:)) {
            // メニュータイトルに現在の文字数を表示
            menuItem.title = String(format: "Fixed Width (%dchars.)...".localized, fixedWrapWidthInChars)
            if displayMode == .page {
                menuItem.state = .off
                return false
            }
            menuItem.state = lineWrapMode == .fixedWidth ? .on : .off
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
    var isUpdatingPages: Bool = false
    var isAddingPage: Bool = false
    private var previousTextLength1: Int = 0
    private var previousTextLength2: Int = 0
    // レイアウト方向切り替え中フラグ（ページ追加を抑制）
    var isChangingLayoutOrientation: Bool = false
    // 遅延削除中フラグ
    private var isDelayedRemoveScheduled: Bool = false
    // レイアウトチェックのワークアイテム（デバウンス用）
    private var layoutCheckWorkItem: DispatchWorkItem?
    // レイアウト完了後のクールダウン期間終了時刻
    var layoutCooldownUntil: Date?
    // 前回 addPage 時点でレイアウト済みだった文字位置
    // （進捗せずに addPage が繰り返されるのを検出して無限ループを防ぐ安全網）
    var lastAddPageLayoutedChar: Int = -1
    // addPage が非同期スケジュール済みかどうか（多重登録防止）
    var isAddPageScheduled: Bool = false

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
                            lastAddPageLayoutedChar = -1
                            return
                        }

                        // 前回 addPage 時から進捗しているかを確認（無限ループ防止の安全網）
                        if lastAddPageLayoutedChar >= lastLayoutedChar {
                            layoutCooldownUntil = Date().addingTimeInterval(0.5)
                            lastAddPageLayoutedChar = -1
                            return
                        }
                        lastAddPageLayoutedChar = lastLayoutedChar

                        // addPage をデリゲート内で同期的に呼ぶと、addPage 中のプロパティ設定
                        // （isSelectable 等）が setNeedsDisplayInRect 経由で fill-holes を
                        // 再帰的に走らせ、NSLayoutManager の外側ループが進捗ゼロで
                        // 回り続けてフリーズする。次のランループに defer することで断ち切る。
                        if !isAddPageScheduled {
                            isAddPageScheduled = true
                            DispatchQueue.main.async { [weak self] in
                                guard let self = self else { return }
                                self.isAddPageScheduled = false
                                self.addPage(to: layoutManager, in: scrollView, for: target)
                            }
                        }
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
            // レイアウト完了時は進捗トラッカーをリセット
            lastAddPageLayoutedChar = -1
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

            // 全テキストビューのフレームとレイアウト方向の更新はレイアウトパス外で行う。
            // setLayoutOrientation はコンテナのレイアウトを無効化するため、
            // デリゲート内で同期的に呼ぶと fill-holes の再入ループを誘発する。
            DispatchQueue.main.async { [weak self] in
                self?.updateAllTextViewFrames(for: target)
            }

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
    func updateAllTextViewFrames(for target: ScrollViewTarget) {
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

    // MARK: - Text Editing Preferences through Print Configuration — see EditorWindowController+TextPrefs.swift

    // Lazy panel properties kept in class body (required for stored property semantics)
    lazy var tabWidthPanel = TabWidthPanel()
    lazy var lineSpacingPanel = LineSpacingPanel()
    lazy var wrappedLineIndentPanel = WrappedLineIndentPanel()
    lazy var documentColorsPanel: DocumentColorsPanel? = DocumentColorsPanel.loadFromNib()
    lazy var pageLayoutPanel: PageLayoutPanel? = PageLayoutPanel.loadFromNib()

    // MARK: - Toolbar Encoding Item — see EditorWindowController+Toolbar.swift
    // MARK: - NSToolbarDelegate — see EditorWindowController+Toolbar.swift

    // MARK: - Document Statistics Calculation — see EditorWindowController+Statistics.swift
    // MARK: - Statistics Counting Helpers — see EditorWindowController+Statistics.swift

    /// 統計計算をスケジュールするための DispatchWorkItem（coalescing 用）
    var statisticsWorkItem: DispatchWorkItem?

    // MARK: - Find Bar — see EditorWindowController+FindBar.swift
}

// MARK: - FindBarDelegate — see EditorWindowController+FindBar.swift
