//
//  JeditTextView+DragDrop.swift
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

extension JeditTextView {

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

    /// ドラッグ開始時のソース選択範囲を保存
    override func beginDraggingSession(with items: [NSDraggingItem], event: NSEvent, source: NSDraggingSource) -> NSDraggingSession {
        dragSourceRange = selectedRange()
        return super.beginDraggingSession(with: items, event: event, source: source)
    }

    /// NSTextView がドラッグ用にペーストボードを準備する際に呼ばれる。
    /// super の RTFD データに加えて、イメージアタッチメントがあれば
    /// NSFilenamesPboardType で一時ファイルパスを追加する。
    /// Finder は NSFilenamesPboardType を RTFD より優先するため、
    /// ファイルとしてドロップされる。
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let result = super.writeSelection(to: pboard, types: types)

        guard let textStorage = textStorage else { return result }
        let selRange = selectedRange()
        guard selRange.length > 0 else { return result }

        // 前回の一時ファイルをクリーンアップ
        cleanupDragTempFiles()

        var tempFilePaths: [String] = []

        textStorage.enumerateAttribute(.attachment, in: selRange, options: []) { value, _, _ in
            guard let attachment = value as? NSTextAttachment else { return }

            var imageData: Data?
            var filename = "image.png"

            // fileWrapper からデータとファイル名を取得
            if let fileWrapper = attachment.fileWrapper,
               let data = fileWrapper.regularFileContents {
                imageData = data
                if let name = fileWrapper.preferredFilename, !name.isEmpty {
                    filename = name
                }
            }

            // セルの画像からデータを取得（フォールバック）
            if imageData == nil,
               let cell = attachment.attachmentCell as? NSCell,
               let image = cell.image,
               let tiffData = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiffData),
               let pngData = rep.representation(using: .png, properties: [:]) {
                imageData = pngData
            }

            guard let data = imageData else { return }

            // 一時ファイルに書き出す
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("JeditImageDrag-\(UUID().uuidString)")
            do {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let tempURL = tempDir.appendingPathComponent(filename)
                try data.write(to: tempURL)
                self.dragTempFileURLs.append(tempURL)
                tempFilePaths.append(tempURL.path)
            } catch {
                // 書き出し失敗時はスキップ
            }
        }

        // イメージがあればファイルパスをペーストボードに追加
        if !tempFilePaths.isEmpty {
            let filenameType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
            pboard.addTypes([filenameType], owner: nil)
            pboard.setPropertyList(tempFilePaths, forType: filenameType)
        }

        return result
    }

    /// ドラッグ用一時ファイルをクリーンアップ
    func cleanupDragTempFiles() {
        for url in dragTempFileURLs {
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: dir)
        }
        dragTempFileURLs.removeAll()
    }

    /// ドラッグセッション終了時にドラッグソース範囲をクリアし、一時ファイルを遅延クリーンアップ
    override func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if handledSameDocumentDrag {
            // 同一書類内ドラッグを自前で処理済み: super に .move を渡すとソースが二重削除されるため
            // .none を渡してソース削除を防ぐ
            super.draggingSession(session, endedAt: screenPoint, operation: [])
            handledSameDocumentDrag = false
        } else {
            super.draggingSession(session, endedAt: screenPoint, operation: operation)
        }
        dragSourceRange = nil

        // Finder がファイルをコピーする時間を確保してから一時ファイルを削除
        let urlsToCleanup = dragTempFileURLs
        dragTempFileURLs.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            for url in urlsToCleanup {
                let dir = url.deletingLastPathComponent()
                try? FileManager.default.removeItem(at: dir)
            }
        }
    }

    /// ドラッグソースが同一書類内のテキストビューかどうかを判定
    func isDragFromSameDocument(_ sender: any NSDraggingInfo) -> Bool {
        guard let sourceView = sender.draggingSource as? JeditTextView,
              let sourceDocument = (sourceView.window?.windowController as? EditorWindowController)?.textDocument,
              let myDocument = (window?.windowController as? EditorWindowController)?.textDocument else {
            return false
        }
        return sourceDocument === myDocument
    }

    /// ドロップ可能なテキスト/RTFファイルURLがペーストボードに含まれているか判定
    func pasteboardContainsDroppableTextFile(_ pboard: NSPasteboard) -> Bool {
        guard let fileURLs = pboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else { return false }

        for url in fileURLs {
            if Self.detectFileContentType(url) != .other {
                return true
            }
        }
        return false
    }

    /// ペーストボードにファイルURLが含まれているか判定
    func pasteboardContainsFileURL(_ pboard: NSPasteboard) -> Bool {
        guard let fileURLs = pboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else { return false }
        return !fileURLs.isEmpty
    }

    /// ファイルURLドラッグ時のオペレーションを判定
    /// Ctrl押下時は.link（↩マーク）、通常はsuperの結果を使用
    func dragOperationForFileDrop(_ sender: any NSDraggingInfo) -> NSDragOperation? {
        if NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            // Ctrl+ドロップ: 任意のファイル/フォルダでパス+リンク挿入
            if pasteboardContainsFileURL(sender.draggingPasteboard) {
                return .link
            }
        }
        // 通常ドロップ: テキストファイルのみ処理
        guard pasteboardContainsDroppableTextFile(sender.draggingPasteboard) else { return nil }
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

    /// ドロップ準備: テキスト/RTFファイルドロップ、またはCtrl+ファイルドロップを受け入れる
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if pasteboardContainsDroppableTextFile(sender.draggingPasteboard) {
            return true
        }
        // Ctrl+ファイルドロップ（任意のファイル/フォルダ）
        if NSEvent.modifierFlags.contains(.control),
           pasteboardContainsFileURL(sender.draggingPasteboard) {
            return true
        }
        return super.prepareForDragOperation(sender)
    }

    /// 同一書類内ドラッグ時のドロップ先文字位置を取得
    func characterIndex(for draggingInfo: any NSDraggingInfo) -> Int? {
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
        // Smart Language Separation: ドロップ操作と同じUndoグループで分離処理を実行
        smartLanguageSeparation?.isPasting = true
        defer {
            smartLanguageSeparation?.isPasting = false
            smartLanguageSeparation?.processPendingFullSeparation()
        }

        let pboard = sender.draggingPasteboard

        // 同一書類内のドラッグで、Optionキーが押されていなければ移動処理
        if isDragFromSameDocument(sender) && !NSEvent.modifierFlags.contains(.option) {
            guard let sourceView = sender.draggingSource as? JeditTextView,
                  let textStorage = textStorage else {
                return super.performDragOperation(sender)
            }

            // ソース側の選択範囲を取得（ドラッグ開始時に保存した範囲を優先）
            let sourceRange = sourceView.dragSourceRange ?? sourceView.selectedRange()
            guard sourceRange.length > 0 else {
                handledSameDocumentDrag = true
                return true  // ソース範囲が不明な場合は何もせず成功を返す（画像消失防止）
            }

            // ドロップ先の文字位置を取得
            guard let dropIndex = characterIndex(for: sender) else {
                return super.performDragOperation(sender)
            }

            // ソースのコンテンツを取得
            let draggedContent = textStorage.attributedSubstring(from: sourceRange)

            // ドロップ先がソース範囲内なら何もしない
            if dropIndex >= sourceRange.location && dropIndex <= sourceRange.location + sourceRange.length {
                handledSameDocumentDrag = true
                return true
            }

            // 移動先の最終位置を計算
            let finalInsertIndex: Int
            if dropIndex < sourceRange.location {
                finalInsertIndex = dropIndex
            } else {
                finalInsertIndex = dropIndex - sourceRange.length
            }

            // 削除と挿入を個別の shouldChangeText/didChangeText ペアで実行し、
            // UndoGrouping でまとめて1つの Undo 操作にする
            undoManager?.beginUndoGrouping()

            // 1. ソースを削除
            if shouldChangeText(in: sourceRange, replacementString: "") {
                textStorage.deleteCharacters(in: sourceRange)
                didChangeText()
            }

            // 2. 調整後の位置に挿入
            let insertRange = NSRange(location: finalInsertIndex, length: 0)
            if shouldChangeText(in: insertRange, replacementString: draggedContent.string) {
                textStorage.insert(draggedContent, at: finalInsertIndex)
                didChangeText()
            }

            undoManager?.endUndoGrouping()
            undoManager?.setActionName(NSLocalizedString("Move", comment: "Undo action name for drag move"))

            // 挿入したテキストを選択
            setSelectedRange(NSRange(location: finalInsertIndex, length: draggedContent.length))
            handledSameDocumentDrag = true
            return true
        }

        // --- 以下は別書類・アプリ外からのドロップ、またはOption+ドラッグ（コピー）---

        // Ctrl+ファイル/フォルダドロップ: フルパス名をリンク付きで挿入
        if NSEvent.modifierFlags.contains(.control),
           let fileURLs = pboard.readObjects(forClasses: [NSURL.self], options: [
               .urlReadingFileURLsOnly: true
           ]) as? [URL], !fileURLs.isEmpty {
            guard let dropIndex = characterIndex(for: sender) else {
                return super.performDragOperation(sender)
            }
            for url in fileURLs {
                insertFilePathWithLink(url, at: dropIndex)
            }
            return true
        }

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
                    alert.messageText = "Convert this document to RTFD format?".localized
                    alert.informativeText = "This document contains graphics or attachments and will be saved in RTFD format (RTF with graphics). RTFD documents may not be compatible with some applications. Do you want to convert?".localized
                    alert.addButton(withTitle: "Convert".localized)
                    alert.addButton(withTitle: "Cancel".localized)

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

        // ブックマークのドロップ: 選択範囲内へのドロップはリンクのみ付与（文字列は挿入しない）
        let bookmarkPboardType = NSPasteboard.PasteboardType("jp.co.artman21.Jedit-open.bookmark")
        if pboard.availableType(from: [bookmarkPboardType]) != nil,
           !isPlainText {
            let selRange = selectedRange()
            if selRange.length > 0,
               let dropIndex = characterIndex(for: sender),
               dropIndex >= selRange.location,
               dropIndex <= selRange.location + selRange.length {
                // ドロップ位置が選択範囲内: 選択テキストにリンクのみ付与
                if let rtfData = pboard.data(forType: .rtf),
                   let attrString = NSAttributedString(rtf: rtfData, documentAttributes: nil),
                   attrString.length > 0,
                   let linkValue = attrString.attribute(.link, at: 0, effectiveRange: nil),
                   let textStorage = textStorage {
                    if shouldChangeText(in: selRange, replacementString: nil) {
                        textStorage.addAttribute(.link, value: linkValue, range: selRange)
                        didChangeText()
                    }
                    return true
                }
            }
            // 選択範囲外へのドロップ or カーソルの場合は通常の挿入処理（superへ）
        }

        return super.performDragOperation(sender)
    }

    // MARK: - Text/RTF File Drop Handling

    /// Markdownファイル拡張子の判定用
    static let markdownFileExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mkdn", "mdwn"
    ]

    /// ドロップされたファイルの内容種別
    enum DroppedFileContentType {
        case plainText       // プレーンテキスト（ソースコード等含む）
        case markdown        // Markdownファイル
        case rtf             // RTFデータ
        case rtfd            // RTFDパッケージ
        case word            // Word (.doc/.docx) または ODT
        case other           // 画像やバイナリ等
    }

    /// ファイルURLから内容種別を判定する（拡張子 + UTI + データ内容で判定）
    static func detectFileContentType(_ url: URL) -> DroppedFileContentType {
        let ext = url.pathExtension.lowercased()

        // Markdown は拡張子で判定（テキストだが特別扱い）
        if markdownFileExtensions.contains(ext) {
            return .markdown
        }

        // RTFD はディレクトリパッケージ
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            // RTFDパッケージ判定：TXT.rtf が含まれているか
            let txtRtf = url.appendingPathComponent("TXT.rtf")
            if FileManager.default.fileExists(atPath: txtRtf.path) {
                return .rtfd
            }
            return .other
        }

        // UTI による判定
        if let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier {
            // RTF
            if UTType(uti)?.conforms(to: .rtf) == true {
                return .rtf
            }
            // Word / ODT
            let wordUTIs: Set<String> = [
                "com.microsoft.word.doc",
                "org.openxmlformats.wordprocessingml.document",
                "com.microsoft.word.wordml",
                "org.oasis-open.opendocument.text"
            ]
            if wordUTIs.contains(uti) {
                return .word
            }
        }

        // データの先頭バイトで RTF 判定（UTI で判定できなかった場合のフォールバック）
        if let fh = try? FileHandle(forReadingFrom: url) {
            let header = fh.readData(ofLength: 6)
            fh.closeFile()
            if header.starts(with: [0x7B, 0x5C, 0x72, 0x74, 0x66]) {  // "{\rtf"
                return .rtf
            }
        }

        // UTI による判定: 既知のバイナリ形式（画像・動画・音声・アーカイブ等）は .other
        if let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
           let utType = UTType(uti) {
            // テキスト系は .plainText
            if utType.conforms(to: .text) {
                return .plainText
            }
            // 既知のバイナリ形式は .other（データ読み込みでの誤判定を防ぐ）
            let binaryTypes: [UTType] = [.image, .audiovisualContent, .archive,
                                         .executable, .database, .spreadsheet,
                                         .presentation, .pdf, .font]
            for binaryType in binaryTypes {
                if utType.conforms(to: binaryType) {
                    return .other
                }
            }
        }

        // UTI で判定できない場合、データを読んでテキストとしてデコードできるか試す
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            let outcome = EncodingDetector.shared.detectAndDecode(
                from: data, fileURL: url, allowUserSelection: false)
            switch outcome {
            case .success:
                return .plainText
            case .needsUserSelection:
                return .plainText
            case .failure:
                break
            }
        }

        return .other
    }

    /// ドロップされたファイルURLがテキスト/RTFファイルの場合に処理する
    /// - Returns: 処理した場合はtrue
    func handleTextFilesDrop(fileURLs: [URL], draggingInfo: any NSDraggingInfo) -> Bool {
        let isCtrlPressed = NSEvent.modifierFlags.contains(.control)

        // ドロップ先の文字位置を取得
        guard let dropIndex = characterIndex(for: draggingInfo) else { return false }

        var handledAny = false

        for url in fileURLs {
            // ファイルの内容種別を判定（拡張子 + UTI + データ内容）
            let contentType = Self.detectFileContentType(url)

            if contentType == .other {
                // プレーンテキスト書類: 非テキストファイルはフルパスを挿入
                if isPlainText {
                    let insertRange = NSRange(location: dropIndex, length: 0)
                    replaceString(in: insertRange, with: url.path)
                    handledAny = true
                    continue
                }
                // リッチテキスト書類: 処理しない（superに委譲してアタッチメント挿入）
                return false
            }

            if isCtrlPressed {
                // Ctrl+ドロップ
                if isPlainText {
                    let insertRange = NSRange(location: dropIndex, length: 0)
                    replaceString(in: insertRange, with: url.path)
                    handledAny = true
                } else {
                    if !upgradeToRTFDForDrop() { return true }
                    insertFileAsAttachment(url, at: dropIndex)
                    handledAny = true
                }
                continue
            }

            // ダイアログで内容挿入かアタッチメント/パス挿入かを選択
            let action = showTextFileDropAlert(fileName: url.lastPathComponent)
            if action == .cancel {
                return true
            }

            if action == .insertContents {
                switch contentType {
                case .plainText, .markdown:
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
                            if !isPlainText && contentType == .markdown {
                                // リッチテキスト書類にMarkdown → 解釈してリッチテキストとしてペースト
                                let attrStr = MarkdownParser.attributedString(from: content, baseURL: url.deletingLastPathComponent())
                                let insertRange = NSRange(location: dropIndex, length: 0)
                                replaceString(in: insertRange, with: attrStr)
                            } else {
                                let convertedContent = applyTextConversions(content)
                                setSelectedRange(NSRange(location: dropIndex, length: 0))
                                insertText(convertedContent, replacementRange: NSRange(location: dropIndex, length: 0))
                            }
                            handledAny = true
                        }
                    }

                case .rtf:
                    if let data = try? Data(contentsOf: url),
                       let attrStr = NSAttributedString(rtf: data, documentAttributes: nil) {
                        insertDroppedAttributedString(attrStr, at: dropIndex)
                        handledAny = true
                    }

                case .rtfd:
                    if let fileWrapper = try? FileWrapper(url: url, options: .immediate),
                       let attrStr = NSAttributedString(rtfdFileWrapper: fileWrapper, documentAttributes: nil) {
                        insertDroppedAttributedString(attrStr, at: dropIndex)
                        handledAny = true
                    }

                case .word:
                    if let data = try? Data(contentsOf: url) {
                        // まず自動判定で読み込み
                        var attrStr = try? NSAttributedString(data: data, options: [:], documentAttributes: nil)
                        // 失敗した場合 officeOpenXML で再試行
                        if attrStr == nil {
                            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: NSAttributedString.DocumentType.officeOpenXML]
                            attrStr = try? NSAttributedString(data: data, options: options, documentAttributes: nil)
                        }
                        if let attrStr = attrStr {
                            insertDroppedAttributedString(attrStr, at: dropIndex)
                            handledAny = true
                        }
                    }

                case .other:
                    break
                }
            } else {
                // insertAttachmentOrPath
                if isPlainText {
                    let insertRange = NSRange(location: dropIndex, length: 0)
                    replaceString(in: insertRange, with: url.path)
                    handledAny = true
                } else {
                    if !upgradeToRTFDForDrop() { return true }
                    insertFileAsAttachment(url, at: dropIndex)
                    handledAny = true
                }
            }
        }

        return handledAny
    }

    /// ドロップされた NSAttributedString を挿入する（プレーン/リッチテキストに応じて処理）
    func insertDroppedAttributedString(_ attrStr: NSAttributedString, at index: Int) {
        if isPlainText {
            let convertedContent = applyTextConversions(attrStr.string)
            let insertRange = NSRange(location: index, length: 0)
            replaceString(in: insertRange, with: convertedContent)
        } else {
            let convertedAttrStr = applyTextConversionsToAttributedString(attrStr)
            let insertRange = NSRange(location: index, length: 0)
            replaceString(in: insertRange, with: convertedAttrStr)
        }
    }

    /// テキストファイルドロップ時のアクション
    enum TextFileDropAction {
        case insertContents
        case insertAttachmentOrPath
        case cancel
    }

    /// テキストファイルドロップ時の選択ダイアログを表示する
    func showTextFileDropAlert(fileName: String) -> TextFileDropAction {
        let alert = NSAlert()
        alert.alertStyle = .informational
        let messageFormat = "Text document \"%@\" was dropped.".localized
        alert.messageText = String(format: messageFormat, fileName)
        alert.informativeText = "Do you want to insert the contents of the file?".localized
        alert.addButton(withTitle: "Insert Contents".localized)
        if isPlainText {
            alert.addButton(withTitle: "Insert File Path".localized)
        } else {
            alert.addButton(withTitle: "Insert File Attachment".localized)
        }
        alert.addButton(withTitle: "Cancel".localized)

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            return .insertContents
        case .alertSecondButtonReturn:
            return .insertAttachmentOrPath
        default:
            return .cancel
        }
    }

    /// ドロップ時に必要であればRTFD変換ダイアログを表示する
    /// - Returns: 続行可能な場合はtrue、キャンセルされた場合はfalse
    func upgradeToRTFDForDrop() -> Bool {
        guard let windowController = window?.windowController as? EditorWindowController,
              let document = windowController.textDocument,
              document.documentType != .rtfd else {
            return true  // すでにRTFDまたは取得できない場合は続行
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Convert this document to RTFD format?".localized
        alert.informativeText = "This document contains graphics or attachments and will be saved in RTFD format (RTF with graphics). RTFD documents may not be compatible with some applications. Do you want to convert?".localized
        alert.addButton(withTitle: "Convert".localized)
        alert.addButton(withTitle: "Cancel".localized)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            document.documentType = .rtfd
            document.updateFileTypeFromDocumentType()
            document.fileURL = nil
            document.autosavedContentsFileURL = nil
            NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: document)
            return true
        }
        return false
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
        openPanel.prompt = "Attach".localized

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
            // 表示用のセルを設定（ResizableImageAttachmentCellで統一し、グレー枠を防止）
            let cell = ResizableImageAttachmentCell(image: image, displaySize: image.size)
            attachment.attachmentCell = cell
            let attrStr = NSAttributedString(attachment: attachment)
            let insertRange = selectedRange()
            replaceString(in: insertRange, with: attrStr)
            return true
        }

        return super.readSelection(from: pboard)
    }

    /// ファイルをテキストアタッチメントとして挿入
    func insertFileAsAttachment(_ url: URL, at index: Int) {
        let attachment = NSTextAttachment()
        let fileWrapper = try? FileWrapper(url: url, options: .immediate)
        attachment.fileWrapper = fileWrapper
        attachment.fileWrapper?.preferredFilename = url.lastPathComponent

        // 画像ファイルの場合はResizableImageAttachmentCellを設定（グレー枠を防止）
        if let data = fileWrapper?.regularFileContents,
           let image = NSImage(data: data) {
            let cell = ResizableImageAttachmentCell(image: image, displaySize: image.size)
            attachment.attachmentCell = cell
        }

        let attrStr = NSAttributedString(attachment: attachment)
        let insertRange = NSRange(location: index, length: 0)
        replaceString(in: insertRange, with: attrStr)
    }

    /// ファイル/フォルダのフルパスをリンク付きで挿入（Ctrl+ドロップ用）
    /// プレーンテキストではパス文字列のみ、リッチテキストではfile:// URLリンク付きで挿入
    func insertFilePathWithLink(_ url: URL, at index: Int) {
        let path = url.path
        let insertRange = NSRange(location: index, length: 0)

        if isPlainText {
            replaceString(in: insertRange, with: path)
        } else {
            let fileURL = url.standardizedFileURL
            // 現在のタイピング属性を継承してリンク属性を追加
            var attrs = typingAttributes
            attrs[.link] = fileURL
            let attrStr = NSAttributedString(string: path, attributes: attrs)
            replaceString(in: insertRange, with: attrStr)
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
    func performSuperPaste(_ sender: Any?) {
        super.paste(sender)
    }

    /// ペースト時に文字変換を適用
    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general

        // Smart Language Separation のペースト中フラグを設定
        smartLanguageSeparation?.isPasting = true
        defer {
            smartLanguageSeparation?.isPasting = false
            smartLanguageSeparation?.processPendingFullSeparation()
        }

        // リッチテキスト書類の場合
        if !isPlainText {
            // RTFDデータまたは画像データがある場合はRTFDに昇格してsuperに委譲
            let hasRTFD = pasteboard.availableType(from: [.rtfd]) != nil
            let hasImage = pasteboard.availableType(from: [.tiff, .png]) != nil
            if hasRTFD || hasImage {
                upgradeToRTFDIfNeeded { [weak self] proceed in
                    guard let self = self, proceed else { return }
                    self.performSuperPaste(sender)
                    self.smartLanguageSeparation?.isPasting = false
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
                fixTextListRenderingAfterPaste()
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
        smartLanguageSeparation?.isPasting = true
        defer {
            smartLanguageSeparation?.isPasting = false
            smartLanguageSeparation?.processPendingFullSeparation()
        }

        let pasteboard = NSPasteboard.general
        if let rtfData = pasteboard.data(forType: .rtf),
           let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            let convertedString = applyTextConversionsToAttributedString(attributedString)
            // insertText ではなく replaceString を使用（書式を保持するため）
            replaceString(in: selectedRange(), with: convertedString)
            fixTextListRenderingAfterPaste()
        } else {
            super.pasteAsRichText(sender)
        }
    }

    /// プレーンテキストとしてペースト時に文字変換を適用
    override func pasteAsPlainText(_ sender: Any?) {
        smartLanguageSeparation?.isPasting = true
        defer {
            smartLanguageSeparation?.isPasting = false
            smartLanguageSeparation?.processPendingFullSeparation()
        }

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
    func pasteboardContainsImageContent(_ pboard: NSPasteboard) -> Bool {
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
            fixTextListRenderingAfterPaste()
            return true
        }
        return super.readSelection(from: pboard, type: type)
    }

    /// ペースト後に NSTextList のレンダリングを修復する
    /// TextKit 1 の NSLayoutManager は RTF デシリアライズ後に NSTextList 属性を
    /// 正しくレンダリングしないバグがあるため、RTF ラウンドトリップで修復する
    func fixTextListRenderingAfterPaste() {
        guard !isPlainText,
              let windowController = window?.windowController as? EditorWindowController,
              let textStorage = textStorage else { return }
        DispatchQueue.main.async {
            windowController.fixTextListRenderingIfNeeded(in: textStorage)
        }
    }

    /// 文字列に対して文字変換を適用
    /// - Parameter string: 変換対象の文字列
    /// - Returns: 変換後の文字列
    func applyTextConversions(_ string: String) -> String {
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
    func applyTextConversionsToAttributedString(_ attributedString: NSAttributedString) -> NSAttributedString {
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
}
