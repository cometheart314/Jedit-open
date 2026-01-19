//
//  NewDocumentsPreferencesViewController.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/29.
//

import Cocoa

class NewDocumentsPreferencesViewController: NSViewController {

    // MARK: - IBOutlets

    @IBOutlet weak var presetTableView: NSTableView!
    @IBOutlet weak var addButton: NSButton!
    @IBOutlet weak var removeButton: NSButton!
    @IBOutlet weak var tabView: NSTabView!

    // View Tab
    @IBOutlet weak var windowWidthField: NSTextField!
    @IBOutlet weak var windowHeightField: NSTextField!
    @IBOutlet weak var windowLeftField: NSTextField!
    @IBOutlet weak var windowTopField: NSTextField!
    @IBOutlet weak var scaleField: NSTextField!
    @IBOutlet weak var scalePopup: NSPopUpButton!
    @IBOutlet weak var lineNumberPopup: NSPopUpButton!
    @IBOutlet weak var rulerPopup: NSPopUpButton!
    @IBOutlet weak var showInspectorBarCheckbox: NSButton!
    @IBOutlet weak var showToolBarCheckbox: NSButton!
    @IBOutlet weak var pageModeMatrix: NSMatrix!  // Window/Page mode radio buttons
    @IBOutlet weak var docWidthPopup: NSPopUpButton!

    // Show Invisibles checkboxes
    @IBOutlet weak var invisibleSpaceCheckbox: NSButton!
    @IBOutlet weak var invisibleNonBreakingSpaceCheckbox: NSButton!
    @IBOutlet weak var invisibleKanjiSpaceCheckbox: NSButton!
    @IBOutlet weak var invisibleTabCheckbox: NSButton!
    @IBOutlet weak var invisibleLineSeparatorCheckbox: NSButton!
    @IBOutlet weak var invisibleParagraphBreakCheckbox: NSButton!
    @IBOutlet weak var invisiblePageBreakCheckbox: NSButton!
    @IBOutlet weak var invisibleVerticalTabCheckbox: NSButton!

    // Format Tab
    @IBOutlet weak var newDocNamePopup: NSPopUpButton!
    @IBOutlet weak var textStyleMatrix: NSMatrix!  // Rich Text / Plain Text radio buttons
    @IBOutlet weak var fileExtensionField: NSTextField!  // ファイル拡張子
    @IBOutlet weak var encodingPopup: NSPopUpButton!
    @IBOutlet weak var lineEndingPopup: NSPopUpButton!
    @IBOutlet weak var bomCheckbox: NSButton!
    @IBOutlet weak var editingDirectionMatrix: NSMatrix!  // Horizontal / Vertical radio buttons
    @IBOutlet weak var tabWidthField: NSTextField!
    @IBOutlet weak var tabWidthStepper: NSStepper!  // タブ幅のステッパー
    @IBOutlet weak var tabWidthUnitPopup: NSPopUpButton!  // Points / Spaces 切り替え
    @IBOutlet weak var tabWidthDescriptionLabel: NSTextField!  // タブ幅の説明ラベル
    @IBOutlet weak var interLineSpacingField: NSTextField!  // 行間
    @IBOutlet weak var interLineSpacingStepper: NSStepper!
    @IBOutlet weak var paragraphSpacingBeforeField: NSTextField!  // 段落前
    @IBOutlet weak var paragraphSpacingBeforeStepper: NSStepper!
    @IBOutlet weak var paragraphSpacingAfterField: NSTextField!  // 段落後
    @IBOutlet weak var paragraphSpacingAfterStepper: NSStepper!
    @IBOutlet weak var autoIndentCheckbox: NSButton!
    @IBOutlet weak var indentWrappedLinesCheckbox: NSButton!  // Indent wrapped lines チェックボックス
    @IBOutlet weak var wrappedLineIndentField: NSTextField!  // Indent wrapped lines 数値フィールド
    @IBOutlet weak var wordWrapPopup: NSPopUpButton!
    @IBOutlet weak var targetSizeTypePopup: NSPopUpButton!  // Target Size Type ポップアップ
    @IBOutlet weak var targetSizeLowerLimitField: NSTextField!  // Target Size Lower limit
    @IBOutlet weak var targetSizeUpperLimitField: NSTextField!  // Target Size Upper limit

    // Font & Colors Tab
    @IBOutlet weak var baseFontLabel: NSTextField!  // フォント名とサイズを表示
    @IBOutlet weak var changeFontButton: NSButton!
    @IBOutlet weak var themePopupButton: JOThemeColorPopupButton!  // テーマ選択
    @IBOutlet weak var textColorWell: NSColorWell!
    @IBOutlet weak var backgroundColorWell: NSColorWell!
    @IBOutlet weak var invisibleColorWell: NSColorWell!
    @IBOutlet weak var caretColorWell: NSColorWell!
    @IBOutlet weak var highlightColorWell: NSColorWell!
    @IBOutlet weak var lineNumberColorWell: NSColorWell!
    @IBOutlet weak var headerColorWell: NSColorWell!
    @IBOutlet weak var footerColorWell: NSColorWell!
    @IBOutlet weak var lineNumberBackgroundColorWell: NSColorWell!

    // フォント設定用のプロパティ
    private var currentBaseFontName: String = NSFont.systemFont(ofSize: 14).fontName
    private var currentBaseFontSize: CGFloat = 14

    // Page Layout Tab
    @IBOutlet weak var topMarginField: NSTextField!
    @IBOutlet weak var leftMarginField: NSTextField!
    @IBOutlet weak var rightMarginField: NSTextField!
    @IBOutlet weak var bottomMarginField: NSTextField!
    @IBOutlet weak var marginUnitPopup: NSPopUpButton!

    // Header/Footer Tab
    @IBOutlet weak var headerTextView: NSTextView!
    @IBOutlet weak var footerTextView: NSTextView!

    // Properties Tab
    @IBOutlet weak var authorField: NSTextField!
    @IBOutlet weak var companyField: NSTextField!
    @IBOutlet weak var copyrightField: NSTextField!

    // MARK: - Properties

    private let presetManager = DocumentPresetManager.shared
    private var selectedPresetIndex: Int = 0

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTableView()
        setupUI()
        selectInitialPreset()
    }

    // MARK: - Setup

    private func setupTableView() {
        presetTableView?.delegate = self
        presetTableView?.dataSource = self
        presetTableView?.doubleAction = #selector(tableViewDoubleClicked(_:))
        presetTableView?.target = self
    }

    private func setupUI() {
        updateRemoveButtonState()
        setupScaleMenu()
        setupDocWidthMenu()
        setupEncodingPopup()
    }

    private func setupEncodingPopup() {
        // encodingPopupにエンコーディング一覧を設定（カスタマイズ項目付き）
        guard let popup = encodingPopup else { return }
        EncodingManager.shared.setupPopUp(
            popup,
            selectedEncoding: .utf8,
            withDefaultEntry: false,
            includeCustomizeItem: true,
            target: self,
            action: #selector(customizeEncodingList(_:))
        )

        // エンコーディングリスト変更通知を監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(encodingsListDidChange(_:)),
            name: .encodingsListChanged,
            object: nil
        )
    }

    @objc private func customizeEncodingList(_ sender: Any) {
        // カスタマイズパネルを表示
        EncodingCustomizeWindowController.showPanel()

        // 元のエンコーディングを再選択（「カスタマイズ...」項目が選択されたままにならないように）
        if let preset = presetManager.preset(at: selectedPresetIndex) {
            encodingPopup?.selectItem(withTag: Int(preset.data.format.textEncoding))
        }
    }

    @objc private func encodingsListDidChange(_ notification: Notification) {
        // エンコーディングリストが変更されたらポップアップを再構築
        guard let popup = encodingPopup,
              let preset = presetManager.preset(at: selectedPresetIndex) else { return }

        let currentEncoding = String.Encoding(rawValue: preset.data.format.textEncoding)
        EncodingManager.shared.setupPopUp(
            popup,
            selectedEncoding: currentEncoding,
            withDefaultEntry: false,
            includeCustomizeItem: true,
            target: self,
            action: #selector(customizeEncodingList(_:))
        )
    }

    private func setupScaleMenu() {
        // scalePopupのメニューにScaleMenuを設定
        if let scaleMenu = scalePopup?.menu as? ScaleMenu {
            scaleMenu.scaleMenuDelegate = self
            scaleMenu.setParentView(self.view)
        }
    }

    private func setupDocWidthMenu() {
        // docWidthPopupのメニューにFixedDocWidthMenuを設定
        if let docWidthMenu = docWidthPopup?.menu as? FixedDocWidthMenu {
            docWidthMenu.fixedDocWidthMenuDelegate = self
            docWidthMenu.setParentView(self.view)
        }
    }

    private func selectInitialPreset() {
        // 保存されている選択を復元
        if let selectedID = presetManager.selectedPresetID,
           let index = presetManager.presets.firstIndex(where: { $0.id == selectedID }) {
            selectedPresetIndex = index
            presetTableView?.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else {
            selectedPresetIndex = 0
            presetTableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        loadSelectedPreset()
    }

    private func updateRemoveButtonState() {
        guard let preset = presetManager.preset(at: selectedPresetIndex) else {
            removeButton?.isEnabled = false
            return
        }
        // ビルトインプリセットは削除不可
        removeButton?.isEnabled = !preset.isBuiltIn
    }

    // MARK: - Load/Save Preset Data

    private func loadSelectedPreset() {
        guard let preset = presetManager.preset(at: selectedPresetIndex) else { return }
        let data = preset.data

        // View Tab
        windowWidthField?.doubleValue = Double(data.view.windowWidth)
        windowHeightField?.doubleValue = Double(data.view.windowHeight)
        windowLeftField?.doubleValue = Double(data.view.windowX)
        windowTopField?.doubleValue = Double(data.view.windowY)

        // スケールの選択（動的メニューのためタイトルで選択）
        // scaleが0の場合（古いデータ）はデフォルト値100を使用
        var scalePercent = Int(data.view.scale * 100)
        if scalePercent == 0 {
            scalePercent = 100
        }
        scaleField?.stringValue = "\(scalePercent)%"
        if let scaleMenu = scalePopup?.menu as? ScaleMenu {
            // メニューにスケールが存在しない場合は追加
            scaleMenu.adjustMenu(for: scalePercent)
        }
        scalePopup?.selectItem(withTitle: "\(scalePercent)%")

        lineNumberPopup?.selectItem(withTag: data.view.lineNumberType.rawValue)
        rulerPopup?.selectItem(withTag: data.view.rulerType.rawValue)
        showInspectorBarCheckbox?.state = data.view.showInspectorBar ? .on : .off
        showToolBarCheckbox?.state = data.view.showToolBar ? .on : .off
        // Page Mode Matrix: tag 0 = Window, tag 1 = Page
        pageModeMatrix?.selectCell(withTag: data.view.pageMode ? 1 : 0)
        docWidthPopup?.selectItem(withTag: data.view.docWidthType.rawValue)

        // Show Invisibles checkboxes
        invisibleSpaceCheckbox?.state = data.view.showInvisibles.space ? .on : .off
        invisibleNonBreakingSpaceCheckbox?.state = data.view.showInvisibles.nonBreakingSpace ? .on : .off
        invisibleKanjiSpaceCheckbox?.state = data.view.showInvisibles.kanjiSpace ? .on : .off
        invisibleTabCheckbox?.state = data.view.showInvisibles.tab ? .on : .off
        invisibleLineSeparatorCheckbox?.state = data.view.showInvisibles.lineSeparator ? .on : .off
        invisibleParagraphBreakCheckbox?.state = data.view.showInvisibles.paragraphBreak ? .on : .off
        invisiblePageBreakCheckbox?.state = data.view.showInvisibles.pageBreak ? .on : .off
        invisibleVerticalTabCheckbox?.state = data.view.showInvisibles.verticalTab ? .on : .off

        // Format Tab
        newDocNamePopup?.selectItem(withTag: data.format.newDocNameType.rawValue)
        // Text Style Matrix: tag 1 = Rich Text, tag 0 = Plain Text
        textStyleMatrix?.selectCell(withTag: data.format.richText ? 1 : 0)
        fileExtensionField?.stringValue = data.format.fileExtension
        // Encoding - tag is the encoding's rawValue
        encodingPopup?.selectItem(withTag: Int(data.format.textEncoding))
        lineEndingPopup?.selectItem(withTag: data.format.lineEndingType.rawValue)
        bomCheckbox?.state = data.format.bom ? .on : .off
        // Editing Direction: tag 0 = Horizontal (Left to Right), tag 1 = Vertical (Right to Left)
        editingDirectionMatrix?.selectCell(withTag: data.format.editingDirection.rawValue)
        // Tab Width: updateTabWidthDisplay() は Font & Colors を読み込んだ後に呼ぶ
        // Line/Paragraph Spacing
        interLineSpacingField?.doubleValue = Double(data.format.interLineSpacing)
        interLineSpacingStepper?.doubleValue = Double(data.format.interLineSpacing)
        interLineSpacingStepper?.increment = 1
        paragraphSpacingBeforeField?.doubleValue = Double(data.format.paragraphSpacingBefore)
        paragraphSpacingBeforeStepper?.doubleValue = Double(data.format.paragraphSpacingBefore)
        paragraphSpacingBeforeStepper?.increment = 1
        paragraphSpacingAfterField?.doubleValue = Double(data.format.paragraphSpacingAfter)
        paragraphSpacingAfterStepper?.doubleValue = Double(data.format.paragraphSpacingAfter)
        paragraphSpacingAfterStepper?.increment = 1
        autoIndentCheckbox?.state = data.format.autoIndent ? .on : .off
        indentWrappedLinesCheckbox?.state = data.format.indentWrappedLines ? .on : .off
        wrappedLineIndentField?.doubleValue = Double(data.format.wrappedLineIndent)
        wordWrapPopup?.selectItem(withTag: data.format.wordWrappingType.rawValue)
        targetSizeTypePopup?.selectItem(withTag: data.format.targetSizeType.rawValue)
        targetSizeLowerLimitField?.integerValue = data.format.minTargetSize
        targetSizeUpperLimitField?.integerValue = data.format.maxTargetSize

        // Font & Colors Tab
        currentBaseFontName = data.fontAndColors.baseFontName
        currentBaseFontSize = data.fontAndColors.baseFontSize
        updateBaseFontLabel()
        // Tab Width の表示を更新（Font設定を読み込んだ後に行う）
        updateTabWidthDisplay()
        // 9色のカラーウェルを読み込み
        textColorWell?.color = data.fontAndColors.colors.character.nsColor
        backgroundColorWell?.color = data.fontAndColors.colors.background.nsColor
        invisibleColorWell?.color = data.fontAndColors.colors.invisible.nsColor
        caretColorWell?.color = data.fontAndColors.colors.caret.nsColor
        highlightColorWell?.color = data.fontAndColors.colors.highlight.nsColor
        lineNumberColorWell?.color = data.fontAndColors.colors.lineNumber.nsColor
        headerColorWell?.color = data.fontAndColors.colors.header.nsColor
        footerColorWell?.color = data.fontAndColors.colors.footer.nsColor
        lineNumberBackgroundColorWell?.color = data.fontAndColors.colors.lineNumberBackground.nsColor

        // Page Layout Tab
        topMarginField?.doubleValue = Double(data.pageLayout.topMargin)
        leftMarginField?.doubleValue = Double(data.pageLayout.leftMargin)
        rightMarginField?.doubleValue = Double(data.pageLayout.rightMargin)
        bottomMarginField?.doubleValue = Double(data.pageLayout.bottomMargin)
        marginUnitPopup?.selectItem(withTag: data.pageLayout.marginUnit.rawValue)

        // Header/Footer Tab
        headerTextView?.string = data.headerFooter.headerText
        footerTextView?.string = data.headerFooter.footerText

        // Properties Tab
        authorField?.stringValue = data.properties.author
        companyField?.stringValue = data.properties.company
        copyrightField?.stringValue = data.properties.copyright
    }

    private func saveCurrentPreset() {
        guard var preset = presetManager.preset(at: selectedPresetIndex) else { return }

        // View Tab
        preset.data.view.windowWidth = CGFloat(windowWidthField?.doubleValue ?? 800)
        preset.data.view.windowHeight = CGFloat(windowHeightField?.doubleValue ?? 600)
        preset.data.view.windowX = CGFloat(windowLeftField?.doubleValue ?? 100)
        preset.data.view.windowY = CGFloat(windowTopField?.doubleValue ?? 100)

        // スケールの保存（フィールドから値を取得、%を除去）
        let scaleString = scaleField?.stringValue.replacingOccurrences(of: "%", with: "") ?? "100"
        let scalePercent = Int(scaleString) ?? 100
        preset.data.view.scale = CGFloat(scalePercent) / 100.0
        preset.data.view.lineNumberType = NewDocData.ViewData.LineNumberType(rawValue: lineNumberPopup?.selectedTag() ?? 0) ?? .logical
        preset.data.view.rulerType = NewDocData.ViewData.RulerType(rawValue: rulerPopup?.selectedTag() ?? 0) ?? .character
        preset.data.view.showInspectorBar = showInspectorBarCheckbox?.state == .on
        preset.data.view.showToolBar = showToolBarCheckbox?.state == .on
        // Page Mode Matrix: tag 0 = Window, tag 1 = Page
        preset.data.view.pageMode = pageModeMatrix?.selectedTag() == 1
        preset.data.view.docWidthType = NewDocData.ViewData.DocWidthType(rawValue: docWidthPopup?.selectedTag() ?? 1) ?? .windowWidth

        // Show Invisibles
        preset.data.view.showInvisibles = NewDocData.ViewData.ShowInvisibles(
            space: invisibleSpaceCheckbox?.state == .on,
            nonBreakingSpace: invisibleNonBreakingSpaceCheckbox?.state == .on,
            kanjiSpace: invisibleKanjiSpaceCheckbox?.state == .on,
            tab: invisibleTabCheckbox?.state == .on,
            lineSeparator: invisibleLineSeparatorCheckbox?.state == .on,
            paragraphBreak: invisibleParagraphBreakCheckbox?.state == .on,
            pageBreak: invisiblePageBreakCheckbox?.state == .on,
            verticalTab: invisibleVerticalTabCheckbox?.state == .on
        )

        // Format Tab
        preset.data.format.newDocNameType = NewDocData.FormatData.NewDocNameType(rawValue: newDocNamePopup?.selectedTag() ?? 0) ?? .untitled
        // Text Style Matrix: tag 1 = Rich Text, tag 0 = Plain Text
        preset.data.format.richText = textStyleMatrix?.selectedTag() == 1
        preset.data.format.fileExtension = fileExtensionField?.stringValue ?? ""
        // Encoding - tag is the encoding's rawValue
        preset.data.format.textEncoding = UInt(encodingPopup?.selectedTag() ?? Int(String.Encoding.utf8.rawValue))
        preset.data.format.lineEndingType = NewDocData.FormatData.LineEndingType(rawValue: lineEndingPopup?.selectedTag() ?? 0) ?? .lf
        preset.data.format.bom = bomCheckbox?.state == .on
        // Editing Direction: tag 0 = Horizontal (Left to Right), tag 1 = Vertical (Right to Left)
        preset.data.format.editingDirection = NewDocData.FormatData.EditingDirection(rawValue: editingDirectionMatrix?.selectedTag() ?? 0) ?? .leftToRight
        preset.data.format.tabWidthPoints = getTabWidthInPoints()
        preset.data.format.tabWidthUnit = getSelectedTabWidthUnit()
        preset.data.format.interLineSpacing = CGFloat(interLineSpacingField?.doubleValue ?? 0)
        preset.data.format.paragraphSpacingBefore = CGFloat(paragraphSpacingBeforeField?.doubleValue ?? 0)
        preset.data.format.paragraphSpacingAfter = CGFloat(paragraphSpacingAfterField?.doubleValue ?? 0)
        preset.data.format.autoIndent = autoIndentCheckbox?.state == .on
        preset.data.format.indentWrappedLines = indentWrappedLinesCheckbox?.state == .on
        preset.data.format.wrappedLineIndent = CGFloat(wrappedLineIndentField?.doubleValue ?? 0)
        preset.data.format.wordWrappingType = NewDocData.FormatData.WordWrappingType(rawValue: wordWrapPopup?.selectedTag() ?? 0) ?? .systemDefault
        preset.data.format.targetSizeType = NewDocData.FormatData.TargetSizeType(rawValue: targetSizeTypePopup?.selectedTag() ?? 0) ?? .none
        preset.data.format.minTargetSize = targetSizeLowerLimitField?.integerValue ?? 0
        preset.data.format.maxTargetSize = targetSizeUpperLimitField?.integerValue ?? 1000

        // Font & Colors Tab
        preset.data.fontAndColors.baseFontName = currentBaseFontName
        preset.data.fontAndColors.baseFontSize = currentBaseFontSize
        // 9色のカラーウェルを保存
        if let color = textColorWell?.color {
            preset.data.fontAndColors.colors.character = CodableColor(color)
        }
        if let color = backgroundColorWell?.color {
            preset.data.fontAndColors.colors.background = CodableColor(color)
        }
        if let color = invisibleColorWell?.color {
            preset.data.fontAndColors.colors.invisible = CodableColor(color)
        }
        if let color = caretColorWell?.color {
            preset.data.fontAndColors.colors.caret = CodableColor(color)
        }
        if let color = highlightColorWell?.color {
            preset.data.fontAndColors.colors.highlight = CodableColor(color)
        }
        if let color = lineNumberColorWell?.color {
            preset.data.fontAndColors.colors.lineNumber = CodableColor(color)
        }
        if let color = headerColorWell?.color {
            preset.data.fontAndColors.colors.header = CodableColor(color)
        }
        if let color = footerColorWell?.color {
            preset.data.fontAndColors.colors.footer = CodableColor(color)
        }
        if let color = lineNumberBackgroundColorWell?.color {
            preset.data.fontAndColors.colors.lineNumberBackground = CodableColor(color)
        }

        // Page Layout Tab
        preset.data.pageLayout.topMargin = CGFloat(topMarginField?.doubleValue ?? 2.0)
        preset.data.pageLayout.leftMargin = CGFloat(leftMarginField?.doubleValue ?? 2.0)
        preset.data.pageLayout.rightMargin = CGFloat(rightMarginField?.doubleValue ?? 2.0)
        preset.data.pageLayout.bottomMargin = CGFloat(bottomMarginField?.doubleValue ?? 2.0)
        preset.data.pageLayout.marginUnit = NewDocData.PageLayoutData.MarginUnit(rawValue: marginUnitPopup?.selectedTag() ?? 0) ?? .centimeter

        // Header/Footer Tab
        preset.data.headerFooter.headerText = headerTextView?.string ?? ""
        preset.data.headerFooter.footerText = footerTextView?.string ?? ""

        // Properties Tab
        preset.data.properties.author = authorField?.stringValue ?? ""
        preset.data.properties.company = companyField?.stringValue ?? ""
        preset.data.properties.copyright = copyrightField?.stringValue ?? ""

        presetManager.updatePreset(preset)
    }

    // MARK: - IBActions

    @IBAction func addPresetClicked(_ sender: Any) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("New Preset", comment: "")
        alert.informativeText = NSLocalizedString("Enter a name for the new preset:", comment: "")
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        inputField.stringValue = NSLocalizedString("New Preset", comment: "")
        alert.accessoryView = inputField

        alert.beginSheetModal(for: view.window!) { response in
            if response == .alertFirstButtonReturn {
                let name = inputField.stringValue.isEmpty ? "New Preset" : inputField.stringValue
                let currentPreset = self.presetManager.preset(at: self.selectedPresetIndex)
                let newPreset = self.presetManager.addPreset(name: name, basedOn: currentPreset)

                self.presetTableView?.reloadData()

                // 新しいプリセットを選択
                if let index = self.presetManager.presets.firstIndex(where: { $0.id == newPreset.id }) {
                    self.selectedPresetIndex = index
                    self.presetTableView?.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                    self.loadSelectedPreset()
                    self.updateRemoveButtonState()
                }
            }
        }
    }

    @IBAction func removePresetClicked(_ sender: Any) {
        guard let preset = presetManager.preset(at: selectedPresetIndex),
              !preset.isBuiltIn else { return }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Delete Preset", comment: "")
        alert.informativeText = String(format: NSLocalizedString("Are you sure you want to delete \"%@\"?", comment: ""), preset.name)
        alert.addButton(withTitle: NSLocalizedString("Delete", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.alertStyle = .warning

        alert.beginSheetModal(for: view.window!) { response in
            if response == .alertFirstButtonReturn {
                self.presetManager.deletePreset(at: self.selectedPresetIndex)
                self.presetTableView?.reloadData()

                // 前のプリセットを選択（または最初のプリセット）
                self.selectedPresetIndex = max(0, self.selectedPresetIndex - 1)
                self.presetTableView?.selectRowIndexes(IndexSet(integer: self.selectedPresetIndex), byExtendingSelection: false)
                self.loadSelectedPreset()
                self.updateRemoveButtonState()
            }
        }
    }

    @IBAction func revertToDefaultClicked(_ sender: Any) {
        guard let preset = presetManager.preset(at: selectedPresetIndex),
              preset.isBuiltIn else { return }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Revert to Default", comment: "")
        alert.informativeText = String(format: NSLocalizedString("Are you sure you want to revert \"%@\" to its default settings?", comment: ""), preset.name)
        alert.addButton(withTitle: NSLocalizedString("Revert", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        alert.beginSheetModal(for: view.window!) { response in
            if response == .alertFirstButtonReturn {
                self.presetManager.revertToDefault(at: self.selectedPresetIndex)
                self.loadSelectedPreset()
            }
        }
    }

    @objc private func tableViewDoubleClicked(_ sender: Any) {
        let clickedRow = presetTableView.clickedRow
        guard clickedRow >= 0,
              let preset = presetManager.preset(at: clickedRow),
              !preset.isBuiltIn else { return }

        // プリセット名の編集
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Rename Preset", comment: "")
        alert.informativeText = NSLocalizedString("Enter a new name for the preset:", comment: "")
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        inputField.stringValue = preset.name
        alert.accessoryView = inputField

        alert.beginSheetModal(for: view.window!) { response in
            if response == .alertFirstButtonReturn {
                var updatedPreset = preset
                updatedPreset.name = inputField.stringValue.isEmpty ? preset.name : inputField.stringValue
                self.presetManager.updatePreset(updatedPreset)
                self.presetTableView?.reloadData()
            }
        }
    }

    // MARK: - Control Actions (値変更時に保存)

    @IBAction func controlValueChanged(_ sender: Any) {
        saveCurrentPreset()
    }

    @IBAction func tabWidthUnitChanged(_ sender: Any) {
        // 単位が切り替わったら、現在の値をポイントに変換してから新しい単位で表示
        convertAndDisplayTabWidth()
        saveCurrentPreset()
    }

    @IBAction func tabWidthStepperChanged(_ sender: NSStepper) {
        // ステッパーの値をフィールドに反映
        tabWidthField?.integerValue = sender.integerValue
        saveCurrentPreset()
    }

    @IBAction func interLineSpacingStepperChanged(_ sender: NSStepper) {
        interLineSpacingField?.doubleValue = sender.doubleValue
        saveCurrentPreset()
    }

    @IBAction func paragraphSpacingBeforeStepperChanged(_ sender: NSStepper) {
        paragraphSpacingBeforeField?.doubleValue = sender.doubleValue
        saveCurrentPreset()
    }

    @IBAction func paragraphSpacingAfterStepperChanged(_ sender: NSStepper) {
        paragraphSpacingAfterField?.doubleValue = sender.doubleValue
        saveCurrentPreset()
    }

    // MARK: - Get Current Window Actions

    @IBAction func getCurrentLocationClicked(_ sender: Any) {
        guard let window = findFrontmostDocumentWindow() else { return }

        let frame = window.frame
        windowLeftField?.doubleValue = Double(frame.origin.x)
        windowTopField?.doubleValue = Double(frame.origin.y)
        saveCurrentPreset()
    }

    @IBAction func getCurrentSizeClicked(_ sender: Any) {
        guard let window = findFrontmostDocumentWindow() else { return }

        let frame = window.frame
        windowWidthField?.doubleValue = Double(frame.size.width)
        windowHeightField?.doubleValue = Double(frame.size.height)
        saveCurrentPreset()
    }

    // MARK: - Show Invisibles Actions

    @IBAction func showAllInvisiblesClicked(_ sender: Any) {
        invisibleSpaceCheckbox?.state = .on
        invisibleNonBreakingSpaceCheckbox?.state = .on
        invisibleKanjiSpaceCheckbox?.state = .on
        invisibleTabCheckbox?.state = .on
        invisibleLineSeparatorCheckbox?.state = .on
        invisibleParagraphBreakCheckbox?.state = .on
        invisiblePageBreakCheckbox?.state = .on
        invisibleVerticalTabCheckbox?.state = .on
        saveCurrentPreset()
    }

    @IBAction func hideAllInvisiblesClicked(_ sender: Any) {
        invisibleSpaceCheckbox?.state = .off
        invisibleNonBreakingSpaceCheckbox?.state = .off
        invisibleKanjiSpaceCheckbox?.state = .off
        invisibleTabCheckbox?.state = .off
        invisibleLineSeparatorCheckbox?.state = .off
        invisibleParagraphBreakCheckbox?.state = .off
        invisiblePageBreakCheckbox?.state = .off
        invisibleVerticalTabCheckbox?.state = .off
        saveCurrentPreset()
    }

    /// 最前面の編集書類ウィンドウを取得
    private func findFrontmostDocumentWindow() -> NSWindow? {
        // 現在のドキュメントのウィンドウを取得
        if let currentDocument = NSDocumentController.shared.currentDocument,
           let windowController = currentDocument.windowControllers.first,
           let window = windowController.window {
            return window
        }

        // mainWindowがドキュメントウィンドウかチェック
        if let mainWindow = NSApp.mainWindow,
           mainWindow.windowController is EditorWindowController {
            return mainWindow
        }

        // orderedWindowsから最前面のドキュメントウィンドウを探す
        for window in NSApp.orderedWindows {
            if window.windowController is EditorWindowController {
                return window
            }
        }

        return nil
    }
}

// MARK: - NSTableViewDataSource

extension NewDocumentsPreferencesViewController: NSTableViewDataSource {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return presetManager.presets.count
    }
}

// MARK: - NSTableViewDelegate

extension NewDocumentsPreferencesViewController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let preset = presetManager.preset(at: row) else { return nil }

        let cellIdentifier = NSUserInterfaceItemIdentifier("PresetCell")
        var cellView = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView

        if cellView == nil {
            cellView = NSTableCellView()
            cellView?.identifier = cellIdentifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            cellView?.addSubview(textField)
            cellView?.textField = textField

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
            ])
        }

        cellView?.textField?.stringValue = preset.name

        return cellView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let newIndex = presetTableView.selectedRow
        guard newIndex >= 0 else { return }

        // 現在の設定を保存
        if selectedPresetIndex != newIndex {
            saveCurrentPreset()
        }

        selectedPresetIndex = newIndex
        presetManager.selectPreset(id: presetManager.presets[newIndex].id)
        loadSelectedPreset()
        updateRemoveButtonState()
    }
}

// MARK: - ScaleMenuDelegate

extension NewDocumentsPreferencesViewController: ScaleMenuDelegate {

    func scaleMenuDidSelectScale(_ scale: Int) {
        // スケールフィールドを更新（%付き）
        scaleField?.stringValue = "\(scale)%"
        // プリセットを保存
        saveCurrentPreset()
    }
}

// MARK: - FixedDocWidthMenuDelegate

extension NewDocumentsPreferencesViewController: FixedDocWidthMenuDelegate {

    func fixedDocWidthMenuDidSelectType(_ type: NewDocData.ViewData.DocWidthType) {
        // ポップアップの選択を更新
        docWidthPopup?.selectItem(withTag: type.rawValue)
        // プリセットを保存
        saveCurrentPreset()
    }

    func fixedDocWidthMenuDidChangeFixedWidth(_ width: Int) {
        // 現在のプリセットのfixedDocWidthを更新
        guard var preset = presetManager.preset(at: selectedPresetIndex) else { return }
        preset.data.view.fixedDocWidth = width
        presetManager.updatePreset(preset)
    }

    func fixedDocWidthMenuGetCurrentFixedWidth() -> Int {
        guard let preset = presetManager.preset(at: selectedPresetIndex) else { return 80 }
        return preset.data.view.fixedDocWidth
    }
}

// MARK: - Tab Width Unit

extension NewDocumentsPreferencesViewController {

    /// 現在のBase Fontの1スペースあたりのポイント幅を計算
    func spaceWidthInPoints() -> CGFloat {
        let font = NSFont(name: currentBaseFontName, size: currentBaseFontSize)
            ?? NSFont.systemFont(ofSize: currentBaseFontSize)

        // スペース文字の幅を計算
        let spaceString = " " as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = spaceString.size(withAttributes: attributes)
        return size.width
    }

    /// ポイントからスペース数に変換
    func pointsToSpaces(_ points: CGFloat) -> CGFloat {
        let spaceWidth = spaceWidthInPoints()
        guard spaceWidth > 0 else { return 4 }  // デフォルト値
        return points / spaceWidth
    }

    /// スペース数からポイントに変換
    func spacesToPoints(_ spaces: CGFloat) -> CGFloat {
        return spaces * spaceWidthInPoints()
    }

    /// タブ幅フィールドの表示を更新
    func updateTabWidthDisplay() {
        guard let preset = presetManager.preset(at: selectedPresetIndex) else { return }
        let tabWidthPoints = preset.data.format.tabWidthPoints

        // 保存されている単位をポップアップに反映
        tabWidthUnitPopup?.selectItem(withTag: preset.data.format.tabWidthUnit.rawValue)

        let unit = preset.data.format.tabWidthUnit

        switch unit {
        case .points:
            tabWidthField?.doubleValue = Double(tabWidthPoints)
            tabWidthStepper?.integerValue = Int(tabWidthPoints)
        case .spaces:
            let spaces = pointsToSpaces(tabWidthPoints)
            // spacesの時は整数で表示
            tabWidthField?.integerValue = Int(round(spaces))
            tabWidthStepper?.integerValue = Int(round(spaces))
        }

        // ステッパーの増分を1に設定
        tabWidthStepper?.increment = 1

        // 説明ラベルを更新
        updateTabWidthDescriptionLabel(for: unit)
    }

    /// タブ幅をポイントで取得（フィールドと単位から計算）
    func getTabWidthInPoints() -> CGFloat {
        let fieldValue = CGFloat(tabWidthField?.doubleValue ?? 28.0)
        let unit = NewDocData.FormatData.TabWidthUnit(rawValue: tabWidthUnitPopup?.selectedTag() ?? 0) ?? .points

        switch unit {
        case .points:
            return fieldValue
        case .spaces:
            return spacesToPoints(fieldValue)
        }
    }

    /// 現在選択されているタブ幅単位を取得
    func getSelectedTabWidthUnit() -> NewDocData.FormatData.TabWidthUnit {
        return NewDocData.FormatData.TabWidthUnit(rawValue: tabWidthUnitPopup?.selectedTag() ?? 0) ?? .points
    }

    /// 単位切り替え時: 現在のフィールド値を新しい単位に変換して表示
    /// previousUnit: 切り替え前の単位（nilの場合は保存されている単位を使用）
    func convertAndDisplayTabWidth() {
        guard let preset = presetManager.preset(at: selectedPresetIndex) else { return }

        // 切り替え前の単位を取得（保存されている単位）
        let previousUnit = preset.data.format.tabWidthUnit
        // 切り替え後の単位を取得（ポップアップで新しく選択された単位）
        let newUnit = getSelectedTabWidthUnit()

        // 同じ単位なら何もしない
        guard previousUnit != newUnit else { return }

        // 現在のフィールド値を取得
        let currentFieldValue = CGFloat(tabWidthField?.doubleValue ?? 28.0)

        // 現在のフィールド値をポイントに変換
        let tabWidthPoints: CGFloat
        switch previousUnit {
        case .points:
            tabWidthPoints = currentFieldValue
        case .spaces:
            tabWidthPoints = spacesToPoints(currentFieldValue)
        }

        // 新しい単位で表示
        switch newUnit {
        case .points:
            tabWidthField?.doubleValue = Double(tabWidthPoints)
            tabWidthStepper?.integerValue = Int(tabWidthPoints)
        case .spaces:
            let spaces = pointsToSpaces(tabWidthPoints)
            // spacesの時は整数で表示
            tabWidthField?.integerValue = Int(round(spaces))
            tabWidthStepper?.integerValue = Int(round(spaces))
        }

        // 説明ラベルを更新
        updateTabWidthDescriptionLabel(for: newUnit)
    }

    /// タブ幅の説明ラベルを更新
    func updateTabWidthDescriptionLabel(for unit: NewDocData.FormatData.TabWidthUnit) {
        switch unit {
        case .points:
            tabWidthDescriptionLabel?.stringValue = "tab code will be inserted by tab key."
        case .spaces:
            tabWidthDescriptionLabel?.stringValue = "space chars. will be inserted by tab key."
        }
    }
}

// MARK: - Font Panel Support

extension NewDocumentsPreferencesViewController {

    /// フォントラベルを更新
    private func updateBaseFontLabel() {
        // フォントの表示名を取得
        let displayName: String
        if let font = NSFont(name: currentBaseFontName, size: currentBaseFontSize) {
            displayName = font.displayName ?? currentBaseFontName
        } else {
            displayName = currentBaseFontName
        }
        let sizeString = String(format: "%.1f", currentBaseFontSize)
        baseFontLabel?.stringValue = "\(displayName) - \(sizeString) pt"
    }

    /// Change ボタンが押された時
    @IBAction func changeFontButtonClicked(_ sender: Any) {
        // フォントパネルを表示
        let fontManager = NSFontManager.shared
        let currentFont = NSFont(name: currentBaseFontName, size: currentBaseFontSize)
            ?? NSFont.systemFont(ofSize: currentBaseFontSize)

        // フォントパネルにターゲットを設定
        fontManager.target = self
        fontManager.action = #selector(changeFont(_:))

        // 現在のフォントをセット
        fontManager.setSelectedFont(currentFont, isMultiple: false)

        // フォントパネルを表示
        fontManager.orderFrontFontPanel(self)
    }

    /// フォントパネルからフォントが変更された時
    @objc func changeFont(_ sender: Any?) {
        guard let fontManager = sender as? NSFontManager else { return }

        let currentFont = NSFont(name: currentBaseFontName, size: currentBaseFontSize)
            ?? NSFont.systemFont(ofSize: currentBaseFontSize)

        let newFont = fontManager.convert(currentFont)
        currentBaseFontName = newFont.fontName
        currentBaseFontSize = newFont.pointSize

        updateBaseFontLabel()
        // フォントが変更されたらタブ幅の表示も更新（スペース単位の場合は値が変わる）
        updateTabWidthDisplay()
        saveCurrentPreset()
    }
}

// MARK: - Theme Color Support

extension NewDocumentsPreferencesViewController {

    /// テーマが選択された時
    @objc func themeSelected(_ sender: NSMenuItem) {
        guard let theme = sender.representedObject as? ThemeColorData else { return }

        // 9つのカラーウェルにテーマの色を設定
        textColorWell?.color = theme.characterColor.nsColor
        backgroundColorWell?.color = theme.backgroundColor.nsColor
        invisibleColorWell?.color = theme.invisibleColor.nsColor
        caretColorWell?.color = theme.caretColor.nsColor
        highlightColorWell?.color = theme.highlightColor.nsColor
        lineNumberColorWell?.color = theme.lineNumberColor.nsColor
        lineNumberBackgroundColorWell?.color = theme.lineNumberBackColor.nsColor
        headerColorWell?.color = theme.headerColor.nsColor
        footerColorWell?.color = theme.footerColor.nsColor

        // プリセットを保存
        saveCurrentPreset()
    }

    /// テーマ追加ダイアログを表示
    @objc func addTheme(_ sender: NSMenuItem) {
        guard let window = view.window else { return }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Add Theme", comment: "")
        alert.informativeText = NSLocalizedString("Enter a name for the new theme:", comment: "")
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        inputField.stringValue = NSLocalizedString("New Theme", comment: "")
        alert.accessoryView = inputField

        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                let themeName = inputField.stringValue.isEmpty ? "New Theme" : inputField.stringValue

                // 現在のカラーウェルの色からテーマを作成
                let newTheme = ThemeColorData(
                    themeName: themeName,
                    removable: true,
                    characterColor: CodableColor(self.textColorWell?.color ?? .textColor),
                    backgroundColor: CodableColor(self.backgroundColorWell?.color ?? .textBackgroundColor),
                    invisibleColor: CodableColor(self.invisibleColorWell?.color ?? .tertiaryLabelColor),
                    caretColor: CodableColor(self.caretColorWell?.color ?? .textColor),
                    highlightColor: CodableColor(self.highlightColorWell?.color ?? .selectedTextBackgroundColor),
                    lineNumberColor: CodableColor(self.lineNumberColorWell?.color ?? .secondaryLabelColor),
                    lineNumberBackColor: CodableColor(self.lineNumberBackgroundColorWell?.color ?? .controlBackgroundColor),
                    headerColor: CodableColor(self.headerColorWell?.color ?? .labelColor),
                    footerColor: CodableColor(self.footerColorWell?.color ?? .labelColor)
                )

                ThemeColorManager.shared.addTheme(newTheme)
            }
        }
    }
}
