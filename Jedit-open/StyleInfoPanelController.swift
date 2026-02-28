// StyleInfoPanelController.swift
// Jedit-open
//
// スタイル情報パネル — 選択範囲のテキスト属性を表示・編集するフローティングパネル

import Cocoa

/// 現在の色を表示する矩形ビュー（nil の場合は白背景に赤いスラッシュ）
private class ColorIndicatorView: NSView {
    var color: NSColor? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds

        if let color = color {
            color.setFill()
            NSBezierPath.fill(rect)
        } else {
            // Not Assigned: テキスト背景色 + 赤スラッシュ
            NSColor.textBackgroundColor.setFill()
            NSBezierPath.fill(rect)
            NSColor.systemRed.setStroke()
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: rect.minX + 2, y: rect.maxY - 2))
            slash.line(to: NSPoint(x: rect.maxX - 2, y: rect.minY + 2))
            slash.lineWidth = 1.5
            slash.stroke()
        }

        // 枠線
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
        border.lineWidth = 1
        border.stroke()
    }
}

class StyleInfoPanelController: NSObject {

    // MARK: - Singleton

    static let shared = StyleInfoPanelController()

    // MARK: - Panel

    private var panel: NSPanel!
    private var isLoaded = false

    /// UI 更新中フラグ（フィードバックループ防止）
    private var isUpdatingUI = false

    /// カラーパネルで編集中の対象属性
    private enum ColorEditTarget {
        case foreground
        case background
        case underlineColor
        case strikethroughColor
        case strokeColor  // Other Color… 用
    }
    private var editingColorTarget: ColorEditTarget?

    /// カラーパネルのセットアップ中フラグ（panel.color 設定時の通知を無視するため）
    private var isSettingUpColorPanel = false

    // MARK: - Font Section
    private var fontFamilyField: NSTextField!
    private var fontStyleField: NSTextField!
    private var fontSizeField: NSTextField!
    private var fontSizeStepper: NSStepper!

    // MARK: - Color Section
    private var foreColorIndicator: ColorIndicatorView!
    private var foreColorPopup: NSPopUpButton!
    private var backColorIndicator: ColorIndicatorView!
    private var backColorPopup: NSPopUpButton!

    // MARK: - Underline Section
    private var underlineStylePopup: NSPopUpButton!
    private var underlinePatternPopup: NSPopUpButton!
    private var underlineColorIndicator: ColorIndicatorView!
    private var underlineColorPopup: NSPopUpButton!

    // MARK: - Strikethrough Section
    private var strikethroughStylePopup: NSPopUpButton!
    private var strikethroughPatternPopup: NSPopUpButton!
    private var strikethroughColorIndicator: ColorIndicatorView!
    private var strikethroughColorPopup: NSPopUpButton!

    // MARK: - Outline Section
    private var strokeWidthField: NSTextField!
    private var strokeWidthStepper: NSStepper!
    private var strokeColorIndicator: ColorIndicatorView!
    private var strokeColorPopup: NSPopUpButton!

    // MARK: - Baseline & Spacing Section
    private var baselineOffsetField: NSTextField!
    private var baselineOffsetStepper: NSStepper!
    private var kernField: NSTextField!
    private var kernStepper: NSStepper!
    private var ligaturePopup: NSPopUpButton!

    // MARK: - Alignment Section
    private var alignmentSegmented: NSSegmentedControl!

    // MARK: - Line Height Section
    private var lineHeightMultipleField: NSTextField!
    private var lineHeightMultipleStepper: NSStepper!
    private var lineHeightMinField: NSTextField!
    private var lineHeightMinStepper: NSStepper!
    private var lineHeightMaxField: NSTextField!
    private var lineHeightMaxStepper: NSStepper!

    // MARK: - Indent Section
    private var firstLineHeadIndentField: NSTextField!
    private var firstLineHeadIndentStepper: NSStepper!
    private var headIndentField: NSTextField!
    private var headIndentStepper: NSStepper!
    private var tailIndentField: NSTextField!
    private var tailIndentStepper: NSStepper!

    // MARK: - Paragraph Spacing Section
    private var lineSpacingField: NSTextField!
    private var lineSpacingStepper: NSStepper!
    private var paragraphSpacingBeforeField: NSTextField!
    private var paragraphSpacingBeforeStepper: NSStepper!
    private var paragraphSpacingAfterField: NSTextField!
    private var paragraphSpacingAfterStepper: NSStepper!

    // MARK: - Constants

    private static let mixedPlaceholder = "Mixed"
    private static let labelWidth: CGFloat = 80
    private static let fieldWidth: CGFloat = 55
    private static let stepperWidth: CGFloat = 19

    // MARK: - Init

    private override init() {
        super.init()
    }

    // MARK: - Public API

    var isPanelVisible: Bool {
        return isLoaded && (panel?.isVisible ?? false)
    }

    /// カラーパネルが当パネルにより管理されているかどうか
    /// （JeditTextView.changeColor から呼ばれ、テキスト色の誤変更を防止する）
    func isManagingColorPanel() -> Bool {
        return editingColorTarget != nil || isSettingUpColorPanel
    }

    func showPanel() {
        loadPanelIfNeeded()
        guard let panel = panel else { return }

        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            updateFromSelection()
            panel.orderFront(nil)
        }
    }

    /// 現在のドキュメント用にパネルを更新
    func updateForCurrentDocument() {
        guard isPanelVisible else { return }
        updateFromSelection()
    }

    /// ウィンドウ閉じ後にパネルを更新
    func updateAfterWindowClose() {
        guard isPanelVisible else { return }
        // 次のイベントループで更新（ウィンドウが完全に閉じた後）
        DispatchQueue.main.async { [weak self] in
            self?.updateFromSelection()
        }
    }

    // MARK: - Panel Setup

    private func loadPanelIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true

        setupPanel()
        setupObservers()

        // ウィンドウ位置の復元
        panel.setFrameAutosaveName("StyleInfoPanel")
    }

    private func setupPanel() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 560),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: true
        )
        panel.title = "Style Info"
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.minSize = NSSize(width: 380, height: 300)
        panel.maxSize = NSSize(width: 380, height: 2000)
        panel.backgroundColor = NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(white: 0.18, alpha: 1.0)
                : NSColor(white: 0.95, alpha: 1.0)
        })

        // メインスタックビュー
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 6
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)

        // セクション追加
        addFontSection(to: mainStack)
        addColorSection(to: mainStack)
        addUnderlineSection(to: mainStack)
        addStrikethroughSection(to: mainStack)
        addOutlineSection(to: mainStack)
        addBaselineKerningSection(to: mainStack)
        addAlignmentSection(to: mainStack)
        addLineHeightSection(to: mainStack)
        addIndentSection(to: mainStack)
        addParagraphSpacingSection(to: mainStack)

        // 下部のスペーサー
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        mainStack.addArrangedSubview(spacer)

        // スクロールビューに格納
        let scrollView = NSScrollView()
        scrollView.documentView = mainStack
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        panel.contentView = scrollView

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            mainStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
    }

    // MARK: - Section Builders

    private func addFontSection(to stack: NSStackView) {
        stack.addArrangedSubview(createSectionHeader("Font"))

        // Family
        let familyRow = createLabeledRow("Family:")
        fontFamilyField = NSTextField(labelWithString: "")
        fontFamilyField.lineBreakMode = .byTruncatingTail
        fontFamilyField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        familyRow.addArrangedSubview(fontFamilyField)

        let fontsButton = NSButton(title: "Change…", target: self, action: #selector(showFontPanel(_:)))
        fontsButton.controlSize = .small
        fontsButton.bezelStyle = .rounded
        fontsButton.setContentHuggingPriority(.required, for: .horizontal)
        familyRow.addArrangedSubview(fontsButton)
        stack.addArrangedSubview(familyRow)

        // Style (weight + italic)
        let styleRow = createLabeledRow("Style:")
        fontStyleField = NSTextField(labelWithString: "")
        fontStyleField.lineBreakMode = .byTruncatingTail
        fontStyleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        styleRow.addArrangedSubview(fontStyleField)
        stack.addArrangedSubview(styleRow)

        // Size
        let sizeRow = createLabeledRow("Size:")
        fontSizeField = createNumberField(action: #selector(fontSizeFieldChanged(_:)))
        fontSizeStepper = createStepper(minValue: 1, maxValue: 999, increment: 1, action: #selector(fontSizeStepperChanged(_:)))
        sizeRow.addArrangedSubview(fontSizeField)
        sizeRow.addArrangedSubview(fontSizeStepper)
        sizeRow.addArrangedSubview(NSTextField(labelWithString: "pt."))
        stack.addArrangedSubview(sizeRow)

        stack.addArrangedSubview(createSeparator())
    }

    private func addColorSection(to stack: NSStackView) {
        stack.addArrangedSubview(createSectionHeader("Colors"))

        // 文字色: インジケータ + ポップアップ
        let foreRow = createLabeledRow("Foreground:")
        foreColorIndicator = createColorIndicator(color: .textColor)
        foreRow.addArrangedSubview(foreColorIndicator)
        foreColorPopup = createForeColorPopup()
        foreRow.addArrangedSubview(foreColorPopup)
        stack.addArrangedSubview(foreRow)

        // 背景色: インジケータ + ポップアップ
        let backRow = createLabeledRow("Background:")
        backColorIndicator = createColorIndicator(color: .clear)
        backRow.addArrangedSubview(backColorIndicator)
        backColorPopup = createBackColorPopup()
        backRow.addArrangedSubview(backColorPopup)
        stack.addArrangedSubview(backRow)

        stack.addArrangedSubview(createSeparator())
    }

    /// 前景色プリセットカラー一覧
    private static let foreColorEntries: [(String, NSColor)] = [
        ("Text Color",  .textColor),
        ("Red",         .systemRed),
        ("Orange",      .systemOrange),
        ("Yellow",      .systemYellow),
        ("Green",       .systemGreen),
        ("Mint",        .systemMint),
        ("Teal",        .systemTeal),
        ("Cyan",        .systemCyan),
        ("Blue",        .systemBlue),
        ("Indigo",      .systemIndigo),
        ("Purple",      .systemPurple),
        ("Pink",        .systemPink),
        ("Brown",       .systemBrown),
        ("Gray",        .systemGray),
    ]

    /// 背景色プリセットカラー一覧（nil = 色なし/Clear）
    private static let backColorEntries: [(String, NSColor?)] = [
        ("Clear",       nil),
        ("Salmon",      NSColor(calibratedRed: 1, green: 0.75, blue: 0.75, alpha: 1)),
        ("Carnation",   NSColor(calibratedRed: 1, green: 0.75, blue: 1, alpha: 1)),
        ("Lavender",    NSColor(calibratedRed: 0.75, green: 0.75, blue: 1, alpha: 1)),
        ("Ice",         NSColor(calibratedRed: 0.75, green: 1, blue: 1, alpha: 1)),
        ("Flora",       NSColor(calibratedRed: 0.75, green: 1, blue: 0.75, alpha: 1)),
        ("Banana",      NSColor(calibratedRed: 1, green: 1, blue: 0.75, alpha: 1)),
    ]

    /// プルダウン色ポップアップの共通セットアップ（pullsDown + 空タイトル + 固定幅）
    private func setupColorPopupAppearance(_ popup: NSPopUpButton) {
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(equalToConstant: 18).isActive = true
    }

    private func createForeColorPopup() -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: true)
        popup.controlSize = .small
        popup.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        // 先頭: 閉じた状態で表示されるタイトル項目（空）
        popup.addItem(withTitle: "")
        for (name, color) in Self.foreColorEntries {
            let item = NSMenuItem()
            item.title = NSLocalizedString(name, comment: "Color name")
            item.image = createColorSwatchImage(color: color)
            item.representedObject = color
            popup.menu?.addItem(item)
        }
        popup.menu?.addItem(NSMenuItem.separator())
        let otherItem = NSMenuItem()
        otherItem.title = NSLocalizedString("Other Color…", comment: "")
        otherItem.representedObject = "other" as NSString  // センチネル
        popup.menu?.addItem(otherItem)
        popup.target = self
        popup.action = #selector(foreColorPopupChanged(_:))
        setupColorPopupAppearance(popup)
        return popup
    }

    private func createBackColorPopup() -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: true)
        popup.controlSize = .small
        popup.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        // 先頭: 閉じた状態で表示されるタイトル項目（空）
        popup.addItem(withTitle: "")
        for (index, (name, color)) in Self.backColorEntries.enumerated() {
            let item = NSMenuItem()
            item.title = NSLocalizedString(name, comment: "Color name")
            item.image = createColorSwatchImage(color: color ?? .white)
            item.representedObject = color  // nil for Clear
            item.tag = index
            popup.menu?.addItem(item)
            if index == 0 {
                popup.menu?.addItem(NSMenuItem.separator())
            }
        }
        popup.menu?.addItem(NSMenuItem.separator())
        let otherItem = NSMenuItem()
        otherItem.title = NSLocalizedString("Other Color…", comment: "")
        otherItem.representedObject = "other" as NSString
        popup.menu?.addItem(otherItem)
        popup.target = self
        popup.action = #selector(backColorPopupChanged(_:))
        setupColorPopupAppearance(popup)
        return popup
    }

    /// カラースウォッチ画像を作成
    private func createColorSwatchImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 20, height: 12)
        return NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath.fill(rect)
            NSColor.separatorColor.setStroke()
            NSBezierPath.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
            return true
        }
    }

    /// 現在の色を表示する矩形インジケータを作成
    private func createColorIndicator(color: NSColor? = nil) -> ColorIndicatorView {
        let view = ColorIndicatorView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.color = color
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 24),
            view.heightAnchor.constraint(equalToConstant: 16),
        ])
        return view
    }

    /// カラーインジケータの色を更新
    private func updateColorIndicator(_ indicator: ColorIndicatorView, color: NSColor?) {
        indicator.color = color
    }

    /// 装飾色用ポップアップ（Clear + Foreground プリセット + Other Color…）
    private func createDecorationColorPopup(action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: true)
        popup.controlSize = .small
        popup.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        // 先頭: 閉じた状態で表示されるタイトル項目（空）
        popup.addItem(withTitle: "")
        // Not Assigned（色指定なし = テキスト色と同じ）
        let clearItem = NSMenuItem()
        clearItem.title = NSLocalizedString("Not Assigned", comment: "No specific color assigned, uses text color")
        clearItem.representedObject = nil
        popup.menu?.addItem(clearItem)
        popup.menu?.addItem(NSMenuItem.separator())
        // Foreground と同じプリセット
        for (name, color) in Self.foreColorEntries {
            let item = NSMenuItem()
            item.title = NSLocalizedString(name, comment: "Color name")
            item.image = createColorSwatchImage(color: color)
            item.representedObject = color
            popup.menu?.addItem(item)
        }
        popup.menu?.addItem(NSMenuItem.separator())
        let otherItem = NSMenuItem()
        otherItem.title = NSLocalizedString("Other Color…", comment: "")
        otherItem.representedObject = "other" as NSString
        popup.menu?.addItem(otherItem)
        popup.target = self
        popup.action = action
        setupColorPopupAppearance(popup)
        return popup
    }

    private func addUnderlineSection(to stack: NSStackView) {
        stack.addArrangedSubview(createSectionHeader("Underline"))

        let styleRow = createLabeledRow("Style:")
        underlineStylePopup = createLineStylePopup(action: #selector(underlineChanged(_:)))
        styleRow.addArrangedSubview(underlineStylePopup)
        underlinePatternPopup = createLinePatternPopup(action: #selector(underlineChanged(_:)))
        styleRow.addArrangedSubview(underlinePatternPopup)
        stack.addArrangedSubview(styleRow)

        let colorRow = createLabeledRow("Color:")
        underlineColorIndicator = createColorIndicator()
        colorRow.addArrangedSubview(underlineColorIndicator)
        underlineColorPopup = createDecorationColorPopup(action: #selector(underlineColorPopupChanged(_:)))
        colorRow.addArrangedSubview(underlineColorPopup)
        stack.addArrangedSubview(colorRow)

        // 初期状態: None なので disable
        underlinePatternPopup.isEnabled = false
        underlineColorPopup.isEnabled = false

        stack.addArrangedSubview(createSeparator())
    }

    private func addStrikethroughSection(to stack: NSStackView) {
        stack.addArrangedSubview(createSectionHeader("Strikethrough"))

        let styleRow = createLabeledRow("Style:")
        strikethroughStylePopup = createLineStylePopup(action: #selector(strikethroughChanged(_:)))
        styleRow.addArrangedSubview(strikethroughStylePopup)
        strikethroughPatternPopup = createLinePatternPopup(action: #selector(strikethroughChanged(_:)))
        styleRow.addArrangedSubview(strikethroughPatternPopup)
        stack.addArrangedSubview(styleRow)

        let colorRow = createLabeledRow("Color:")
        strikethroughColorIndicator = createColorIndicator()
        colorRow.addArrangedSubview(strikethroughColorIndicator)
        strikethroughColorPopup = createDecorationColorPopup(action: #selector(strikethroughColorPopupChanged(_:)))
        colorRow.addArrangedSubview(strikethroughColorPopup)
        stack.addArrangedSubview(colorRow)

        // 初期状態: None なので disable
        strikethroughPatternPopup.isEnabled = false
        strikethroughColorPopup.isEnabled = false

        stack.addArrangedSubview(createSeparator())
    }

    private func addOutlineSection(to stack: NSStackView) {
        stack.addArrangedSubview(createSectionHeader("Outline"))

        let row = createLabeledRow("Width:")
        strokeWidthField = createNumberField(action: #selector(strokeWidthFieldChanged(_:)))
        strokeWidthStepper = createStepper(minValue: -10, maxValue: 10, increment: 0.5, action: #selector(strokeWidthStepperChanged(_:)))
        row.addArrangedSubview(strokeWidthField)
        row.addArrangedSubview(strokeWidthStepper)
        row.addArrangedSubview(NSTextField(labelWithString: "pt."))
        row.addArrangedSubview(createSmallSpacer())
        row.addArrangedSubview(NSTextField(labelWithString: "Color:"))
        strokeColorIndicator = createColorIndicator()
        row.addArrangedSubview(strokeColorIndicator)
        strokeColorPopup = createDecorationColorPopup(action: #selector(strokeColorPopupChanged(_:)))
        row.addArrangedSubview(strokeColorPopup)
        stack.addArrangedSubview(row)

        stack.addArrangedSubview(createSeparator())
    }

    private func addBaselineKerningSection(to stack: NSStackView) {
        stack.addArrangedSubview(createSectionHeader("Baseline & Spacing"))

        // Baseline Offset
        let baselineRow = createLabeledRow("Baseline Offset:")
        baselineOffsetField = createNumberField(action: #selector(baselineOffsetFieldChanged(_:)))
        baselineOffsetStepper = createStepper(minValue: -100, maxValue: 100, increment: 1, action: #selector(baselineOffsetStepperChanged(_:)))
        baselineRow.addArrangedSubview(baselineOffsetField)
        baselineRow.addArrangedSubview(baselineOffsetStepper)
        baselineRow.addArrangedSubview(NSTextField(labelWithString: "pt."))
        stack.addArrangedSubview(baselineRow)

        // Kerning
        let kernRow = createLabeledRow("Kerning:")
        kernField = createNumberField(action: #selector(kernFieldChanged(_:)))
        kernStepper = createStepper(minValue: -100, maxValue: 100, increment: 0.5, action: #selector(kernStepperChanged(_:)))
        kernRow.addArrangedSubview(kernField)
        kernRow.addArrangedSubview(kernStepper)
        kernRow.addArrangedSubview(NSTextField(labelWithString: "pt."))
        stack.addArrangedSubview(kernRow)

        // Ligatures
        let ligatureRow = createLabeledRow("Ligatures:")
        ligaturePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        ligaturePopup.controlSize = .small
        ligaturePopup.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        ligaturePopup.addItems(withTitles: ["Default", "None", "All"])
        ligaturePopup.target = self
        ligaturePopup.action = #selector(ligatureChanged(_:))
        ligatureRow.addArrangedSubview(ligaturePopup)
        stack.addArrangedSubview(ligatureRow)

        stack.addArrangedSubview(createSeparator())
    }

    private func addAlignmentSection(to stack: NSStackView) {
        stack.addArrangedSubview(createSectionHeader("Alignment"))

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 4

        alignmentSegmented = NSSegmentedControl(
            images: [
                NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "Left")!,
                NSImage(systemSymbolName: "text.aligncenter", accessibilityDescription: "Center")!,
                NSImage(systemSymbolName: "text.alignright", accessibilityDescription: "Right")!,
                NSImage(systemSymbolName: "text.justify", accessibilityDescription: "Justified")!,
            ],
            trackingMode: .selectOne,
            target: self,
            action: #selector(alignmentChanged(_:))
        )
        alignmentSegmented.controlSize = .regular
        row.addArrangedSubview(alignmentSegmented)
        stack.addArrangedSubview(row)

        stack.addArrangedSubview(createSeparator())
    }

    private func addLineHeightSection(to stack: NSStackView) {
        stack.addArrangedSubview(createSectionHeader("Line Height"))

        // Multiple
        let multipleRow = createLabeledRow("Multiple:")
        lineHeightMultipleField = createNumberField(action: #selector(lineHeightMultipleFieldChanged(_:)))
        lineHeightMultipleStepper = createStepper(minValue: 0, maxValue: 10, increment: 0.1, action: #selector(lineHeightMultipleStepperChanged(_:)))
        multipleRow.addArrangedSubview(lineHeightMultipleField)
        multipleRow.addArrangedSubview(lineHeightMultipleStepper)
        multipleRow.addArrangedSubview(NSTextField(labelWithString: "times"))
        stack.addArrangedSubview(multipleRow)

        // Min
        let minRow = createLabeledRow("Min:")
        lineHeightMinField = createNumberField(action: #selector(lineHeightMinFieldChanged(_:)))
        lineHeightMinStepper = createStepper(minValue: 0, maxValue: 999, increment: 1, action: #selector(lineHeightMinStepperChanged(_:)))
        minRow.addArrangedSubview(lineHeightMinField)
        minRow.addArrangedSubview(lineHeightMinStepper)
        minRow.addArrangedSubview(NSTextField(labelWithString: "pt."))
        stack.addArrangedSubview(minRow)

        // Max
        let maxRow = createLabeledRow("Max:")
        lineHeightMaxField = createNumberField(action: #selector(lineHeightMaxFieldChanged(_:)))
        lineHeightMaxStepper = createStepper(minValue: 0, maxValue: 999, increment: 1, action: #selector(lineHeightMaxStepperChanged(_:)))
        maxRow.addArrangedSubview(lineHeightMaxField)
        maxRow.addArrangedSubview(lineHeightMaxStepper)
        maxRow.addArrangedSubview(NSTextField(labelWithString: "pt."))
        stack.addArrangedSubview(maxRow)

        stack.addArrangedSubview(createSeparator())
    }

    private func addIndentSection(to stack: NSStackView) {
        stack.addArrangedSubview(createSectionHeader("Indents"))

        let firstRow = createLabeledRow("First Line:")
        firstLineHeadIndentField = createNumberField(action: #selector(firstLineHeadIndentFieldChanged(_:)))
        firstLineHeadIndentStepper = createStepper(minValue: 0, maxValue: 999, increment: 1, action: #selector(firstLineHeadIndentStepperChanged(_:)))
        firstRow.addArrangedSubview(firstLineHeadIndentField)
        firstRow.addArrangedSubview(firstLineHeadIndentStepper)
        firstRow.addArrangedSubview(NSTextField(labelWithString: "pt."))
        stack.addArrangedSubview(firstRow)

        let headRow = createLabeledRow("Head:")
        headIndentField = createNumberField(action: #selector(headIndentFieldChanged(_:)))
        headIndentStepper = createStepper(minValue: 0, maxValue: 999, increment: 1, action: #selector(headIndentStepperChanged(_:)))
        headRow.addArrangedSubview(headIndentField)
        headRow.addArrangedSubview(headIndentStepper)
        headRow.addArrangedSubview(NSTextField(labelWithString: "pt."))
        stack.addArrangedSubview(headRow)

        let tailRow = createLabeledRow("Tail:")
        tailIndentField = createNumberField(action: #selector(tailIndentFieldChanged(_:)))
        tailIndentStepper = createStepper(minValue: -999, maxValue: 999, increment: 1, action: #selector(tailIndentStepperChanged(_:)))
        tailRow.addArrangedSubview(tailIndentField)
        tailRow.addArrangedSubview(tailIndentStepper)
        tailRow.addArrangedSubview(NSTextField(labelWithString: "pt."))
        stack.addArrangedSubview(tailRow)

        stack.addArrangedSubview(createSeparator())
    }

    private func addParagraphSpacingSection(to stack: NSStackView) {
        stack.addArrangedSubview(createSectionHeader("Paragraph Spacing"))

        let lineSpaceRow = createLabeledRow("Line Space:")
        lineSpacingField = createNumberField(action: #selector(lineSpacingFieldChanged(_:)))
        lineSpacingStepper = createStepper(minValue: 0, maxValue: 999, increment: 1, action: #selector(lineSpacingStepperChanged(_:)))
        lineSpaceRow.addArrangedSubview(lineSpacingField)
        lineSpaceRow.addArrangedSubview(lineSpacingStepper)
        lineSpaceRow.addArrangedSubview(NSTextField(labelWithString: "pt."))
        stack.addArrangedSubview(lineSpaceRow)

        let beforeRow = createLabeledRow("Before:")
        paragraphSpacingBeforeField = createNumberField(action: #selector(paragraphSpacingBeforeFieldChanged(_:)))
        paragraphSpacingBeforeStepper = createStepper(minValue: 0, maxValue: 999, increment: 1, action: #selector(paragraphSpacingBeforeStepperChanged(_:)))
        beforeRow.addArrangedSubview(paragraphSpacingBeforeField)
        beforeRow.addArrangedSubview(paragraphSpacingBeforeStepper)
        beforeRow.addArrangedSubview(NSTextField(labelWithString: "pt."))
        stack.addArrangedSubview(beforeRow)

        let afterRow = createLabeledRow("After:")
        paragraphSpacingAfterField = createNumberField(action: #selector(paragraphSpacingAfterFieldChanged(_:)))
        paragraphSpacingAfterStepper = createStepper(minValue: 0, maxValue: 999, increment: 1, action: #selector(paragraphSpacingAfterStepperChanged(_:)))
        afterRow.addArrangedSubview(paragraphSpacingAfterField)
        afterRow.addArrangedSubview(paragraphSpacingAfterStepper)
        afterRow.addArrangedSubview(NSTextField(labelWithString: "pt."))
        stack.addArrangedSubview(afterRow)
    }

    // MARK: - UI Helper Methods

    private func createSectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.boldSystemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func createSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        return separator
    }

    private func createLabeledRow(_ labelText: String) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 4
        row.alignment = .centerY

        let label = NSTextField(labelWithString: labelText)
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: Self.labelWidth).isActive = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        row.addArrangedSubview(label)

        return row
    }

    private func createNumberField(action: Selector) -> NSTextField {
        let field = NSTextField()
        field.controlSize = .small
        field.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        field.alignment = .right
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: Self.fieldWidth).isActive = true
        field.target = self
        field.action = action

        // NumberFormatter を設定
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        field.formatter = formatter

        return field
    }

    private func createStepper(minValue: Double, maxValue: Double, increment: Double, action: Selector) -> NSStepper {
        let stepper = NSStepper()
        stepper.controlSize = .small
        stepper.minValue = minValue
        stepper.maxValue = maxValue
        stepper.increment = increment
        stepper.valueWraps = false
        stepper.autorepeat = true
        stepper.target = self
        stepper.action = action
        return stepper
    }

    private func createLineStylePopup(action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .small
        popup.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        popup.addItems(withTitles: ["None", "Single", "Thick", "Double"])
        popup.target = self
        popup.action = action
        return popup
    }

    private func createLinePatternPopup(action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .small
        popup.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        popup.addItems(withTitles: ["Solid", "Dot", "Dash", "Dash Dot", "Dash Dot Dot"])
        popup.target = self
        popup.action = action
        return popup
    }

    private func createSmallSpacer() -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: 8).isActive = true
        return spacer
    }

    // MARK: - Observers

    private func setupObservers() {
        // 選択変更の監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionDidChange(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: nil
        )
        // テキスト変更の監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: nil
        )
        // ウィンドウ切り替えの監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeMain(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
        // カラーパネルの色変更を監視（NSColorWellのactivateを使わず自前で管理）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(colorPanelDidChangeColor(_:)),
            name: NSColorPanel.colorDidChangeNotification,
            object: nil
        )
        // カラーパネルの閉じを監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(colorPanelWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: NSColorPanel.shared
        )
    }

    @objc private func selectionDidChange(_ notification: Notification) {
        guard isPanelVisible else { return }
        guard let textView = notification.object as? NSTextView,
              !(textView.window is NSPanel) else { return }
        updateFromSelection()
    }

    @objc private func textDidChange(_ notification: Notification) {
        guard isPanelVisible else { return }
        guard let textView = notification.object as? NSTextView,
              !(textView.window is NSPanel) else { return }
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(debouncedUpdate), object: nil)
        perform(#selector(debouncedUpdate), with: nil, afterDelay: 0.1)
    }

    @objc private func windowDidBecomeMain(_ notification: Notification) {
        guard isPanelVisible else { return }
        guard let window = notification.object as? NSWindow,
              !(window is NSPanel) else { return }
        updateFromSelection()
    }

    @objc private func debouncedUpdate() {
        updateFromSelection()
    }

    /// カラーパネルの色変更通知ハンドラ — 対象属性に色を適用し、パネルを閉じる
    @objc private func colorPanelDidChangeColor(_ notification: Notification) {
        guard !isUpdatingUI, !isSettingUpColorPanel else { return }
        guard let target = editingColorTarget else { return }
        let color = NSColorPanel.shared.color
        // 編集対象をクリア（再入防止）
        editingColorTarget = nil

        // 該当する属性を適用し、インジケータを更新
        switch target {
        case .foreground:
            updateColorIndicator(foreColorIndicator, color: color)
            applySimpleAttribute(.foregroundColor, value: color)
        case .background:
            updateColorIndicator(backColorIndicator, color: color)
            applySimpleAttribute(.backgroundColor, value: color)
        case .underlineColor:
            updateColorIndicator(underlineColorIndicator, color: color)
            applySimpleAttribute(.underlineColor, value: color)
        case .strikethroughColor:
            updateColorIndicator(strikethroughColorIndicator, color: color)
            applySimpleAttribute(.strikethroughColor, value: color)
        case .strokeColor:
            updateColorIndicator(strokeColorIndicator, color: color)
            applySimpleAttribute(.strokeColor, value: color)
            updateFromSelection()
        }

        // 色を適用したらカラーパネルを閉じる（どの属性用か混乱しないように）
        NSColorPanel.shared.orderOut(nil)
    }

    /// カラーパネルが閉じられたら編集状態をクリア
    @objc private func colorPanelWillClose(_ notification: Notification) {
        editingColorTarget = nil
    }

    /// NSColorPanel を開いて色編集を開始（Other Color… 用共通処理）
    private func openColorPanelForEditing(currentColor: NSColor) {
        // panel.color 設定時に colorDidChangeNotification が同期的に発火するため、
        // isSettingUpColorPanel フラグで通知と changeColor: をブロックする
        let savedTarget = editingColorTarget
        isSettingUpColorPanel = true
        let panel = NSColorPanel.shared
        panel.color = currentColor
        isSettingUpColorPanel = false
        editingColorTarget = savedTarget
        panel.orderFront(nil)
    }

    // beginEditingColor は不要（全てポップアップメニューに移行済み）

    // MARK: - Current Text View Helper

    private func currentTextView() -> JeditTextView? {
        guard let mainWindow = NSApp.mainWindow,
              !(mainWindow is NSPanel),
              let windowController = mainWindow.windowController as? EditorWindowController else {
            return nil
        }
        // EditorWindowController の currentTextView() を使用
        return windowController.currentTextView() as? JeditTextView
    }

    // MARK: - Read Attributes from Selection

    private func updateFromSelection() {
        isUpdatingUI = true
        defer { isUpdatingUI = false }

        guard let textView = currentTextView(),
              let textStorage = textView.textStorage else {
            clearAllFields()
            return
        }

        let selectedRange = textView.selectedRange()

        if selectedRange.length == 0 {
            // 挿入ポイント: typingAttributes を使用
            let attrs = textView.typingAttributes
            updateUIFromSingleAttributes(attrs)
            return
        }

        // 選択範囲の属性を収集
        var fonts: [NSFont] = []
        var foreColors: [NSColor] = []
        var backColors: [NSColor?] = []
        var underlineStyles: [Int] = []
        var underlineColors: [NSColor?] = []
        var strikethroughStyles: [Int] = []
        var strikethroughColors: [NSColor?] = []
        var strokeWidths: [CGFloat] = []
        var strokeColors: [NSColor?] = []
        var baselineOffsets: [CGFloat] = []
        var kerns: [CGFloat] = []
        var ligatures: [Int] = []
        var paragraphStyles: [NSParagraphStyle] = []

        textStorage.enumerateAttributes(in: selectedRange, options: []) { attrs, _, _ in
            if let font = attrs[.font] as? NSFont {
                fonts.append(font)
            }
            foreColors.append((attrs[.foregroundColor] as? NSColor) ?? .textColor)
            backColors.append(attrs[.backgroundColor] as? NSColor)
            underlineStyles.append((attrs[.underlineStyle] as? Int) ?? 0)
            underlineColors.append(attrs[.underlineColor] as? NSColor)
            strikethroughStyles.append((attrs[.strikethroughStyle] as? Int) ?? 0)
            strikethroughColors.append(attrs[.strikethroughColor] as? NSColor)
            strokeWidths.append((attrs[.strokeWidth] as? CGFloat) ?? 0)
            strokeColors.append(attrs[.strokeColor] as? NSColor)
            baselineOffsets.append((attrs[.baselineOffset] as? CGFloat) ?? 0)
            kerns.append((attrs[.kern] as? CGFloat) ?? 0)
            ligatures.append((attrs[.ligature] as? Int) ?? 1)
            paragraphStyles.append((attrs[.paragraphStyle] as? NSParagraphStyle) ?? .default)
        }

        // Font
        updateFontSection(fonts: fonts)

        // Colors
        updateForeColorPopup(colors: foreColors)
        updateBackColorPopup(colors: backColors)

        // Underline
        updateLineDecorationSection(
            stylePopup: underlineStylePopup,
            patternPopup: underlinePatternPopup,
            colorPopup: underlineColorPopup,
            colorIndicator: underlineColorIndicator,
            styles: underlineStyles,
            colors: underlineColors
        )

        // Strikethrough
        updateLineDecorationSection(
            stylePopup: strikethroughStylePopup,
            patternPopup: strikethroughPatternPopup,
            colorPopup: strikethroughColorPopup,
            colorIndicator: strikethroughColorIndicator,
            styles: strikethroughStyles,
            colors: strikethroughColors
        )

        // Outline
        updateNumberField(strokeWidthField, stepper: strokeWidthStepper, values: strokeWidths)
        updateDecorationColorPopup(strokeColorPopup, indicator: strokeColorIndicator, colors: strokeColors)

        // Baseline & Spacing
        updateNumberField(baselineOffsetField, stepper: baselineOffsetStepper, values: baselineOffsets)
        updateNumberField(kernField, stepper: kernStepper, values: kerns)
        updateLigaturePopup(values: ligatures)

        // Paragraph
        updateParagraphSection(paragraphStyles: paragraphStyles)
    }

    /// 単一属性セットから UI を更新（挿入ポイント用）
    private func updateUIFromSingleAttributes(_ attrs: [NSAttributedString.Key: Any]) {
        // Font
        if let font = attrs[.font] as? NSFont {
            fontFamilyField.stringValue = font.familyName ?? font.fontName
            fontStyleField.stringValue = font.fontDescriptor.object(forKey: .face) as? String ?? ""
            fontSizeField.doubleValue = Double(font.pointSize)
            fontSizeStepper.doubleValue = Double(font.pointSize)
        } else {
            fontFamilyField.stringValue = ""
            fontStyleField.stringValue = ""
            fontSizeField.stringValue = ""
        }

        // Colors
        updateForeColorPopup(colors: [(attrs[.foregroundColor] as? NSColor) ?? .textColor])
        updateBackColorPopup(colors: [attrs[.backgroundColor] as? NSColor])

        // Underline
        let underline = (attrs[.underlineStyle] as? Int) ?? 0
        setLineDecorationPopups(underlineStylePopup, patternPopup: underlinePatternPopup, rawValue: underline)
        updateDecorationColorPopup(underlineColorPopup, indicator: underlineColorIndicator, colors: [attrs[.underlineColor] as? NSColor])
        let underlineIsNone = (underline == 0)
        underlinePatternPopup.isEnabled = !underlineIsNone
        underlineColorPopup.isEnabled = !underlineIsNone

        // Strikethrough
        let strikethrough = (attrs[.strikethroughStyle] as? Int) ?? 0
        setLineDecorationPopups(strikethroughStylePopup, patternPopup: strikethroughPatternPopup, rawValue: strikethrough)
        updateDecorationColorPopup(strikethroughColorPopup, indicator: strikethroughColorIndicator, colors: [attrs[.strikethroughColor] as? NSColor])
        let strikethroughIsNone = (strikethrough == 0)
        strikethroughPatternPopup.isEnabled = !strikethroughIsNone
        strikethroughColorPopup.isEnabled = !strikethroughIsNone

        // Outline
        let strokeWidth = (attrs[.strokeWidth] as? CGFloat) ?? 0
        strokeWidthField.doubleValue = Double(strokeWidth)
        strokeWidthStepper.doubleValue = Double(strokeWidth)
        updateDecorationColorPopup(strokeColorPopup, indicator: strokeColorIndicator, colors: [attrs[.strokeColor] as? NSColor])

        // Baseline & Spacing
        let baseline = (attrs[.baselineOffset] as? CGFloat) ?? 0
        baselineOffsetField.doubleValue = Double(baseline)
        baselineOffsetStepper.doubleValue = Double(baseline)
        let kern = (attrs[.kern] as? CGFloat) ?? 0
        kernField.doubleValue = Double(kern)
        kernStepper.doubleValue = Double(kern)
        let ligature = (attrs[.ligature] as? Int) ?? 1
        ligaturePopup.selectItem(at: ligature == 0 ? 1 : (ligature == 2 ? 2 : 0))

        // Paragraph
        let paraStyle = (attrs[.paragraphStyle] as? NSParagraphStyle) ?? .default
        updateParagraphUI(from: paraStyle)
    }

    private func clearAllFields() {
        fontFamilyField.stringValue = ""
        fontStyleField.stringValue = ""
        fontSizeField.stringValue = ""
        updateColorIndicator(foreColorIndicator, color: .textColor)
        updateColorIndicator(backColorIndicator, color: nil)
        updateColorIndicator(underlineColorIndicator, color: nil)
        updateColorIndicator(strikethroughColorIndicator, color: nil)
        updateColorIndicator(strokeColorIndicator, color: nil)
        underlineStylePopup.selectItem(at: 0)
        underlinePatternPopup.selectItem(at: 0)
        strikethroughStylePopup.selectItem(at: 0)
        strikethroughPatternPopup.selectItem(at: 0)
        strokeWidthField.stringValue = "0"
        strokeWidthStepper.doubleValue = 0
        baselineOffsetField.stringValue = "0"
        baselineOffsetStepper.doubleValue = 0
        kernField.stringValue = "0"
        kernStepper.doubleValue = 0
        ligaturePopup.selectItem(at: 0)
        alignmentSegmented.selectedSegment = 0
        lineHeightMultipleField.stringValue = "0"
        lineHeightMinField.stringValue = "0"
        lineHeightMaxField.stringValue = "0"
        firstLineHeadIndentField.stringValue = "0"
        headIndentField.stringValue = "0"
        tailIndentField.stringValue = "0"
        lineSpacingField.stringValue = "0"
        paragraphSpacingBeforeField.stringValue = "0"
        paragraphSpacingAfterField.stringValue = "0"
    }

    // MARK: - Section Update Helpers

    private func updateFontSection(fonts: [NSFont]) {
        let families = Set(fonts.map { $0.familyName ?? $0.fontName })
        if families.count == 1, let family = families.first {
            fontFamilyField.stringValue = family
        } else if families.isEmpty {
            fontFamilyField.stringValue = ""
        } else {
            fontFamilyField.stringValue = Self.mixedPlaceholder
        }

        let faces = Set(fonts.compactMap { $0.fontDescriptor.object(forKey: .face) as? String })
        if faces.count == 1, let face = faces.first {
            fontStyleField.stringValue = face
        } else if faces.isEmpty {
            fontStyleField.stringValue = ""
        } else {
            fontStyleField.stringValue = Self.mixedPlaceholder
        }

        let sizes = Set(fonts.map { $0.pointSize })
        if sizes.count == 1, let size = sizes.first {
            fontSizeField.doubleValue = Double(size)
            fontSizeStepper.doubleValue = Double(size)
        } else {
            fontSizeField.placeholderString = Self.mixedPlaceholder
            fontSizeField.stringValue = ""
        }
    }

    /// 前景色インジケータを更新
    private func updateForeColorPopup(colors: [NSColor]) {
        let unique = Set(colors.map { $0.description })
        if unique.count == 1, let color = colors.first {
            updateColorIndicator(foreColorIndicator, color: color)
        } else {
            updateColorIndicator(foreColorIndicator, color: nil)
        }
    }

    /// 背景色インジケータを更新
    private func updateBackColorPopup(colors: [NSColor?]) {
        let nonNil = colors.compactMap { $0 }
        if nonNil.isEmpty {
            updateColorIndicator(backColorIndicator, color: nil)
        } else if Set(colors.map { $0?.description ?? "nil" }).count == 1, let color = nonNil.first {
            updateColorIndicator(backColorIndicator, color: color)
        } else {
            updateColorIndicator(backColorIndicator, color: nil)
        }
    }

    /// 装飾色インジケータを更新
    private func updateDecorationColorPopup(_ popup: NSPopUpButton, indicator: ColorIndicatorView?, colors: [NSColor?]) {
        let nonNil = colors.compactMap { $0 }
        if nonNil.isEmpty {
            indicator?.color = nil
        } else if Set(nonNil.map { $0.description }).count == 1, let color = nonNil.first {
            indicator?.color = color
        } else {
            indicator?.color = nil
        }
    }

    /// 2つの色が実質的に同じかを比較（カラースペース差を許容）
    private func colorsMatch(_ a: NSColor?, _ b: NSColor?) -> Bool {
        guard let a = a, let b = b else { return a == nil && b == nil }
        guard let ac = a.usingColorSpace(.sRGB),
              let bc = b.usingColorSpace(.sRGB) else { return false }
        return abs(ac.redComponent - bc.redComponent) < 0.02 &&
               abs(ac.greenComponent - bc.greenComponent) < 0.02 &&
               abs(ac.blueComponent - bc.blueComponent) < 0.02 &&
               abs(ac.alphaComponent - bc.alphaComponent) < 0.02
    }

    private func updateLineDecorationSection(
        stylePopup: NSPopUpButton,
        patternPopup: NSPopUpButton,
        colorPopup: NSPopUpButton,
        colorIndicator: ColorIndicatorView?,
        styles: [Int],
        colors: [NSColor?]
    ) {
        let uniqueStyles = Set(styles)
        let isNone: Bool
        if uniqueStyles.count == 1, let raw = uniqueStyles.first {
            setLineDecorationPopups(stylePopup, patternPopup: patternPopup, rawValue: raw)
            isNone = (raw == 0)
        } else {
            stylePopup.selectItem(at: -1)
            patternPopup.selectItem(at: -1)
            isNone = false  // 混在時は有効のまま
        }
        // None の時はパターンと色を disable
        patternPopup.isEnabled = !isNone
        colorPopup.isEnabled = !isNone
        updateDecorationColorPopup(colorPopup, indicator: colorIndicator, colors: colors)
    }

    private func setLineDecorationPopups(_ stylePopup: NSPopUpButton, patternPopup: NSPopUpButton, rawValue: Int) {
        // NSUnderlineStyle: single=1, thick=2, double=9, pattern bits at 0x0F00
        let styleBits = rawValue & 0x000F
        let patternBits = rawValue & 0x0F00

        switch styleBits {
        case 0: stylePopup.selectItem(at: 0) // None
        case NSUnderlineStyle.single.rawValue: stylePopup.selectItem(at: 1)
        case NSUnderlineStyle.thick.rawValue: stylePopup.selectItem(at: 2)
        case NSUnderlineStyle.double.rawValue: stylePopup.selectItem(at: 3)
        default: stylePopup.selectItem(at: 0)
        }

        switch patternBits {
        case 0: patternPopup.selectItem(at: 0) // Solid
        case NSUnderlineStyle.patternDot.rawValue: patternPopup.selectItem(at: 1)
        case NSUnderlineStyle.patternDash.rawValue: patternPopup.selectItem(at: 2)
        case NSUnderlineStyle.patternDashDot.rawValue: patternPopup.selectItem(at: 3)
        case NSUnderlineStyle.patternDashDotDot.rawValue: patternPopup.selectItem(at: 4)
        default: patternPopup.selectItem(at: 0)
        }
    }

    private func lineDecorationRawValue(stylePopup: NSPopUpButton, patternPopup: NSPopUpButton) -> Int {
        let styleIndex = stylePopup.indexOfSelectedItem
        let patternIndex = patternPopup.indexOfSelectedItem

        let styleBits: Int
        switch styleIndex {
        case 1: styleBits = NSUnderlineStyle.single.rawValue
        case 2: styleBits = NSUnderlineStyle.thick.rawValue
        case 3: styleBits = NSUnderlineStyle.double.rawValue
        default: styleBits = 0
        }

        let patternBits: Int
        switch patternIndex {
        case 1: patternBits = NSUnderlineStyle.patternDot.rawValue
        case 2: patternBits = NSUnderlineStyle.patternDash.rawValue
        case 3: patternBits = NSUnderlineStyle.patternDashDot.rawValue
        case 4: patternBits = NSUnderlineStyle.patternDashDotDot.rawValue
        default: patternBits = 0
        }

        return styleBits | patternBits
    }

    private func updateNumberField(_ field: NSTextField, stepper: NSStepper, values: [CGFloat]) {
        let unique = Set(values)
        if unique.count == 1, let val = unique.first {
            field.doubleValue = Double(val)
            stepper.doubleValue = Double(val)
        } else {
            field.placeholderString = Self.mixedPlaceholder
            field.stringValue = ""
        }
    }

    private func updateLigaturePopup(values: [Int]) {
        let unique = Set(values)
        if unique.count == 1, let val = unique.first {
            ligaturePopup.selectItem(at: val == 0 ? 1 : (val == 2 ? 2 : 0))
        } else {
            ligaturePopup.selectItem(at: -1)
        }
    }

    private func updateParagraphSection(paragraphStyles: [NSParagraphStyle]) {
        guard !paragraphStyles.isEmpty else { return }

        // Alignment
        let alignments = Set(paragraphStyles.map { $0.alignment })
        if alignments.count == 1, let alignment = alignments.first {
            switch alignment {
            case .left: alignmentSegmented.selectedSegment = 0
            case .center: alignmentSegmented.selectedSegment = 1
            case .right: alignmentSegmented.selectedSegment = 2
            case .justified: alignmentSegmented.selectedSegment = 3
            default: alignmentSegmented.selectedSegment = 0
            }
        } else {
            alignmentSegmented.selectedSegment = -1
        }

        // Line Height
        updateParagraphNumberField(lineHeightMultipleField, stepper: lineHeightMultipleStepper, values: paragraphStyles.map { $0.lineHeightMultiple })
        updateParagraphNumberField(lineHeightMinField, stepper: lineHeightMinStepper, values: paragraphStyles.map { $0.minimumLineHeight })
        updateParagraphNumberField(lineHeightMaxField, stepper: lineHeightMaxStepper, values: paragraphStyles.map { $0.maximumLineHeight })

        // Indents
        updateParagraphNumberField(firstLineHeadIndentField, stepper: firstLineHeadIndentStepper, values: paragraphStyles.map { $0.firstLineHeadIndent })
        updateParagraphNumberField(headIndentField, stepper: headIndentStepper, values: paragraphStyles.map { $0.headIndent })
        updateParagraphNumberField(tailIndentField, stepper: tailIndentStepper, values: paragraphStyles.map { $0.tailIndent })

        // Spacing
        updateParagraphNumberField(lineSpacingField, stepper: lineSpacingStepper, values: paragraphStyles.map { $0.lineSpacing })
        updateParagraphNumberField(paragraphSpacingBeforeField, stepper: paragraphSpacingBeforeStepper, values: paragraphStyles.map { $0.paragraphSpacingBefore })
        updateParagraphNumberField(paragraphSpacingAfterField, stepper: paragraphSpacingAfterStepper, values: paragraphStyles.map { $0.paragraphSpacing })
    }

    private func updateParagraphNumberField(_ field: NSTextField, stepper: NSStepper, values: [CGFloat]) {
        let unique = Set(values)
        if unique.count == 1, let val = unique.first {
            field.doubleValue = Double(val)
            stepper.doubleValue = Double(val)
        } else {
            field.placeholderString = Self.mixedPlaceholder
            field.stringValue = ""
        }
    }

    private func updateParagraphUI(from style: NSParagraphStyle) {
        switch style.alignment {
        case .left: alignmentSegmented.selectedSegment = 0
        case .center: alignmentSegmented.selectedSegment = 1
        case .right: alignmentSegmented.selectedSegment = 2
        case .justified: alignmentSegmented.selectedSegment = 3
        default: alignmentSegmented.selectedSegment = 0
        }

        lineHeightMultipleField.doubleValue = Double(style.lineHeightMultiple)
        lineHeightMultipleStepper.doubleValue = Double(style.lineHeightMultiple)
        lineHeightMinField.doubleValue = Double(style.minimumLineHeight)
        lineHeightMinStepper.doubleValue = Double(style.minimumLineHeight)
        lineHeightMaxField.doubleValue = Double(style.maximumLineHeight)
        lineHeightMaxStepper.doubleValue = Double(style.maximumLineHeight)

        firstLineHeadIndentField.doubleValue = Double(style.firstLineHeadIndent)
        firstLineHeadIndentStepper.doubleValue = Double(style.firstLineHeadIndent)
        headIndentField.doubleValue = Double(style.headIndent)
        headIndentStepper.doubleValue = Double(style.headIndent)
        tailIndentField.doubleValue = Double(style.tailIndent)
        tailIndentStepper.doubleValue = Double(style.tailIndent)

        lineSpacingField.doubleValue = Double(style.lineSpacing)
        lineSpacingStepper.doubleValue = Double(style.lineSpacing)
        paragraphSpacingBeforeField.doubleValue = Double(style.paragraphSpacingBefore)
        paragraphSpacingBeforeStepper.doubleValue = Double(style.paragraphSpacingBefore)
        paragraphSpacingAfterField.doubleValue = Double(style.paragraphSpacing)
        paragraphSpacingAfterStepper.doubleValue = Double(style.paragraphSpacing)
    }

    // MARK: - Write Attributes (Actions)

    // MARK: Font Actions

    @objc private func showFontPanel(_ sender: Any?) {
        NSFontManager.shared.orderFrontFontPanel(sender)
    }

    @objc private func fontSizeFieldChanged(_ sender: NSTextField) {
        guard !isUpdatingUI else { return }
        let newSize = CGFloat(sender.doubleValue)
        guard newSize > 0 else { return }
        fontSizeStepper.doubleValue = Double(newSize)
        applyFontSize(newSize)
    }

    @objc private func fontSizeStepperChanged(_ sender: NSStepper) {
        guard !isUpdatingUI else { return }
        let newSize = CGFloat(sender.doubleValue)
        guard newSize > 0 else { return }
        fontSizeField.doubleValue = Double(newSize)
        applyFontSize(newSize)
    }

    private func applyFontSize(_ size: CGFloat) {
        guard let textView = currentTextView(),
              let textStorage = textView.textStorage else { return }
        let range = textView.selectedRange()

        if range.length == 0 {
            if let font = textView.typingAttributes[.font] as? NSFont {
                let newFont = NSFontManager.shared.convert(font, toSize: size)
                textView.typingAttributes[.font] = newFont
            }
        } else {
            if textView.shouldChangeText(in: range, replacementString: nil) {
                textStorage.beginEditing()
                textStorage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                    if let font = value as? NSFont {
                        let newFont = NSFontManager.shared.convert(font, toSize: size)
                        textStorage.addAttribute(.font, value: newFont, range: subRange)
                    }
                }
                textStorage.endEditing()
                textView.didChangeText()
            }
        }
    }

    // MARK: Color Actions

    @objc private func foreColorPopupChanged(_ sender: NSPopUpButton) {
        guard !isUpdatingUI else { return }
        guard let item = sender.selectedItem else { return }
        if item.representedObject is NSString {
            // "Other Color…" — カラーパネルを開く
            editingColorTarget = .foreground
            openColorPanelForEditing(currentColor: currentForeColor())
        } else if let color = item.representedObject as? NSColor {
            updateColorIndicator(foreColorIndicator, color: color)
            applySimpleAttribute(.foregroundColor, value: color)
        }
    }

    @objc private func backColorPopupChanged(_ sender: NSPopUpButton) {
        guard !isUpdatingUI else { return }
        guard let item = sender.selectedItem else { return }
        if item.representedObject is NSString {
            // "Other Color…" — カラーパネルを開く
            editingColorTarget = .background
            openColorPanelForEditing(currentColor: currentBackColor() ?? .white)
        } else {
            // nil → Clear, NSColor → 背景色
            if let color = item.representedObject as? NSColor {
                updateColorIndicator(backColorIndicator, color: color)
                applySimpleAttribute(.backgroundColor, value: color)
            } else {
                updateColorIndicator(backColorIndicator, color: nil)
                removeSimpleAttribute(.backgroundColor)
            }
        }
    }

    /// 現在の文字色を取得
    private func currentForeColor() -> NSColor {
        guard let textView = currentTextView() else { return .textColor }
        let attrs = textView.selectedRange().length == 0
            ? textView.typingAttributes
            : textView.textStorage?.attributes(at: textView.selectedRange().location, effectiveRange: nil) ?? [:]
        return (attrs[.foregroundColor] as? NSColor) ?? .textColor
    }

    /// 現在の背景色を取得
    private func currentBackColor() -> NSColor? {
        guard let textView = currentTextView() else { return nil }
        let attrs = textView.selectedRange().length == 0
            ? textView.typingAttributes
            : textView.textStorage?.attributes(at: textView.selectedRange().location, effectiveRange: nil) ?? [:]
        return attrs[.backgroundColor] as? NSColor
    }

    // MARK: Underline Actions

    @objc private func underlineChanged(_ sender: Any?) {
        guard !isUpdatingUI else { return }
        let raw = lineDecorationRawValue(stylePopup: underlineStylePopup, patternPopup: underlinePatternPopup)
        let isNone = (raw == 0)
        underlinePatternPopup.isEnabled = !isNone
        underlineColorPopup.isEnabled = !isNone
        if raw == 0 {
            removeSimpleAttribute(.underlineStyle)
        } else {
            applySimpleAttribute(.underlineStyle, value: raw)
        }
    }

    @objc private func underlineColorPopupChanged(_ sender: NSPopUpButton) {
        guard !isUpdatingUI else { return }
        guard let item = sender.selectedItem else { return }
        if item.representedObject is NSString {
            // "Other Color…"
            editingColorTarget = .underlineColor
            let current = currentAttributeColor(.underlineColor)
            openColorPanelForEditing(currentColor: current ?? .textColor)
        } else if let color = item.representedObject as? NSColor {
            updateColorIndicator(underlineColorIndicator, color: color)
            applySimpleAttribute(.underlineColor, value: color)
        } else {
            // Clear
            updateColorIndicator(underlineColorIndicator, color: nil)
            removeSimpleAttribute(.underlineColor)
        }
    }

    // MARK: Strikethrough Actions

    @objc private func strikethroughChanged(_ sender: Any?) {
        guard !isUpdatingUI else { return }
        let raw = lineDecorationRawValue(stylePopup: strikethroughStylePopup, patternPopup: strikethroughPatternPopup)
        let isNone = (raw == 0)
        strikethroughPatternPopup.isEnabled = !isNone
        strikethroughColorPopup.isEnabled = !isNone
        if raw == 0 {
            removeSimpleAttribute(.strikethroughStyle)
        } else {
            applySimpleAttribute(.strikethroughStyle, value: raw)
        }
    }

    @objc private func strikethroughColorPopupChanged(_ sender: NSPopUpButton) {
        guard !isUpdatingUI else { return }
        guard let item = sender.selectedItem else { return }
        if item.representedObject is NSString {
            // "Other Color…"
            editingColorTarget = .strikethroughColor
            let current = currentAttributeColor(.strikethroughColor)
            openColorPanelForEditing(currentColor: current ?? .textColor)
        } else if let color = item.representedObject as? NSColor {
            updateColorIndicator(strikethroughColorIndicator, color: color)
            applySimpleAttribute(.strikethroughColor, value: color)
        } else {
            // Clear
            updateColorIndicator(strikethroughColorIndicator, color: nil)
            removeSimpleAttribute(.strikethroughColor)
        }
    }

    /// 現在の属性色を取得する汎用ヘルパー
    private func currentAttributeColor(_ key: NSAttributedString.Key) -> NSColor? {
        guard let textView = currentTextView() else { return nil }
        let attrs = textView.selectedRange().length == 0
            ? textView.typingAttributes
            : textView.textStorage?.attributes(at: textView.selectedRange().location, effectiveRange: nil) ?? [:]
        return attrs[key] as? NSColor
    }

    // MARK: Outline Actions

    @objc private func strokeWidthFieldChanged(_ sender: NSTextField) {
        guard !isUpdatingUI else { return }
        strokeWidthStepper.doubleValue = sender.doubleValue
        applyStrokeWidth(CGFloat(sender.doubleValue))
    }

    @objc private func strokeWidthStepperChanged(_ sender: NSStepper) {
        guard !isUpdatingUI else { return }
        strokeWidthField.doubleValue = sender.doubleValue
        applyStrokeWidth(CGFloat(sender.doubleValue))
    }

    private func applyStrokeWidth(_ width: CGFloat) {
        if width == 0 {
            removeSimpleAttribute(.strokeWidth)
        } else {
            applySimpleAttribute(.strokeWidth, value: width)
        }
    }

    @objc private func strokeColorPopupChanged(_ sender: NSPopUpButton) {
        guard !isUpdatingUI else { return }
        guard let item = sender.selectedItem else { return }
        if item.representedObject is NSString {
            // "Other Color…"
            editingColorTarget = .strokeColor
            let current = currentAttributeColor(.strokeColor)
            openColorPanelForEditing(currentColor: current ?? .textColor)
        } else if let color = item.representedObject as? NSColor {
            updateColorIndicator(strokeColorIndicator, color: color)
            applySimpleAttribute(.strokeColor, value: color)
        } else {
            // Not Assigned
            updateColorIndicator(strokeColorIndicator, color: nil)
            removeSimpleAttribute(.strokeColor)
        }
    }

    // MARK: Baseline & Kerning Actions

    @objc private func baselineOffsetFieldChanged(_ sender: NSTextField) {
        guard !isUpdatingUI else { return }
        baselineOffsetStepper.doubleValue = sender.doubleValue
        applySimpleAttribute(.baselineOffset, value: CGFloat(sender.doubleValue))
    }

    @objc private func baselineOffsetStepperChanged(_ sender: NSStepper) {
        guard !isUpdatingUI else { return }
        baselineOffsetField.doubleValue = sender.doubleValue
        applySimpleAttribute(.baselineOffset, value: CGFloat(sender.doubleValue))
    }

    @objc private func kernFieldChanged(_ sender: NSTextField) {
        guard !isUpdatingUI else { return }
        kernStepper.doubleValue = sender.doubleValue
        let value = CGFloat(sender.doubleValue)
        if value == 0 {
            removeSimpleAttribute(.kern)
        } else {
            applySimpleAttribute(.kern, value: value)
        }
    }

    @objc private func kernStepperChanged(_ sender: NSStepper) {
        guard !isUpdatingUI else { return }
        kernField.doubleValue = sender.doubleValue
        let value = CGFloat(sender.doubleValue)
        if value == 0 {
            removeSimpleAttribute(.kern)
        } else {
            applySimpleAttribute(.kern, value: value)
        }
    }

    @objc private func ligatureChanged(_ sender: NSPopUpButton) {
        guard !isUpdatingUI else { return }
        let index = sender.indexOfSelectedItem
        let value: Int
        switch index {
        case 1: value = 0  // None
        case 2: value = 2  // All
        default: value = 1 // Default
        }
        applySimpleAttribute(.ligature, value: value)
    }

    // MARK: Alignment Action

    @objc private func alignmentChanged(_ sender: NSSegmentedControl) {
        guard !isUpdatingUI else { return }
        let alignments: [NSTextAlignment] = [.left, .center, .right, .justified]
        guard sender.selectedSegment >= 0, sender.selectedSegment < alignments.count else { return }
        let alignment = alignments[sender.selectedSegment]
        applyParagraphAttribute { $0.alignment = alignment }
    }

    // MARK: Line Height Actions

    @objc private func lineHeightMultipleFieldChanged(_ sender: NSTextField) {
        guard !isUpdatingUI else { return }
        lineHeightMultipleStepper.doubleValue = sender.doubleValue
        applyParagraphAttribute { $0.lineHeightMultiple = CGFloat(sender.doubleValue) }
    }

    @objc private func lineHeightMultipleStepperChanged(_ sender: NSStepper) {
        guard !isUpdatingUI else { return }
        // 0 から上矢印を押した場合は 0.1 ではなく 1.0 から開始（0.1 だと行が重なって見づらいため）
        if sender.doubleValue > 0 && sender.doubleValue < 1.0 && lineHeightMultipleField.doubleValue == 0 {
            sender.doubleValue = 1.0
        }
        lineHeightMultipleField.doubleValue = sender.doubleValue
        applyParagraphAttribute { $0.lineHeightMultiple = CGFloat(sender.doubleValue) }
    }

    @objc private func lineHeightMinFieldChanged(_ sender: NSTextField) {
        guard !isUpdatingUI else { return }
        lineHeightMinStepper.doubleValue = sender.doubleValue
        applyParagraphAttribute { $0.minimumLineHeight = CGFloat(sender.doubleValue) }
    }

    @objc private func lineHeightMinStepperChanged(_ sender: NSStepper) {
        guard !isUpdatingUI else { return }
        lineHeightMinField.doubleValue = sender.doubleValue
        applyParagraphAttribute { $0.minimumLineHeight = CGFloat(sender.doubleValue) }
    }

    @objc private func lineHeightMaxFieldChanged(_ sender: NSTextField) {
        guard !isUpdatingUI else { return }
        lineHeightMaxStepper.doubleValue = sender.doubleValue
        applyParagraphAttribute { $0.maximumLineHeight = CGFloat(sender.doubleValue) }
    }

    @objc private func lineHeightMaxStepperChanged(_ sender: NSStepper) {
        guard !isUpdatingUI else { return }
        lineHeightMaxField.doubleValue = sender.doubleValue
        applyParagraphAttribute { $0.maximumLineHeight = CGFloat(sender.doubleValue) }
    }

    // MARK: Indent Actions

    @objc private func firstLineHeadIndentFieldChanged(_ sender: NSTextField) {
        guard !isUpdatingUI else { return }
        firstLineHeadIndentStepper.doubleValue = sender.doubleValue
        applyParagraphAttribute { $0.firstLineHeadIndent = CGFloat(sender.doubleValue) }
    }

    @objc private func firstLineHeadIndentStepperChanged(_ sender: NSStepper) {
        guard !isUpdatingUI else { return }
        firstLineHeadIndentField.doubleValue = sender.doubleValue
        applyParagraphAttribute { $0.firstLineHeadIndent = CGFloat(sender.doubleValue) }
    }

    @objc private func headIndentFieldChanged(_ sender: NSTextField) {
        guard !isUpdatingUI else { return }
        headIndentStepper.doubleValue = sender.doubleValue
        applyParagraphAttribute { $0.headIndent = CGFloat(sender.doubleValue) }
    }

    @objc private func headIndentStepperChanged(_ sender: NSStepper) {
        guard !isUpdatingUI else { return }
        headIndentField.doubleValue = sender.doubleValue
        applyParagraphAttribute { $0.headIndent = CGFloat(sender.doubleValue) }
    }

    @objc private func tailIndentFieldChanged(_ sender: NSTextField) {
        guard !isUpdatingUI else { return }
        tailIndentStepper.doubleValue = sender.doubleValue
        applyParagraphAttribute { $0.tailIndent = CGFloat(sender.doubleValue) }
    }

    @objc private func tailIndentStepperChanged(_ sender: NSStepper) {
        guard !isUpdatingUI else { return }
        tailIndentField.doubleValue = sender.doubleValue
        applyParagraphAttribute { $0.tailIndent = CGFloat(sender.doubleValue) }
    }

    // MARK: Paragraph Spacing Actions

    @objc private func lineSpacingFieldChanged(_ sender: NSTextField) {
        guard !isUpdatingUI else { return }
        lineSpacingStepper.doubleValue = sender.doubleValue
        applyParagraphAttribute { $0.lineSpacing = CGFloat(sender.doubleValue) }
    }

    @objc private func lineSpacingStepperChanged(_ sender: NSStepper) {
        guard !isUpdatingUI else { return }
        lineSpacingField.doubleValue = sender.doubleValue
        applyParagraphAttribute { $0.lineSpacing = CGFloat(sender.doubleValue) }
    }

    @objc private func paragraphSpacingBeforeFieldChanged(_ sender: NSTextField) {
        guard !isUpdatingUI else { return }
        paragraphSpacingBeforeStepper.doubleValue = sender.doubleValue
        applyParagraphAttribute { $0.paragraphSpacingBefore = CGFloat(sender.doubleValue) }
    }

    @objc private func paragraphSpacingBeforeStepperChanged(_ sender: NSStepper) {
        guard !isUpdatingUI else { return }
        paragraphSpacingBeforeField.doubleValue = sender.doubleValue
        applyParagraphAttribute { $0.paragraphSpacingBefore = CGFloat(sender.doubleValue) }
    }

    @objc private func paragraphSpacingAfterFieldChanged(_ sender: NSTextField) {
        guard !isUpdatingUI else { return }
        paragraphSpacingAfterStepper.doubleValue = sender.doubleValue
        applyParagraphAttribute { $0.paragraphSpacing = CGFloat(sender.doubleValue) }
    }

    @objc private func paragraphSpacingAfterStepperChanged(_ sender: NSStepper) {
        guard !isUpdatingUI else { return }
        paragraphSpacingAfterField.doubleValue = sender.doubleValue
        applyParagraphAttribute { $0.paragraphSpacing = CGFloat(sender.doubleValue) }
    }

    // MARK: - Attribute Application Helpers

    /// 単純な属性を選択範囲に適用
    private func applySimpleAttribute(_ key: NSAttributedString.Key, value: Any) {
        guard let textView = currentTextView() else { return }
        let range = textView.selectedRange()

        if range.length == 0 {
            textView.typingAttributes[key] = value
        } else {
            // 属性のみの変更 — replacementString:nil で選択範囲を保持しつつ Undo 対応
            guard let textStorage = textView.textStorage else { return }
            if textView.shouldChangeText(in: range, replacementString: nil) {
                textStorage.beginEditing()
                textStorage.addAttribute(key, value: value, range: range)
                textStorage.endEditing()
                textView.didChangeText()
            }
        }
    }

    /// 単純な属性を選択範囲から削除
    private func removeSimpleAttribute(_ key: NSAttributedString.Key) {
        guard let textView = currentTextView() else { return }
        let range = textView.selectedRange()

        if range.length == 0 {
            textView.typingAttributes.removeValue(forKey: key)
        } else {
            // 属性のみの削除 — replacementString:nil で選択範囲を保持しつつ Undo 対応
            guard let textStorage = textView.textStorage else { return }
            if textView.shouldChangeText(in: range, replacementString: nil) {
                textStorage.beginEditing()
                textStorage.removeAttribute(key, range: range)
                textStorage.endEditing()
                textView.didChangeText()
            }
        }
    }

    /// 段落属性を既存の NSParagraphStyle を保持しつつ変更
    private func applyParagraphAttribute(_ modifier: (NSMutableParagraphStyle) -> Void) {
        guard let textView = currentTextView(),
              let textStorage = textView.textStorage else { return }
        let range = textView.selectedRange()

        if range.length == 0 {
            let existing = textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle ?? .default
            let mutable = existing.mutableCopy() as! NSMutableParagraphStyle
            modifier(mutable)
            textView.typingAttributes[.paragraphStyle] = mutable
        } else {
            if textView.shouldChangeText(in: range, replacementString: nil) {
                textStorage.beginEditing()
                textStorage.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, subRange, _ in
                    let existing = (value as? NSParagraphStyle) ?? .default
                    let mutable = existing.mutableCopy() as! NSMutableParagraphStyle
                    modifier(mutable)
                    textStorage.addAttribute(.paragraphStyle, value: mutable, range: subRange)
                }
                textStorage.endEditing()
                textView.didChangeText()
            }
        }
    }
}


