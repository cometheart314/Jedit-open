//
//  StylesPreferencesViewController.swift
//  Jedit-open
//
//  Created by Claude on 2026/02/26.
//

import Cocoa

class StylesPreferencesViewController: NSViewController {

    // MARK: - Properties

    private let styleManager = StyleManager.shared

    private var splitView: NSSplitView!
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var addButton: NSButton!
    private var removeButton: NSButton!
    private var duplicateButton: NSButton!
    private var revertButton: NSButton!

    // Right panel
    private var editorScrollView: NSScrollView!
    private var editorContentView: NSView!
    private var nameField: NSTextField!
    private var keyEquivalentField: NSTextField!
    private var modifierCommandCheckBox: NSButton!
    private var modifierOptionCheckBox: NSButton!
    private var modifierShiftCheckBox: NSButton!
    private var modifierControlCheckBox: NSButton!

    // 文字属性コントロール
    private var fontFamilyCheckBox: NSButton!
    private var fontFamilyPopUp: NSPopUpButton!
    private var fontSizeCheckBox: NSButton!
    private var fontSizeField: NSTextField!
    private var fontSizeStepper: NSStepper!
    private var fontWeightCheckBox: NSButton!
    private var fontWeightPopUp: NSPopUpButton!
    private var isItalicCheckBox: NSButton!

    private var foregroundColorCheckBox: NSButton!
    private var foregroundColorWell: NSColorWell!
    private var backgroundColorCheckBox: NSButton!
    private var backgroundColorWell: NSColorWell!

    private var underlineStyleCheckBox: NSButton!
    private var underlineStylePopUp: NSPopUpButton!
    private var underlineColorCheckBox: NSButton!
    private var underlineColorWell: NSColorWell!
    private var strikethroughStyleCheckBox: NSButton!
    private var strikethroughStylePopUp: NSPopUpButton!
    private var strikethroughColorCheckBox: NSButton!
    private var strikethroughColorWell: NSColorWell!

    private var baselineOffsetCheckBox: NSButton!
    private var baselineOffsetField: NSTextField!
    private var kernCheckBox: NSButton!
    private var kernField: NSTextField!
    private var superscriptCheckBox: NSButton!
    private var superscriptPopUp: NSPopUpButton!
    private var ligatureCheckBox: NSButton!
    private var ligaturePopUp: NSPopUpButton!

    // 段落属性コントロール
    private var alignmentCheckBox: NSButton!
    private var alignmentPopUp: NSPopUpButton!
    private var lineSpacingCheckBox: NSButton!
    private var lineSpacingField: NSTextField!
    private var paragraphSpacingCheckBox: NSButton!
    private var paragraphSpacingField: NSTextField!
    private var paragraphSpacingBeforeCheckBox: NSButton!
    private var paragraphSpacingBeforeField: NSTextField!
    private var headIndentCheckBox: NSButton!
    private var headIndentField: NSTextField!
    private var tailIndentCheckBox: NSButton!
    private var tailIndentField: NSTextField!
    private var firstLineHeadIndentCheckBox: NSButton!
    private var firstLineHeadIndentField: NSTextField!
    private var lineHeightMultipleCheckBox: NSButton!
    private var lineHeightMultipleComboBox: NSComboBox!
    private var hyphenationFactorCheckBox: NSButton!
    private var hyphenationFactorField: NSTextField!

    // プレビュー
    private var previewTextView: NSTextView!

    private var selectedStyleIndex: Int = -1

    private var isUpdatingUI = false
    private var isSelfEditing = false

    // MARK: - Lifecycle

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        selectStyle(at: 0)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stylesDidChange(_:)),
            name: .textStylesDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func stylesDidChange(_ notification: Notification) {
        // 自分自身の編集操作による通知の場合はテーブルのみ更新（スクロールリセットを避ける）
        if isSelfEditing {
            tableView.reloadData()
            return
        }
        tableView.reloadData()
        updateEditorForSelection()
    }

    // MARK: - UI Setup

    private func setupUI() {
        splitView = NSSplitView(frame: view.bounds)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]
        splitView.delegate = self
        view.addSubview(splitView)

        // 左パネル: スタイルリスト
        let leftPanel = setupLeftPanel()
        splitView.addArrangedSubview(leftPanel)

        // 右パネル: 属性エディタ
        let rightPanel = setupRightPanel()
        splitView.addArrangedSubview(rightPanel)

        // 左パネルの幅を固定（リサイズ時は右パネルだけ伸縮する）
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        splitView.setPosition(184, ofDividerAt: 0)
    }

    // MARK: - Left Panel (Style List)

    private func setupLeftPanel() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 184, height: 500))

        // テーブルビュー
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 32, width: 184, height: 468))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        tableView = NSTableView(frame: scrollView.bounds)
        tableView.headerView = nil
        tableView.rowSizeStyle = .default
        tableView.allowsMultipleSelection = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("StyleName"))
        column.width = 180
        tableView.addTableColumn(column)

        tableView.dataSource = self
        tableView.delegate = self

        // ドラッグ＆ドロップ並べ替え
        tableView.registerForDraggedTypes([.string])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)

        scrollView.documentView = tableView
        container.addSubview(scrollView)

        // ボタンバー
        let buttonBar = NSView(frame: NSRect(x: 0, y: 0, width: 184, height: 28))
        buttonBar.autoresizingMask = [.width]

        addButton = NSButton(image: NSImage(named: NSImage.addTemplateName)!, target: self, action: #selector(addStyle(_:)))
        addButton.bezelStyle = .smallSquare
        addButton.frame = NSRect(x: 0, y: 0, width: 24, height: 24)
        addButton.isBordered = true
        buttonBar.addSubview(addButton)

        removeButton = NSButton(image: NSImage(named: NSImage.removeTemplateName)!, target: self, action: #selector(removeStyle(_:)))
        removeButton.bezelStyle = .smallSquare
        removeButton.frame = NSRect(x: 24, y: 0, width: 24, height: 24)
        removeButton.isBordered = true
        buttonBar.addSubview(removeButton)

        duplicateButton = NSButton(title: "Duplicate", target: self, action: #selector(duplicateStyle(_:)))
        duplicateButton.bezelStyle = .smallSquare
        duplicateButton.frame = NSRect(x: 52, y: 0, width: 72, height: 24)
        duplicateButton.font = .systemFont(ofSize: 11)
        buttonBar.addSubview(duplicateButton)

        revertButton = NSButton(title: "Revert", target: self, action: #selector(revertStyle(_:)))
        revertButton.bezelStyle = .smallSquare
        revertButton.frame = NSRect(x: 124, y: 0, width: 60, height: 24)
        revertButton.font = .systemFont(ofSize: 11)
        buttonBar.addSubview(revertButton)

        container.addSubview(buttonBar)

        return container
    }

    // MARK: - Right Panel (Attribute Editor)

    private func setupRightPanel() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))

        editorScrollView = NSScrollView(frame: container.bounds)
        editorScrollView.autoresizingMask = [.width, .height]
        editorScrollView.hasVerticalScroller = true
        editorScrollView.borderType = .noBorder

        editorContentView = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 900))

        var y: CGFloat = 880

        // スタイル名
        y = addSectionHeader("Style Name", at: y)
        nameField = NSTextField(frame: NSRect(x: 20, y: y - 22, width: 340, height: 22))
        nameField.placeholderString = "Style Name"
        nameField.target = self
        nameField.action = #selector(nameFieldChanged(_:))
        editorContentView.addSubview(nameField)
        y -= 32

        // ショートカット
        let shortcutLabel = NSTextField(labelWithString: "Shortcut:")
        shortcutLabel.frame = NSRect(x: 20, y: y - 22, width: 64, height: 22)
        shortcutLabel.font = .systemFont(ofSize: 12)
        editorContentView.addSubview(shortcutLabel)

        modifierControlCheckBox = NSButton(checkboxWithTitle: "⌃", target: self, action: #selector(modifierChanged(_:)))
        modifierControlCheckBox.frame = NSRect(x: 86, y: y - 22, width: 36, height: 22)
        modifierControlCheckBox.font = .systemFont(ofSize: 12)
        editorContentView.addSubview(modifierControlCheckBox)

        modifierOptionCheckBox = NSButton(checkboxWithTitle: "⌥", target: self, action: #selector(modifierChanged(_:)))
        modifierOptionCheckBox.frame = NSRect(x: 122, y: y - 22, width: 36, height: 22)
        modifierOptionCheckBox.font = .systemFont(ofSize: 12)
        editorContentView.addSubview(modifierOptionCheckBox)

        modifierShiftCheckBox = NSButton(checkboxWithTitle: "⇧", target: self, action: #selector(modifierChanged(_:)))
        modifierShiftCheckBox.frame = NSRect(x: 158, y: y - 22, width: 36, height: 22)
        modifierShiftCheckBox.font = .systemFont(ofSize: 12)
        editorContentView.addSubview(modifierShiftCheckBox)

        modifierCommandCheckBox = NSButton(checkboxWithTitle: "⌘", target: self, action: #selector(modifierChanged(_:)))
        modifierCommandCheckBox.frame = NSRect(x: 194, y: y - 22, width: 36, height: 22)
        modifierCommandCheckBox.font = .systemFont(ofSize: 12)
        editorContentView.addSubview(modifierCommandCheckBox)

        keyEquivalentField = NSTextField(frame: NSRect(x: 236, y: y - 22, width: 40, height: 22))
        keyEquivalentField.placeholderString = ""
        keyEquivalentField.alignment = .center
        keyEquivalentField.target = self
        keyEquivalentField.action = #selector(keyEquivalentFieldChanged(_:))
        editorContentView.addSubview(keyEquivalentField)
        y -= 32

        // プレビュー
        y = addSectionHeader("Preview", at: y)
        let previewScroll = NSScrollView(frame: NSRect(x: 20, y: y - 60, width: 340, height: 60))
        previewScroll.hasVerticalScroller = false
        previewScroll.borderType = .bezelBorder
        previewTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 340, height: 60))
        previewTextView.isEditable = false
        previewTextView.isSelectable = false
        previewTextView.string = "The quick brown fox jumps over the lazy dog. 素早い茶色の狐が怠けた犬を飛び越える。"
        previewScroll.documentView = previewTextView
        editorContentView.addSubview(previewScroll)
        y -= 80

        // ── 文字属性 ──
        y = addSectionHeader("Character Attributes", at: y)

        // Font Family
        (fontFamilyCheckBox, fontFamilyPopUp, y) = addPopUpRow(
            "Font Family", at: y, tag: 100
        )
        populateFontFamilyPopUp()

        // Font Size
        let sizeRow: NSView
        (fontSizeCheckBox, sizeRow, y) = addCheckBoxWithCustomView("Font Size", at: y, tag: 101)
        fontSizeField = NSTextField(frame: NSRect(x: 0, y: 0, width: 60, height: 22))
        fontSizeField.formatter = createNumberFormatter(min: 1, max: 999, decimals: 1)
        fontSizeField.tag = 101
        fontSizeField.target = self
        fontSizeField.action = #selector(attributeFieldChanged(_:))
        sizeRow.addSubview(fontSizeField)
        fontSizeStepper = NSStepper(frame: NSRect(x: 64, y: 0, width: 19, height: 22))
        fontSizeStepper.minValue = 1
        fontSizeStepper.maxValue = 999
        fontSizeStepper.increment = 0.5
        fontSizeStepper.valueWraps = false
        fontSizeStepper.target = self
        fontSizeStepper.action = #selector(fontSizeStepperChanged(_:))
        sizeRow.addSubview(fontSizeStepper)
        let sizeUnitLabel = NSTextField(labelWithString: "pt")
        sizeUnitLabel.frame = NSRect(x: 87, y: 0, width: 30, height: 22)
        sizeUnitLabel.font = .systemFont(ofSize: 11)
        sizeUnitLabel.textColor = .secondaryLabelColor
        sizeRow.addSubview(sizeUnitLabel)

        // Font Weight
        (fontWeightCheckBox, fontWeightPopUp, y) = addPopUpRow(
            "Font Weight", at: y, tag: 102
        )
        for weight in FontWeight.allCases {
            fontWeightPopUp.addItem(withTitle: weight.displayName)
            fontWeightPopUp.lastItem?.representedObject = weight
        }

        // Italic
        (isItalicCheckBox, _, y) = addSimpleCheckBoxRow("Italic", at: y, tag: 103)

        y -= 10

        // Foreground Color
        (foregroundColorCheckBox, foregroundColorWell, y) = addColorRow(
            "Text Color", at: y, tag: 110
        )

        // Background Color
        (backgroundColorCheckBox, backgroundColorWell, y) = addColorRow(
            "Background Color", at: y, tag: 111
        )

        y -= 10

        // Underline Style
        (underlineStyleCheckBox, underlineStylePopUp, y) = addPopUpRow(
            "Underline", at: y, tag: 120
        )
        for style in UnderlineStyle.allCases {
            underlineStylePopUp.addItem(withTitle: style.displayName)
            underlineStylePopUp.lastItem?.representedObject = style
        }

        // Underline Color
        (underlineColorCheckBox, underlineColorWell, y) = addColorRow(
            "Underline Color", at: y, tag: 121
        )

        // Strikethrough Style
        (strikethroughStyleCheckBox, strikethroughStylePopUp, y) = addPopUpRow(
            "Strikethrough", at: y, tag: 122
        )
        for style in UnderlineStyle.allCases {
            strikethroughStylePopUp.addItem(withTitle: style.displayName)
            strikethroughStylePopUp.lastItem?.representedObject = style
        }

        // Strikethrough Color
        (strikethroughColorCheckBox, strikethroughColorWell, y) = addColorRow(
            "Strikethrough Color", at: y, tag: 123
        )

        y -= 10

        // Baseline Offset
        (baselineOffsetCheckBox, baselineOffsetField, y) = addTextFieldRow(
            "Baseline Offset", at: y, tag: 130,
            formatter: createNumberFormatter(min: -100, max: 100, decimals: 1),
            unit: "pt"
        )

        // Kern
        (kernCheckBox, kernField, y) = addTextFieldRow(
            "Kerning", at: y, tag: 131,
            formatter: createNumberFormatter(min: -100, max: 100, decimals: 1),
            unit: "pt"
        )

        // Superscript
        (superscriptCheckBox, superscriptPopUp, y) = addPopUpRow(
            "Superscript", at: y, tag: 132
        )
        superscriptPopUp.addItem(withTitle: "Superscript")
        superscriptPopUp.lastItem?.tag = 1
        superscriptPopUp.addItem(withTitle: "Subscript")
        superscriptPopUp.lastItem?.tag = -1

        // Ligature
        (ligatureCheckBox, ligaturePopUp, y) = addPopUpRow(
            "Ligature", at: y, tag: 133
        )
        ligaturePopUp.addItem(withTitle: "No Ligature")
        ligaturePopUp.lastItem?.tag = 0
        ligaturePopUp.addItem(withTitle: "Default Ligature")
        ligaturePopUp.lastItem?.tag = 1

        y -= 16

        // ── 段落属性 ──
        y = addSectionHeader("Paragraph Attributes", at: y)

        // Alignment
        (alignmentCheckBox, alignmentPopUp, y) = addPopUpRow(
            "Alignment", at: y, tag: 200
        )
        for alignment in TextAlignment.allCases {
            alignmentPopUp.addItem(withTitle: alignment.displayName)
            alignmentPopUp.lastItem?.representedObject = alignment
        }

        // Line Spacing
        (lineSpacingCheckBox, lineSpacingField, y) = addTextFieldRow(
            "Line Spacing", at: y, tag: 201,
            formatter: createNumberFormatter(min: 0, max: 999, decimals: 1),
            unit: "pt"
        )

        // Paragraph Spacing
        (paragraphSpacingCheckBox, paragraphSpacingField, y) = addTextFieldRow(
            "Paragraph Spacing", at: y, tag: 202,
            formatter: createNumberFormatter(min: 0, max: 999, decimals: 1),
            unit: "pt"
        )

        // Paragraph Spacing Before
        (paragraphSpacingBeforeCheckBox, paragraphSpacingBeforeField, y) = addTextFieldRow(
            "Spacing Before", at: y, tag: 203,
            formatter: createNumberFormatter(min: 0, max: 999, decimals: 1),
            unit: "pt"
        )

        // Head Indent
        (headIndentCheckBox, headIndentField, y) = addTextFieldRow(
            "Head Indent", at: y, tag: 204,
            formatter: createNumberFormatter(min: 0, max: 999, decimals: 1),
            unit: "pt"
        )

        // Tail Indent
        (tailIndentCheckBox, tailIndentField, y) = addTextFieldRow(
            "Tail Indent", at: y, tag: 205,
            formatter: createNumberFormatter(min: -999, max: 999, decimals: 1),
            unit: "pt"
        )

        // First Line Head Indent
        (firstLineHeadIndentCheckBox, firstLineHeadIndentField, y) = addTextFieldRow(
            "First Line Indent", at: y, tag: 206,
            formatter: createNumberFormatter(min: 0, max: 999, decimals: 1),
            unit: "pt"
        )

        // Line Height Multiple
        (lineHeightMultipleCheckBox, lineHeightMultipleComboBox, y) = addComboBoxRow(
            "Line Height Multiple", at: y, tag: 207,
            items: ["0.8", "0.9", "1.0", "1.1", "1.2", "1.3", "1.4", "1.5", "1.6", "1.8", "2.0", "2.5", "3.0"],
            unit: "×"
        )

        // Hyphenation Factor
        (hyphenationFactorCheckBox, hyphenationFactorField, y) = addTextFieldRow(
            "Hyphenation", at: y, tag: 208,
            formatter: createNumberFormatter(min: 0, max: 1, decimals: 2)
        )

        // コンテンツビューのサイズを調整
        let contentHeight = 900 - y + 20
        editorContentView.frame = NSRect(x: 0, y: 0, width: 380, height: contentHeight)

        // すべてのサブビューのY座標を調整（下に詰める）
        let offset = contentHeight - 900
        for subview in editorContentView.subviews {
            var frame = subview.frame
            frame.origin.y += offset
            subview.frame = frame
        }

        editorScrollView.documentView = editorContentView
        container.addSubview(editorScrollView)

        return container
    }

    // MARK: - UI Helper Methods

    @discardableResult
    private func addSectionHeader(_ title: String, at y: CGFloat) -> CGFloat {
        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: 8, y: y - 18, width: 360, height: 18)
        label.font = .boldSystemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        editorContentView.addSubview(label)

        let separator = NSBox(frame: NSRect(x: 8, y: y - 22, width: 360, height: 1))
        separator.boxType = .separator
        editorContentView.addSubview(separator)

        return y - 30
    }

    /// チェックボックス + ポップアップメニューの行を追加
    private func addPopUpRow(_ title: String, at y: CGFloat, tag: Int) -> (NSButton, NSPopUpButton, CGFloat) {
        let checkBox = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkBoxChanged(_:)))
        checkBox.frame = NSRect(x: 20, y: y - 22, width: 150, height: 22)
        checkBox.tag = tag
        checkBox.font = .systemFont(ofSize: 12)
        editorContentView.addSubview(checkBox)

        let popUp = NSPopUpButton(frame: NSRect(x: 170, y: y - 22, width: 180, height: 22), pullsDown: false)
        popUp.font = .systemFont(ofSize: 12)
        popUp.isEnabled = false
        popUp.target = self
        popUp.action = #selector(attributePopUpChanged(_:))
        popUp.tag = tag
        editorContentView.addSubview(popUp)

        return (checkBox, popUp, y - 28)
    }

    /// チェックボックス + テキストフィールドの行を追加
    private func addTextFieldRow(_ title: String, at y: CGFloat, tag: Int, formatter: NumberFormatter?, unit: String? = nil) -> (NSButton, NSTextField, CGFloat) {
        let checkBox = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkBoxChanged(_:)))
        checkBox.frame = NSRect(x: 20, y: y - 22, width: 150, height: 22)
        checkBox.tag = tag
        checkBox.font = .systemFont(ofSize: 12)
        editorContentView.addSubview(checkBox)

        let field = NSTextField(frame: NSRect(x: 170, y: y - 22, width: 80, height: 22))
        field.formatter = formatter
        field.isEnabled = false
        field.target = self
        field.action = #selector(attributeFieldChanged(_:))
        field.tag = tag
        editorContentView.addSubview(field)

        if let unit = unit {
            let unitLabel = NSTextField(labelWithString: unit)
            unitLabel.frame = NSRect(x: 254, y: y - 22, width: 40, height: 22)
            unitLabel.font = .systemFont(ofSize: 11)
            unitLabel.textColor = .secondaryLabelColor
            editorContentView.addSubview(unitLabel)
        }

        return (checkBox, field, y - 28)
    }

    /// チェックボックス + コンボボックスの行を追加（プリセット値のリスト付きで自由入力も可能）
    private func addComboBoxRow(_ title: String, at y: CGFloat, tag: Int, items: [String], unit: String? = nil) -> (NSButton, NSComboBox, CGFloat) {
        let checkBox = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkBoxChanged(_:)))
        checkBox.frame = NSRect(x: 20, y: y - 22, width: 150, height: 22)
        checkBox.tag = tag
        checkBox.font = .systemFont(ofSize: 12)
        editorContentView.addSubview(checkBox)

        let comboBox = NSComboBox(frame: NSRect(x: 170, y: y - 22, width: 80, height: 22))
        comboBox.isEditable = true
        comboBox.completes = true
        comboBox.numberOfVisibleItems = 10
        comboBox.isEnabled = false
        comboBox.font = .systemFont(ofSize: 12)
        comboBox.delegate = self
        comboBox.target = self
        comboBox.action = #selector(comboBoxChanged(_:))
        comboBox.tag = tag
        for item in items {
            comboBox.addItem(withObjectValue: item)
        }
        editorContentView.addSubview(comboBox)

        if let unit = unit {
            let unitLabel = NSTextField(labelWithString: unit)
            unitLabel.frame = NSRect(x: 254, y: y - 22, width: 40, height: 22)
            unitLabel.font = .systemFont(ofSize: 11)
            unitLabel.textColor = .secondaryLabelColor
            editorContentView.addSubview(unitLabel)
        }

        return (checkBox, comboBox, y - 28)
    }

    /// チェックボックス + カラーウェルの行を追加
    private func addColorRow(_ title: String, at y: CGFloat, tag: Int) -> (NSButton, NSColorWell, CGFloat) {
        let checkBox = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkBoxChanged(_:)))
        checkBox.frame = NSRect(x: 20, y: y - 22, width: 150, height: 22)
        checkBox.tag = tag
        checkBox.font = .systemFont(ofSize: 12)
        editorContentView.addSubview(checkBox)

        let colorWell = NSColorWell(frame: NSRect(x: 170, y: y - 22, width: 44, height: 22))
        colorWell.isEnabled = false
        colorWell.target = self
        colorWell.action = #selector(colorWellChanged(_:))
        colorWell.tag = tag
        editorContentView.addSubview(colorWell)

        return (checkBox, colorWell, y - 28)
    }

    /// チェックボックスのみの行（Italic など）
    private func addSimpleCheckBoxRow(_ title: String, at y: CGFloat, tag: Int) -> (NSButton, NSButton?, CGFloat) {
        let checkBox = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkBoxChanged(_:)))
        checkBox.frame = NSRect(x: 20, y: y - 22, width: 150, height: 22)
        checkBox.tag = tag
        checkBox.font = .systemFont(ofSize: 12)
        editorContentView.addSubview(checkBox)

        return (checkBox, nil, y - 28)
    }

    /// チェックボックス + カスタムビューの行
    private func addCheckBoxWithCustomView(_ title: String, at y: CGFloat, tag: Int) -> (NSButton, NSView, CGFloat) {
        let checkBox = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkBoxChanged(_:)))
        checkBox.frame = NSRect(x: 20, y: y - 22, width: 150, height: 22)
        checkBox.tag = tag
        checkBox.font = .systemFont(ofSize: 12)
        editorContentView.addSubview(checkBox)

        let customView = NSView(frame: NSRect(x: 170, y: y - 22, width: 180, height: 22))
        editorContentView.addSubview(customView)

        return (checkBox, customView, y - 28)
    }

    private func createNumberFormatter(min: Double, max: Double, decimals: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = NSNumber(value: min)
        formatter.maximum = NSNumber(value: max)
        formatter.maximumFractionDigits = decimals
        formatter.minimumFractionDigits = 0
        formatter.allowsFloats = true
        formatter.isLenient = true
        return formatter
    }

    private func populateFontFamilyPopUp() {
        fontFamilyPopUp.removeAllItems()
        let families = NSFontManager.shared.availableFontFamilies.sorted()
        for family in families {
            fontFamilyPopUp.addItem(withTitle: family)
        }
    }

    // MARK: - Selection

    private func selectStyle(at index: Int) {
        guard index >= 0 && index < styleManager.styles.count else { return }
        selectedStyleIndex = index
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        updateEditorForSelection()
    }

    private var selectedStyle: TextStyle? {
        guard selectedStyleIndex >= 0 && selectedStyleIndex < styleManager.styles.count else { return nil }
        return styleManager.styles[selectedStyleIndex]
    }

    // MARK: - Update Editor UI

    private func updateEditorForSelection() {
        isUpdatingUI = true
        defer { isUpdatingUI = false }

        guard let style = selectedStyle else {
            setEditorEnabled(false)
            return
        }

        setEditorEnabled(true)

        nameField.stringValue = style.name
        keyEquivalentField.stringValue = style.keyEquivalent ?? ""

        // 修飾キーチェックボックスを更新
        let modifiers = style.keyEquivalentModifierMask
        modifierCommandCheckBox.state = modifiers.contains(.command) ? .on : .off
        modifierOptionCheckBox.state = modifiers.contains(.option) ? .on : .off
        modifierShiftCheckBox.state = modifiers.contains(.shift) ? .on : .off
        modifierControlCheckBox.state = modifiers.contains(.control) ? .on : .off
        modifierCommandCheckBox.isEnabled = true
        modifierOptionCheckBox.isEnabled = true
        modifierShiftCheckBox.isEnabled = true
        modifierControlCheckBox.isEnabled = true

        // ビルトインスタイルの場合、名前変更不可
        nameField.isEditable = !style.isBuiltIn
        removeButton.isEnabled = !style.isBuiltIn
        revertButton.isEnabled = style.isBuiltIn

        // 文字属性
        updateCheckBoxAndControl(fontFamilyCheckBox, control: fontFamilyPopUp, hasValue: style.fontFamily != nil)
        if let family = style.fontFamily {
            fontFamilyPopUp.selectItem(withTitle: family)
        }

        updateCheckBoxAndControl(fontSizeCheckBox, control: fontSizeField, hasValue: style.fontSize != nil)
        fontSizeStepper.isEnabled = style.fontSize != nil
        if let size = style.fontSize {
            fontSizeField.doubleValue = Double(size)
            fontSizeStepper.doubleValue = Double(size)
        }

        updateCheckBoxAndControl(fontWeightCheckBox, control: fontWeightPopUp, hasValue: style.fontWeight != nil)
        if let weight = style.fontWeight {
            for (index, item) in fontWeightPopUp.itemArray.enumerated() {
                if let w = item.representedObject as? FontWeight, w == weight {
                    fontWeightPopUp.selectItem(at: index)
                    break
                }
            }
        }

        // Italic: チェックボックスのみ（3ステート: OFF=無効, mixed=適用しない, ON=italic適用）
        updateItalicCheckBox(style.isItalic)

        updateCheckBoxAndControl(foregroundColorCheckBox, control: foregroundColorWell, hasValue: style.foregroundColor != nil)
        if let color = style.foregroundColor { foregroundColorWell.color = color.nsColor }

        updateCheckBoxAndControl(backgroundColorCheckBox, control: backgroundColorWell, hasValue: style.backgroundColor != nil)
        if let color = style.backgroundColor { backgroundColorWell.color = color.nsColor }

        updateCheckBoxAndControl(underlineStyleCheckBox, control: underlineStylePopUp, hasValue: style.underlineStyle != nil)
        if let us = style.underlineStyle {
            for (index, item) in underlineStylePopUp.itemArray.enumerated() {
                if let s = item.representedObject as? UnderlineStyle, s == us {
                    underlineStylePopUp.selectItem(at: index)
                    break
                }
            }
        }

        updateCheckBoxAndControl(underlineColorCheckBox, control: underlineColorWell, hasValue: style.underlineColor != nil)
        if let color = style.underlineColor { underlineColorWell.color = color.nsColor }

        updateCheckBoxAndControl(strikethroughStyleCheckBox, control: strikethroughStylePopUp, hasValue: style.strikethroughStyle != nil)
        if let ss = style.strikethroughStyle {
            for (index, item) in strikethroughStylePopUp.itemArray.enumerated() {
                if let s = item.representedObject as? UnderlineStyle, s == ss {
                    strikethroughStylePopUp.selectItem(at: index)
                    break
                }
            }
        }

        updateCheckBoxAndControl(strikethroughColorCheckBox, control: strikethroughColorWell, hasValue: style.strikethroughColor != nil)
        if let color = style.strikethroughColor { strikethroughColorWell.color = color.nsColor }

        updateCheckBoxAndControl(baselineOffsetCheckBox, control: baselineOffsetField, hasValue: style.baselineOffset != nil)
        if let offset = style.baselineOffset { baselineOffsetField.doubleValue = Double(offset) }

        updateCheckBoxAndControl(kernCheckBox, control: kernField, hasValue: style.kern != nil)
        if let k = style.kern { kernField.doubleValue = Double(k) }

        updateCheckBoxAndControl(superscriptCheckBox, control: superscriptPopUp, hasValue: style.superscript != nil)
        if let sup = style.superscript {
            superscriptPopUp.selectItem(withTag: sup)
        }

        updateCheckBoxAndControl(ligatureCheckBox, control: ligaturePopUp, hasValue: style.ligature != nil)
        if let lig = style.ligature {
            ligaturePopUp.selectItem(withTag: lig)
        }

        // 段落属性
        updateCheckBoxAndControl(alignmentCheckBox, control: alignmentPopUp, hasValue: style.alignment != nil)
        if let alignment = style.alignment {
            for (index, item) in alignmentPopUp.itemArray.enumerated() {
                if let a = item.representedObject as? TextAlignment, a == alignment {
                    alignmentPopUp.selectItem(at: index)
                    break
                }
            }
        }

        updateCheckBoxAndControl(lineSpacingCheckBox, control: lineSpacingField, hasValue: style.lineSpacing != nil)
        if let s = style.lineSpacing { lineSpacingField.doubleValue = Double(s) }

        updateCheckBoxAndControl(paragraphSpacingCheckBox, control: paragraphSpacingField, hasValue: style.paragraphSpacing != nil)
        if let s = style.paragraphSpacing { paragraphSpacingField.doubleValue = Double(s) }

        updateCheckBoxAndControl(paragraphSpacingBeforeCheckBox, control: paragraphSpacingBeforeField, hasValue: style.paragraphSpacingBefore != nil)
        if let s = style.paragraphSpacingBefore { paragraphSpacingBeforeField.doubleValue = Double(s) }

        updateCheckBoxAndControl(headIndentCheckBox, control: headIndentField, hasValue: style.headIndent != nil)
        if let i = style.headIndent { headIndentField.doubleValue = Double(i) }

        updateCheckBoxAndControl(tailIndentCheckBox, control: tailIndentField, hasValue: style.tailIndent != nil)
        if let i = style.tailIndent { tailIndentField.doubleValue = Double(i) }

        updateCheckBoxAndControl(firstLineHeadIndentCheckBox, control: firstLineHeadIndentField, hasValue: style.firstLineHeadIndent != nil)
        if let i = style.firstLineHeadIndent { firstLineHeadIndentField.doubleValue = Double(i) }

        updateCheckBoxAndControl(lineHeightMultipleCheckBox, control: lineHeightMultipleComboBox, hasValue: style.lineHeightMultiple != nil)
        if let m = style.lineHeightMultiple { lineHeightMultipleComboBox.stringValue = String(format: "%.2g", Double(m)) }

        updateCheckBoxAndControl(hyphenationFactorCheckBox, control: hyphenationFactorField, hasValue: style.hyphenationFactor != nil)
        if let h = style.hyphenationFactor { hyphenationFactorField.doubleValue = Double(h) }

        updatePreview()

        // 右パネルを先頭にスクロール
        editorContentView.scroll(NSPoint(x: 0, y: editorContentView.frame.height))
    }

    private func updateCheckBoxAndControl(_ checkBox: NSButton, control: NSView?, hasValue: Bool) {
        checkBox.state = hasValue ? .on : .off
        if let nsControl = control as? NSControl {
            nsControl.isEnabled = hasValue
        }
        if let colorWell = control as? NSColorWell {
            colorWell.isEnabled = hasValue
        }
    }

    private func updateItalicCheckBox(_ isItalic: Bool?) {
        if let italic = isItalic {
            isItalicCheckBox.state = italic ? .on : .mixed
            isItalicCheckBox.allowsMixedState = true
        } else {
            isItalicCheckBox.state = .off
            isItalicCheckBox.allowsMixedState = false
        }
    }

    private func setEditorEnabled(_ enabled: Bool) {
        for subview in editorContentView.subviews {
            if let control = subview as? NSControl {
                control.isEnabled = enabled
            }
        }
    }

    /// スタイルを更新する（通知による再スクロールを防止）
    private func saveStyle(_ style: TextStyle) {
        isSelfEditing = true
        styleManager.updateStyle(style)
        isSelfEditing = false
    }

    // MARK: - Preview

    private func updatePreview() {
        guard let style = selectedStyle else { return }

        let text = "The quick brown fox jumps over the lazy dog. 素早い茶色の狐が怠けた犬を飛び越える。"
        let attrString = NSMutableAttributedString(string: text)

        // デフォルト属性
        let defaultFont = NSFont.systemFont(ofSize: 14)
        attrString.addAttribute(.font, value: defaultFont, range: NSRange(location: 0, length: attrString.length))

        // スタイルを適用
        let attrs = style.attributes()
        attrString.addAttributes(attrs, range: NSRange(location: 0, length: attrString.length))

        previewTextView.textStorage?.setAttributedString(attrString)
    }

    // MARK: - Actions

    @objc private func addStyle(_ sender: Any) {
        let _ = styleManager.addStyle(name: "New Style")
        tableView.reloadData()
        selectStyle(at: styleManager.styles.count - 1)
    }

    @objc private func removeStyle(_ sender: Any) {
        guard selectedStyleIndex >= 0 else { return }
        let style = styleManager.styles[selectedStyleIndex]
        guard !style.isBuiltIn else { return }

        styleManager.deleteStyle(at: selectedStyleIndex)
        tableView.reloadData()

        let newIndex = min(selectedStyleIndex, styleManager.styles.count - 1)
        selectStyle(at: newIndex)
    }

    @objc private func duplicateStyle(_ sender: Any) {
        guard let style = selectedStyle else { return }
        let _ = styleManager.addStyle(name: "\(style.name) Copy", basedOn: style)
        tableView.reloadData()
        selectStyle(at: styleManager.styles.count - 1)
    }

    @objc private func revertStyle(_ sender: Any) {
        guard selectedStyleIndex >= 0 else { return }
        styleManager.revertToDefault(at: selectedStyleIndex)
        tableView.reloadData()
        updateEditorForSelection()
    }

    @objc private func nameFieldChanged(_ sender: NSTextField) {
        guard !isUpdatingUI, selectedStyleIndex >= 0 else { return }
        var style = styleManager.styles[selectedStyleIndex]
        style.name = sender.stringValue
        saveStyle(style)
        tableView.reloadData()
    }

    @objc private func keyEquivalentFieldChanged(_ sender: NSTextField) {
        guard !isUpdatingUI, selectedStyleIndex >= 0 else { return }
        var style = styleManager.styles[selectedStyleIndex]
        let key = sender.stringValue.lowercased()
        style.keyEquivalent = key.isEmpty ? nil : key

        // キーが設定されて修飾キーが未設定なら⌘をデフォルトにする
        if !key.isEmpty && style.keyEquivalentModifierRawValue == nil {
            style.keyEquivalentModifierMask = [.command]
            isUpdatingUI = true
            modifierCommandCheckBox.state = .on
            isUpdatingUI = false
        }

        saveStyle(style)
    }

    @objc private func modifierChanged(_ sender: NSButton) {
        guard !isUpdatingUI, selectedStyleIndex >= 0 else { return }
        var style = styleManager.styles[selectedStyleIndex]

        var modifiers: NSEvent.ModifierFlags = []
        if modifierCommandCheckBox.state == .on { modifiers.insert(.command) }
        if modifierOptionCheckBox.state == .on { modifiers.insert(.option) }
        if modifierShiftCheckBox.state == .on { modifiers.insert(.shift) }
        if modifierControlCheckBox.state == .on { modifiers.insert(.control) }

        style.keyEquivalentModifierMask = modifiers
        saveStyle(style)
    }

    @objc private func checkBoxChanged(_ sender: NSButton) {
        guard !isUpdatingUI, selectedStyleIndex >= 0 else { return }
        var style = styleManager.styles[selectedStyleIndex]
        let enabled = sender.state == .on || sender.state == .mixed

        switch sender.tag {
        case 100: // Font Family
            fontFamilyPopUp.isEnabled = enabled
            style.fontFamily = enabled ? (fontFamilyPopUp.titleOfSelectedItem ?? "Helvetica") : nil
        case 101: // Font Size
            fontSizeField.isEnabled = enabled
            fontSizeStepper.isEnabled = enabled
            style.fontSize = enabled ? CGFloat(fontSizeField.doubleValue > 0 ? fontSizeField.doubleValue : 14) : nil
        case 102: // Font Weight
            fontWeightPopUp.isEnabled = enabled
            if enabled, let weight = fontWeightPopUp.selectedItem?.representedObject as? FontWeight {
                style.fontWeight = weight
            } else {
                style.fontWeight = nil
            }
        case 103: // Italic
            if sender.state == .off {
                style.isItalic = nil
                sender.allowsMixedState = false
            } else if sender.state == .on {
                style.isItalic = true
            } else { // .mixed
                style.isItalic = false
            }
        case 110: // Foreground Color
            foregroundColorWell.isEnabled = enabled
            style.foregroundColor = enabled ? CodableColor(foregroundColorWell.color) : nil
        case 111: // Background Color
            backgroundColorWell.isEnabled = enabled
            style.backgroundColor = enabled ? CodableColor(backgroundColorWell.color) : nil
        case 120: // Underline Style
            underlineStylePopUp.isEnabled = enabled
            if enabled, let us = underlineStylePopUp.selectedItem?.representedObject as? UnderlineStyle {
                style.underlineStyle = us
            } else {
                style.underlineStyle = nil
            }
        case 121: // Underline Color
            underlineColorWell.isEnabled = enabled
            style.underlineColor = enabled ? CodableColor(underlineColorWell.color) : nil
        case 122: // Strikethrough Style
            strikethroughStylePopUp.isEnabled = enabled
            if enabled, let ss = strikethroughStylePopUp.selectedItem?.representedObject as? UnderlineStyle {
                style.strikethroughStyle = ss
            } else {
                style.strikethroughStyle = nil
            }
        case 123: // Strikethrough Color
            strikethroughColorWell.isEnabled = enabled
            style.strikethroughColor = enabled ? CodableColor(strikethroughColorWell.color) : nil
        case 130: // Baseline Offset
            baselineOffsetField.isEnabled = enabled
            style.baselineOffset = enabled ? CGFloat(baselineOffsetField.doubleValue) : nil
        case 131: // Kern
            kernField.isEnabled = enabled
            style.kern = enabled ? CGFloat(kernField.doubleValue) : nil
        case 132: // Superscript
            superscriptPopUp.isEnabled = enabled
            style.superscript = enabled ? superscriptPopUp.selectedTag() : nil
        case 133: // Ligature
            ligaturePopUp.isEnabled = enabled
            style.ligature = enabled ? ligaturePopUp.selectedTag() : nil

        case 200: // Alignment
            alignmentPopUp.isEnabled = enabled
            if enabled, let a = alignmentPopUp.selectedItem?.representedObject as? TextAlignment {
                style.alignment = a
            } else {
                style.alignment = nil
            }
        case 201: // Line Spacing
            lineSpacingField.isEnabled = enabled
            style.lineSpacing = enabled ? CGFloat(lineSpacingField.doubleValue) : nil
        case 202: // Paragraph Spacing
            paragraphSpacingField.isEnabled = enabled
            style.paragraphSpacing = enabled ? CGFloat(paragraphSpacingField.doubleValue) : nil
        case 203: // Paragraph Spacing Before
            paragraphSpacingBeforeField.isEnabled = enabled
            style.paragraphSpacingBefore = enabled ? CGFloat(paragraphSpacingBeforeField.doubleValue) : nil
        case 204: // Head Indent
            headIndentField.isEnabled = enabled
            style.headIndent = enabled ? CGFloat(headIndentField.doubleValue) : nil
        case 205: // Tail Indent
            tailIndentField.isEnabled = enabled
            style.tailIndent = enabled ? CGFloat(tailIndentField.doubleValue) : nil
        case 206: // First Line Head Indent
            firstLineHeadIndentField.isEnabled = enabled
            style.firstLineHeadIndent = enabled ? CGFloat(firstLineHeadIndentField.doubleValue) : nil
        case 207: // Line Height Multiple
            lineHeightMultipleComboBox.isEnabled = enabled
            let comboValue = Double(lineHeightMultipleComboBox.stringValue) ?? 1.0
            style.lineHeightMultiple = enabled ? CGFloat(comboValue > 0 ? comboValue : 1.0) : nil
        case 208: // Hyphenation Factor
            hyphenationFactorField.isEnabled = enabled
            style.hyphenationFactor = enabled ? Float(hyphenationFactorField.doubleValue) : nil
        default:
            break
        }

        saveStyle(style)
        updatePreview()
    }

    @objc private func attributePopUpChanged(_ sender: NSPopUpButton) {
        guard !isUpdatingUI, selectedStyleIndex >= 0 else { return }
        var style = styleManager.styles[selectedStyleIndex]

        switch sender.tag {
        case 100: // Font Family
            style.fontFamily = sender.titleOfSelectedItem
        case 102: // Font Weight
            style.fontWeight = sender.selectedItem?.representedObject as? FontWeight
        case 120: // Underline Style
            style.underlineStyle = sender.selectedItem?.representedObject as? UnderlineStyle
        case 122: // Strikethrough Style
            style.strikethroughStyle = sender.selectedItem?.representedObject as? UnderlineStyle
        case 132: // Superscript
            style.superscript = sender.selectedTag()
        case 133: // Ligature
            style.ligature = sender.selectedTag()
        case 200: // Alignment
            style.alignment = sender.selectedItem?.representedObject as? TextAlignment
        default:
            break
        }

        saveStyle(style)
        updatePreview()
    }

    @objc private func attributeFieldChanged(_ sender: NSTextField) {
        guard !isUpdatingUI, selectedStyleIndex >= 0 else { return }
        var style = styleManager.styles[selectedStyleIndex]

        switch sender.tag {
        case 101: // Font Size
            style.fontSize = CGFloat(sender.doubleValue)
            fontSizeStepper.doubleValue = sender.doubleValue
        case 130: // Baseline Offset
            style.baselineOffset = CGFloat(sender.doubleValue)
        case 131: // Kern
            style.kern = CGFloat(sender.doubleValue)
        case 201: // Line Spacing
            style.lineSpacing = CGFloat(sender.doubleValue)
        case 202: // Paragraph Spacing
            style.paragraphSpacing = CGFloat(sender.doubleValue)
        case 203: // Paragraph Spacing Before
            style.paragraphSpacingBefore = CGFloat(sender.doubleValue)
        case 204: // Head Indent
            style.headIndent = CGFloat(sender.doubleValue)
        case 205: // Tail Indent
            style.tailIndent = CGFloat(sender.doubleValue)
        case 206: // First Line Head Indent
            style.firstLineHeadIndent = CGFloat(sender.doubleValue)
        case 208: // Hyphenation Factor
            style.hyphenationFactor = Float(sender.doubleValue)
        default:
            break
        }

        saveStyle(style)
        updatePreview()
    }

    @objc private func fontSizeStepperChanged(_ sender: NSStepper) {
        guard !isUpdatingUI, selectedStyleIndex >= 0 else { return }
        fontSizeField.doubleValue = sender.doubleValue
        var style = styleManager.styles[selectedStyleIndex]
        style.fontSize = CGFloat(sender.doubleValue)
        saveStyle(style)
        updatePreview()
    }

    @objc private func comboBoxChanged(_ sender: NSComboBox) {
        guard !isUpdatingUI, selectedStyleIndex >= 0 else { return }
        var style = styleManager.styles[selectedStyleIndex]

        switch sender.tag {
        case 207: // Line Height Multiple
            let value = Double(sender.stringValue) ?? 1.0
            style.lineHeightMultiple = CGFloat(value)
        default:
            break
        }

        saveStyle(style)
        updatePreview()
    }

    @objc private func colorWellChanged(_ sender: NSColorWell) {
        guard !isUpdatingUI, selectedStyleIndex >= 0 else { return }
        var style = styleManager.styles[selectedStyleIndex]

        switch sender.tag {
        case 110: // Foreground Color
            style.foregroundColor = CodableColor(sender.color)
        case 111: // Background Color
            style.backgroundColor = CodableColor(sender.color)
        case 121: // Underline Color
            style.underlineColor = CodableColor(sender.color)
        case 123: // Strikethrough Color
            style.strikethroughColor = CodableColor(sender.color)
        default:
            break
        }

        saveStyle(style)
        updatePreview()
    }
}

// MARK: - NSTableViewDataSource

extension StylesPreferencesViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return styleManager.styles.count
    }

    // ドラッグ＆ドロップ並べ替え
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: .string)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if dropOperation == .above {
            return .move
        }
        return []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let item = info.draggingPasteboard.pasteboardItems?.first,
              let rowStr = item.string(forType: .string),
              let sourceRow = Int(rowStr) else { return false }

        styleManager.moveStyle(from: sourceRow, to: row)
        tableView.reloadData()

        // 移動後の選択を更新
        let newIndex: Int
        if sourceRow < row {
            newIndex = row - 1
        } else {
            newIndex = row
        }
        selectStyle(at: newIndex)

        return true
    }
}

// MARK: - NSTableViewDelegate

extension StylesPreferencesViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("StyleCell")
        var cellView = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView

        if cellView == nil {
            cellView = NSTableCellView(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
            cellView?.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.frame = NSRect(x: 4, y: 2, width: 172, height: 20)
            textField.font = .systemFont(ofSize: 13)
            textField.lineBreakMode = .byTruncatingTail
            cellView?.addSubview(textField)
            cellView?.textField = textField
        }

        let style = styleManager.styles[row]
        cellView?.textField?.stringValue = style.name
        cellView?.textField?.textColor = style.isBuiltIn ? .secondaryLabelColor : .labelColor

        return cellView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        selectedStyleIndex = row
        updateEditorForSelection()
    }
}

// MARK: - NSComboBoxDelegate

extension StylesPreferencesViewController: NSComboBoxDelegate {
    func comboBoxSelectionDidChange(_ notification: Notification) {
        guard !isUpdatingUI, selectedStyleIndex >= 0,
              let comboBox = notification.object as? NSComboBox else { return }

        // 選択後、次の RunLoop で stringValue が更新されるため遅延実行
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            var style = self.styleManager.styles[self.selectedStyleIndex]

            switch comboBox.tag {
            case 207: // Line Height Multiple
                let value = Double(comboBox.stringValue) ?? 1.0
                style.lineHeightMultiple = CGFloat(value > 0 ? value : 1.0)
            default:
                break
            }

            self.saveStyle(style)
            self.updatePreview()
        }
    }
}

// MARK: - NSSplitViewDelegate

extension StylesPreferencesViewController: NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return 120
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return splitView.bounds.width - 300
    }

    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        // ウィンドウリサイズ時は右パネルだけ伸縮する
        return view != splitView.subviews.first
    }
}
