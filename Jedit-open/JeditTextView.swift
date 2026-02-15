//
//  JeditTextView.swift
//  Jedit-open
//
//  Custom NSTextView subclass that detects clicks on image attachments
//

import Cocoa

// MARK: - JeditTextView

class JeditTextView: NSTextView {

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

    /// RTFD昇格済みフラグ（performDragOperationでアラート表示後にreadSelectionで再チェックしない）
    private var rtfdUpgradeHandled: Bool = false

    /// テキストファイルドロップ処理中フラグ（readSelectionでのパス名挿入を抑制）
    private var handlingTextFileDrop: Bool = false

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

    /// 同期的にdocumentTypeをRTFDに昇格させる（アラートなし）
    /// readSelection(from:type:)のような同期メソッドから呼ばれる
    /// ドラッグ＆ドロップ時は既にRTFDであるはずだが、念のため昇格を確認する
    private func performUpgradeToRTFD() {
        guard let windowController = window?.windowController as? EditorWindowController,
              let document = windowController.textDocument else {
            return
        }

        // すでにRTFDなら何もしない
        if document.documentType == .rtfd {
            return
        }

        // RTFの場合はサイレントに昇格
        if document.documentType == .rtf {
            document.documentType = .rtfd
            document.updateFileTypeFromDocumentType()
            // fileURLをクリアして次回保存時にSave Panelを表示させる（.rtfd拡張子で保存）
            document.fileURL = nil
            document.autosavedContentsFileURL = nil
            NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: document)
        }
    }

    /// 画像挿入時にdocumentTypeをRTFDに昇格させる（必要に応じてアラートを表示）
    /// - Parameter completion: 昇格が完了（または不要）した場合にtrueを渡して呼び出される。キャンセルの場合はfalse。
    private func upgradeToRTFDIfNeeded(completion: @escaping (Bool) -> Void) {
        guard let windowController = window?.windowController as? EditorWindowController,
              let document = windowController.textDocument else {
            completion(false)
            return
        }

        // すでにRTFDなら何もしない
        if document.documentType == .rtfd {
            completion(true)
            return
        }

        // RTFの場合はアラートを表示
        guard document.documentType == .rtf else {
            completion(false)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Convert this document to RTFD format?", comment: "RTFD conversion alert message")
        alert.informativeText = NSLocalizedString("This document contains graphics or attachments and will be saved in RTFD format (RTF with graphics). RTFD documents may not be compatible with some applications. Do you want to convert?", comment: "RTFD conversion alert informative text")
        alert.addButton(withTitle: NSLocalizedString("Convert", comment: "Convert button"))
        alert.addButton(withTitle: NSLocalizedString("Duplicate", comment: "Duplicate button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))

        guard let parentWindow = window else {
            completion(false)
            return
        }

        alert.beginSheetModal(for: parentWindow) { response in
            switch response {
            case .alertFirstButtonReturn:
                // 変換: そのままRTFDに昇格
                document.documentType = .rtfd
                document.updateFileTypeFromDocumentType()
                // fileURLをクリアして次回保存時にSave Panelを表示させる（.rtfd拡張子で保存）
                document.fileURL = nil
                document.autosavedContentsFileURL = nil
                NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: document)
                completion(true)

            case .alertSecondButtonReturn:
                // 複製: 新しいRTFD書類を作成してコンテンツをコピー
                do {
                    guard let newDocument = try NSDocumentController.shared.makeUntitledDocument(ofType: "com.apple.rtfd") as? Document else {
                        completion(false)
                        return
                    }
                    newDocument.applyPresetData(NewDocData.richText)
                    newDocument.documentType = .rtfd
                    newDocument.updateFileTypeFromDocumentType()
                    NSDocumentController.shared.addDocument(newDocument)
                    newDocument.makeWindowControllers()
                    newDocument.showWindows()

                    // 元の書類のコンテンツをコピー
                    newDocument.textStorage.setAttributedString(document.textStorage)

                    completion(true)
                } catch {
                    completion(false)
                }

            default:
                // キャンセル
                completion(false)
            }
        }
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

    // MARK: - Drag Source / Destination Operation

    /// ソース側: 同一アプリ内ではmove+copy+genericを許可
    override func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .withinApplication:
            return [.move, .copy, .generic]
        case .outsideApplication:
            return [.copy]
        @unknown default:
            return super.draggingSession(session, sourceOperationMaskFor: context)
        }
    }

    /// ドラッグソースが同一書類内のテキストビューかどうかを判定
    private func isDragFromSameDocument(_ sender: any NSDraggingInfo) -> Bool {
        guard let sourceView = sender.draggingSource as? JeditTextView,
              let sourceDocument = (sourceView.window?.windowController as? EditorWindowController)?.textDocument,
              let myDocument = (window?.windowController as? EditorWindowController)?.textDocument else {
            return false
        }
        return sourceDocument === myDocument
    }

    /// ドロップ可能なテキスト/RTFファイルURLがペーストボードに含まれているか判定
    private func pasteboardContainsDroppableTextFile(_ pboard: NSPasteboard) -> Bool {
        guard let fileURLs = pboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else { return false }

        for url in fileURLs {
            let ext = url.pathExtension.lowercased()
            if Self.textFileExtensions.contains(ext) ||
               Self.rtfFileExtensions.contains(ext) ||
               Self.rtfdFileExtensions.contains(ext) {
                return true
            }
        }
        return false
    }

    /// ファイルURLドラッグ時のオペレーションを判定
    /// Ctrl押下時は.link（↩マーク）、通常はsuperの結果を使用
    private func dragOperationForFileDrop(_ sender: any NSDraggingInfo) -> NSDragOperation? {
        guard pasteboardContainsDroppableTextFile(sender.draggingPasteboard) else { return nil }
        if NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            return .link
        }
        return nil
    }

    /// ドラッグ進入時: Ctrl+ファイルドロップは.link、通常ファイルドロップはsuperに委譲
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if let op = dragOperationForFileDrop(sender) {
            return op
        }
        return super.draggingEntered(sender)
    }

    /// デスティネーション側: 同一書類内はデフォルトmove、別書類はcopy
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        // Ctrl+ファイルドロップは.link（↩マーク）
        if let op = dragOperationForFileDrop(sender) {
            return op
        }

        // superを呼んでドロップ先カーソル表示等の内部処理を実行
        let superResult = super.draggingUpdated(sender)

        if isDragFromSameDocument(sender) {
            // Optionキーが押されていればcopy、そうでなければmove
            if NSEvent.modifierFlags.contains(.option) {
                return .copy
            }
            return .move
        }

        return superResult
    }

    /// ドロップ準備: テキスト/RTFファイルドロップを受け入れる
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if pasteboardContainsDroppableTextFile(sender.draggingPasteboard) {
            return true
        }
        return super.prepareForDragOperation(sender)
    }

    /// 同一書類内ドラッグ時のドロップ先文字位置を取得
    private func characterIndex(for draggingInfo: any NSDraggingInfo) -> Int? {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return nil }
        let point = convert(draggingInfo.draggingLocation, from: nil)
        let locationInContainer = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        let glyphIndex = layoutManager.glyphIndex(for: locationInContainer, in: textContainer)
        return layoutManager.characterIndexForGlyph(at: glyphIndex)
    }

    /// 同一書類内のドラッグ＆ドロップで移動を実現
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let pboard = sender.draggingPasteboard

        // 同一書類内のドラッグで、Optionキーが押されていなければ移動処理
        if isDragFromSameDocument(sender) && !NSEvent.modifierFlags.contains(.option) {
            guard let sourceView = sender.draggingSource as? JeditTextView,
                  let textStorage = textStorage else {
                return super.performDragOperation(sender)
            }

            // ソース側の選択範囲を保存
            let sourceRange = sourceView.selectedRange()
            guard sourceRange.length > 0 else {
                return super.performDragOperation(sender)
            }

            // ドロップ先の文字位置を取得
            guard let dropIndex = characterIndex(for: sender) else {
                return super.performDragOperation(sender)
            }

            // ソースのコンテンツを取得
            let draggedContent = textStorage.attributedSubstring(from: sourceRange)

            // ドロップ先がソース範囲内なら何もしない
            if dropIndex >= sourceRange.location && dropIndex <= sourceRange.location + sourceRange.length {
                return true
            }

            // 移動先の最終位置を計算
            let finalInsertIndex: Int
            if dropIndex < sourceRange.location {
                finalInsertIndex = dropIndex
            } else {
                finalInsertIndex = dropIndex - sourceRange.length
            }

            // 単一のUndoableな操作として実行: 元の範囲を削除してから挿入
            // shouldChangeTextで全体の変更を通知し、didChangeTextは1回だけ呼ぶ
            if shouldChangeText(in: sourceRange, replacementString: "") {
                textStorage.beginEditing()
                // 1. ソースを削除
                textStorage.deleteCharacters(in: sourceRange)
                // 2. 調整後の位置に挿入
                textStorage.insert(draggedContent, at: finalInsertIndex)
                textStorage.endEditing()
                didChangeText()
            }

            // 挿入したテキストを選択
            setSelectedRange(NSRange(location: finalInsertIndex, length: draggedContent.length))
            return true
        }

        // --- 以下は別書類・アプリ外からのドロップ、またはOption+ドラッグ（コピー）---

        // ファイルURLがドロップされた場合のテキストファイル/RTFファイル処理
        if let fileURLs = pboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !fileURLs.isEmpty {
            handlingTextFileDrop = true
            let result = handleTextFilesDrop(fileURLs: fileURLs, draggingInfo: sender)
            handlingTextFileDrop = false
            if result {
                return true
            }
        }

        // RTFDや画像を含むドロップで、現在RTF書類の場合はアラートを表示
        if !isPlainText, !rtfdUpgradeHandled {
            if pasteboardContainsImageContent(pboard) {
                guard let windowController = window?.windowController as? EditorWindowController,
                      let document = windowController.textDocument else {
                    return super.performDragOperation(sender)
                }

                // すでにRTFDなら問題なし
                if document.documentType == .rtfd {
                    return super.performDragOperation(sender)
                }

                // RTFの場合はアラートを表示（同期的にモーダルで実行）
                if document.documentType == .rtf {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = NSLocalizedString("Convert this document to RTFD format?", comment: "RTFD conversion alert message")
                    alert.informativeText = NSLocalizedString("This document contains graphics or attachments and will be saved in RTFD format (RTF with graphics). RTFD documents may not be compatible with some applications. Do you want to convert?", comment: "RTFD conversion alert informative text")
                    alert.addButton(withTitle: NSLocalizedString("Convert", comment: "Convert button"))
                    alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))

                    let response = alert.runModal()

                    if response == .alertFirstButtonReturn {
                        document.documentType = .rtfd
                        document.updateFileTypeFromDocumentType()
                        document.fileURL = nil
                        document.autosavedContentsFileURL = nil
                        NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: document)
                        rtfdUpgradeHandled = true
                        let result = super.performDragOperation(sender)
                        rtfdUpgradeHandled = false
                        return result
                    } else {
                        return false
                    }
                }
            }
        }

        return super.performDragOperation(sender)
    }

    // MARK: - Text/RTF File Drop Handling

    /// テキストファイル拡張子の判定用
    private static let textFileExtensions: Set<String> = [
        "txt", "text", "md", "markdown", "csv", "tsv", "log",
        "json", "xml", "html", "htm", "css", "js", "ts",
        "swift", "m", "h", "c", "cpp", "java", "py", "rb", "sh",
        "yaml", "yml", "toml", "ini", "conf", "cfg",
        "tex", "sty", "cls", "bib",
        "sql", "r", "pl", "php", "go", "rs", "kt", "scala"
    ]

    /// RTFファイル拡張子の判定用
    private static let rtfFileExtensions: Set<String> = ["rtf"]

    /// RTFDファイル拡張子の判定用
    private static let rtfdFileExtensions: Set<String> = ["rtfd"]

    /// ドロップされたファイルURLがテキスト/RTFファイルの場合に処理する
    /// - Returns: 処理した場合はtrue
    private func handleTextFilesDrop(fileURLs: [URL], draggingInfo: any NSDraggingInfo) -> Bool {
        let isCtrlPressed = NSEvent.modifierFlags.contains(.control)

        // ドロップ先の文字位置を取得
        guard let dropIndex = characterIndex(for: draggingInfo) else { return false }

        var handledAny = false

        for url in fileURLs {
            let ext = url.pathExtension.lowercased()
            if isCtrlPressed {
                // Ctrl+ドロップ
                if isPlainText {
                    // プレーンテキスト → 常にパス名挿入（ファイル種別を問わない）
                    let path = url.path
                    let insertRange = NSRange(location: dropIndex, length: 0)
                    replaceString(in: insertRange, with: path)
                    handledAny = true
                } else {
                    // リッチテキスト → テキストアタッチメントとして挿入
                    // RTFD変換が必要
                    if let windowController = window?.windowController as? EditorWindowController,
                       let document = windowController.textDocument,
                       document.documentType != .rtfd {
                        let alert = NSAlert()
                        alert.alertStyle = .warning
                        alert.messageText = NSLocalizedString("Convert this document to RTFD format?", comment: "RTFD conversion alert message")
                        alert.informativeText = NSLocalizedString("This document contains graphics or attachments and will be saved in RTFD format (RTF with graphics). RTFD documents may not be compatible with some applications. Do you want to convert?", comment: "RTFD conversion alert informative text")
                        alert.addButton(withTitle: NSLocalizedString("Convert", comment: "Convert button"))
                        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))

                        let response = alert.runModal()
                        if response == .alertFirstButtonReturn {
                            document.documentType = .rtfd
                            document.updateFileTypeFromDocumentType()
                            document.fileURL = nil
                            document.autosavedContentsFileURL = nil
                            NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: document)
                        } else {
                            return true  // キャンセル
                        }
                    }
                    insertFileAsAttachment(url, at: dropIndex)
                    handledAny = true
                }

            } else if Self.textFileExtensions.contains(ext) {
                // テキストファイル → エンコーディング自動判定して内容を読み込んでペースト
                if let data = try? Data(contentsOf: url) {
                    let outcome = EncodingDetector.shared.detectAndDecode(
                        from: data, fileURL: url, allowUserSelection: false)
                    var content: String?
                    switch outcome {
                    case .success(_, let str):
                        content = str
                    case .needsUserSelection(let candidates):
                        if let best = candidates.first {
                            content = String(data: data, encoding: best.encoding)
                        }
                    case .failure:
                        break
                    }
                    if let content = content {
                        let convertedContent = applyTextConversions(content)
                        setSelectedRange(NSRange(location: dropIndex, length: 0))
                        insertText(convertedContent, replacementRange: NSRange(location: dropIndex, length: 0))
                        handledAny = true
                    }
                }

            } else if Self.rtfFileExtensions.contains(ext) {
                // RTFファイル
                if isPlainText {
                    // プレーンテキスト書類 → テキスト部分のみペースト
                    if let data = try? Data(contentsOf: url),
                       let attrStr = NSAttributedString(rtf: data, documentAttributes: nil) {
                        let convertedContent = applyTextConversions(attrStr.string)
                        let insertRange = NSRange(location: dropIndex, length: 0)
                        replaceString(in: insertRange, with: convertedContent)
                        handledAny = true
                    }
                } else {
                    // リッチテキスト書類 → リッチテキストとしてペースト（文字変換を適用）
                    if let data = try? Data(contentsOf: url),
                       let attrStr = NSAttributedString(rtf: data, documentAttributes: nil) {
                        let convertedAttrStr = applyTextConversionsToAttributedString(attrStr)
                        let insertRange = NSRange(location: dropIndex, length: 0)
                        replaceString(in: insertRange, with: convertedAttrStr)
                        handledAny = true
                    }
                }

            } else if Self.rtfdFileExtensions.contains(ext) {
                // RTFDファイル
                if isPlainText {
                    // プレーンテキスト書類 → テキスト部分のみペースト
                    if let fileWrapper = try? FileWrapper(url: url, options: .immediate),
                       let attrStr = NSAttributedString(rtfdFileWrapper: fileWrapper, documentAttributes: nil) {
                        let convertedContent = applyTextConversions(attrStr.string)
                        let insertRange = NSRange(location: dropIndex, length: 0)
                        replaceString(in: insertRange, with: convertedContent)
                        handledAny = true
                    }
                } else {
                    // リッチテキスト書類 → RTFD変換アラートを表示してリッチテキストとしてペースト
                    guard let windowController = window?.windowController as? EditorWindowController,
                          let document = windowController.textDocument else {
                        return false
                    }

                    // RTFD変換が必要か判定（すでにRTFDなら不要）
                    if document.documentType != .rtfd {
                        let alert = NSAlert()
                        alert.alertStyle = .warning
                        alert.messageText = NSLocalizedString("Convert this document to RTFD format?", comment: "RTFD conversion alert message")
                        alert.informativeText = NSLocalizedString("This document contains graphics or attachments and will be saved in RTFD format (RTF with graphics). RTFD documents may not be compatible with some applications. Do you want to convert?", comment: "RTFD conversion alert informative text")
                        alert.addButton(withTitle: NSLocalizedString("Convert", comment: "Convert button"))
                        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))

                        let response = alert.runModal()
                        if response == .alertFirstButtonReturn {
                            document.documentType = .rtfd
                            document.updateFileTypeFromDocumentType()
                            document.fileURL = nil
                            document.autosavedContentsFileURL = nil
                            NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: document)
                        } else {
                            return true  // キャンセル：何もしない
                        }
                    }

                    // RTFDファイルをリッチテキストとしてペースト（文字変換を適用）
                    if let fileWrapper = try? FileWrapper(url: url, options: .immediate),
                       let attrStr = NSAttributedString(rtfdFileWrapper: fileWrapper, documentAttributes: nil) {
                        let convertedAttrStr = applyTextConversionsToAttributedString(attrStr)
                        let insertRange = NSRange(location: dropIndex, length: 0)
                        replaceString(in: insertRange, with: convertedAttrStr)
                        handledAny = true
                    }
                }
            } else {
                // テキスト/RTF/画像以外のファイル → 処理しない（superに委譲）
                return false
            }
        }

        return handledAny
    }

    // MARK: - Attach Files

    /// Edit > Attach Files... メニューアクション
    @IBAction func attachFile(_ sender: Any?) {
        // プレーンテキストでは使用不可
        guard !isPlainText else { return }

        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = true
        openPanel.prompt = NSLocalizedString("Attach", comment: "Attach button in open panel")

        guard let parentWindow = window else { return }

        openPanel.beginSheetModal(for: parentWindow) { [weak self] response in
            guard response == .OK, let self = self else { return }

            self.upgradeToRTFDIfNeeded { [weak self] proceed in
                guard proceed, let self = self else { return }

                let insertionPoint = self.selectedRange().location
                for (i, url) in openPanel.urls.enumerated() {
                    self.insertFileAsAttachment(url, at: insertionPoint + i)
                }
            }
        }
    }

    // MARK: - Continuity Camera (Import from iPhone or iPad)

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        // リッチテキストかつ画像受け入れ可能な場合、Continuity Cameraをサポート
        if sendType == nil, let returnType = returnType {
            if !isPlainText && NSImage.imageTypes.contains(returnType.rawValue) {
                return self
            }
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    override func readSelection(from pboard: NSPasteboard) -> Bool {
        guard !isPlainText else { return false }

        // RTFD昇格
        performUpgradeToRTFD()

        // ペーストボードから画像を取得して挿入
        // TIFFデータを優先（保存時にfileWrapperが必要）
        if let imageData = pboard.data(forType: .tiff) ?? pboard.data(forType: .png),
           let image = NSImage(data: imageData) {
            let attachment = NSTextAttachment()
            // fileWrapperにデータを設定（RTFD保存時に必要）
            let fileWrapper = FileWrapper(regularFileWithContents: imageData)
            let ext = pboard.data(forType: .png) != nil ? "png" : "tiff"
            fileWrapper.preferredFilename = "image.\(ext)"
            attachment.fileWrapper = fileWrapper
            // 表示用のセルを設定
            let cell = NSTextAttachmentCell(imageCell: image)
            attachment.attachmentCell = cell
            let attrStr = NSAttributedString(attachment: attachment)
            let insertRange = selectedRange()
            replaceString(in: insertRange, with: attrStr)
            return true
        }

        return super.readSelection(from: pboard)
    }

    /// ファイルをテキストアタッチメントとして挿入
    private func insertFileAsAttachment(_ url: URL, at index: Int) {
        let attachment = NSTextAttachment()
        let fileWrapper = try? FileWrapper(url: url, options: .immediate)
        attachment.fileWrapper = fileWrapper
        attachment.fileWrapper?.preferredFilename = url.lastPathComponent

        let attrStr = NSAttributedString(attachment: attachment)
        let insertRange = NSRange(location: index, length: 0)
        replaceString(in: insertRange, with: attrStr)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Check for double-click on an attachment
        if event.clickCount == 2 {
            // アタッチメントがファイルアタッチメント（非画像）の場合は対応アプリで開く
            if let attachment = attachmentAtPoint(point),
               isFileAttachment(attachment) {
                openFileAttachment(attachment)
                return
            }

            // 画像アタッチメントの場合はリサイズパネルを表示
            if let controller = imageResizeController,
               controller.handleClick(in: self, at: point) {
                return
            }
        }

        // Not an attachment double-click, proceed with normal behavior
        super.mouseDown(with: event)
    }

    /// 指定座標にあるNSTextAttachmentを取得
    private func attachmentAtPoint(_ point: NSPoint) -> NSTextAttachment? {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let textStorage = textStorage,
              textStorage.length > 0 else {
            return nil
        }

        let textContainerOrigin = textContainerOrigin
        let locationInContainer = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )

        let glyphIndex = layoutManager.glyphIndex(for: locationInContainer, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < textStorage.length else { return nil }

        let attributes = textStorage.attributes(at: charIndex, effectiveRange: nil)
        return attributes[.attachment] as? NSTextAttachment
    }

    /// アタッチメントがファイルアタッチメント（非画像）かどうかを判定
    /// 画像拡張子を持つファイルは画像アタッチメントとして扱う
    private func isFileAttachment(_ attachment: NSTextAttachment) -> Bool {
        guard let fileWrapper = attachment.fileWrapper,
              let filename = fileWrapper.preferredFilename ?? fileWrapper.filename else {
            return false
        }

        // 画像拡張子の場合は画像アタッチメント（リサイズ対象）
        let ext = (filename as NSString).pathExtension.lowercased()
        let imageExtensions: Set<String> = [
            "png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "ico", "heic", "heif", "webp", "svg"
        ]
        if imageExtensions.contains(ext) {
            return false  // 画像アタッチメント
        }

        // ファイルラッパーがディレクトリの場合もファイルアタッチメント
        // 拡張子が画像でない場合はファイルアタッチメント
        return true
    }

    /// ファイルアタッチメントを対応アプリで開く
    private func openFileAttachment(_ attachment: NSTextAttachment) {
        guard let fileWrapper = attachment.fileWrapper else { return }

        // 一時ディレクトリにファイルを書き出してから開く
        let tempDir = FileManager.default.temporaryDirectory
        let filename = fileWrapper.preferredFilename ?? fileWrapper.filename ?? "attachment"
        let tempURL = tempDir.appendingPathComponent(filename)

        do {
            // 既存ファイルがあれば削除
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            try fileWrapper.write(to: tempURL, options: .atomic, originalContentsURL: nil)
            NSWorkspace.shared.open(tempURL)
        } catch {
            NSSound.beep()
        }
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

    /// リッチテキスト書類の場合、画像タイプも読み取り可能に追加
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        var types = super.readablePasteboardTypes
        if !isPlainText {
            // 画像タイプがまだ含まれていなければ追加
            for imageType in [NSPasteboard.PasteboardType.tiff, .png] {
                if !types.contains(imageType) {
                    types.append(imageType)
                }
            }
        }
        return types
    }

    /// superのpasteを呼び出す（クロージャ内から呼ぶため）
    private func performSuperPaste(_ sender: Any?) {
        super.paste(sender)
    }

    /// ペースト時に文字変換を適用
    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general

        // リッチテキスト書類の場合
        if !isPlainText {
            // RTFDデータまたは画像データがある場合はRTFDに昇格してsuperに委譲
            let hasRTFD = pasteboard.availableType(from: [.rtfd]) != nil
            let hasImage = pasteboard.availableType(from: [.tiff, .png]) != nil
            if hasRTFD || hasImage {
                upgradeToRTFDIfNeeded { [weak self] proceed in
                    guard let self = self, proceed else { return }
                    self.performSuperPaste(sender)
                }
                return
            }

            // RTFデータがある場合はリッチテキストとしてペースト（書式を保持）
            // insertText ではなく replaceString を使用する
            // （insertText は typingAttributes を適用してしまい書式が失われるため）
            if let rtfData = pasteboard.data(forType: .rtf),
               let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
                let convertedString = applyTextConversionsToAttributedString(attributedString)
                replaceString(in: selectedRange(), with: convertedString)
                return
            }
        }

        // ペーストボードからテキストを取得して変換を適用
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
            // insertText ではなく replaceString を使用（書式を保持するため）
            replaceString(in: selectedRange(), with: convertedString)
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

    /// ペーストボードに画像コンテンツが含まれているかを判定する
    /// データとして直接含まれる場合と、ファイルURLとして含まれる場合の両方をチェック
    private func pasteboardContainsImageContent(_ pboard: NSPasteboard) -> Bool {
        // 直接的な画像/RTFDデータのチェック
        let imageTypes: [NSPasteboard.PasteboardType] = [
            .rtfd,
            NSPasteboard.PasteboardType("NeXT RTFD pasteboard type"),
            NSPasteboard.PasteboardType("com.apple.flat-rtfd"),
            .tiff, .png
        ]
        if pboard.availableType(from: imageTypes) != nil {
            return true
        }

        // ファイルURLのチェック（画像ファイルがドロップされた場合）
        if let fileURLs = pboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] {
            let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "heic", "webp", "pdf", "eps"]
            for url in fileURLs {
                if imageExtensions.contains(url.pathExtension.lowercased()) {
                    return true
                }
            }
        }

        return false
    }

    /// ドラッグ＆ドロップ時に文字変換を適用
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        // ファイルURLのドロップ: performDragOperationで処理中の場合はパス名挿入を抑制
        // （handleTextFilesDrop → replaceString → readSelectionと再帰的に呼ばれるため）
        if type == NSPasteboard.PasteboardType("NSFilenamesPboardType") ||
           type == .fileURL {
            if handlingTextFileDrop {
                // performDragOperationのhandleTextFilesDropで処理中
                // trueを返してNSTextViewのデフォルトのパス名挿入を抑制
                return true
            }
        }

        // 画像コンテンツ（RTFD、画像データ、画像ファイルURL）が含まれている場合は
        // RTFD昇格を行い、superに委譲して画像を正しく処理させる
        if !isPlainText, pasteboardContainsImageContent(pboard) {
            // performDragOperationで昇格済みでなければサイレントに昇格（同一ビュー内ドラッグ等）
            if !rtfdUpgradeHandled {
                performUpgradeToRTFD()
            }
            return super.readSelection(from: pboard, type: type)
        }

        // テキストのみの場合は変換を適用
        if type == .string, let string = pboard.string(forType: .string) {
            let convertedString = applyTextConversions(string)
            insertText(convertedString, replacementRange: selectedRange())
            return true
        } else if type == .rtf, let rtfData = pboard.data(forType: .rtf),
                  let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            let convertedString = applyTextConversionsToAttributedString(attributedString)
            // insertText ではなく replaceString を使用（書式を保持するため）
            replaceString(in: selectedRange(), with: convertedString)
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
    /// NSMutableAttributedString の replaceCharacters(in:with:) を使い、
    /// 置換箇所以外の属性を全て保持する
    /// - Parameter attributedString: 変換対象の属性付き文字列
    /// - Returns: 変換後の属性付き文字列（全属性が保持される）
    private func applyTextConversionsToAttributedString(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        let defaults = UserDefaults.standard

        // 変換ペアを構築（applyTextConversions と同じ変換内容）
        var replacements: [(target: String, replacement: String)] = []

        // 1. 改行コードをLFに統一（CRLF → LF を先に処理）
        replacements.append(("\r\n", "\n"))
        replacements.append(("\r", "\n"))

        // 2. 円記号をバックスラッシュに変換
        if defaults.bool(forKey: UserDefaults.Keys.convertYenToBackSlash) {
            replacements.append(("\u{00A5}", "\\"))
        }

        // 3. オーバーラインをチルダに変換
        if defaults.bool(forKey: UserDefaults.Keys.convertOverlineToTilde) {
            replacements.append(("\u{203E}", "~"))
        }

        // 4. 全角チルダを波ダッシュに変換
        if defaults.bool(forKey: UserDefaults.Keys.convertFullWidthTilde) {
            replacements.append(("\u{FF5E}", "\u{301C}"))
        }

        // 各変換を属性保持のまま適用
        for (target, replacement) in replacements {
            var searchRange = NSRange(location: 0, length: mutable.length)
            while searchRange.location < mutable.length {
                let nsString = mutable.string as NSString
                let foundRange = nsString.range(of: target, options: [], range: searchRange)
                if foundRange.location == NSNotFound { break }
                mutable.replaceCharacters(in: foundRange, with: replacement)
                // 置換後のインデックスから検索を続行
                searchRange.location = foundRange.location + (replacement as NSString).length
                searchRange.length = mutable.length - searchRange.location
            }
        }

        return mutable
    }

    // MARK: - Menu Validation

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let action = menuItem.action

        // Set paperclip image for Attach Files menu item
        if action == #selector(attachFile(_:)), menuItem.image == nil {
            if let image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Attach Files") {
                image.size = NSSize(width: 16, height: 16)
                menuItem.image = image
            }
        }

        // Baseline submenu actions, Character colors, and Attach Files are disabled for plain text
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
                 #selector(orderFrontBackColorPanel(_:)),
                 #selector(attachFile(_:)):
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

        // リッチテキスト書類でクリップボードに画像がある場合、Pasteを有効化
        if action == #selector(paste(_:)) {
            if !isPlainText {
                let pasteboard = NSPasteboard.general
                if pasteboard.availableType(from: [.tiff, .png]) != nil {
                    return true
                }
            }
        }

        return super.validateMenuItem(menuItem)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        // リッチテキスト書類でクリップボードに画像がある場合、Pasteを有効化
        if item.action == #selector(paste(_:)) {
            if !isPlainText {
                let pasteboard = NSPasteboard.general
                if pasteboard.availableType(from: [.tiff, .png]) != nil {
                    return true
                }
            }
        }

        return super.validateUserInterfaceItem(item)
    }
}
