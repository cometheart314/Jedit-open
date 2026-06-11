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
        // 矩形（カラム）選択は複数レンジを持つため全レンジを保存する
        dragSourceRanges = selectedRanges.map { $0.rangeValue }
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
        dragSourceRanges = nil

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
    /// Note: ここではファイル内容の種別判定 (detectFileContentType) を行わないこと。
    /// draggingUpdated からマウス移動のたびに呼ばれるため、内容判定 (UTI 不明の
    /// ファイルでは全読み込み + エンコーディング検出) を行うとホバー中に固まる。
    /// 種別判定はドロップ確定時 (prepareForDragOperation / performDragOperation) に行う。
    func dragOperationForFileDrop(_ sender: any NSDraggingInfo) -> NSDragOperation? {
        if NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            // Ctrl+ドロップ: 任意のファイル/フォルダでパス+リンク挿入
            if pasteboardContainsFileURL(sender.draggingPasteboard) {
                return .link
            }
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

        // 矩形（カラム）選択のドロップは列分配で処理する。
        // ドラッグ元が複数レンジ（矩形選択）か、ペーストボードに矩形マーカーがある場合。
        // 通常の移動／挿入経路では selectedRange() の1レンジしか扱わず最初の行しか
        // ドロップされないため、専用処理へ振り分ける。
        let isRectangularDrop = ((sender.draggingSource as? JeditTextView)?.dragSourceRanges?.count ?? 0) > 1
            || pboard.availableType(from: Self.rectangularSelectionPasteboardTypes) != nil
        if isRectangularDrop, performColumnarDrop(sender) {
            return true
        }

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

        // 他アプリ/他書類からのリッチテキストのドロップ: RTF を取り込み、
        // 文字変換＋明暗モード色正規化を適用して挿入する（コピー＆ペーストと同じ挙動）。
        let nextRTFType = NSPasteboard.PasteboardType("NeXT Rich Text Format v1.0 pasteboard type")
        if let rtfType = pboard.availableType(from: [.rtf, nextRTFType]),
           let rtfData = pboard.data(forType: rtfType) ?? pboard.data(forType: .rtf),
           let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            let converted = applyTextConversionsToAttributedString(attributedString)
            replaceString(in: selectedRange(), with: converted)
            fixTextListRenderingAfterPaste()
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

    /// 矩形（カラム）選択を示すペーストボード型（コピー／ドラッグ共通）
    static let rectangularSelectionPasteboardTypes: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType("Apple rectangular text selection pasteboard type"),
        NSPasteboard.PasteboardType(
            "dyn.ah62d4rv4gu8yc6durvwwa6xfqr4gc5xhsz0gc6vasvw1u7basrw023pdsvy085vasbu1g7dfqm10c6xeeb4hw6df"),
    ]

    /// 矩形ペーストボードから行データを取得（リッチは RTF から属性付きで色等を保持、それ以外はプレーン）
    func columnarRows(from pasteboard: NSPasteboard) -> [NSAttributedString] {
        let nextRTFType = NSPasteboard.PasteboardType("NeXT Rich Text Format v1.0 pasteboard type")
        if isRichText,
           let rtfType = pasteboard.availableType(from: [.rtf, nextRTFType]),
           let rtfData = pasteboard.data(forType: rtfType) ?? pasteboard.data(forType: .rtf),
           let attr = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            // 文字変換＋明暗モード色正規化を適用してから行分割する
            let converted = applyTextConversionsToAttributedString(attr)
            return Self.splitAttributedByNewline(converted)
        } else if let string = pasteboard.string(forType: .string) {
            return string.components(separatedBy: "\n").map {
                NSAttributedString(string: $0, attributes: typingAttributes)
            }
        }
        return []
    }

    /// 矩形（カラム）選択のコピーを TextEdit / Jedit Ω と同じ列分配で貼り付ける。
    /// - Returns: 列分配を実施したら true。条件を満たさず通常ペーストに任せる場合は false。
    func performColumnarPaste(from pasteboard: NSPasteboard) -> Bool {
        let rows = columnarRows(from: pasteboard)
        // 1行のみなら矩形分配の意味がないため通常ペーストに任せる
        guard rows.count > 1 else { return false }
        return columnarInsert(rows: rows)
    }

    /// 与えられた各行を、現在のキャレットの列位置 (x) に合わせて後続の表示行へ分配挿入する。
    /// （矩形ペースト／矩形ドロップ共通の挿入処理）
    @discardableResult
    func columnarInsert(rows: [NSAttributedString]) -> Bool {
        guard let layoutManager = layoutManager,
              textContainer != nil,
              let textStorage = textStorage,
              selectedRange().length == 0,
              rows.count > 1 else { return false }

        // キャレットのジオメトリ（列 x と行の高さ）を求める
        let caretLoc = selectedRange().location
        let origin = textContainerOrigin
        let glyphCount = layoutManager.numberOfGlyphs
        let caretGlyph = min(layoutManager.glyphIndexForCharacter(at: caretLoc), max(0, glyphCount - 1))
        let fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: caretGlyph, effectiveRange: nil)
        let locationInFragment = layoutManager.location(forGlyphAt: caretGlyph)
        let caretX = fragmentRect.origin.x + locationInFragment.x
        let lineHeight = fragmentRect.height > 0 ? fragmentRect.height : 16

        // 各行の挿入位置を元テキスト上で算出（キャレットと同じ x で1行ずつ下の行へ）
        var insertIndexes: [Int] = []
        for i in 0..<rows.count {
            let point = CGPoint(x: caretX + origin.x,
                                y: fragmentRect.origin.y + (CGFloat(i) + 0.5) * lineHeight + origin.y)
            insertIndexes.append(characterIndexForInsertion(at: point))
        }

        // Undo 対応: 全レンジ分の変更を通知してから、下の行から挿入してインデックスずれを回避
        let ranges = insertIndexes.map { NSValue(range: NSRange(location: $0, length: 0)) }
        let strings = rows.map { $0.string }
        guard shouldChangeText(inRanges: ranges, replacementStrings: strings) else { return false }
        textStorage.beginEditing()
        for i in stride(from: rows.count - 1, through: 0, by: -1) {
            textStorage.replaceCharacters(in: NSRange(location: insertIndexes[i], length: 0), with: rows[i])
        }
        textStorage.endEditing()
        didChangeText()

        // 選択を先頭行の挿入直後に置く
        setSelectedRange(NSRange(location: insertIndexes[0] + rows[0].length, length: 0))
        return true
    }

    /// 矩形（カラム）選択のドロップを列分配で処理する。
    /// 同一書類内ドラッグ（移動）の場合はソースの全レンジを削除してから挿入する。
    /// - Returns: 矩形ドロップとして処理したら true。対象外なら false（通常処理へ）。
    func performColumnarDrop(_ sender: any NSDraggingInfo) -> Bool {
        guard let textStorage = textStorage,
              let dropIndex0 = characterIndex(for: sender) else { return false }

        let pboard = sender.draggingPasteboard
        let isMove = isDragFromSameDocument(sender) && !NSEvent.modifierFlags.contains(.option)
        let sourceView = sender.draggingSource as? JeditTextView

        // 行データ: 同一書類のソースがあればソース範囲から（属性保持・確実）、
        // なければドラッグペーストボードから取得する。
        var rows: [NSAttributedString]
        var sourceRanges: [NSRange] = []
        if let sourceView = sourceView,
           let sourceStorage = sourceView.textStorage,
           let savedRanges = sourceView.dragSourceRanges,
           savedRanges.count > 1 {
            sourceRanges = savedRanges.filter { $0.length > 0 }.sorted { $0.location < $1.location }
            rows = sourceRanges.map { sourceStorage.attributedSubstring(from: $0) }
        } else {
            rows = columnarRows(from: pboard)
        }
        guard rows.count > 1 else { return false }

        // ドロップ位置がいずれかのソース範囲内なら移動の意味がないので何もしない
        if isMove, sourceRanges.contains(where: { NSLocationInRange(dropIndex0, $0) || dropIndex0 == $0.location }) {
            handledSameDocumentDrag = true
            return true
        }

        undoManager?.beginUndoGrouping()

        var dropIndex = dropIndex0
        // 移動の場合はソースの全レンジを削除（高位→低位、ドロップ位置を補正）
        if isMove, !sourceRanges.isEmpty {
            for range in sourceRanges.sorted(by: { $0.location > $1.location }) {
                if NSMaxRange(range) <= dropIndex { dropIndex -= range.length }
                if shouldChangeText(in: range, replacementString: "") {
                    textStorage.deleteCharacters(in: range)
                    didChangeText()
                }
            }
        }

        // ドロップ位置にキャレットを置いて列分配挿入
        setSelectedRange(NSRange(location: min(dropIndex, textStorage.length), length: 0))
        let inserted = columnarInsert(rows: rows)

        undoManager?.endUndoGrouping()
        if isMove {
            undoManager?.setActionName(NSLocalizedString("Move", comment: "Undo action name for drag move"))
        }
        handledSameDocumentDrag = true
        return inserted
    }

    /// 属性付き文字列を改行 (\n) で分割する（各行の属性は保持）
    static func splitAttributedByNewline(_ attr: NSAttributedString) -> [NSAttributedString] {
        var result: [NSAttributedString] = []
        let ns = attr.string as NSString
        var start = 0
        while start <= ns.length {
            let searchRange = NSRange(location: start, length: ns.length - start)
            let found = ns.range(of: "\n", options: [], range: searchRange)
            if found.location == NSNotFound {
                result.append(attr.attributedSubstring(from: NSRange(location: start, length: ns.length - start)))
                break
            }
            result.append(attr.attributedSubstring(from: NSRange(location: start, length: found.location - start)))
            start = found.location + 1
        }
        return result
    }

    /// ペースト時に文字変換を適用
    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general

        // 矩形（カラム）選択のコピーは、各行をキャレットの列位置 (x) に合わせて
        // 後続の表示行へ分配する（カラムナーペースト = TextEdit / Jedit Ω と同じ挙動）。
        // 通常のカスタムペースト経路（insertText / replaceString）では全行が改行付きで
        // 1か所に挿入されてしまう。NSTextView 標準の readSelection は本アプリのカスタム
        // テキストスタックでは列分配にならないため、レイアウトのジオメトリを用いて自前で
        // 分配する（performColumnarPaste）。
        if pasteboard.availableType(from: Self.rectangularSelectionPasteboardTypes) != nil,
           performColumnarPaste(from: pasteboard) {
            return
        }

        // RTFD 昇格でシート（非同期）を出す経路では、実際の挿入は完了クロージャ内で
        // 後から行われる。下の defer 群は paste() の return 時点（＝挿入前）に
        // 発火してしまうため、その経路では後処理を完了クロージャに肩代わりさせ、
        // ここでの早期発火をこのフラグでスキップする。
        var pasteHandledByUpgradeCompletion = false

        #if JEDIT_PRO
        // 青空文庫ルビ記法のペースト後パース用に、ペースト前の選択範囲と
        // textStorage 長さを記録する。defer は宣言順の逆に発火するため、
        // Smart Language Separation の defer より「後 (= 先に宣言した方が後)」
        // にこの defer を置けば、テキスト編集が完了した状態で hook が走る。
        let rubyPrePasteRange = selectedRange()
        let rubyPrePasteLength = textStorage?.length ?? 0
        defer {
            if !pasteHandledByUpgradeCompletion {
                handleRubyParseAfterPaste(preRange: rubyPrePasteRange,
                                           oldLength: rubyPrePasteLength)
            }
        }
        #endif

        // Smart Language Separation のペースト中フラグを設定
        smartLanguageSeparation?.isPasting = true
        defer {
            if !pasteHandledByUpgradeCompletion {
                smartLanguageSeparation?.isPasting = false
                smartLanguageSeparation?.processPendingFullSeparation()
            }
        }

        // リッチテキスト書類の場合
        if !isPlainText {
            // RTFDデータまたは画像データがある場合はRTFDに昇格してsuperに委譲。
            // RTFD は外部アプリ/レガシー型 (com.apple.flat-rtfd /
            // "NeXT RTFD pasteboard type") で載ることもあるので、readNormalizedRTFD
            // が扱う型をすべて検出対象にする。
            let rtfdTypes: [NSPasteboard.PasteboardType] = [
                .rtfd,
                NSPasteboard.PasteboardType("com.apple.flat-rtfd"),
                NSPasteboard.PasteboardType("NeXT RTFD pasteboard type"),
            ]
            let hasRTFD = pasteboard.availableType(from: rtfdTypes) != nil
            let hasImage = pasteboard.availableType(from: [.tiff, .png]) != nil
            if hasRTFD || hasImage {
                // 昇格シートは非同期。後処理 (isPasting 解除・分離・ルビパース) は
                // paste() の defer ではなく、挿入が完了したこの完了クロージャ内で行う。
                pasteHandledByUpgradeCompletion = true
                upgradeToRTFDIfNeeded { [weak self] proceed in
                    guard let self = self else { return }
                    // proceed/キャンセルに関わらず、挿入後（またはキャンセル後）に
                    // ペースト中フラグの解除とペンディング処理を必ず行う。
                    defer {
                        self.smartLanguageSeparation?.isPasting = false
                        self.smartLanguageSeparation?.processPendingFullSeparation()
                        #if JEDIT_PRO
                        self.handleRubyParseAfterPaste(preRange: rubyPrePasteRange,
                                                       oldLength: rubyPrePasteLength)
                        #endif
                    }
                    guard proceed else { return }
                    // RTFD は自前で NSAttributedString に展開し、色を正規化してから
                    // 差し込む。これにより super.paste 経路でも、ダークモード非対応
                    // アプリ由来のハードコード黒文字色がダイナミック色に置き換わる。
                    // 画像のみ (RTFD なし) のときは従来通り super.paste に委譲する。
                    if hasRTFD, let normalized = self.readNormalizedRTFD(from: pasteboard) {
                        self.replaceString(in: self.selectedRange(), with: normalized)
                        self.fixTextListRenderingAfterPaste()
                    } else {
                        self.performSuperPaste(sender)
                    }
                }
                return
            }

            // RTFデータがある場合はリッチテキストとしてペースト（書式を保持）。
            // 外部アプリは RTF を .rtf (public.rtf) ではなく
            // "NeXT Rich Text Format v1.0 pasteboard type" で載せることがある。
            // ドラッグ経路 (readSelection) と同様、両方を RTF として扱わないと
            // 書式が見つからずプレーンテキストにフォールバックしてしまう。
            // insertText ではなく replaceString を使用する
            // （insertText は typingAttributes を適用してしまい書式が失われるため）
            let nextRTFType = NSPasteboard.PasteboardType("NeXT Rich Text Format v1.0 pasteboard type")
            if let rtfType = pasteboard.availableType(from: [.rtf, nextRTFType]),
               let rtfData = pasteboard.data(forType: rtfType) ?? pasteboard.data(forType: .rtf),
               let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
                let convertedString = applyTextConversionsToAttributedString(attributedString)
                replaceString(in: selectedRange(), with: convertedString)
                fixTextListRenderingAfterPaste()
                return
            }

            // RTF/RTFD が無く HTML がある場合 (ブラウザ等からのコピー) は、
            // HTML をリッチテキストとして取り込む。これが無いと書式が見つからず
            // プレーンテキストにフォールバックしてしまう。
            if let normalizedHTML = readNormalizedHTML(from: pasteboard) {
                replaceString(in: selectedRange(), with: normalizedHTML)
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
        let nextRTFType = NSPasteboard.PasteboardType("NeXT Rich Text Format v1.0 pasteboard type")
        if let rtfType = pasteboard.availableType(from: [.rtf, nextRTFType]),
           let rtfData = pasteboard.data(forType: rtfType) ?? pasteboard.data(forType: .rtf),
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
            // RTFD タイプは自前で NSAttributedString に展開し、色を正規化してから
            // 差し込む (super 委譲だとダークモード非対応アプリ由来の黒文字が
            // そのまま入る)。画像のみのドロップは従来通り super に委譲する。
            if let normalized = readNormalizedRTFD(from: pboard) {
                replaceString(in: selectedRange(), with: normalized)
                fixTextListRenderingAfterPaste()
                return true
            }
            return super.readSelection(from: pboard, type: type)
        }

        // テキストのみの場合は変換を適用
        if type == .string, let string = pboard.string(forType: .string) {
            let convertedString = applyTextConversions(string)
            insertText(convertedString, replacementRange: selectedRange())
            return true
        }

        // RTF データ。NSTextView が D&D 時に渡してくる型は実環境では
        // .rtf (public.rtf) ではなく "NeXT Rich Text Format v1.0 pasteboard type"
        // のことが多いので、両方を RTF として扱う。
        let nextRTFType = NSPasteboard.PasteboardType("NeXT Rich Text Format v1.0 pasteboard type")
        if (type == .rtf || type == nextRTFType),
           let rtfData = pboard.data(forType: type) ?? pboard.data(forType: .rtf),
           let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            let convertedString = applyTextConversionsToAttributedString(attributedString)
            // insertText ではなく replaceString を使用（書式を保持するため）
            replaceString(in: selectedRange(), with: convertedString)
            fixTextListRenderingAfterPaste()
            return true
        }

        // HTML (ブラウザ等からのリッチテキスト)。RTF が無くてもリッチとして取り込み、
        // ペースト経路と同じく色正規化・文字変換を適用する。
        if !isPlainText, let normalizedHTML = readNormalizedHTML(from: pboard) {
            replaceString(in: selectedRange(), with: normalizedHTML)
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
            windowController.fixTextListRenderingIfNeeded(in: textStorage, preservingSelection: true)
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

        // ペースト元がダークモード非対応の場合に備えて色をダイナミック化
        normalizePastedColorsForAppearance(in: mutable)

        return mutable
    }

    /// ペーストボードから HTML データを NSAttributedString として読み、文字変換と
    /// 色正規化を適用して返す。ブラウザ等は RTF ではなく HTML でリッチテキストを
    /// 載せるため、RTF/RTFD が無くてもこの経路で書式を保持できる。HTML タイプが
    /// 無い/解釈できない場合は nil を返し、呼び出し側でフォールバックする想定。
    func readNormalizedHTML(from pasteboard: NSPasteboard) -> NSAttributedString? {
        let htmlTypes: [NSPasteboard.PasteboardType] = [
            .html,
            NSPasteboard.PasteboardType("Apple HTML pasteboard type"),
        ]
        for type in htmlTypes {
            guard let data = pasteboard.data(forType: type) else { continue }
            if let attr = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            ) {
                return applyTextConversionsToAttributedString(attr)
            }
        }
        return nil
    }

    /// ペーストボードから RTFD / flat-RTFD データを NSAttributedString として読み、
    /// 文字変換と色正規化を適用して返す。RTFD タイプが無い (画像のみ等) 場合は
    /// nil を返し、呼び出し側で super フォールバックする想定。
    func readNormalizedRTFD(from pasteboard: NSPasteboard) -> NSAttributedString? {
        let rtfdTypes: [NSPasteboard.PasteboardType] = [
            .rtfd,
            NSPasteboard.PasteboardType("com.apple.flat-rtfd"),
            NSPasteboard.PasteboardType("NeXT RTFD pasteboard type"),
        ]
        for type in rtfdTypes {
            guard let data = pasteboard.data(forType: type) else { continue }
            if let attr = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtfd],
                documentAttributes: nil
            ) {
                return applyTextConversionsToAttributedString(attr)
            }
        }
        return nil
    }

    /// ペースト/ドロップで取り込まれた属性付き文字列の色を、コピー先（この書類）の
    /// 明暗モードに合わせて正規化する。
    ///
    /// - コピー元・コピー先がライト/ダーク/不明かをテキスト色から判定し、
    ///   ライト→ダークのときダーク変換、ダーク→ライトのときライト変換を行う。
    ///   同一モード・どちらかが不明のときは色変換しない。
    /// - 前景色属性が無い run は、ダークモードでも読めるよう動的な `.textColor` を付与する。
    private func normalizePastedColorsForAppearance(in attributedString: NSMutableAttributedString) {
        Self.applyColorNormalization(to: attributedString,
                                     sourceMode: Self.sourceColorMode(of: attributedString),
                                     destinationMode: destinationColorMode())
    }

    /// コピー先（この書類）の明暗モードをテキスト色から判定する。
    private func destinationColorMode() -> ColorAppearanceMode {
        let color = destinationModeTextColor()
        var mode: ColorAppearanceMode = .unknown
        let resolve = {
            if let rgb = Self.rgbComponents(of: color) {
                mode = Self.classifyColorMode(r: rgb.r, g: rgb.g, b: rgb.b)
            }
        }
        // 動的色 (.textColor 等) をこのビューの実効アピアランスで解決してから判定する
        if #available(macOS 11.0, *) {
            effectiveAppearance.performAsCurrentDrawingAppearance(resolve)
        } else {
            let saved = NSAppearance.current
            NSAppearance.current = effectiveAppearance
            resolve()
            NSAppearance.current = saved
        }
        return mode
    }

    /// コピー先の代表テキスト色（先頭文字の前景色 → typingAttributes → 動的 textColor）
    private func destinationModeTextColor() -> NSColor {
        if let textStorage = textStorage, textStorage.length > 0,
           let color = textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor {
            return color
        }
        if let color = typingAttributes[.foregroundColor] as? NSColor {
            return color
        }
        return .textColor
    }

    /// 色正規化の本体。ビューに依存しないよう static にしてあり、ライブな
    /// テキストビューが無い経路 (サービスメニュー経由の新規書類作成など) からも
    /// 利用できる。
    ///
    /// 仕様:
    ///   - コピー元ライト × コピー先ダーク → ダーク変換 (toDark)
    ///   - コピー元ダーク × コピー先ライト → ライト変換 (toLight)
    ///   - それ以外 (同一モード / どちらか不明) → 色変換なし
    ///   変換は前景色・背景色の両方に適用する。
    ///   前景色属性が無い run には、読みやすさのため動的 `.textColor` を付与する。
    static func applyColorNormalization(to attributedString: NSMutableAttributedString,
                                        sourceMode: ColorAppearanceMode,
                                        destinationMode: ColorAppearanceMode) {
        let range = NSRange(location: 0, length: attributedString.length)
        guard range.length > 0 else { return }

        // 変換方向を決定（新仕様）
        let conversion: ColorModeConversion
        if sourceMode == .light && destinationMode == .dark {
            conversion = .toDark
        } else if sourceMode == .dark && destinationMode == .light {
            conversion = .toLight
        } else {
            conversion = .none
        }

        // 前景色・背景色の変換（クロスモード時のみ）。
        // 列挙中に属性を書き換えると run 構造が変わるため、収集してから適用する。
        if conversion != .none {
            for key in [NSAttributedString.Key.foregroundColor, .backgroundColor] {
                var changes: [(NSRange, NSColor)] = []
                attributedString.enumerateAttribute(key, in: range, options: []) { value, subrange, _ in
                    guard let color = value as? NSColor,
                          let rgb = rgbComponents(of: color) else { return }
                    let source = ModeRGB(r: Double(rgb.r), g: Double(rgb.g),
                                         b: Double(rgb.b), alpha: Double(rgb.a))
                    let converted = (conversion == .toDark) ? source.toDark() : source.toLight()
                    changes.append((subrange, converted.nsColor))
                }
                for (subrange, color) in changes {
                    attributedString.addAttribute(key, value: color, range: subrange)
                }
            }
        }

        // 前景色属性が無い run は、既定の純黒を避けて動的 `.textColor` を付与する。
        var colorless: [NSRange] = []
        attributedString.enumerateAttribute(.foregroundColor, in: range, options: []) { value, subrange, _ in
            if value == nil { colorless.append(subrange) }
        }
        for subrange in colorless {
            attributedString.addAttribute(.foregroundColor, value: NSColor.textColor, range: subrange)
        }
    }

    /// コピー元の属性付き文字列の代表テキスト色から明暗モードを判定する。
    static func sourceColorMode(of attributedString: NSAttributedString) -> ColorAppearanceMode {
        guard let color = dominantForegroundColor(of: attributedString),
              let rgb = rgbComponents(of: color) else { return .unknown }
        return classifyColorMode(r: rgb.r, g: rgb.g, b: rgb.b)
    }

    /// テキスト色を ライト/ダーク/不明 に分類する。
    /// ほぼ黒（全成分が小さい）→ ライトモード、ほぼ白（全成分が大きい）→ ダークモード。
    static func classifyColorMode(r: CGFloat, g: CGFloat, b: CGFloat) -> ColorAppearanceMode {
        let low: CGFloat = 0.25
        let high: CGFloat = 0.75
        if r < low && g < low && b < low { return .light }
        if r > high && g > high && b > high { return .dark }
        return .unknown
    }

    /// 属性付き文字列で最も多く使われている前景色（文字数で重み付け）を返す。
    static func dominantForegroundColor(of attributedString: NSAttributedString) -> NSColor? {
        let range = NSRange(location: 0, length: attributedString.length)
        var lengths: [NSColor: Int] = [:]
        var best: NSColor?
        var bestLength = 0
        attributedString.enumerateAttribute(.foregroundColor, in: range, options: []) { value, subrange, _ in
            guard let color = value as? NSColor else { return }
            let total = (lengths[color] ?? 0) + subrange.length
            lengths[color] = total
            if total > bestLength {
                bestLength = total
                best = color
            }
        }
        return best
    }

    /// ビュー非依存の色正規化エントリ。サービスメニュー経由の新規書類作成など、
    /// ライブなテキストビューが無い経路から、ペーストと同じ色補正を適用する。
    /// コピー先のモードは実効アピアランス (isDark) から与える。
    static func normalizedColorsForAppearance(_ attributedString: NSAttributedString,
                                              isDark: Bool) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        applyColorNormalization(to: mutable,
                                sourceMode: sourceColorMode(of: mutable),
                                destinationMode: isDark ? .dark : .light)
        return mutable
    }

    /// 複数のカラースペースを試し、最初に得られた sRGB 相当の RGBA を返す。
    /// 外部アプリ由来の RTF/RTFD では色が deviceRGB やキャリブレーション付き空間で
    /// 来ることがあるため、sRGB だけで諦めずにフォールバックする。
    private static func rgbComponents(of color: NSColor)
        -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
        let candidates: [NSColorSpace] = [
            .sRGB, .deviceRGB, .genericRGB, .extendedSRGB
        ]
        for cs in candidates {
            if let c = color.usingColorSpace(cs) {
                return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
            }
        }
        return nil
    }

}

// MARK: - ライト/ダークモード 色変換

/// テキスト色から判定する明暗モード
enum ColorAppearanceMode {
    case light    // テキストがほぼ黒 → ライトモード
    case dark     // テキストがほぼ白 → ダークモード
    case unknown  // それ以外
}

/// 色変換の方向
enum ColorModeConversion {
    case toDark
    case toLight
    case none
}

/// ライト/ダークモード間の色変換ユーティリティ（HSB ベース）。
/// 明度の補正を反転させることで、ダーク背景（深いグレー）↔ ライト背景（白）、
/// ダーク文字（オフホワイト）↔ ライト文字（黒）を双方向に綺麗にマッピングする。
struct ModeRGB {
    let r: Double  // 0.0 ~ 1.0
    let g: Double
    let b: Double
    let alpha: Double

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(alpha))
    }

    /// ライトモード → ダークモード への変換
    func toDark() -> ModeRGB {
        let (h, s, brightness) = toHSB()
        // 明度補正: [0.0, 1.0] -> [0.15, 0.92]
        let newBrightness = 0.15 + (1.0 - brightness) * 0.77
        // 彩度補正: 暗い背景でギラつかないよう 15% 下げる
        let newSaturation = s * 0.85
        return ModeRGB.fromHSB(h: h, s: newSaturation, b: newBrightness, alpha: alpha)
    }

    /// ダークモード → ライトモード への変換
    func toLight() -> ModeRGB {
        let (h, s, brightness) = toHSB()
        // 明度補正: [0.15, 0.92] を [1.0, 0.0] 方向に逆転してマッピング
        let normalized = (brightness - 0.15) / 0.77
        let clamped = max(0.0, min(1.0, normalized))
        let newBrightness = 1.0 - clamped
        // 彩度補正: 白背景でも色がぼやけないよう 15% 引き上げる
        let newSaturation = max(0.0, min(1.0, s / 0.85))
        return ModeRGB.fromHSB(h: h, s: newSaturation, b: newBrightness, alpha: alpha)
    }

    // MARK: HSB ↔ RGB

    private func toHSB() -> (h: Double, s: Double, b: Double) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC

        var h: Double = 0
        if delta > 0 {
            if maxC == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == g {
                h = ((b - r) / delta) + 2
            } else {
                h = ((r - g) / delta) + 4
            }
            h /= 6
            if h < 0 { h += 1 }
        }

        let s = maxC == 0 ? 0 : delta / maxC
        return (h, s, maxC)
    }

    static func fromHSB(h: Double, s: Double, b: Double, alpha: Double) -> ModeRGB {
        if s == 0 { return ModeRGB(r: b, g: b, b: b, alpha: alpha) }

        let hp = h * 6
        let c = b * s
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let m = b - c

        var (r1, g1, b1) = (0.0, 0.0, 0.0)
        switch Int(hp) {
        case 0: (r1, g1, b1) = (c, x, 0)
        case 1: (r1, g1, b1) = (x, c, 0)
        case 2: (r1, g1, b1) = (0, c, x)
        case 3: (r1, g1, b1) = (0, x, c)
        case 4: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }

        return ModeRGB(r: r1 + m, g: g1 + m, b: b1 + m, alpha: alpha)
    }
}
