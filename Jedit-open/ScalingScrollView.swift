//
//  ScalingScrollView.swift
//  Jedit-open
//
//  Created by 松本慧 on 2026/01/01.
//

import Cocoa


class ScalingScrollView: NSScrollView {

    // MARK: - Notifications

    static let magnificationDidChangeNotification = Notification.Name("ScalingScrollViewMagnificationDidChange")

    // MARK: - Properties

    private var currentMagnification: CGFloat = 1.0
    private var frameObserver: Any?

    /// フレーム変更時にコンテナサイズを自動調整するかどうか
    /// trueの場合: follows window widthモード（ウィンドウ幅に追従）
    /// falseの場合: follows paper width / fixed width / no wrapモード（EditorWindowControllerが管理）
    var autoAdjustsContainerSizeOnFrameChange: Bool = true

    // MARK: - Split Buttons

    private var splitNoneButton: NSButton?
    private var splitVertButton: NSButton?
    private var splitHoriButton: NSButton?

    /// スプリットボタンのアクションターゲット（通常はEditorWindowController）
    weak var splitButtonTarget: AnyObject?

    // MARK: - Edit Lock Button

    /// 編集ロックボタン（水平スクロールバーの左端、テキストタイプボタンの左に配置）
    private var editLockButton: NSButton?

    // MARK: - Text Type Button

    /// テキストタイプボタン（水平スクロールバーの左端に配置）
    private var textTypeButton: NSButton?

    // MARK: - Scale Button

    /// スケール表示＆メニューボタン（水平スクロールバーのテキストタイプボタンの右に配置）
    private var scaleButton: NSButton?
    private var scaleMenu: ScaleMenu?

    // MARK: - Info Field

    /// 情報フィールド（スケールボタンの右に配置、クリックで行を切り替え）
    private var infoField: NSButton?

    /// 書類情報パネル表示ボタン（情報フィールドの右に配置）
    private var infoPanelButton: NSButton?

    /// 情報フィールドの行名（Location[Size] タブと同じ）
    private static let infoRowNames = [
        "Location",
        "Characters",
        "Visible Chars",
        "Words",
        "Rows",
        "Paragraphs",
        "Pages",
        "Char. Code"
    ]

    /// 現在表示中の行インデックス
    private var infoFieldRow: Int {
        get { UserDefaults.standard.integer(forKey: UserDefaults.Keys.infoFieldRow) }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaults.Keys.infoFieldRow) }
    }

    /// 現在の統計情報（EditorWindowController から更新される）
    private var currentStatistics: DocumentStatistics?

    // MARK: - Initialization

    override func awakeFromNib() {
        super.awakeFromNib()
        setupMagnification()
        setupFrameObserver()
        setupSplitButtons()
        setupEditLockButton()
        setupTextTypeButton()
        setupScaleButton()
        setupInfoField()
        setupInfoPanelButton()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let observer = frameObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Setup

    private func setupMagnification() {
        allowsMagnification = true
        minMagnification = 0.25
        maxMagnification = 4.0
        magnification = 1.0
        currentMagnification = 1.0
    }

    private func setupFrameObserver() {
        // フレーム変更通知を有効にする
        postsFrameChangedNotifications = true

        // フレーム変更時にテキストコンテナサイズを更新
        // ただしライブリサイズ中は処理しない（viewDidEndLiveResizeで処理）
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // ライブリサイズ中は更新しない
            if !self.inLiveResize {
                self.updateTextContainerSize()
            }
        }
    }

    private func setupSplitButtons() {
        // スプリットボタンのサイズ（画像サイズに合わせる: 16x12）
        let buttonWidth: CGFloat = 16.0
        let buttonHeight: CGFloat = 12.0

        // splitNoneButton - 単一ビューに戻す
        let noneButton = NSButton(frame: NSRect(x: 0, y: 0, width: buttonWidth, height: buttonHeight))
        noneButton.title = ""
        noneButton.setButtonType(.momentaryLight)
        noneButton.bezelStyle = .shadowlessSquare
        noneButton.isBordered = false
        noneButton.image = NSImage(named: "splitNone")
        noneButton.imagePosition = .imageOnly
        noneButton.imageScaling = .scaleNone
        noneButton.target = nil
        noneButton.action = #selector(EditorWindowController.collapseViews(_:))
        noneButton.refusesFirstResponder = true
        noneButton.toolTip = NSLocalizedString("Collapse to single view.", comment: "Split button tooltip")
        addSubview(noneButton)
        splitNoneButton = noneButton

        // splitHoriButton - 水平分割
        let horiButton = NSButton(frame: NSRect(x: 0, y: 0, width: buttonWidth, height: buttonHeight))
        horiButton.title = ""
        horiButton.setButtonType(.momentaryLight)
        horiButton.bezelStyle = .shadowlessSquare
        horiButton.isBordered = false
        horiButton.image = NSImage(named: "splitHori")
        horiButton.imagePosition = .imageOnly
        horiButton.imageScaling = .scaleNone
        horiButton.target = nil
        horiButton.action = #selector(EditorWindowController.splitHorizontally(_:))
        horiButton.refusesFirstResponder = true
        horiButton.toolTip = NSLocalizedString("Split view horizontally.", comment: "Split button tooltip")
        addSubview(horiButton)
        splitHoriButton = horiButton

        // splitVertButton - 垂直分割
        let vertButton = NSButton(frame: NSRect(x: 0, y: 0, width: buttonWidth, height: buttonHeight))
        vertButton.title = ""
        vertButton.setButtonType(.momentaryLight)
        vertButton.bezelStyle = .shadowlessSquare
        vertButton.isBordered = false
        vertButton.image = NSImage(named: "splitVert")
        vertButton.imagePosition = .imageOnly
        vertButton.imageScaling = .scaleNone
        vertButton.target = nil
        vertButton.action = #selector(EditorWindowController.splitVertically(_:))
        vertButton.refusesFirstResponder = true
        vertButton.toolTip = NSLocalizedString("Split view vertically.", comment: "Split button tooltip")
        addSubview(vertButton)
        splitVertButton = vertButton
    }

    private func setupEditLockButton() {
        // 編集ロックボタン（水平スクロールバーの左端に配置）
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 20, height: 15))
        button.title = ""
        button.setButtonType(.momentaryLight)
        button.bezelStyle = .smallSquare
        button.isBordered = true
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        // 初期状態: 編集可能 (pencil)
        if let image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Editable") {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
        }
        button.target = nil
        button.action = #selector(EditorWindowController.togglePreventEditing(_:))
        button.refusesFirstResponder = true
        button.toolTip = NSLocalizedString("Toggle editing lock", comment: "Edit lock button tooltip")
        addSubview(button)
        editLockButton = button
    }

    private func setupTextTypeButton() {
        // テキストタイプボタン（水平スクロールバーの左端に配置）
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 36, height: 15))
        button.title = "Plain"
        button.setButtonType(.momentaryLight)
        button.bezelStyle = .smallSquare
        button.isBordered = true
        button.font = NSFont.systemFont(ofSize: 9)
        button.target = nil
        button.action = #selector(EditorWindowController.toggleRichText(_:))
        button.refusesFirstResponder = true
        button.toolTip = NSLocalizedString("Document type", comment: "Text type button tooltip")
        addSubview(button)
        textTypeButton = button
    }

    private func setupScaleButton() {
        // ScaleMenu を作成
        let menu = ScaleMenu(title: "Scale")
        menu.delegate = menu  // awakeFromNib が呼ばれないため明示的に設定
        menu.scaleMenuDelegate = self
        menu.setParentView(self)
        scaleMenu = menu

        // NSButton を作成（クリック時に ScaleMenu をポップアップ表示）
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 38, height: 15))
        button.title = "100%"
        button.setButtonType(.momentaryLight)
        button.bezelStyle = .smallSquare
        button.isBordered = true
        button.font = NSFont.systemFont(ofSize: 9)
        button.target = self
        button.action = #selector(scaleButtonClicked(_:))
        button.refusesFirstResponder = true
        button.toolTip = NSLocalizedString("Document scale", comment: "Scale button tooltip")

        addSubview(button)
        scaleButton = button

        // 初期表示
        updateScaleDisplay()
    }

    @objc private func scaleButtonClicked(_ sender: NSButton) {
        guard let menu = scaleMenu else { return }
        // ボタンの左下からメニューをポップアップ表示
        let location = NSPoint(x: 0, y: sender.bounds.height)
        menu.popUp(positioning: nil, at: location, in: sender)
    }

    private func setupInfoField() {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 150, height: 15))
        button.title = ""
        button.setButtonType(.momentaryLight)
        button.bezelStyle = .smallSquare
        button.isBordered = true
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        button.alignment = .center
        button.target = self
        button.action = #selector(infoFieldClicked(_:))
        button.refusesFirstResponder = true
        button.toolTip = NSLocalizedString("Click to cycle through statistics", comment: "Info field tooltip")

        addSubview(button)
        infoField = button

        // 統計情報変更通知を監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(statisticsDidChange(_:)),
            name: Document.statisticsDidChangeNotification,
            object: nil
        )

        updateInfoField()
    }

    private func setupInfoPanelButton() {
        let size: CGFloat = 15
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: size, height: size))
        button.title = ""
        button.setButtonType(.momentaryLight)
        button.bezelStyle = .smallSquare
        button.isBordered = true
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        if let image = NSImage(systemSymbolName: "info", accessibilityDescription: "Document Info") {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
        }
        button.target = nil
        button.action = #selector(AppDelegate.showDocumentInfo(_:))
        button.refusesFirstResponder = true
        button.toolTip = NSLocalizedString("Show Document Info", comment: "Info panel button tooltip")

        addSubview(button)
        infoPanelButton = button
    }

    @objc private func infoFieldClicked(_ sender: NSButton) {
        let totalRows = Self.infoRowNames.count
        infoFieldRow = (infoFieldRow + 1) % totalRows
        updateInfoField()
    }

    @objc private func statisticsDidChange(_ notification: Notification) {
        // 自分の所属する EditorWindowController の Document からの通知かチェック
        guard let document = notification.object as? Document,
              let windowController = window?.windowController as? EditorWindowController,
              let myDocument = windowController.document as? Document,
              document === myDocument else { return }
        currentStatistics = document.statistics
        updateInfoField()
    }

    /// 情報フィールドの表示を更新
    func updateInfoField() {
        guard let button = infoField else { return }
        let row = infoFieldRow
        let rowName = Self.infoRowNames[row]
        let stats = currentStatistics ?? DocumentStatistics()

        let selText = infoSelectionText(for: row, stats: stats)
        let wholeText = infoWholeText(for: row, stats: stats)

        if wholeText.isEmpty {
            button.title = "\(rowName): \(selText)"
        } else if selText.isEmpty {
            button.title = "\(rowName): \(wholeText)"
        } else {
            button.title = "\(rowName): \(selText) / \(wholeText)"
        }
    }

    /// Selection 列の情報テキスト
    private func infoSelectionText(for row: Int, stats: DocumentStatistics) -> String {
        let f: (Int) -> String = DocumentStatistics.formatted
        let fd: (Double) -> String = DocumentStatistics.formatted
        let hasSelection = (stats.selectionLength > 0)

        switch row {
        case 0: // Location
            if stats.totalCharacters > 0 {
                let percent = Int(round(Double(stats.selectionLocation) / Double(stats.totalCharacters) * 100))
                return "\(percent) %"
            }
            return "0 %"

        case 1: // Characters
            if hasSelection {
                return "\(f(stats.selectionLocation)) [\(f(stats.selectionCharacters))]"
            }
            return f(stats.selectionLocation)

        case 2: // Visible Chars
            if hasSelection {
                return "[\(fd(stats.selectionVisibleChars))]"
            }
            return ""

        case 3: // Words
            if hasSelection {
                return "\(f(stats.locationWords)) [\(f(stats.selectionWords))]"
            }
            return f(stats.locationWords)

        case 4: // Rows
            if !stats.showRows { return "–" }
            if hasSelection {
                return "\(f(stats.locationRows)) [\(f(stats.selectionRows))]"
            }
            return f(stats.locationRows)

        case 5: // Paragraphs
            if hasSelection {
                return "\(f(stats.locationParagraphs)) [\(f(stats.selectionParagraphs))]"
            }
            return f(stats.locationParagraphs)

        case 6: // Pages
            if !stats.showPages { return "–" }
            if hasSelection {
                return "\(f(stats.locationPages)) [\(f(stats.selectionPages))]"
            }
            return f(stats.locationPages)

        case 7: // Char. Code
            return stats.charCode

        default:
            return ""
        }
    }

    /// Whole Doc. 列の情報テキスト
    private func infoWholeText(for row: Int, stats: DocumentStatistics) -> String {
        let f: (Int) -> String = DocumentStatistics.formatted
        let fd: (Double) -> String = DocumentStatistics.formatted

        switch row {
        case 0: // Location
            return "100 %"
        case 1: // Characters
            return f(stats.totalCharacters)
        case 2: // Visible Chars
            return fd(stats.totalVisibleChars)
        case 3: // Words
            return f(stats.totalWords)
        case 4: // Rows
            if !stats.showRows { return "–" }
            return f(stats.totalRows)
        case 5: // Paragraphs
            return f(stats.totalParagraphs)
        case 6: // Pages
            if !stats.showPages { return "–" }
            return f(stats.totalPages)
        case 7: // Char. Code
            return ""
        default:
            return ""
        }
    }

    /// テキストタイプボタンのタイトルを更新
    /// - Parameter typeName: 表示するタイプ名（"Plain", "Rich", "MD", "DOC", "DOCX", "ODT" など）
    func updateTextTypeButton(typeName: String) {
        textTypeButton?.title = typeName
    }

    /// スケール表示を現在の倍率で更新
    func updateScaleDisplay() {
        let percent = Int(round(currentMagnification * 100))
        scaleButton?.title = "\(percent)%"
    }

    /// 編集ロックボタンの表示を更新
    /// - Parameter isEditable: trueの場合は"pencil"（編集可能）、falseの場合は"pencil.slash"（ロック）を表示
    func updateEditLockButton(isEditable: Bool) {
        guard let button = editLockButton else { return }
        let symbolName = isEditable ? "pencil" : "pencil.slash"
        let description = isEditable ? "Editable" : "Read Only"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description) {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
        }
        button.toolTip = isEditable
            ? NSLocalizedString("Prevent Editing", comment: "Edit lock button tooltip - editable")
            : NSLocalizedString("Allow Editing", comment: "Edit lock button tooltip - locked")
    }

    // MARK: - Live Resize

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        // リサイズ完了後にコンテナサイズを再計算
        updateTextContainerSize()
    }

    // MARK: - Tile Override

    override func tile() {
        super.tile()

        guard let verticalScroller = verticalScroller,
              let splitNoneButton = splitNoneButton,
              let splitHoriButton = splitHoriButton,
              let splitVertButton = splitVertButton else {
            return
        }

        var verticalScrollerFrame = verticalScroller.frame
        let buttonHeight = splitNoneButton.frame.height

        // splitNoneButton - 縦スクロールバーの最上部
        var buttonFrame = verticalScrollerFrame
        buttonFrame.size.height = buttonHeight
        buttonFrame.size.width = verticalScrollerFrame.width

        verticalScrollerFrame.origin.y += buttonHeight
        verticalScrollerFrame.size.height -= buttonHeight
        verticalScroller.frame = verticalScrollerFrame
        splitNoneButton.frame = buttonFrame

        // splitHoriButton - splitNoneButtonの下
        buttonFrame = verticalScrollerFrame
        buttonFrame.size.height = buttonHeight
        buttonFrame.size.width = verticalScrollerFrame.width

        verticalScrollerFrame.origin.y += buttonHeight
        verticalScrollerFrame.size.height -= buttonHeight
        verticalScroller.frame = verticalScrollerFrame
        splitHoriButton.frame = buttonFrame

        // splitVertButton - splitHoriButtonの下
        buttonFrame = verticalScrollerFrame
        buttonFrame.size.height = buttonHeight
        buttonFrame.size.width = verticalScrollerFrame.width

        verticalScrollerFrame.origin.y += buttonHeight
        verticalScrollerFrame.size.height -= buttonHeight
        verticalScroller.frame = verticalScrollerFrame
        splitVertButton.frame = buttonFrame

        // 編集ロックボタンとテキストタイプボタン - 水平スクロールバーの左端に配置
        if let horizontalScroller = horizontalScroller {
            var horizontalScrollerFrame = horizontalScroller.frame

            // 編集ロックボタン - 最左端
            if let editLockButton = editLockButton {
                let editLockButtonWidth = editLockButton.frame.width

                var editLockButtonFrame = horizontalScrollerFrame
                editLockButtonFrame.size.width = editLockButtonWidth
                editLockButtonFrame.size.height = horizontalScrollerFrame.height
                editLockButton.frame = editLockButtonFrame

                horizontalScrollerFrame.origin.x += editLockButtonWidth
                horizontalScrollerFrame.size.width -= editLockButtonWidth
            }

            // テキストタイプボタン - 編集ロックボタンの右
            if let textTypeButton = textTypeButton {
                let textTypeButtonWidth = textTypeButton.frame.width

                var textTypeButtonFrame = horizontalScrollerFrame
                textTypeButtonFrame.size.width = textTypeButtonWidth
                textTypeButtonFrame.size.height = horizontalScrollerFrame.height
                textTypeButton.frame = textTypeButtonFrame

                horizontalScrollerFrame.origin.x += textTypeButtonWidth
                horizontalScrollerFrame.size.width -= textTypeButtonWidth
            }

            // スケールボタン - テキストタイプボタンの右
            if let scaleButton = scaleButton {
                let scaleButtonWidth = scaleButton.frame.width

                var scaleButtonFrame = horizontalScrollerFrame
                scaleButtonFrame.size.width = scaleButtonWidth
                scaleButtonFrame.size.height = horizontalScrollerFrame.height
                scaleButton.frame = scaleButtonFrame

                horizontalScrollerFrame.origin.x += scaleButtonWidth
                horizontalScrollerFrame.size.width -= scaleButtonWidth
            }

            // 情報フィールド - スケールボタンの右
            if let infoField = infoField {
                let infoFieldWidth = infoField.frame.width

                var infoFieldFrame = horizontalScrollerFrame
                infoFieldFrame.size.width = infoFieldWidth
                infoFieldFrame.size.height = horizontalScrollerFrame.height
                infoField.frame = infoFieldFrame

                horizontalScrollerFrame.origin.x += infoFieldWidth
                horizontalScrollerFrame.size.width -= infoFieldWidth
            }

            // 書類情報パネルボタン - 情報フィールドの右
            if let infoPanelButton = infoPanelButton {
                let buttonWidth = infoPanelButton.frame.width

                var buttonFrame = horizontalScrollerFrame
                buttonFrame.size.width = buttonWidth
                buttonFrame.size.height = horizontalScrollerFrame.height
                infoPanelButton.frame = buttonFrame

                horizontalScrollerFrame.origin.x += buttonWidth
                horizontalScrollerFrame.size.width -= buttonWidth
            }

            // 水平スクロールバーのフレームを更新
            horizontalScroller.frame = horizontalScrollerFrame
        }
    }

    // MARK: - Appearance Change

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // アピアランス変更時にスプリットボタンの画像を再設定
        updateSplitButtonImages()
    }

    private func updateSplitButtonImages() {
        // NSImageはアセットカタログのダークモード対応画像を自動で取得するが、
        // 既存のボタンの画像は更新されないため、明示的に再設定する
        splitNoneButton?.image = NSImage(named: "splitNone")
        splitHoriButton?.image = NSImage(named: "splitHori")
        splitVertButton?.image = NSImage(named: "splitVert")
    }

    // MARK: - Zoom Methods

    func zoomIn() {
        let newMagnification = min(currentMagnification * 1.2, maxMagnification)
        setMagnification(newMagnification, centeredAt: NSPoint(x: bounds.midX, y: bounds.midY))
        currentMagnification = newMagnification
        updateTextContainerSize()
        updateScaleDisplay()
        postMagnificationNotification()
    }

    func zoomOut() {
        let newMagnification = max(currentMagnification / 1.2, minMagnification)
        setMagnification(newMagnification, centeredAt: NSPoint(x: bounds.midX, y: bounds.midY))
        currentMagnification = newMagnification
        updateTextContainerSize()
        updateScaleDisplay()
        postMagnificationNotification()
    }

    func resetZoom() {
        setMagnification(1.0, centeredAt: NSPoint(x: bounds.midX, y: bounds.midY))
        currentMagnification = 1.0
        updateTextContainerSize()
        updateScaleDisplay()
        postMagnificationNotification()
    }

    func setZoomLevel(_ level: CGFloat) {
        let clampedLevel = max(minMagnification, min(level, maxMagnification))
        setMagnification(clampedLevel, centeredAt: NSPoint(x: bounds.midX, y: bounds.midY))
        currentMagnification = clampedLevel
        updateTextContainerSize()
        updateScaleDisplay()
        postMagnificationNotification()
    }

    private func postMagnificationNotification() {
        NotificationCenter.default.post(
            name: ScalingScrollView.magnificationDidChangeNotification,
            object: self,
            userInfo: ["magnification": currentMagnification]
        )
    }

    // MARK: - Gesture Handling

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        // ピンチジェスチャー終了時のみ処理
        if event.phase == .ended || event.phase == .cancelled {
            currentMagnification = magnification
            updateTextContainerSize()
            updateScaleDisplay()
            postMagnificationNotification()
        } else if event.phase == .changed {
            // ジェスチャー中も通知を送る（行番号表示更新のため）
            currentMagnification = magnification
            updateScaleDisplay()
            postMagnificationNotification()
        }
    }

    // MARK: - Helper Methods

    private func updateTextContainerSize() {
        // autoAdjustsContainerSizeOnFrameChangeがfalseの場合は、
        // EditorWindowControllerがコンテナサイズを管理するため、ここでは何もしない
        guard autoAdjustsContainerSizeOnFrameChange else { return }

        guard let textView = documentView as? NSTextView,
              let textContainer = textView.textContainer else {
            return
        }

        let isVertical = textView.layoutOrientation == .vertical
        let containerInset = textView.textContainerInset
        let padding = textContainer.lineFragmentPadding

        // macOS 26: ルーラー表示時はシステムがスクロールバー幅を追加するため、その分を補正
        let rulerCompensation: CGFloat
        if rulersVisible {
            rulerCompensation = NSScroller.scrollerWidth(for: .regular, scrollerStyle: scrollerStyle)
        } else {
            rulerCompensation = 0
        }

        if isVertical {
            // 縦書き時: 行の長さを調整
            // 縦書きでは containerSize.width が行の長さ（画面上の高さ方向）を表す
            // 水平スクロールは文章の進行に必要なので、textViewの幅は制限しない
            var availableHeight = contentView.frame.height
            // macOS 26: ルーラー表示時はシステムがスクロールバー幅を追加するため、その分を補正
            availableHeight -= rulerCompensation
            availableHeight = availableHeight / magnification
            let expectedContainerWidth = availableHeight - (containerInset.height * 2) - (padding * 2)

            if expectedContainerWidth > 0 {
                textContainer.containerSize = NSSize(width: expectedContainerWidth, height: CGFloat.greatestFiniteMagnitude)
                textView.setFrameSize(NSSize(width: textView.frame.width, height: availableHeight))
            }
        } else {
            // 横書き時: 幅を調整
            var availableWidth = contentView.frame.width
            // ルーラー表示時の補正を適用
            availableWidth -= rulerCompensation
            availableWidth = availableWidth / magnification
            let expectedContainerWidth = availableWidth - (containerInset.width * 2) - (padding * 2)

            if expectedContainerWidth > 0 {
                textContainer.containerSize = NSSize(width: expectedContainerWidth, height: CGFloat.greatestFiniteMagnitude)
                textView.setFrameSize(NSSize(width: availableWidth, height: textView.frame.height))
            }
        }
    }
}

// MARK: - ScaleMenuDelegate

extension ScalingScrollView: ScaleMenuDelegate {
    func scaleMenuDidSelectScale(_ scale: Int) {
        setZoomLevel(CGFloat(scale) / 100.0)
    }
}

