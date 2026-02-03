//
//  ImageClickableTextView.swift
//  Jedit-open
//
//  Custom NSTextView subclass that detects clicks on image attachments
//

import Cocoa

// MARK: - ImageClickableTextView

class ImageClickableTextView: NSTextView {

    // MARK: - Properties

    /// Controller for handling image resize operations
    var imageResizeController: ImageResizeController?

    /// Character index of the image attachment for context menu action
    private var contextMenuImageCharIndex: Int?

    /// カラーパネルのモード（前景色か背景色か）
    private enum ColorPanelMode {
        case none
        case foreground
        case background
    }
    private var colorPanelMode: ColorPanelMode = .none

    /// updateRuler()の再入防止フラグ
    private var isUpdatingRuler: Bool = false

    /// Returns whether this document is plain text
    private var isPlainText: Bool {
        guard let windowController = window?.windowController as? EditorWindowController else {
            return false
        }
        return windowController.textDocument?.documentType == .plain
    }

    /// Returns whether substitutions should only apply to rich text
    private var richTextSubstitutionsOnly: Bool {
        return UserDefaults.standard.bool(forKey: UserDefaults.Keys.richTextSubstitutionsEnabled)
    }

    // MARK: - Text Replacement with Undo Support

    /// テキストまたは属性付きテキストを指定範囲に置換（Undo/Redo対応）
    /// すべてのテキスト変更はこのメソッドを経由することで、自動的にUndo/Redoがサポートされる
    /// - Parameters:
    ///   - range: 置換する範囲
    ///   - string: 置換するテキスト（String または NSAttributedString）
    func replaceString(in range: NSRange, with string: Any) {
        if let plainString = string as? String {
            if shouldChangeText(in: range, replacementString: plainString) {
                replaceCharacters(in: range, with: plainString)
                didChangeText()
            }
        } else if let attributedString = string as? NSAttributedString {
            if shouldChangeText(in: range, replacementString: attributedString.string) {
                textStorage?.beginEditing()
                textStorage?.replaceCharacters(in: range, with: attributedString)
                textStorage?.endEditing()
                didChangeText()
            }
        }
    }

    /// 指定範囲の属性を変更（Undo/Redo対応）
    /// - Parameters:
    ///   - range: 変更する範囲
    ///   - attributes: 適用する属性の辞書
    func applyAttributes(_ attributes: [NSAttributedString.Key: Any], to range: NSRange) {
        guard let textStorage = textStorage,
              range.length > 0,
              range.location + range.length <= textStorage.length else { return }

        // 現在のテキストを取得して属性を変更
        let currentAttributedString = textStorage.attributedSubstring(from: range)
        let mutableString = NSMutableAttributedString(attributedString: currentAttributedString)
        mutableString.addAttributes(attributes, range: NSRange(location: 0, length: mutableString.length))

        // replaceStringを使って置換（Undo対応）
        replaceString(in: range, with: mutableString)
    }

    /// 指定範囲から属性を削除（Undo/Redo対応）
    /// - Parameters:
    ///   - attributeKey: 削除する属性のキー
    ///   - range: 変更する範囲
    func removeAttribute(_ attributeKey: NSAttributedString.Key, from range: NSRange) {
        guard let textStorage = textStorage,
              range.length > 0,
              range.location + range.length <= textStorage.length else { return }

        // 現在のテキストを取得して属性を削除
        let currentAttributedString = textStorage.attributedSubstring(from: range)
        let mutableString = NSMutableAttributedString(attributedString: currentAttributedString)
        mutableString.removeAttribute(attributeKey, range: NSRange(location: 0, length: mutableString.length))

        // replaceStringを使って置換（Undo対応）
        replaceString(in: range, with: mutableString)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        // Check for double-click on an image attachment
        if event.clickCount == 2 {
            let point = convert(event.locationInWindow, from: nil)

            if let controller = imageResizeController,
               controller.handleClick(in: self, at: point) {
                // Image was double-clicked, panel is shown, don't pass the event
                return
            }
        }

        // Not an image double-click, proceed with normal behavior
        super.mouseDown(with: event)
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        // Get the base context menu
        guard let menu = super.menu(for: event) else {
            return nil
        }

        // Check if the click is on an image attachment
        let point = convert(event.locationInWindow, from: nil)

        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let textStorage = textStorage,
              textStorage.length > 0 else {
            return menu
        }

        // Convert point to text container coordinates
        let textContainerOrigin = textContainerOrigin
        let locationInContainer = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )

        // Get glyph index at point
        var fraction: CGFloat = 0
        let glyphIndex = layoutManager.glyphIndex(for: locationInContainer, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)

        // Convert glyph index to character index
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

        // Check if there's an attachment at this character index
        guard charIndex < textStorage.length else {
            return menu
        }

        // Check for attachment attribute using imageResizeController
        if let controller = imageResizeController,
           controller.getImageAttachment(in: self, at: charIndex) != nil {
            // Store the character index for the menu action
            contextMenuImageCharIndex = charIndex

            // Create "Change Image Size..." menu item
            let changeImageSizeItem = NSMenuItem(
                title: NSLocalizedString("Change Image Size...", comment: "Context menu item for changing image size"),
                action: #selector(changeImageSize(_:)),
                keyEquivalent: ""
            )
            changeImageSizeItem.target = self

            // Insert at the beginning of the menu
            menu.insertItem(changeImageSizeItem, at: 0)
            menu.insertItem(NSMenuItem.separator(), at: 1)
        }

        return menu
    }

    /// Action for "Change Image Size..." context menu item
    @objc private func changeImageSize(_ sender: Any?) {
        guard let charIndex = contextMenuImageCharIndex,
              let controller = imageResizeController else {
            return
        }

        controller.showResizePanelForAttachment(in: self, at: charIndex)
        contextMenuImageCharIndex = nil
    }

    // MARK: - Spelling and Grammar Menu Actions

    @IBAction override func toggleContinuousSpellChecking(_ sender: Any?) {
        super.toggleContinuousSpellChecking(sender)
        UserDefaults.standard.set(isContinuousSpellCheckingEnabled, forKey: UserDefaults.Keys.checkSpellingAsYouType)
    }

    @IBAction override func toggleGrammarChecking(_ sender: Any?) {
        super.toggleGrammarChecking(sender)
        UserDefaults.standard.set(isGrammarCheckingEnabled, forKey: UserDefaults.Keys.checkGrammarWithSpelling)
    }

    @IBAction override func toggleAutomaticSpellingCorrection(_ sender: Any?) {
        super.toggleAutomaticSpellingCorrection(sender)
        UserDefaults.standard.set(isAutomaticSpellingCorrectionEnabled, forKey: UserDefaults.Keys.correctSpellingAutomatically)
    }

    // MARK: - Substitutions Menu Actions

    @IBAction override func toggleSmartInsertDelete(_ sender: Any?) {
        super.toggleSmartInsertDelete(sender)
        UserDefaults.standard.set(smartInsertDeleteEnabled, forKey: UserDefaults.Keys.smartCopyPaste)
    }

    @IBAction override func toggleAutomaticQuoteSubstitution(_ sender: Any?) {
        super.toggleAutomaticQuoteSubstitution(sender)
        UserDefaults.standard.set(isAutomaticQuoteSubstitutionEnabled, forKey: UserDefaults.Keys.smartQuotes)
    }

    @IBAction override func toggleAutomaticDashSubstitution(_ sender: Any?) {
        super.toggleAutomaticDashSubstitution(sender)
        UserDefaults.standard.set(isAutomaticDashSubstitutionEnabled, forKey: UserDefaults.Keys.smartDashes)
    }

    @IBAction override func toggleAutomaticLinkDetection(_ sender: Any?) {
        super.toggleAutomaticLinkDetection(sender)
        UserDefaults.standard.set(isAutomaticLinkDetectionEnabled, forKey: UserDefaults.Keys.smartLinks)
    }

    @IBAction override func toggleAutomaticDataDetection(_ sender: Any?) {
        super.toggleAutomaticDataDetection(sender)
        UserDefaults.standard.set(isAutomaticDataDetectionEnabled, forKey: UserDefaults.Keys.dataDetectors)
    }

    @IBAction override func toggleAutomaticTextReplacement(_ sender: Any?) {
        super.toggleAutomaticTextReplacement(sender)
        UserDefaults.standard.set(isAutomaticTextReplacementEnabled, forKey: UserDefaults.Keys.textReplacements)
    }

    // MARK: - Stamp Date/Time Actions

    @IBAction func stampDate(_ sender: Any?) {
        let dateFormatType = UserDefaults.standard.integer(forKey: UserDefaults.Keys.dateFormatType)
        guard let formatType = CalendarDateHelper.DateFormatType(rawValue: dateFormatType) else { return }
        let dateString = formatType.formattedDate()
        insertText(dateString, replacementRange: selectedRange())
    }

    @IBAction func stampTime(_ sender: Any?) {
        let timeFormatType = UserDefaults.standard.integer(forKey: UserDefaults.Keys.timeFormatType)
        guard let formatType = CalendarDateHelper.TimeFormatType(rawValue: timeFormatType) else { return }
        let timeString = formatType.formattedTime()
        insertText(timeString, replacementRange: selectedRange())
    }

    // MARK: - Font Panel Support

    /// フォントパネルからのフォント変更を処理
    /// Format > Font メニューやインスペクターバーからのフォント変更に対応
    @objc override func changeFont(_ sender: Any?) {
        // BasicFontPanelController がアクティブな場合は処理をスキップ
        // （Basic Font パネルは独自に処理する）
        if BasicFontPanelController.shared.isFontPanelActive {
            return
        }

        // プレーンテキストの場合、アラートを表示して確認
        if isPlainText {
            guard let fontManager = sender as? NSFontManager else {
                return
            }

            // 現在のフォントを取得
            let currentFont = self.font ?? NSFont.systemFont(ofSize: 14)
            let newFont = fontManager.convert(currentFont)

            showPlainTextAttributeChangeAlert(
                message: NSLocalizedString("Change Font", comment: "Alert title for font change in plain text"),
                informativeText: NSLocalizedString("In plain text documents, font changes apply to the entire document. Do you want to continue?", comment: "Alert message for font change in plain text")
            ) { [weak self] in
                self?.applyFontToEntireDocument(newFont)
            }
            return
        }

        // RTF の場合は NSTextView のデフォルト実装を使用
        // これにより Undo/Redo も自動的にサポートされる
        super.changeFont(sender)
    }

    /// テキスト属性（色など）の変更を処理
    override func changeAttributes(_ sender: Any?) {
        // プレーンテキストの場合は警告を表示して拒否
        if isPlainText {
            showPlainTextColorChangeNotAllowedAlert()
            return
        }

        // RTF の場合は NSTextView のデフォルト実装を使用
        super.changeAttributes(sender)
    }

    /// プレーンテキストで色変更が許可されていないことを警告
    private func showPlainTextColorChangeNotAllowedAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Color Change Not Allowed", comment: "Alert title for color change not allowed in plain text")
        alert.informativeText = NSLocalizedString("Character colors cannot be changed in plain text documents. To change colors, convert the document to Rich Text format.", comment: "Alert message for color change not allowed in plain text")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))

        if let window = self.window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    /// 下線の変更を処理 (Format > Font > Underline)
    @IBAction override func underline(_ sender: Any?) {
        // プレーンテキストの場合、アラートを表示して確認
        if isPlainText {
            showPlainTextAttributeChangeAlert(
                message: NSLocalizedString("Underline", comment: "Alert title for underline change in plain text"),
                informativeText: NSLocalizedString("In plain text documents, underline changes apply to the entire document. Do you want to continue?", comment: "Alert message for underline change in plain text")
            ) { [weak self] in
                self?.applyUnderlineToEntireDocument()
            }
            return
        }

        // RTF の場合は NSTextView のデフォルト実装を使用
        super.underline(sender)
    }

    // MARK: - Kern Support

    /// Use Standard Kerning (Format > Font > Kern)
    @IBAction override func useStandardKerning(_ sender: Any?) {
        if isPlainText {
            showPlainTextAttributeChangeAlert(
                message: NSLocalizedString("Kern", comment: "Alert title for kern change in plain text"),
                informativeText: NSLocalizedString("In plain text documents, kerning changes apply to the entire document. Do you want to continue?", comment: "Alert message for kern change in plain text")
            ) { [weak self] in
                self?.applyKernToEntireDocument(value: 0) // 0 = standard kerning
            }
            return
        }
        super.useStandardKerning(sender)
    }

    /// Turn Off Kerning (Format > Font > Kern)
    @IBAction override func turnOffKerning(_ sender: Any?) {
        if isPlainText {
            showPlainTextAttributeChangeAlert(
                message: NSLocalizedString("Kern", comment: "Alert title for kern change in plain text"),
                informativeText: NSLocalizedString("In plain text documents, kerning changes apply to the entire document. Do you want to continue?", comment: "Alert message for kern change in plain text")
            ) { [weak self] in
                self?.applyKernToEntireDocument(value: nil) // nil = turn off
            }
            return
        }
        super.turnOffKerning(sender)
    }

    /// Tighten Kerning (Format > Font > Kern)
    @IBAction override func tightenKerning(_ sender: Any?) {
        if isPlainText {
            showPlainTextAttributeChangeAlert(
                message: NSLocalizedString("Kern", comment: "Alert title for kern change in plain text"),
                informativeText: NSLocalizedString("In plain text documents, kerning changes apply to the entire document. Do you want to continue?", comment: "Alert message for kern change in plain text")
            ) { [weak self] in
                self?.adjustKernToEntireDocument(delta: -1.0)
            }
            return
        }
        super.tightenKerning(sender)
    }

    /// Loosen Kerning (Format > Font > Kern)
    @IBAction override func loosenKerning(_ sender: Any?) {
        if isPlainText {
            showPlainTextAttributeChangeAlert(
                message: NSLocalizedString("Kern", comment: "Alert title for kern change in plain text"),
                informativeText: NSLocalizedString("In plain text documents, kerning changes apply to the entire document. Do you want to continue?", comment: "Alert message for kern change in plain text")
            ) { [weak self] in
                self?.adjustKernToEntireDocument(delta: 1.0)
            }
            return
        }
        super.loosenKerning(sender)
    }

    // MARK: - Ligature Support

    /// Use Standard Ligatures (Format > Font > Ligatures)
    @IBAction override func useStandardLigatures(_ sender: Any?) {
        if isPlainText {
            showPlainTextAttributeChangeAlert(
                message: NSLocalizedString("Ligatures", comment: "Alert title for ligature change in plain text"),
                informativeText: NSLocalizedString("In plain text documents, ligature changes apply to the entire document. Do you want to continue?", comment: "Alert message for ligature change in plain text")
            ) { [weak self] in
                self?.applyLigatureToEntireDocument(value: 1) // 1 = standard ligatures
            }
            return
        }
        super.useStandardLigatures(sender)
    }

    /// Turn Off Ligatures (Format > Font > Ligatures)
    @IBAction override func turnOffLigatures(_ sender: Any?) {
        if isPlainText {
            showPlainTextAttributeChangeAlert(
                message: NSLocalizedString("Ligatures", comment: "Alert title for ligature change in plain text"),
                informativeText: NSLocalizedString("In plain text documents, ligature changes apply to the entire document. Do you want to continue?", comment: "Alert message for ligature change in plain text")
            ) { [weak self] in
                self?.applyLigatureToEntireDocument(value: 0) // 0 = no ligatures
            }
            return
        }
        super.turnOffLigatures(sender)
    }

    /// Use All Ligatures (Format > Font > Ligatures)
    @IBAction override func useAllLigatures(_ sender: Any?) {
        if isPlainText {
            showPlainTextAttributeChangeAlert(
                message: NSLocalizedString("Ligatures", comment: "Alert title for ligature change in plain text"),
                informativeText: NSLocalizedString("In plain text documents, ligature changes apply to the entire document. Do you want to continue?", comment: "Alert message for ligature change in plain text")
            ) { [weak self] in
                self?.applyLigatureToEntireDocument(value: 2) // 2 = all ligatures
            }
            return
        }
        super.useAllLigatures(sender)
    }

    // MARK: - Text Alignment Support

    /// Align Left (Format > Text > Align Left)
    @IBAction override func alignLeft(_ sender: Any?) {
        if isPlainText {
            showPlainTextAttributeChangeAlert(
                message: NSLocalizedString("Text Alignment", comment: "Alert title for text alignment change in plain text"),
                informativeText: NSLocalizedString("In plain text documents, alignment changes apply to the entire document. Do you want to continue?", comment: "Alert message for alignment change in plain text")
            ) { [weak self] in
                self?.applyAlignmentToEntireDocument(.left)
            }
            return
        }
        super.alignLeft(sender)
    }

    /// Align Center (Format > Text > Center)
    @IBAction override func alignCenter(_ sender: Any?) {
        if isPlainText {
            showPlainTextAttributeChangeAlert(
                message: NSLocalizedString("Text Alignment", comment: "Alert title for text alignment change in plain text"),
                informativeText: NSLocalizedString("In plain text documents, alignment changes apply to the entire document. Do you want to continue?", comment: "Alert message for alignment change in plain text")
            ) { [weak self] in
                self?.applyAlignmentToEntireDocument(.center)
            }
            return
        }
        super.alignCenter(sender)
    }

    /// Align Right (Format > Text > Align Right)
    @IBAction override func alignRight(_ sender: Any?) {
        if isPlainText {
            showPlainTextAttributeChangeAlert(
                message: NSLocalizedString("Text Alignment", comment: "Alert title for text alignment change in plain text"),
                informativeText: NSLocalizedString("In plain text documents, alignment changes apply to the entire document. Do you want to continue?", comment: "Alert message for alignment change in plain text")
            ) { [weak self] in
                self?.applyAlignmentToEntireDocument(.right)
            }
            return
        }
        super.alignRight(sender)
    }

    /// Justify (Format > Text > Justify)
    @IBAction override func alignJustified(_ sender: Any?) {
        if isPlainText {
            showPlainTextAttributeChangeAlert(
                message: NSLocalizedString("Text Alignment", comment: "Alert title for text alignment change in plain text"),
                informativeText: NSLocalizedString("In plain text documents, alignment changes apply to the entire document. Do you want to continue?", comment: "Alert message for alignment change in plain text")
            ) { [weak self] in
                self?.applyAlignmentToEntireDocument(.justified)
            }
            return
        }
        super.alignJustified(sender)
    }

    /// プレーンテキスト全文にアラインメントを適用
    private func applyAlignmentToEntireDocument(_ alignment: NSTextAlignment) {
        guard let windowController = window?.windowController as? EditorWindowController else {
            return
        }
        windowController.applyAlignmentToEntireDocument(alignment)
    }

    // MARK: - Paragraph Style Support (Inspector Bar)

    /// 段落スタイル変更前の状態を保持（リスト検出用）
    private var previousTextLists: [NSTextList]?

    /// Inspector barからのsetAlignment変更をインターセプト
    /// プレーンテキストでは全文に適用
    override func setAlignment(_ alignment: NSTextAlignment, range: NSRange) {
        if isPlainText {
            // プレーンテキストでは全文に適用
            guard let textStorage = textStorage, textStorage.length > 0 else {
                super.setAlignment(alignment, range: range)
                return
            }
            let fullRange = NSRange(location: 0, length: textStorage.length)
            super.setAlignment(alignment, range: fullRange)
            return
        }
        super.setAlignment(alignment, range: range)
    }

    /// NSTextViewが属性変更を許可するかどうかを決定
    /// Inspector barからのリスト変更を検出してプレーンテキストでは拒否
    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        // プレーンテキストで、テキスト変更ではなく属性変更（replacementStringがnil）の場合
        if isPlainText && replacementString == nil {
            // 現在のリスト状態を保存
            if let textStorage = textStorage, affectedCharRange.location < textStorage.length {
                let style = textStorage.attribute(.paragraphStyle, at: affectedCharRange.location, effectiveRange: nil) as? NSParagraphStyle
                previousTextLists = style?.textLists
            } else {
                previousTextLists = nil
            }
        }
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    /// テキスト変更後の処理
    /// プレーンテキストでリスト追加を検出して元に戻す、またはLine Spacingを全文に適用
    override func didChangeText() {
        super.didChangeText()

        guard isPlainText, let textStorage = textStorage, textStorage.length > 0 else {
            return
        }

        // 段落スタイルの変更を検出して処理
        let selectedRange = self.selectedRange()
        guard selectedRange.location < textStorage.length else { return }

        let currentStyle = textStorage.attribute(.paragraphStyle, at: min(selectedRange.location, textStorage.length - 1), effectiveRange: nil) as? NSParagraphStyle

        // リストが追加された場合は警告を出して元に戻す
        if let currentLists = currentStyle?.textLists, !currentLists.isEmpty {
            let previousLists = previousTextLists ?? []
            if previousLists.isEmpty {
                // リストが新しく追加された - 警告を出して削除
                showPlainTextListChangeNotAllowedAlert()

                // リストを削除した段落スタイルを作成
                let mutableStyle = (currentStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                mutableStyle.textLists = []

                // 全文に適用
                let fullRange = NSRange(location: 0, length: textStorage.length)
                textStorage.addAttribute(.paragraphStyle, value: mutableStyle, range: fullRange)
            }
        } else if let currentStyle = currentStyle {
            // リストがない場合、段落スタイル（Line Spacingなど）を全文に適用
            // ただし、段落スタイルが変更された場合のみ
            applyParagraphStyleToEntireDocumentIfNeeded(currentStyle)
        }

        previousTextLists = nil
    }

    /// 段落スタイル変更前の状態を保持
    private var previousParagraphStyle: NSParagraphStyle?

    /// 段落スタイルを全文に適用（プレーンテキスト用）
    /// Line Spacing、段落間隔などが変更された場合に全文に適用
    private func applyParagraphStyleToEntireDocumentIfNeeded(_ newStyle: NSParagraphStyle) {
        guard let textStorage = textStorage, textStorage.length > 0 else { return }

        // 全文に段落スタイルを適用
        let fullRange = NSRange(location: 0, length: textStorage.length)

        // 現在のスタイルと同じかどうかを確認（最初の文字の段落スタイルと比較）
        let firstCharStyle = textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        if firstCharStyle != newStyle {
            textStorage.addAttribute(.paragraphStyle, value: newStyle, range: fullRange)
        }
    }

    /// プレーンテキストでリスト変更が許可されていないことを警告
    private func showPlainTextListChangeNotAllowedAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("List Not Available", comment: "Alert title for list not available in plain text")
        alert.informativeText = NSLocalizedString("Lists cannot be used in plain text documents. To use lists, convert the document to Rich Text format.", comment: "Alert message for list not available in plain text")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))

        if let window = self.window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    /// Inspector barからのLine Spacing変更を処理
    /// プレーンテキストでは全文に適用
    override func setBaseWritingDirection(_ writingDirection: NSWritingDirection, range: NSRange) {
        if isPlainText {
            // プレーンテキストでは全文に適用
            guard let textStorage = textStorage, textStorage.length > 0 else {
                super.setBaseWritingDirection(writingDirection, range: range)
                return
            }
            let fullRange = NSRange(location: 0, length: textStorage.length)
            super.setBaseWritingDirection(writingDirection, range: fullRange)
            return
        }
        super.setBaseWritingDirection(writingDirection, range: range)
    }

    // MARK: - Character Color Support

    /// カラーパネルからの自動changeColor呼び出しを制御
    /// カスタムカラーパネルモードがアクティブな場合は無視
    @objc override func changeColor(_ sender: Any?) {
        // カスタムカラーパネルモードがアクティブな場合は無視
        // （colorPanelChanged で処理される）
        if colorPanelMode != .none {
            return
        }
        // それ以外は標準動作
        super.changeColor(sender)
    }

    /// 文字前景色を変更 (Format > Font > Character Fore Color)
    @objc func changeForeColor(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem,
              let color = menuItem.representedObject as? NSColor else {
            return
        }

        // プレーンテキストの場合、アラートを表示して確認
        if isPlainText {
            showPlainTextAttributeChangeAlert(
                message: NSLocalizedString("Character Fore Color", comment: "Alert title for fore color change in plain text"),
                informativeText: NSLocalizedString("In plain text documents, color changes apply to the entire document. Do you want to continue?", comment: "Alert message for color change in plain text")
            ) { [weak self] in
                self?.applyForeColorToEntireDocument(color)
            }
            return
        }

        // RTF の場合は選択範囲に適用
        applyForeColorToSelection(color)
    }

    /// カラーパネルから前景色を選択 (Format > Font > Character Fore Color > Other Color...)
    @objc func orderFrontForeColorPanel(_ sender: Any?) {
        // プレーンテキストの場合、アラートを表示して確認
        if isPlainText {
            showPlainTextAttributeChangeAlert(
                message: NSLocalizedString("Character Fore Color", comment: "Alert title for fore color change in plain text"),
                informativeText: NSLocalizedString("In plain text documents, color changes apply to the entire document. Do you want to continue?", comment: "Alert message for color change in plain text")
            ) { [weak self] in
                self?.showForeColorPanel()
            }
            return
        }

        showForeColorPanel()
    }

    /// 文字背景色を変更 (Format > Font > Character Back Color)
    @objc func changeBackColor(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem else {
            return
        }
        let color = menuItem.representedObject as? NSColor  // nil = Clear

        // プレーンテキストの場合、アラートを表示して確認
        if isPlainText {
            showPlainTextAttributeChangeAlert(
                message: NSLocalizedString("Character Back Color", comment: "Alert title for back color change in plain text"),
                informativeText: NSLocalizedString("In plain text documents, color changes apply to the entire document. Do you want to continue?", comment: "Alert message for color change in plain text")
            ) { [weak self] in
                self?.applyBackColorToEntireDocument(color)
            }
            return
        }

        // RTF の場合は選択範囲に適用
        applyBackColorToSelection(color)
    }

    /// カラーパネルから背景色を選択 (Format > Font > Character Back Color > Other Color...)
    @objc func orderFrontBackColorPanel(_ sender: Any?) {
        // プレーンテキストの場合、アラートを表示して確認
        if isPlainText {
            showPlainTextAttributeChangeAlert(
                message: NSLocalizedString("Character Back Color", comment: "Alert title for back color change in plain text"),
                informativeText: NSLocalizedString("In plain text documents, color changes apply to the entire document. Do you want to continue?", comment: "Alert message for color change in plain text")
            ) { [weak self] in
                self?.showBackColorPanel()
            }
            return
        }

        showBackColorPanel()
    }

    /// 前景色カラーパネルを表示
    private func showForeColorPanel() {
        colorPanelMode = .foreground
        let colorPanel = NSColorPanel.shared
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(colorPanelChanged(_:)))
        colorPanel.color = self.textColor ?? .black
        colorPanel.orderFront(nil)

        // カラーパネルが閉じられた時にモードをリセット
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(colorPanelWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: colorPanel
        )
    }

    /// 背景色カラーパネルを表示
    private func showBackColorPanel() {
        colorPanelMode = .background
        let colorPanel = NSColorPanel.shared
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(colorPanelChanged(_:)))
        colorPanel.color = self.backgroundColor
        colorPanel.orderFront(nil)

        // カラーパネルが閉じられた時にモードをリセット
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(colorPanelWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: colorPanel
        )
    }

    /// カラーパネルが閉じられた時の処理
    @objc private func colorPanelWillClose(_ notification: Notification) {
        colorPanelMode = .none
        // オブザーバーを解除
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.willCloseNotification,
            object: NSColorPanel.shared
        )
    }

    /// カラーパネルから色が変更された
    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        let color = sender.color
        switch colorPanelMode {
        case .foreground:
            if isPlainText {
                applyForeColorToEntireDocument(color)
            } else {
                applyForeColorToSelection(color)
            }
        case .background:
            if isPlainText {
                applyBackColorToEntireDocument(color)
            } else {
                applyBackColorToSelection(color)
            }
        case .none:
            break
        }
    }

    /// 選択範囲に前景色を適用（Undo/Redo対応）
    private func applyForeColorToSelection(_ color: NSColor) {
        let range = selectedRange()
        guard range.length > 0 else { return }

        // applyAttributesを使って色を適用（Undo対応）
        applyAttributes([.foregroundColor: color], to: range)
    }

    /// 選択範囲に背景色を適用（Undo/Redo対応）
    private func applyBackColorToSelection(_ color: NSColor?) {
        let range = selectedRange()
        guard range.length > 0 else { return }

        // applyAttributes/removeAttributeを使って色を適用（Undo対応）
        if let color = color {
            applyAttributes([.backgroundColor: color], to: range)
        } else {
            removeAttribute(.backgroundColor, from: range)
        }
    }

    /// プレーンテキスト全文に前景色を適用
    private func applyForeColorToEntireDocument(_ color: NSColor) {
        guard let windowController = window?.windowController as? EditorWindowController else {
            return
        }
        windowController.applyForeColorToEntireDocument(color)
    }

    /// プレーンテキスト全文に背景色を適用
    private func applyBackColorToEntireDocument(_ color: NSColor?) {
        guard let windowController = window?.windowController as? EditorWindowController else {
            return
        }
        windowController.applyBackColorToEntireDocument(color)
    }

    // MARK: - Plain Text Attribute Change Support

    /// プレーンテキストで属性変更時にアラートを表示
    /// - Parameters:
    ///   - message: アラートのタイトル
    ///   - informativeText: アラートの説明文
    ///   - onConfirm: OKが押された時のコールバック
    private func showPlainTextAttributeChangeAlert(message: String, informativeText: String, onConfirm: @escaping () -> Void) {
        guard let window = self.window else {
            onConfirm()
            return
        }

        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informativeText
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                onConfirm()
            }
        }
    }

    /// プレーンテキスト全文に下線をトグル適用
    /// EditorWindowControllerのメソッドに委譲（Undo/Redo対応）
    private func applyUnderlineToEntireDocument() {
        guard let windowController = window?.windowController as? EditorWindowController else {
            return
        }
        windowController.applyUnderlineToEntireDocument()
    }

    /// プレーンテキスト全文にカーニングを適用
    /// EditorWindowControllerのメソッドに委譲（Undo/Redo対応）
    private func applyKernToEntireDocument(value: Float?) {
        guard let windowController = window?.windowController as? EditorWindowController else {
            return
        }
        windowController.applyKernToEntireDocument(value: value)
    }

    /// プレーンテキスト全文のカーニングを調整
    /// EditorWindowControllerのメソッドに委譲（Undo/Redo対応）
    private func adjustKernToEntireDocument(delta: Float) {
        guard let windowController = window?.windowController as? EditorWindowController else {
            return
        }
        windowController.adjustKernToEntireDocument(delta: delta)
    }

    /// プレーンテキスト全文に合字設定を適用
    /// EditorWindowControllerのメソッドに委譲（Undo/Redo対応）
    private func applyLigatureToEntireDocument(value: Int) {
        guard let windowController = window?.windowController as? EditorWindowController else {
            return
        }
        windowController.applyLigatureToEntireDocument(value: value)
    }

    /// プレーンテキスト全文にフォントを適用し、presetDataを更新
    /// EditorWindowControllerのメソッドに委譲（Undo/Redo対応）
    private func applyFontToEntireDocument(_ font: NSFont) {
        guard let windowController = window?.windowController as? EditorWindowController else {
            return
        }

        // EditorWindowControllerのメソッドを呼び出す（Undo/Redo対応済み）
        windowController.applyFontToEntireDocument(font)
    }

    // MARK: - Tab Handling

    /// タブキーが押されたときの処理
    /// タブ幅の単位が "spaces" の場合はスペース文字を挿入
    override func insertTab(_ sender: Any?) {
        guard let windowController = window?.windowController as? EditorWindowController,
              let presetData = windowController.textDocument?.presetData else {
            super.insertTab(sender)
            return
        }

        let tabUnit = presetData.format.tabWidthUnit

        if tabUnit == .spaces {
            // スペースモード: 指定された数のスペース文字を挿入
            let spaceCount = Int(presetData.format.tabWidthPoints)
            let spaces = String(repeating: " ", count: max(1, spaceCount))
            insertText(spaces, replacementRange: selectedRange())
        } else {
            // ポイントモード: 通常のタブ文字を挿入
            super.insertTab(sender)
        }
    }

    // MARK: - Auto Indent

    /// 改行が挿入されたときの処理
    /// Auto Indent が有効な場合、現在の行の先頭の空白文字を新しい行にコピー
    /// プレーンテキストで Wrapped Line Indent が有効な場合、パラグラフスタイルも設定
    override func insertNewline(_ sender: Any?) {
        guard let windowController = window?.windowController as? EditorWindowController,
              let presetData = windowController.textDocument?.presetData,
              presetData.format.autoIndent else {
            // Auto Indent が無効な場合は通常の改行
            super.insertNewline(sender)
            return
        }

        // 現在のカーソル位置を取得
        let currentRange = selectedRange()

        // 現在の行の先頭のインデント文字列を取得
        let indentString = getLeadingIndent(at: currentRange.location)

        // 改行 + インデント文字列を挿入
        let newlineWithIndent = "\n" + indentString
        insertText(newlineWithIndent, replacementRange: currentRange)

        // プレーンテキストの場合のみ Wrapped Line Indent のパラグラフスタイルを適用
        if isPlainText {
            applyWrappedLineIndentStyle(
                indentString: indentString,
                presetData: presetData
            )
        }
    }

    /// Wrapped Line Indent のパラグラフスタイルを新しい行に適用（プレーンテキスト専用）
    /// - Parameters:
    ///   - indentString: Auto Indent でコピーされた空白文字列
    ///   - presetData: ドキュメントのプリセットデータ
    private func applyWrappedLineIndentStyle(indentString: String, presetData: NewDocData) {
        guard let textStorage = textStorage else { return }

        // 現在のカーソル位置（改行 + インデント挿入後）
        let cursorLocation = selectedRange().location

        // 新しい行の開始位置を計算（カーソル位置 - インデント文字列の長さ）
        let newLineStart = cursorLocation - indentString.count

        // 範囲チェック：空のテキストや範囲外の場合は何もしない
        guard newLineStart >= 0, textStorage.length > 0, newLineStart < textStorage.length else { return }

        // 新しい行のパラグラフ範囲を取得
        let paragraphRange = (textStorage.string as NSString).paragraphRange(for: NSRange(location: newLineStart, length: 0))

        // インデント文字列の幅をポイントで計算
        let indentWidth = calculateIndentWidth(indentString: indentString, presetData: presetData)

        // 現在のパラグラフスタイルを取得または新規作成
        let existingStyle = textStorage.attribute(.paragraphStyle, at: newLineStart, effectiveRange: nil) as? NSParagraphStyle
        let newStyle = (existingStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()

        if presetData.format.indentWrappedLines {
            // Wrapped Line Indent がオンの場合
            // firstLineHeadIndent = 0
            // headIndent = インデント幅 + wrappedLineIndent
            newStyle.firstLineHeadIndent = 0
            newStyle.headIndent = indentWidth + presetData.format.wrappedLineIndent
        } else {
            // Wrapped Line Indent がオフの場合
            // firstLineHeadIndent = 0
            // headIndent = 0
            newStyle.firstLineHeadIndent = 0
            newStyle.headIndent = 0
        }

        // パラグラフスタイルを適用
        textStorage.addAttribute(.paragraphStyle, value: newStyle, range: paragraphRange)
    }

    /// インデント文字列の幅をポイントで計算
    /// - Parameters:
    ///   - indentString: 空白文字列（タブ、半角スペース、全角スペース）
    ///   - presetData: ドキュメントのプリセットデータ
    /// - Returns: インデント幅（ポイント）
    private func calculateIndentWidth(indentString: String, presetData: NewDocData) -> CGFloat {
        var totalWidth: CGFloat = 0

        // フォントを取得
        let font = NSFont(name: presetData.fontAndColors.baseFontName, size: presetData.fontAndColors.baseFontSize)
            ?? NSFont.systemFont(ofSize: presetData.fontAndColors.baseFontSize)

        // タブ幅を取得
        let tabWidth: CGFloat
        if presetData.format.tabWidthUnit == .spaces {
            // スペースモードの場合、スペースの幅 × スペース数
            let spaceWidth = " ".size(withAttributes: [.font: font]).width
            tabWidth = spaceWidth * presetData.format.tabWidthPoints
        } else {
            // ポイントモードの場合、直接ポイント数を使用
            tabWidth = presetData.format.tabWidthPoints
        }

        // 各文字の幅を計算
        for char in indentString {
            switch char {
            case "\t":
                // タブ文字
                totalWidth += tabWidth
            case " ":
                // 半角スペース
                let spaceWidth = " ".size(withAttributes: [.font: font]).width
                totalWidth += spaceWidth
            case "\u{3000}":
                // 全角スペース
                let fullWidthSpaceWidth = "　".size(withAttributes: [.font: font]).width
                totalWidth += fullWidthSpaceWidth
            default:
                break
            }
        }

        return totalWidth
    }

    /// 指定位置の行の先頭にある空白文字（タブ、半角スペース、全角スペース）を取得
    /// - Parameter location: テキスト内の位置
    /// - Returns: 行の先頭の空白文字列
    private func getLeadingIndent(at location: Int) -> String {
        guard let textStorage = textStorage else { return "" }
        let text = textStorage.string as NSString

        // 現在位置から行の先頭を探す
        var lineStart = location
        while lineStart > 0 {
            let prevChar = text.character(at: lineStart - 1)
            // 改行文字（\n, \r）を見つけたらそこで止める
            if prevChar == 0x0A || prevChar == 0x0D {
                break
            }
            lineStart -= 1
        }

        // 行の先頭から空白文字を収集
        var indentString = ""
        var pos = lineStart
        while pos < text.length && pos < location {
            let char = text.character(at: pos)
            // タブ (0x09), 半角スペース (0x20), 全角スペース (0x3000)
            if char == 0x09 || char == 0x20 || char == 0x3000 {
                indentString.append(Character(UnicodeScalar(char)!))
                pos += 1
            } else {
                // 空白以外の文字が出現したら終了
                break
            }
        }

        return indentString
    }

    // MARK: - Ruler Update Safety

    /// ルーラー更新をオーバーライドして空のtextStorageでのクラッシュを防ぐ
    /// プレーンテキストの場合はアクセサリビュー（段落スタイルコントロール）を非表示にする
    override func updateRuler() {
        // 再入防止
        guard !isUpdatingRuler else { return }
        isUpdatingRuler = true
        defer { isUpdatingRuler = false }

        // ウィンドウが閉じようとしている場合はスキップ
        guard let window = window else { return }

        // textStorageが空または無効な場合はルーラー更新をスキップ
        guard let textStorage = textStorage,
              textStorage.length > 0 else {
            return
        }
        super.updateRuler()

        // プレーンテキストの場合はルーラーのアクセサリビューを非表示にする
        // ウィンドウが表示中かつウィンドウコントローラーにアクセス可能な場合のみ
        if window.isVisible,
           let windowController = window.windowController as? EditorWindowController,
           windowController.textDocument?.documentType == .plain {
            if let scrollView = enclosingScrollView {
                if let horizontalRuler = scrollView.horizontalRulerView,
                   horizontalRuler.accessoryView != nil {
                    horizontalRuler.accessoryView = nil
                    horizontalRuler.reservedThicknessForAccessoryView = 0
                }
                if let verticalRuler = scrollView.verticalRulerView,
                   verticalRuler.accessoryView != nil {
                    verticalRuler.accessoryView = nil
                    verticalRuler.reservedThicknessForAccessoryView = 0
                }
            }
        }
    }

    // MARK: - Paste and Drop Text Conversion

    /// ペースト時に文字変換を適用
    override func paste(_ sender: Any?) {
        // ペーストボードからテキストを取得して変換を適用
        let pasteboard = NSPasteboard.general
        if let string = pasteboard.string(forType: .string) {
            let convertedString = applyTextConversions(string)
            // 変換後の文字列をペースト
            insertText(convertedString, replacementRange: selectedRange())
        } else {
            // テキスト以外の場合は通常のペースト
            super.paste(sender)
        }
    }

    /// 属性付きテキストのペースト時に文字変換を適用
    override func pasteAsRichText(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let rtfData = pasteboard.data(forType: .rtf),
           let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            let convertedString = applyTextConversionsToAttributedString(attributedString)
            insertText(convertedString, replacementRange: selectedRange())
        } else {
            super.pasteAsRichText(sender)
        }
    }

    /// プレーンテキストとしてペースト時に文字変換を適用
    override func pasteAsPlainText(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let string = pasteboard.string(forType: .string) {
            let convertedString = applyTextConversions(string)
            insertText(convertedString, replacementRange: selectedRange())
        } else {
            super.pasteAsPlainText(sender)
        }
    }

    /// ドラッグ＆ドロップ時に文字変換を適用
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        // テキストタイプの場合は変換を適用
        if type == .string, let string = pboard.string(forType: .string) {
            let convertedString = applyTextConversions(string)
            insertText(convertedString, replacementRange: selectedRange())
            return true
        } else if type == .rtf, let rtfData = pboard.data(forType: .rtf),
                  let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            let convertedString = applyTextConversionsToAttributedString(attributedString)
            insertText(convertedString, replacementRange: selectedRange())
            return true
        }
        return super.readSelection(from: pboard, type: type)
    }

    /// 文字列に対して文字変換を適用
    /// - Parameter string: 変換対象の文字列
    /// - Returns: 変換後の文字列
    private func applyTextConversions(_ string: String) -> String {
        let defaults = UserDefaults.standard
        var result = string

        // 1. 改行コードをLFに統一
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")

        // 2. 円記号をバックスラッシュに変換（設定が有効な場合）
        if defaults.bool(forKey: UserDefaults.Keys.convertYenToBackSlash) {
            result = result.replacingOccurrences(of: "\u{00A5}", with: "\\")
        }

        // 3. オーバーラインをチルダに変換（設定が有効な場合）
        if defaults.bool(forKey: UserDefaults.Keys.convertOverlineToTilde) {
            result = result.replacingOccurrences(of: "\u{203E}", with: "~")
        }

        // 4. 全角チルダを波ダッシュに変換（設定が有効な場合）
        if defaults.bool(forKey: UserDefaults.Keys.convertFullWidthTilde) {
            result = result.replacingOccurrences(of: "\u{FF5E}", with: "\u{301C}")
        }

        return result
    }

    /// 属性付き文字列に対して文字変換を適用
    /// - Parameter attributedString: 変換対象の属性付き文字列
    /// - Returns: 変換後の属性付き文字列
    private func applyTextConversionsToAttributedString(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        let convertedText = applyTextConversions(mutableString.string)

        // 文字列の長さが変わる可能性があるため、属性を保持しながら文字列を置換
        // 簡易的な実装: 元の属性を最初の文字から取得して適用
        if mutableString.length > 0 {
            let attributes = mutableString.attributes(at: 0, effectiveRange: nil)
            return NSAttributedString(string: convertedText, attributes: attributes)
        } else {
            return NSAttributedString(string: convertedText)
        }
    }

    // MARK: - Menu Validation

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let action = menuItem.action

        // Baseline submenu actions and Character colors are disabled for plain text
        // (These attributes are not meaningful in plain text documents)
        if isPlainText {
            // Note: subscript is a Swift keyword, so we use Selector directly
            let subscriptSelector = Selector(("subscript:"))
            switch action {
            case #selector(raiseBaseline(_:)),
                 #selector(lowerBaseline(_:)),
                 #selector(superscript(_:)),
                 #selector(unscript(_:)),
                 subscriptSelector,
                 #selector(changeForeColor(_:)),
                 #selector(orderFrontForeColorPanel(_:)),
                 #selector(changeBackColor(_:)),
                 #selector(orderFrontBackColorPanel(_:)):
                return false
            default:
                break
            }
        }

        // Substitution actions that respect "Rich Text Only" setting
        // When "Following Substitutions Enabled Only in Rich Text" is ON and this is plain text,
        // show these items as unchecked (but still enabled)
        if richTextSubstitutionsOnly && isPlainText {
            switch action {
            case #selector(toggleAutomaticQuoteSubstitution(_:)),
                 #selector(toggleAutomaticDashSubstitution(_:)),
                 #selector(toggleAutomaticTextReplacement(_:)),
                 #selector(toggleAutomaticSpellingCorrection(_:)):
                menuItem.state = .off
                return true
            default:
                break
            }
        }

        return super.validateMenuItem(menuItem)
    }
}
