//
//  JeditTextView+Styling.swift
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

extension JeditTextView {

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
                message: "Change Font".localized,
                informativeText: "In plain text documents, font changes apply to the entire document. Do you want to continue?".localized
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
    func showPlainTextColorChangeNotAllowedAlert() {
        let alert = NSAlert()
        alert.messageText = "Color Change Not Allowed".localized
        alert.informativeText = "Character colors cannot be changed in plain text documents. To change colors, convert the document to Rich Text format.".localized
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK".localized)

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
                message: "Underline".localized,
                informativeText: "In plain text documents, underline changes apply to the entire document. Do you want to continue?".localized
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
                message: "Kern".localized,
                informativeText: "In plain text documents, kerning changes apply to the entire document. Do you want to continue?".localized
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
                message: "Kern".localized,
                informativeText: "In plain text documents, kerning changes apply to the entire document. Do you want to continue?".localized
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
                message: "Kern".localized,
                informativeText: "In plain text documents, kerning changes apply to the entire document. Do you want to continue?".localized
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
                message: "Kern".localized,
                informativeText: "In plain text documents, kerning changes apply to the entire document. Do you want to continue?".localized
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
                message: "Ligatures".localized,
                informativeText: "In plain text documents, ligature changes apply to the entire document. Do you want to continue?".localized
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
                message: "Ligatures".localized,
                informativeText: "In plain text documents, ligature changes apply to the entire document. Do you want to continue?".localized
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
                message: "Ligatures".localized,
                informativeText: "In plain text documents, ligature changes apply to the entire document. Do you want to continue?".localized
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
                message: "Text Alignment".localized,
                informativeText: "In plain text documents, alignment changes apply to the entire document. Do you want to continue?".localized
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
                message: "Text Alignment".localized,
                informativeText: "In plain text documents, alignment changes apply to the entire document. Do you want to continue?".localized
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
                message: "Text Alignment".localized,
                informativeText: "In plain text documents, alignment changes apply to the entire document. Do you want to continue?".localized
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
                message: "Text Alignment".localized,
                informativeText: "In plain text documents, alignment changes apply to the entire document. Do you want to continue?".localized
            ) { [weak self] in
                self?.applyAlignmentToEntireDocument(.justified)
            }
            return
        }
        super.alignJustified(sender)
    }

    /// プレーンテキスト全文にアラインメントを適用
    func applyAlignmentToEntireDocument(_ alignment: NSTextAlignment) {
        guard let windowController = window?.windowController as? EditorWindowController else {
            return
        }
        windowController.applyAlignmentToEntireDocument(alignment)
    }

    // MARK: - Paragraph Style Support (Inspector Bar)

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

                // 全文に適用（Undo グルーピングを壊さないよう Undo 登録を無効化）
                let fullRange = NSRange(location: 0, length: textStorage.length)
                undoManager?.disableUndoRegistration()
                textStorage.addAttribute(.paragraphStyle, value: mutableStyle, range: fullRange)
                undoManager?.enableUndoRegistration()
            }
        } else if let currentStyle = currentStyle {
            // リストがない場合、段落スタイル（Line Spacingなど）を全文に適用
            // ただし、段落スタイルが変更された場合のみ
            applyParagraphStyleToEntireDocumentIfNeeded(currentStyle)
        }

        previousTextLists = nil
    }

    /// 段落スタイルを全文に適用（プレーンテキスト用）
    /// Line Spacing、段落間隔などが変更された場合に全文に適用
    func applyParagraphStyleToEntireDocumentIfNeeded(_ newStyle: NSParagraphStyle) {
        guard let textStorage = textStorage, textStorage.length > 0 else { return }

        // 全文に段落スタイルを適用
        let fullRange = NSRange(location: 0, length: textStorage.length)

        // 現在のスタイルと同じかどうかを確認（最初の文字の段落スタイルと比較）
        let firstCharStyle = textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        if firstCharStyle != newStyle {
            // Undo 登録を無効化して、NSTextView の自動 Undo グルーピングを壊さないようにする
            undoManager?.disableUndoRegistration()
            textStorage.addAttribute(.paragraphStyle, value: newStyle, range: fullRange)
            undoManager?.enableUndoRegistration()
        }
    }

    /// プレーンテキストでリスト変更が許可されていないことを警告
    func showPlainTextListChangeNotAllowedAlert() {
        let alert = NSAlert()
        alert.messageText = "List Not Available".localized
        alert.informativeText = "Lists cannot be used in plain text documents. To use lists, convert the document to Rich Text format.".localized
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK".localized)

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
        // スタイル情報パネルがカラーパネルを管理中の場合は無視
        // （全ての色変更は StyleInfoPanelController.colorPanelDidChangeColor で処理する）
        if StyleInfoPanelController.shared.isManagingColorPanel() {
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
                message: "Character Fore Color".localized,
                informativeText: "In plain text documents, color changes apply to the entire document. Do you want to continue?".localized
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
                message: "Character Fore Color".localized,
                informativeText: "In plain text documents, color changes apply to the entire document. Do you want to continue?".localized
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
                message: "Character Back Color".localized,
                informativeText: "In plain text documents, color changes apply to the entire document. Do you want to continue?".localized
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
                message: "Character Back Color".localized,
                informativeText: "In plain text documents, color changes apply to the entire document. Do you want to continue?".localized
            ) { [weak self] in
                self?.showBackColorPanel()
            }
            return
        }

        showBackColorPanel()
    }

    /// 前景色カラーパネルを表示
    func showForeColorPanel() {
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
    func showBackColorPanel() {
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
    @objc func colorPanelWillClose(_ notification: Notification) {
        colorPanelMode = .none
        // オブザーバーを解除
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.willCloseNotification,
            object: NSColorPanel.shared
        )
    }

    /// カラーパネルから色が変更された
    @objc func colorPanelChanged(_ sender: NSColorPanel) {
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
    func applyForeColorToSelection(_ color: NSColor) {
        let range = selectedRange()
        guard range.length > 0 else { return }

        // applyAttributesを使って色を適用（Undo対応）
        applyAttributes([.foregroundColor: color], to: range)
    }

    /// 選択範囲に背景色を適用（Undo/Redo対応）
    func applyBackColorToSelection(_ color: NSColor?) {
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
    func applyForeColorToEntireDocument(_ color: NSColor) {
        guard let windowController = window?.windowController as? EditorWindowController else {
            return
        }
        windowController.applyForeColorToEntireDocument(color)
    }

    /// プレーンテキスト全文に背景色を適用
    func applyBackColorToEntireDocument(_ color: NSColor?) {
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
    func showPlainTextAttributeChangeAlert(message: String, informativeText: String, onConfirm: @escaping () -> Void) {
        guard let window = self.window else {
            onConfirm()
            return
        }

        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informativeText
        alert.addButton(withTitle: "OK".localized)
        alert.addButton(withTitle: "Cancel".localized)

        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                onConfirm()
            }
        }
    }

    /// プレーンテキスト全文に下線をトグル適用
    /// EditorWindowControllerのメソッドに委譲（Undo/Redo対応）
    func applyUnderlineToEntireDocument() {
        guard let windowController = window?.windowController as? EditorWindowController else {
            return
        }
        windowController.applyUnderlineToEntireDocument()
    }

    /// プレーンテキスト全文にカーニングを適用
    /// EditorWindowControllerのメソッドに委譲（Undo/Redo対応）
    func applyKernToEntireDocument(value: Float?) {
        guard let windowController = window?.windowController as? EditorWindowController else {
            return
        }
        windowController.applyKernToEntireDocument(value: value)
    }

    /// プレーンテキスト全文のカーニングを調整
    /// EditorWindowControllerのメソッドに委譲（Undo/Redo対応）
    func adjustKernToEntireDocument(delta: Float) {
        guard let windowController = window?.windowController as? EditorWindowController else {
            return
        }
        windowController.adjustKernToEntireDocument(delta: delta)
    }

    /// プレーンテキスト全文に合字設定を適用
    /// EditorWindowControllerのメソッドに委譲（Undo/Redo対応）
    func applyLigatureToEntireDocument(value: Int) {
        guard let windowController = window?.windowController as? EditorWindowController else {
            return
        }
        windowController.applyLigatureToEntireDocument(value: value)
    }

    /// プレーンテキスト全文にフォントを適用し、presetDataを更新
    /// EditorWindowControllerのメソッドに委譲（Undo/Redo対応）
    func applyFontToEntireDocument(_ font: NSFont) {
        guard let windowController = window?.windowController as? EditorWindowController else {
            return
        }

        // EditorWindowControllerのメソッドを呼び出す（Undo/Redo対応済み）
        windowController.applyFontToEntireDocument(font)
    }

    // MARK: - Style Menu Actions

    /// スタイルメニューからスタイルを適用
    @objc func applyTextStyle(_ sender: NSMenuItem) {
        guard let style = sender.representedObject as? TextStyle,
              let textStorage = textStorage else { return }

        let range = selectedRange()

        if range.length == 0 {
            // 選択なし: typingAttributes を更新して、以降の入力に適用
            let merged = style.mergedAttributes(with: typingAttributes)
            typingAttributes = merged
            return
        }

        // shouldChangeText(replacementString: nil) で属性変更を通知し、Undo を自動登録
        if shouldChangeText(in: range, replacementString: nil) {
            textStorage.beginEditing()
            textStorage.enumerateAttributes(in: range, options: []) { existingAttrs, subRange, _ in
                let mergedAttrs = style.mergedAttributes(with: existingAttrs)
                textStorage.setAttributes(mergedAttrs, range: subRange)
            }
            textStorage.endEditing()
            didChangeText()
        }
    }
}
