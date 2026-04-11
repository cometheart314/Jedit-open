//
//  Document+Export.swift
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
import UniformTypeIdentifiers

extension Document {

    // MARK: - Encoding Selection

    /// エンコーディング選択ダイアログをモーダルで表示（ドキュメントを開く前に使用）
    /// - Parameter candidates: エンコーディング候補リスト
    /// - Returns: ユーザーが選択したエンコーディング、キャンセル時は最初の候補
    func showEncodingSelectionDialogModal(candidates: [EncodingDetectionResult]) -> String.Encoding? {
        guard !candidates.isEmpty else { return nil }

        let alert = NSAlert()
        alert.messageText = "Text Encoding".localized
        alert.informativeText = "The text encoding could not be determined with high confidence. Please select the correct encoding:".localized
        alert.alertStyle = .warning

        // ポップアップボタンを作成
        let popupButton = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 25), pullsDown: false)
        for candidate in candidates {
            let title = "\(candidate.name) (\(candidate.confidence)%)"
            popupButton.addItem(withTitle: title)
            popupButton.lastItem?.representedObject = candidate.encoding
        }
        alert.accessoryView = popupButton

        alert.addButton(withTitle: "OK".localized)
        alert.addButton(withTitle: "Cancel".localized)

        // モーダルで表示
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // ユーザーが選択したエンコーディングを返す
            return popupButton.selectedItem?.representedObject as? String.Encoding
        } else {
            // キャンセル時は最初の候補を返す（ファイルを開くため）
            return candidates.first?.encoding
        }
    }

    // MARK: - Duplicate

    /// 複製されたドキュメントには元の書類の presetData を引き継ぐ
    /// （Duplicate で作られた書類は通常の RTF として扱う）
    override func duplicate() throws -> NSDocument {
        // 複製前に現在のウィンドウ状態で presetData を更新
        updatePresetDataFromCurrentState()

        // init() で参照できるよう static 変数にセット
        Self.duplicatingPresetData = self.presetData

        let newDoc: NSDocument
        do {
            newDoc = try super.duplicate()
        } catch {
            Self.duplicatingPresetData = nil
            throw error
        }
        Self.duplicatingPresetData = nil

        if let newDocument = newDoc as? Document {
            newDocument.isMarkdownDocument = self.isMarkdownDocument
        }
        return newDoc
    }

    // MARK: - Save Panel

    /// ドキュメントの保存可能なタイプを返す
    /// documentTypeに応じて適切なファイルタイプを優先的に返す
    override nonisolated func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        // ドキュメントタイプに応じた順序で返す（現在のタイプを先頭にする）
        // Note: Markdown ドキュメントは documentType = .rtf として扱う。
        // data(ofType:) は常に RTF を返し、save 完了後にファイルを Markdown で上書きする
        let docType = MainActor.assumeIsolated { self.documentType }
        switch docType {
        case .plain:
            return ["public.plain-text", "public.rtf", "com.apple.rtfd"]
        case .rtfd:
            return ["com.apple.rtfd", "public.rtf", "public.plain-text"]
        default:
            return ["public.rtf", "com.apple.rtfd", "public.plain-text"]
        }
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        // 前回の Save Panel 状態をクリーンアップ
        savePanelFormatTag = nil
        savePanelEncodingPopUp = nil
        savePanelLineEndingPopUp = nil
        savePanelBOMCheckbox = nil
        saveFormatAction = nil
        saveEncodingAction = nil

        // ExportAccessoryView.xib を読み込む
        var topLevelObjects: NSArray?
        guard Bundle.main.loadNibNamed("ExportAccessoryView", owner: nil, topLevelObjects: &topLevelObjects),
              let objects = topLevelObjects,
              let accessoryView = objects.compactMap({ $0 as? NSView }).first(where: { $0.frame.size.height > 0 })
        else {
            return super.prepareSavePanel(savePanel)
        }

        // アクセサリビュー内のコントロールをプロパティで特定（Export と同じロジック）
        let allButtons = accessoryView.subviews.compactMap { $0 as? NSButton }
        let allPopUps = accessoryView.subviews.compactMap { $0 as? NSPopUpButton }
        let allLabels = accessoryView.subviews.compactMap { $0 as? NSTextField }

        let encodingPopUp = allPopUps.first(where: { $0.toolTip?.contains("encoding") == true })
        let formatPopUp = allPopUps.first(where: { $0 !== encodingPopUp && $0.numberOfItems > 4 })
        let lineEndingPopUp = allPopUps.first(where: { $0 !== encodingPopUp && $0 !== formatPopUp })
        let bomCheckbox = allButtons.first(where: { ($0.cell as? NSButtonCell)?.title == "BOM" })
        let selectionOnlyCheckbox = allButtons.first(where: { ($0.cell as? NSButtonCell)?.title.contains("Selection") == true })
        let encodingLabel = allLabels.first(where: { ($0.cell as? NSTextFieldCell)?.title == "Encoding:" })

        // 「Export Only Selection」チェックボックスを非表示にする（Save では不要）
        selectionOnlyCheckbox?.isHidden = true

        // エンコーディングポップアップを手動で構築
        if let encodingCell = encodingPopUp?.cell as? NSPopUpButtonCell {
            EncodingManager.shared.setupPopUpCell(encodingCell,
                                                   selectedEncoding: UInt(documentEncoding.rawValue),
                                                   withDefaultEntry: false)
            EncodingManager.shared.disableIncompatibleEncodings(in: encodingCell, for: textStorage.string)
        }

        // 現在のドキュメントタイプに基づいて初期フォーマットを選択
        if isMarkdownDocument {
            formatPopUp?.selectItem(withTag: 7)
        } else {
            switch documentType {
            case .plain:
                formatPopUp?.selectItem(withTag: 0)
            case .rtfd:
                formatPopUp?.selectItem(withTag: 2)
            default:
                // アタッチメントが含まれている場合は RTFD を選択
                if textStorage.containsAttachments {
                    formatPopUp?.selectItem(withTag: 2)
                } else {
                    formatPopUp?.selectItem(withTag: 1)
                }
            }
        }

        // 初期フォーマットタグを保存
        savePanelFormatTag = formatPopUp?.selectedTag()

        // 改行コード・BOMの初期値を設定
        lineEndingPopUp?.selectItem(withTag: lineEnding.rawValue)
        bomCheckbox?.state = hasBOM ? .on : .off

        // Unicode エンコーディング判定クロージャ
        let isUnicodeEncoding: () -> Bool = {
            guard let cell = encodingPopUp?.cell as? NSPopUpButtonCell,
                  let selectedItem = cell.selectedItem,
                  let encNumber = selectedItem.representedObject as? NSNumber else { return false }
            return EncodingManager.isUnicodeEncoding(String.Encoding(rawValue: encNumber.uintValue))
        }
        bomCheckbox?.isEnabled = isUnicodeEncoding()

        // アクセサリビューを設定
        savePanel.accessoryView = accessoryView
        savePanel.isExtensionHidden = false
        savePanel.canSelectHiddenExtension = true

        // フォーマットに基づいてパネルの allowedContentTypes を更新
        updateExportPanelContentTypes(savePanel: savePanel, formatTag: formatPopUp?.selectedTag() ?? 1)

        // フォーマットポップアップ変更時のアクション
        saveFormatAction = { [weak self, weak savePanel] in
            guard let self = self, let panel = savePanel,
                  let currentTag = formatPopUp?.selectedTag() else { return }
            self.savePanelFormatTag = currentTag
            self.updateExportPanelContentTypes(savePanel: panel, formatTag: currentTag)
            // プレーンテキスト以外では Encoding/改行/BOM を非表示
            let isPlainText = currentTag == 0
            encodingPopUp?.isHidden = !isPlainText
            encodingLabel?.isHidden = !isPlainText
            lineEndingPopUp?.isHidden = !isPlainText
            bomCheckbox?.isHidden = !isPlainText
        }
        formatPopUp?.target = self
        formatPopUp?.action = #selector(saveFormatPopUpChanged(_:))

        // エンコーディングポップアップ変更時のアクション
        saveEncodingAction = {
            bomCheckbox?.isEnabled = isUnicodeEncoding()
            if !(bomCheckbox?.isEnabled ?? false) {
                bomCheckbox?.state = .off
            }
        }
        encodingPopUp?.target = self
        encodingPopUp?.action = #selector(saveEncodingPopUpChanged(_:))

        // 初期状態でプレーンテキスト以外は Encoding/改行/BOM を非表示
        let isPlainText = (formatPopUp?.selectedTag() ?? 1) == 0
        encodingPopUp?.isHidden = !isPlainText
        encodingLabel?.isHidden = !isPlainText
        lineEndingPopUp?.isHidden = !isPlainText
        bomCheckbox?.isHidden = !isPlainText

        // Save Panel のコントロール参照を保存（save 時に使用）
        savePanelEncodingPopUp = encodingPopUp
        savePanelLineEndingPopUp = lineEndingPopUp
        savePanelBOMCheckbox = bomCheckbox

        // 新規ドキュメント（まだユーザーが明示的に保存していない）の場合、ファイル名を提案
        // autosavesInPlace により fileURL が設定済みの場合があるため、
        // untitledDocumentName の有無で判定する
        if let customName = untitledDocumentName {
            let nameType = presetData?.format.newDocNameType ?? .untitled
            if nameType == .untitled {
                // Untitled の場合は先頭テキストの要約をファイル名として提案
                let suggestedName = generateSuggestedFileName()
                if !suggestedName.isEmpty {
                    savePanel.nameFieldStringValue = suggestedName
                }
            } else {
                // 日付系などカスタム名の場合はそのカスタム名をファイル名として使用
                savePanel.nameFieldStringValue = customName
            }
        }

        return super.prepareSavePanel(savePanel)
    }

    @objc func saveFormatPopUpChanged(_ sender: Any?) {
        saveFormatAction?()
    }

    @objc func saveEncodingPopUpChanged(_ sender: Any?) {
        saveEncodingAction?()
    }

    // MARK: - Export

    /// エクスポートパネルのフォーマットポップアップ変更時コールバック
    var exportFormatAction: (() -> Void)? {
        get { return _exportFormatAction }
        set { _exportFormatAction = newValue }
    }
    /// エクスポートパネルのエンコーディングポップアップ変更時コールバック
    var exportEncodingAction: (() -> Void)? {
        get { return _exportEncodingAction }
        set { _exportEncodingAction = newValue }
    }

    @objc func exportFormatPopUpChanged(_ sender: Any?) {
        _exportFormatAction?()
    }

    @objc func exportEncodingPopUpChanged(_ sender: Any?) {
        _exportEncodingAction?()
    }

    /// Export... メニューアクション
    @IBAction func exportDocument(_ sender: Any?) {
        guard let window = windowControllers.first?.window else { return }

        // ExportAccessoryView.xib を読み込む
        var topLevelObjects: NSArray?
        guard Bundle.main.loadNibNamed("ExportAccessoryView", owner: nil, topLevelObjects: &topLevelObjects),
              let objects = topLevelObjects,
              let accessoryView = objects.compactMap({ $0 as? NSView }).first(where: { $0.frame.size.height > 0 })
        else { return }

        // アクセサリビュー内のコントロールをプロパティで特定
        let allButtons = accessoryView.subviews.compactMap { $0 as? NSButton }
        let allPopUps = accessoryView.subviews.compactMap { $0 as? NSPopUpButton }
        let allLabels = accessoryView.subviews.compactMap { $0 as? NSTextField }

        // Encoding ポップアップ（toolTipで特定。XIBの customClass=EncodingPopUpButtonCell は
        // loadNibNamed 時に NSPopUpButtonCell としてロードされるため cell is では判定不可）
        let encodingPopUp = allPopUps.first(where: { $0.toolTip?.contains("encoding") == true })
        // 8項目以上のメニューを持つポップアップ = File Format ポップアップ
        let formatPopUp = allPopUps.first(where: { $0 !== encodingPopUp && $0.numberOfItems > 4 })
        // 3項目のポップアップ (LF/CR/CR+LF) = 改行コードポップアップ
        let lineEndingPopUp = allPopUps.first(where: { $0 !== encodingPopUp && $0 !== formatPopUp })
        // チェックボックスの中で "BOM" を含むもの
        let bomCheckbox = allButtons.first(where: { ($0.cell as? NSButtonCell)?.title == "BOM" })
        // チェックボックスの中で "Selection" を含むもの
        let selectionOnlyCheckbox = allButtons.first(where: { ($0.cell as? NSButtonCell)?.title.contains("Selection") == true })
        // "Encoding:" ラベル
        let encodingLabel = allLabels.first(where: { ($0.cell as? NSTextFieldCell)?.title == "Encoding:" })

        // NIBロード後にエンコーディングポップアップを手動で構築
        // （XIBの EncodingPopUpButtonCell が NSPopUpButtonCell としてロードされ、
        //   init(coder:) の自動構築が機能しないため、手動でエンコーディングリストを設定する）
        if let encodingCell = encodingPopUp?.cell as? NSPopUpButtonCell {
            EncodingManager.shared.setupPopUpCell(encodingCell,
                                                   selectedEncoding: UInt(documentEncoding.rawValue),
                                                   withDefaultEntry: false)

            // テキスト内容で変換できないエンコーディングをグレイアウト
            EncodingManager.shared.disableIncompatibleEncodings(in: encodingCell, for: textStorage.string)
        }

        // 現在のドキュメントタイプに基づいて初期フォーマットを選択
        if isMarkdownDocument {
            formatPopUp?.selectItem(withTag: 7)
        } else {
            switch documentType {
            case .plain:
                formatPopUp?.selectItem(withTag: 0)
            case .rtfd:
                formatPopUp?.selectItem(withTag: 2)
            default:
                // アタッチメントが含まれている場合は RTFD を選択
                if textStorage.containsAttachments {
                    formatPopUp?.selectItem(withTag: 2)
                } else {
                    formatPopUp?.selectItem(withTag: 1)
                }
            }
        }

        // 改行コードの初期値を設定
        lineEndingPopUp?.selectItem(withTag: lineEnding.rawValue)

        // BOMの初期値を設定
        bomCheckbox?.state = hasBOM ? .on : .off

        // 選択中のエンコーディングがUnicode系かどうかを判定するクロージャ
        let isUnicodeEncoding: () -> Bool = {
            guard let cell = encodingPopUp?.cell as? NSPopUpButtonCell,
                  let selectedItem = cell.selectedItem,
                  let encNumber = selectedItem.representedObject as? NSNumber else { return false }
            return EncodingManager.isUnicodeEncoding(String.Encoding(rawValue: encNumber.uintValue))
        }

        // BOMチェックボックスの初期状態
        bomCheckbox?.isEnabled = isUnicodeEncoding()

        // 選択範囲がない場合は「Export Only Selection」を無効化
        if let textView = windowControllers.first.flatMap({ ($0 as? EditorWindowController)?.currentTextView() }) {
            let hasSelection = textView.selectedRange().length > 0
            selectionOnlyCheckbox?.isEnabled = hasSelection
            if !hasSelection {
                selectionOnlyCheckbox?.state = .off
            }
        }

        // Save パネルを構成
        let savePanel = NSSavePanel()
        savePanel.accessoryView = accessoryView
        savePanel.isExtensionHidden = false
        savePanel.canSelectHiddenExtension = true
        savePanel.title = "Export".localized

        // ファイル名を提案
        if let url = fileURL {
            savePanel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent
        } else {
            let suggestedName = generateSuggestedFileName()
            if !suggestedName.isEmpty {
                savePanel.nameFieldStringValue = suggestedName
            }
        }

        // フォーマットに基づいてパネルのallowedContentTypesを更新
        updateExportPanelContentTypes(savePanel: savePanel, formatTag: formatPopUp?.selectedTag() ?? 1)

        // フォーマットポップアップ変更時のアクション
        _exportFormatAction = { [weak self, weak savePanel] in
            guard let self = self, let panel = savePanel,
                  let currentTag = formatPopUp?.selectedTag() else { return }
            self.updateExportPanelContentTypes(savePanel: panel, formatTag: currentTag)
            // プレーンテキスト以外では Encoding/改行/BOM を非表示
            let isPlainText = currentTag == 0
            encodingPopUp?.isHidden = !isPlainText
            encodingLabel?.isHidden = !isPlainText
            lineEndingPopUp?.isHidden = !isPlainText
            bomCheckbox?.isHidden = !isPlainText
        }
        formatPopUp?.target = self
        formatPopUp?.action = #selector(exportFormatPopUpChanged(_:))

        // エンコーディングポップアップ変更時のアクション
        _exportEncodingAction = {
            bomCheckbox?.isEnabled = isUnicodeEncoding()
            if !(bomCheckbox?.isEnabled ?? false) {
                bomCheckbox?.state = .off
            }
        }
        encodingPopUp?.target = self
        encodingPopUp?.action = #selector(exportEncodingPopUpChanged(_:))

        // 初期状態でプレーンテキスト以外は Encoding/改行/BOM を非表示
        let isPlainText = (formatPopUp?.selectedTag() ?? 1) == 0
        encodingPopUp?.isHidden = !isPlainText
        encodingLabel?.isHidden = !isPlainText
        lineEndingPopUp?.isHidden = !isPlainText
        bomCheckbox?.isHidden = !isPlainText

        savePanel.beginSheetModal(for: window) { [weak self] response in
            // コールバックをクリーンアップ
            self?._exportFormatAction = nil
            self?._exportEncodingAction = nil

            guard response == .OK, let self = self, let url = savePanel.url else { return }

            let tag = formatPopUp?.selectedTag() ?? 1
            let exportSelectionOnly = selectionOnlyCheckbox?.state == .on

            do {
                let data = try self.generateExportData(
                    formatTag: tag,
                    selectionOnly: exportSelectionOnly,
                    encodingPopUp: encodingPopUp,
                    lineEndingPopUp: lineEndingPopUp,
                    bomCheckbox: bomCheckbox
                )

                // RTFD の場合は FileWrapper で保存
                if tag == 2 {
                    let fileWrapper = try self.generateExportFileWrapper(selectionOnly: exportSelectionOnly)
                    try fileWrapper.write(to: url, options: .atomic, originalContentsURL: nil)
                } else {
                    try data.write(to: url, options: .atomic)
                }
            } catch {
                let alert = NSAlert(error: error)
                alert.beginSheetModal(for: window)
            }
        }
    }

    /// エクスポートパネルの allowedContentTypes をフォーマットタグに基づいて更新
    func updateExportPanelContentTypes(savePanel: NSSavePanel, formatTag: Int) {
        switch formatTag {
        case 0: // Plain Text
            savePanel.allowedContentTypes = [.plainText]
        case 1: // RTF
            savePanel.allowedContentTypes = [.rtf]
        case 2: // RTFD
            savePanel.allowedContentTypes = [.rtfd]
        case 3: // Word 97 (.doc)
            if let type = UTType("com.microsoft.word.doc") {
                savePanel.allowedContentTypes = [type]
            }
        case 4: // Word 2003 XML (.xml)
            if let type = UTType("com.microsoft.word.wordml") {
                savePanel.allowedContentTypes = [type]
            } else {
                savePanel.allowedContentTypes = [.xml]
            }
        case 5: // Word 2007 (.docx)
            if let type = UTType("org.openxmlformats.wordprocessingml.document") {
                savePanel.allowedContentTypes = [type]
            }
        case 6: // OpenDocument (.odt)
            if let type = UTType("org.oasis-open.opendocument.text") {
                savePanel.allowedContentTypes = [type]
            }
        case 7: // Markdown (.md)
            if let type = UTType("net.daringfireball.markdown") {
                savePanel.allowedContentTypes = [type]
            } else {
                savePanel.allowedContentTypes = [.plainText]
            }
        default:
            savePanel.allowedContentTypes = [.rtf]
        }
    }

    /// エクスポート用のデータを生成
    func generateExportData(
        formatTag: Int,
        selectionOnly: Bool,
        encodingPopUp: NSPopUpButton?,
        lineEndingPopUp: NSPopUpButton?,
        bomCheckbox: NSButton?
    ) throws -> Data {
        // テキスト範囲を決定
        let range: NSRange
        if selectionOnly,
           let textView = windowControllers.first.flatMap({ ($0 as? EditorWindowController)?.currentTextView() }),
           textView.selectedRange().length > 0 {
            range = textView.selectedRange()
        } else {
            range = NSRange(location: 0, length: textStorage.length)
        }

        // フォーマットタグに対応する DocumentType を決定
        let docType: NSAttributedString.DocumentType
        switch formatTag {
        case 0: return try generateExportPlainTextData(range: range, encodingPopUp: encodingPopUp, lineEndingPopUp: lineEndingPopUp, bomCheckbox: bomCheckbox)
        case 7: return try generateExportMarkdownData(range: range)
        case 1: docType = .rtf
        case 2: docType = .rtfd
        case 3: docType = .docFormat
        case 4: docType = .wordML
        case 5: docType = .officeOpenXML
        case 6: docType = .officeOpenXML  // ODTは直接サポートされないためdocxで試行
        default: docType = .rtf
        }

        var options: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: docType
        ]

        // Document properties を設定
        if let properties = presetData?.properties {
            if !properties.author.isEmpty { options[.author] = properties.author }
            if !properties.company.isEmpty { options[.company] = properties.company }
            if !properties.copyright.isEmpty { options[.copyright] = properties.copyright }
            if !properties.title.isEmpty { options[.title] = properties.title }
            if !properties.subject.isEmpty { options[.subject] = properties.subject }
            if !properties.keywords.isEmpty {
                let keywordsArray = properties.keywords.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                options[.keywords] = keywordsArray
            }
            if !properties.comment.isEmpty { options[.comment] = properties.comment }
        }

        return try textStorage.data(from: range, documentAttributes: options)
    }

    /// エクスポート用の RTFD FileWrapper を生成
    func generateExportFileWrapper(selectionOnly: Bool) throws -> FileWrapper {
        let range: NSRange
        if selectionOnly,
           let textView = windowControllers.first.flatMap({ ($0 as? EditorWindowController)?.currentTextView() }),
           textView.selectedRange().length > 0 {
            range = textView.selectedRange()
        } else {
            range = NSRange(location: 0, length: textStorage.length)
        }

        var documentAttributes: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtfd
        ]

        // Document properties を設定
        if let properties = presetData?.properties {
            if !properties.author.isEmpty { documentAttributes[.author] = properties.author }
            if !properties.company.isEmpty { documentAttributes[.company] = properties.company }
            if !properties.copyright.isEmpty { documentAttributes[.copyright] = properties.copyright }
            if !properties.title.isEmpty { documentAttributes[.title] = properties.title }
            if !properties.subject.isEmpty { documentAttributes[.subject] = properties.subject }
            if !properties.keywords.isEmpty {
                let keywordsArray = properties.keywords.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                documentAttributes[.keywords] = keywordsArray
            }
            if !properties.comment.isEmpty { documentAttributes[.comment] = properties.comment }
        }

        guard let fileWrapper = textStorage.rtfdFileWrapper(from: range, documentAttributes: documentAttributes) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: [
                NSLocalizedDescriptionKey: "Could not create RTFD file wrapper"
            ])
        }
        return fileWrapper
    }

    /// エクスポート用のプレーンテキストデータを生成
    func generateExportPlainTextData(
        range: NSRange,
        encodingPopUp: NSPopUpButton?,
        lineEndingPopUp: NSPopUpButton?,
        bomCheckbox: NSButton?
    ) throws -> Data {
        // テキストを取得
        let fullText = textStorage.string
        let text: String
        if let swiftRange = Range(range, in: fullText) {
            text = String(fullText[swiftRange])
        } else {
            text = fullText
        }

        // エンコーディングを決定
        var encoding: String.Encoding = documentEncoding
        if let encodingCell = encodingPopUp?.cell as? NSPopUpButtonCell,
           let selectedItem = encodingCell.selectedItem,
           let enc = selectedItem.representedObject as? NSNumber {
            let rawValue = enc.uintValue
            if rawValue != NoStringEncoding {
                encoding = String.Encoding(rawValue: UInt(rawValue))
            }
        }

        // 改行コードを決定
        let lineEndingTag = lineEndingPopUp?.selectedTag() ?? 0
        let exportLineEnding = LineEnding(rawValue: lineEndingTag) ?? .lf

        // 改行コードを変換
        let convertedText = convertLineEndings(in: text, to: exportLineEnding)

        // エンコード
        var exportData: Data
        if let encoded = convertedText.data(using: encoding) {
            exportData = encoded
        } else {
            // フォールバック: UTF-8
            guard let utf8Data = convertedText.data(using: .utf8) else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteInapplicableStringEncodingError, userInfo: [
                    NSLocalizedDescriptionKey: "Could not encode text"
                ])
            }
            exportData = utf8Data
            encoding = .utf8
        }

        // BOM を付加
        if bomCheckbox?.state == .on {
            exportData = addBOM(to: exportData, encoding: encoding)
        }

        return exportData
    }

    /// エクスポート用の Markdown データを生成
    func generateExportMarkdownData(range: NSRange) throws -> Data {
        // プレインテキスト書類の場合はテキストをそのまま出力（拡張子のみ .md に変更）
        if documentType == .plain {
            let plainText: String
            if range.location == 0 && range.length == textStorage.length {
                plainText = textStorage.string
            } else {
                plainText = (textStorage.string as NSString).substring(with: range)
            }
            guard let data = plainText.data(using: .utf8) else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteInapplicableStringEncodingError, userInfo: [
                    NSLocalizedDescriptionKey: "Could not encode text as UTF-8"
                ])
            }
            return data
        }

        // リッチテキスト書類の場合は NSAttributedString から Markdown に逆変換
        let attrString: NSAttributedString
        if range.location == 0 && range.length == textStorage.length {
            attrString = textStorage
        } else {
            attrString = textStorage.attributedSubstring(from: range)
        }

        // Markdown 逆変換
        let markdown = MarkdownParser.markdownString(from: attrString)

        guard let data = markdown.data(using: .utf8) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteInapplicableStringEncodingError, userInfo: [
                NSLocalizedDescriptionKey: "Could not encode Markdown text as UTF-8"
            ])
        }
        return data
    }

    /// ドキュメント内容から推奨ファイル名を生成（24文字以内）
    func generateSuggestedFileName() -> String {
        let content = textStorage.string

        // 空の場合は空文字を返す
        guard !content.isEmpty else { return "" }

        // 最初の行を取得（改行で分割）
        let firstLine = content.components(separatedBy: .newlines).first ?? ""

        // 空白をトリム
        var suggestion = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)

        // 空の場合は全体から空白以外の文字を取得
        if suggestion.isEmpty {
            suggestion = content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 空の場合は空文字を返す
        guard !suggestion.isEmpty else { return "" }

        // ファイル名に使用できない文字を除去または置換
        let invalidCharacters = CharacterSet(charactersIn: ":/\\")
        suggestion = suggestion.components(separatedBy: invalidCharacters).joined(separator: "-")

        // 24文字に制限
        if suggestion.count > 24 {
            let index = suggestion.index(suggestion.startIndex, offsetBy: 24)
            suggestion = String(suggestion[..<index])
        }

        // 末尾の空白やハイフンをトリム
        suggestion = suggestion.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-")))

        return suggestion
    }
}
