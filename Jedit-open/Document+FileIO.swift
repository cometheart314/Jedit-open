//
//  Document+FileIO.swift
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

    // MARK: - Reading and Writing

    // RTFDファイルパッケージの読み込みをサポート
    override nonisolated func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
        // RTFDとして読み込むかどうかを判定
        // 1. typeNameがcom.apple.rtfdの場合
        // 2. ディレクトリパッケージでTXT.rtfを含む場合（RTFD構造）
        let isRTFD = typeName == "com.apple.rtfd" || isRTFDPackage(fileWrapper)

        if isRTFD && fileWrapper.isDirectory {
            // RTFDはFileWrapperから直接読み込む
            var documentAttributes: NSDictionary?
            guard let attributedString = NSAttributedString(rtfdFileWrapper: fileWrapper, documentAttributes: &documentAttributes) else {
                throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                    NSLocalizedDescriptionKey: "Could not read RTFD document"
                ])
            }

            // bounds メタデータを読み込む
            var boundsInfoList: [AttachmentBoundsInfo] = []
            if let fileWrappers = fileWrapper.fileWrappers,
               let metadataWrapper = fileWrappers[".attachment_bounds.json"],
               let metadataData = metadataWrapper.regularFileContents {
                boundsInfoList = (try? JSONDecoder().decode([AttachmentBoundsInfo].self, from: metadataData)) ?? []
            }

            // エイリアスアタッチメントのセキュリティスコープ付きブックマークを復元
            let restoredURLs = Self.restoreAttachmentBookmarks(from: fileWrapper)

            MainActor.assumeIsolated {
                self.documentType = .rtfd
                self.textStorage.setAttributedString(attributedString)

                // セキュリティスコープ付きURLを保持
                self.securityScopedAttachmentURLs = restoredURLs

                // bounds情報を適用
                if !boundsInfoList.isEmpty {
                    self.applyAttachmentBoundsMetadata(boundsInfoList)
                }

                // すべての画像アタッチメントを ResizableImageAttachmentCell に変換
                // （デフォルト NSTextAttachmentCell のグレー枠を防止）
                self.convertAllImageAttachmentsToResizableCell()

                // Document attributes から properties を取得して反映
                if let attrs = documentAttributes as? [NSAttributedString.DocumentAttributeKey: Any] {
                    self.applyDocumentAttributesToProperties(attrs)
                }

                NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
            }
        } else {
            // その他のファイルタイプは通常のread(from:ofType:)に委譲
            if let data = fileWrapper.regularFileContents {
                try read(from: data, ofType: typeName)
            } else {
                throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                    NSLocalizedDescriptionKey: "Could not read file contents"
                ])
            }
        }
    }

    /// FileWrapperがRTFDパッケージ構造かどうかを判定
    nonisolated func isRTFDPackage(_ fileWrapper: FileWrapper) -> Bool {
        guard fileWrapper.isDirectory,
              let fileWrappers = fileWrapper.fileWrappers else {
            return false
        }
        // RTFDパッケージは必ずTXT.rtfを含む
        return fileWrappers["TXT.rtf"] != nil
    }

    /// RTFD パッケージの FileWrapper を作成する。
    /// アクセスできないシンボリックリンク（サンドボックス外を指すリンク等）をスキップし、
    /// 読み込み可能なファイルのみで FileWrapper を構築する。
    nonisolated static func createRTFDFileWrapperSkippingInaccessibleSymlinks(from url: URL) throws -> FileWrapper {
        let fm = FileManager.default
        let directoryWrapper = FileWrapper(directoryWithFileWrappers: [:])

        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                NSLocalizedDescriptionKey: "Could not read RTFD directory contents"
            ])
        }

        for itemURL in contents {
            let resourceValues = try? itemURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
            let isSymlink = resourceValues?.isSymbolicLink ?? false

            if isSymlink {
                // シンボリックリンク: リンク先にアクセスできるか確認
                let destination = itemURL.resolvingSymlinksInPath()
                if fm.isReadableFile(atPath: destination.path) {
                    // アクセス可能ならリンク先の内容で通常のファイルとして追加
                    if let data = try? Data(contentsOf: destination) {
                        let childWrapper = FileWrapper(regularFileWithContents: data)
                        childWrapper.preferredFilename = itemURL.lastPathComponent
                        directoryWrapper.addFileWrapper(childWrapper)
                    }
                }
                // アクセスできない場合はスキップ
            } else if resourceValues?.isDirectory ?? false {
                // サブディレクトリ: 再帰的に FileWrapper を作成
                if let childWrapper = try? FileWrapper(url: itemURL, options: .immediate) {
                    childWrapper.preferredFilename = itemURL.lastPathComponent
                    directoryWrapper.addFileWrapper(childWrapper)
                }
            } else {
                // 通常ファイル
                if let data = try? Data(contentsOf: itemURL) {
                    let childWrapper = FileWrapper(regularFileWithContents: data)
                    childWrapper.preferredFilename = itemURL.lastPathComponent
                    directoryWrapper.addFileWrapper(childWrapper)
                }
            }
        }

        return directoryWrapper
    }

    // RTFDファイルパッケージの書き込みをサポート
    override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        // RTFDとして保存するかどうかを判定
        // 1. typeNameがcom.apple.rtfdの場合
        // 2. documentTypeが.rtfdの場合（拡張子が.rtfdでないRTFDパッケージを読み込んだ場合）
        let shouldSaveAsRTFD = typeName == "com.apple.rtfd" || documentType == .rtfd

        if shouldSaveAsRTFD {
            // RTFDはFileWrapperとして書き出す
            let range = NSRange(location: 0, length: textStorage.length)

            // Document properties を document attributes に設定
            var documentAttributes: [NSAttributedString.DocumentAttributeKey: Any] = [:]
            if let properties = presetData?.properties {
                if !properties.author.isEmpty {
                    documentAttributes[.author] = properties.author
                }
                if !properties.company.isEmpty {
                    documentAttributes[.company] = properties.company
                }
                if !properties.copyright.isEmpty {
                    documentAttributes[.copyright] = properties.copyright
                }
                if !properties.title.isEmpty {
                    documentAttributes[.title] = properties.title
                }
                if !properties.subject.isEmpty {
                    documentAttributes[.subject] = properties.subject
                }
                if !properties.keywords.isEmpty {
                    let keywordsArray = properties.keywords.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    documentAttributes[.keywords] = keywordsArray
                }
                if !properties.comment.isEmpty {
                    documentAttributes[.comment] = properties.comment
                }
            }

            // ビュー・ページ設定を document attributes に設定
            setViewAndPageLayoutDocumentAttributes(&documentAttributes)

            // リスト行のマーカー属性を正規化（RTFD エンコード前に必要）
            normalizeListMarkerAttributes()

            // RTFD 保存前にアンカー属性をリンク属性に変換
            let savedAnchorData = convertAnchorsToLinksForSave()

            guard let fileWrapper = textStorage.rtfdFileWrapper(from: range, documentAttributes: documentAttributes) else {
                // エラー時も復元
                restoreAnchorsAfterSave(savedAnchorData)
                throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                    NSLocalizedDescriptionKey: "Could not create RTFD file wrapper"
                ])
            }

            // 保存後にリンク属性をアンカー属性に復元
            restoreAnchorsAfterSave(savedAnchorData)

            // 画像のbounds情報をメタデータとして保存
            let boundsMetadata = collectAttachmentBoundsMetadata()
            if !boundsMetadata.isEmpty {
                if let metadataData = try? JSONEncoder().encode(boundsMetadata) {
                    let metadataWrapper = FileWrapper(regularFileWithContents: metadataData)
                    metadataWrapper.preferredFilename = ".attachment_bounds.json"
                    fileWrapper.addFileWrapper(metadataWrapper)
                }
            }

            // エイリアスアタッチメントのセキュリティスコープ付きブックマークを保存
            saveAttachmentBookmarks(to: fileWrapper)

            return fileWrapper
        } else {
            // その他のファイルタイプは通常のdata(ofType:)を使用
            let data = try data(ofType: typeName)
            return FileWrapper(regularFileWithContents: data)
        }
    }

    // MARK: - Attachment Security-Scoped Bookmarks

    /// RTFD パッケージ内のエイリアス（シンボリックリンク）FileWrapper のセキュリティスコープ付き
    /// ブックマークを .attachment_bookmarks.json として保存する
    func saveAttachmentBookmarks(to fileWrapper: FileWrapper) {
        guard let childWrappers = fileWrapper.fileWrappers else { return }

        var bookmarkEntries: [[String: String]] = []

        for (name, child) in childWrappers {
            // シンボリックリンク FileWrapper のリンク先URLに対してブックマークを作成
            if child.isSymbolicLink, let destURL = child.symbolicLinkDestinationURL {
                do {
                    let bookmarkData = try destURL.bookmarkData(
                        options: [.withSecurityScope],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    bookmarkEntries.append([
                        "filename": name,
                        "bookmark": bookmarkData.base64EncodedString()
                    ])
                } catch {
                    // ブックマーク作成失敗は無視（コピーされたファイルには不要）
                }
            }
        }

        guard !bookmarkEntries.isEmpty else { return }

        if let data = try? JSONSerialization.data(withJSONObject: bookmarkEntries, options: [.prettyPrinted]) {
            // 既存のブックマークメタデータがあれば削除
            if let existing = fileWrapper.fileWrappers?[".attachment_bookmarks.json"] {
                fileWrapper.removeFileWrapper(existing)
            }
            let bookmarkWrapper = FileWrapper(regularFileWithContents: data)
            bookmarkWrapper.preferredFilename = ".attachment_bookmarks.json"
            fileWrapper.addFileWrapper(bookmarkWrapper)
        }
    }

    /// RTFD パッケージから .attachment_bookmarks.json を読み込み、
    /// セキュリティスコープ付きリソースのアクセスを開始する
    /// - Returns: アクセス中のセキュリティスコープ付きURL
    nonisolated static func restoreAttachmentBookmarks(from fileWrapper: FileWrapper) -> [URL] {
        guard let fileWrappers = fileWrapper.fileWrappers,
              let bookmarkWrapper = fileWrappers[".attachment_bookmarks.json"],
              let data = bookmarkWrapper.regularFileContents,
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            return []
        }

        var accessedURLs: [URL] = []

        for entry in entries {
            guard let base64 = entry["bookmark"],
                  let bookmarkData = Data(base64Encoded: base64) else {
                continue
            }

            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if url.startAccessingSecurityScopedResource() {
                    accessedURLs.append(url)
                }
            }
        }

        return accessedURLs
    }

    // MARK: - List Marker Attribute Normalization

    /// RTF/RTFD 保存前にリスト行のマーカー属性を正規化する
    ///
    /// NSTextView がリスト行を管理する際、テキストストレージには `\t•\t` のようなマーカー文字が含まれる。
    /// ユーザーがマーカーの途中から属性（色、字消し線など）を変更すると、マーカー部分に部分的に属性が
    /// 適用された状態になる。RTF 保存時に `\t•\t` は `{\listtext}` としてエンコードされるが、
    /// マーカー部分に部分的にかかった属性は RTF フォーマットでは正しく表現できず、再読み込み時に
    /// マーカー文字が除去される際に属性情報が失われる。
    ///
    /// この問題を回避するため、保存前にマーカー部分 (`\t•\t`) の属性をマーカー直後のテキストの
    /// 属性に統一する。
    func normalizeListMarkerAttributes() {
        guard textStorage.length > 0 else { return }

        let nsString = textStorage.string as NSString
        var paragraphStart = 0

        textStorage.beginEditing()
        while paragraphStart < textStorage.length {
            let paragraphRange = nsString.paragraphRange(for: NSRange(location: paragraphStart, length: 0))

            // リスト属性を持つ段落のみ処理
            if let style = textStorage.attribute(.paragraphStyle, at: paragraphStart, effectiveRange: nil) as? NSParagraphStyle,
               !style.textLists.isEmpty {

                // 段落の先頭に \t + (任意の文字) + \t のマーカーパターンがあるか確認
                let lineText = nsString.substring(with: paragraphRange)
                if lineText.hasPrefix("\t"),
                   lineText.count >= 3 {
                    // 2番目の \t を探してマーカー範囲を決定
                    if let secondTabIndex = lineText.index(lineText.startIndex, offsetBy: 1, limitedBy: lineText.endIndex),
                       let markerEnd = lineText[secondTabIndex...].firstIndex(of: "\t") {
                        let markerLength = lineText.distance(from: lineText.startIndex, to: lineText.index(after: markerEnd))
                        let textStart = paragraphRange.location + markerLength

                        // マーカー後にテキストがある場合のみ処理
                        if textStart < NSMaxRange(paragraphRange) {
                            let markerRange = NSRange(location: paragraphRange.location, length: markerLength)
                            let textAttrs = textStorage.attributes(at: UInt(textStart), effectiveRange: nil)
                            textStorage.setAttributes(textAttrs, range: markerRange)
                        }
                    }
                }
            }

            paragraphStart = NSMaxRange(paragraphRange)
        }
        textStorage.endEditing()
    }

    // MARK: - Attachment Bounds Metadata

    /// 画像attachmentのbounds情報を収集
    func collectAttachmentBoundsMetadata() -> [AttachmentBoundsInfo] {
        var boundsInfoList: [AttachmentBoundsInfo] = []

        textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment else { return }

            // boundsが設定されている場合のみ保存
            if attachment.bounds.size.width > 0 && attachment.bounds.size.height > 0 {
                // ファイル名を取得
                let filename = attachment.fileWrapper?.preferredFilename ?? "unknown_\(range.location)"
                let info = AttachmentBoundsInfo(
                    location: range.location,
                    filename: filename,
                    width: attachment.bounds.size.width,
                    height: attachment.bounds.size.height
                )
                boundsInfoList.append(info)
            }
        }

        return boundsInfoList
    }

    /// すべての画像アタッチメントのセルを ResizableImageAttachmentCell に変換する
    /// macOS デフォルトの NSTextAttachmentCell はグレー枠を描画するため、
    /// RTFD 読み込み後に呼び出してグレー枠を防止する
    func convertAllImageAttachmentsToResizableCell() {
        var replacements: [(range: NSRange, attachment: NSTextAttachment)] = []

        textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            // すでに ResizableImageAttachmentCell の場合はスキップ
            if attachment.attachmentCell is ResizableImageAttachmentCell { return }
            // 画像データを持つアタッチメントのみ対象
            // （シンボリックリンク型 FileWrapper では regularFileContents が例外をスローするためチェック）
            guard let fileWrapper = attachment.fileWrapper,
                  fileWrapper.isRegularFile,
                  let data = fileWrapper.regularFileContents,
                  let image = NSImage(data: data) else { return }
            // ファイル拡張子で画像かどうかを判定
            let imageExtensions = ["png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "webp", "heic", "heif", "ico", "svg"]
            if let filename = fileWrapper.preferredFilename,
               let ext = filename.components(separatedBy: ".").last?.lowercased(),
               !imageExtensions.contains(ext) {
                return
            }
            replacements.append((range: range, attachment: attachment))
        }

        guard !replacements.isEmpty else { return }

        // 後ろから置き換え（位置ずれ防止）
        let sorted = replacements.sorted { $0.range.location > $1.range.location }

        textStorage.beginEditing()
        for item in sorted {
            let newAttachment = NSTextAttachment()
            newAttachment.fileWrapper = item.attachment.fileWrapper
            newAttachment.bounds = item.attachment.bounds

            if let fw = item.attachment.fileWrapper, fw.isRegularFile,
               let data = fw.regularFileContents,
               let image = NSImage(data: data) {
                let displaySize = item.attachment.bounds.size.width > 0 ? item.attachment.bounds.size : image.size
                let cell = ResizableImageAttachmentCell(image: image, displaySize: displaySize)
                newAttachment.attachmentCell = cell
            }

            // 元の属性（段落スタイル等）を保持してアタッチメントのみ置き換える
            let originalAttrs = textStorage.attributes(at: UInt(item.range.location), effectiveRange: nil) as? [NSAttributedString.Key: Any] ?? [:]
            var newAttrs = originalAttrs
            newAttrs[NSAttributedString.Key.attachment] = newAttachment
            let attachmentString = NSAttributedString(string: "\u{FFFC}", attributes: newAttrs)
            textStorage.replaceCharacters(in: item.range, with: attachmentString)
        }
        textStorage.endEditing()
    }

    /// 画像attachmentにbounds情報を適用
    func applyAttachmentBoundsMetadata(_ boundsInfoList: [AttachmentBoundsInfo]) {
        // attachmentを置き換えてboundsを適用する
        // 単にboundsを設定するだけでは表示に反映されないため、attachmentごと置き換える

        var replacements: [(range: NSRange, attachment: NSTextAttachment, bounds: CGRect)] = []

        // まずファイル名で照合してリストを作成
        textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment,
                  let filename = attachment.fileWrapper?.preferredFilename else { return }

            // boundsInfoListから対応する情報を検索
            if let info = boundsInfoList.first(where: { $0.filename == filename }) {
                let newBounds = CGRect(x: 0, y: 0, width: info.width, height: info.height)
                replacements.append((range: range, attachment: attachment, bounds: newBounds))
            }
        }

        // 位置でも検索（ファイル名がない場合のフォールバック）
        for info in boundsInfoList {
            if info.location < textStorage.length {
                let attrs = textStorage.attributes(at: UInt(info.location), effectiveRange: nil) as? [NSAttributedString.Key: Any] ?? [:]
                if let attachment = attrs[NSAttributedString.Key.attachment] as? NSTextAttachment {
                    // すでにリストに含まれているかチェック
                    if !replacements.contains(where: { $0.range.location == info.location }) {
                        let newBounds = CGRect(x: 0, y: 0, width: info.width, height: info.height)
                        replacements.append((range: NSRange(location: info.location, length: 1), attachment: attachment, bounds: newBounds))
                    }
                }
            }
        }

        // 後ろから置き換えていく（位置がずれないように）
        let sortedReplacements = replacements.sorted { $0.range.location > $1.range.location }

        textStorage.beginEditing()
        for replacement in sortedReplacements {
            // 新しいattachmentを作成
            let newAttachment = NSTextAttachment()
            newAttachment.fileWrapper = replacement.attachment.fileWrapper
            newAttachment.bounds = replacement.bounds

            // 画像を取得してカスタムセルを設定（縦書き対応）
            if let fileWrapper = replacement.attachment.fileWrapper, fileWrapper.isRegularFile,
               let data = fileWrapper.regularFileContents,
               let image = NSImage(data: data) {
                let cell = ResizableImageAttachmentCell(image: image, displaySize: replacement.bounds.size)
                newAttachment.attachmentCell = cell
            }

            // 元の属性（段落スタイル等）を保持してアタッチメントのみ置き換える
            let originalAttrs = textStorage.attributes(at: UInt(replacement.range.location), effectiveRange: nil) as? [NSAttributedString.Key: Any] ?? [:]
            var newAttrs = originalAttrs
            newAttrs[NSAttributedString.Key.attachment] = newAttachment
            let attachmentString = NSAttributedString(string: "\u{FFFC}", attributes: newAttrs)
            textStorage.replaceCharacters(in: replacement.range, with: attachmentString)
        }
        textStorage.endEditing()
    }

    override func data(ofType typeName: String) throws -> Data {
        // 保存時は既存の documentType を使用する
        // （autosave等で typeName が実際の書類タイプと異なる場合があるため）
        let docType = self.documentType

        // ドキュメントタイプに応じて保存
        if docType == .plain {
            // プレーンテキストの場合
            return try dataForPlainText()
        } else {
            // RTFまたはRTFDの場合はNSAttributedStringを使用
            let range = NSRange(location: 0, length: textStorage.length)
            var options: [NSAttributedString.DocumentAttributeKey: Any] = [
                .documentType: docType
            ]

            // Document properties を document attributes に設定
            if let properties = presetData?.properties {
                if !properties.author.isEmpty {
                    options[.author] = properties.author
                }
                if !properties.company.isEmpty {
                    options[.company] = properties.company
                }
                if !properties.copyright.isEmpty {
                    options[.copyright] = properties.copyright
                }
                if !properties.title.isEmpty {
                    options[.title] = properties.title
                }
                if !properties.subject.isEmpty {
                    options[.subject] = properties.subject
                }
                if !properties.keywords.isEmpty {
                    // keywords はカンマ区切りの文字列を配列に変換
                    let keywordsArray = properties.keywords.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    options[.keywords] = keywordsArray
                }
                if !properties.comment.isEmpty {
                    options[.comment] = properties.comment
                }
            }

            // ビュー・ページ設定を document attributes に設定
            setViewAndPageLayoutDocumentAttributes(&options)

            // リスト行のマーカー属性を正規化（RTF エンコード前に必要）
            normalizeListMarkerAttributes()

            // RTF 保存前にアンカー属性をリンク属性に変換（RTF にはカスタム属性が保存されないため）
            let savedAnchorData = convertAnchorsToLinksForSave()

            do {
                let data = try textStorage.data(from: range, documentAttributes: options)
                // 保存後にリンク属性をアンカー属性に復元
                restoreAnchorsAfterSave(savedAnchorData)
                return data
            } catch {
                // エラー時も復元
                restoreAnchorsAfterSave(savedAnchorData)
                throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                    NSLocalizedDescriptionKey: "Could not write \(docType == .rtf ? "RTF" : "RTFD") document: \(error.localizedDescription)"
                ])
            }
        }
    }

    /// プレーンテキストの保存データを生成
    func dataForPlainText() throws -> Data {
        let defaults = UserDefaults.standard

        // Save Panel のフォーマット選択で Plain Text が選ばれた場合は
        // Save Panel のポップアップの値を優先する（UserDefaults の設定をバイパス）
        let useSavePanelValues = savePanelFormatTag != nil

        // 1. エンコーディングを決定
        let saveEncoding: String.Encoding
        if useSavePanelValues {
            // Save Panel の値を使用（applyFormatTagForSave で documentEncoding に設定済み）
            saveEncoding = documentEncoding
        } else {
            let encodingForWriteInt = defaults.integer(forKey: UserDefaults.Keys.plainTextEncodingForWrite)
            if encodingForWriteInt <= 0 {
                // Automatic: Documentのプロパティを使用
                saveEncoding = documentEncoding
            } else {
                // 指定されたエンコーディングを使用
                saveEncoding = String.Encoding(rawValue: UInt(encodingForWriteInt))
            }
        }

        // 2. 改行コードを決定
        let saveLineEnding: LineEnding
        if useSavePanelValues {
            // Save Panel の値を使用（applyFormatTagForSave で lineEnding に設定済み）
            saveLineEnding = lineEnding
        } else {
            let lineEndingForWriteInt = defaults.integer(forKey: UserDefaults.Keys.plainTextLineEndingForWrite)
            if lineEndingForWriteInt < 0 {
                // Automatic: Documentのプロパティを使用
                saveLineEnding = lineEnding
            } else {
                // 指定された改行コードを使用
                saveLineEnding = LineEnding(rawValue: lineEndingForWriteInt) ?? .lf
            }
        }

        // 3. BOMを付加するかどうかを決定
        let shouldAddBOM: Bool
        if useSavePanelValues {
            // Save Panel の値を使用（applyFormatTagForSave で hasBOM に設定済み）
            shouldAddBOM = hasBOM
        } else {
            let bomForWriteInt = defaults.integer(forKey: UserDefaults.Keys.plainTextBomForWrite)
            if bomForWriteInt < 0 {
                // Automatic: Documentのプロパティを使用
                shouldAddBOM = hasBOM
            } else {
                // 0 = OFF, 1 = ON
                shouldAddBOM = bomForWriteInt == 1
            }
        }

        // 4. テキストを取得し、改行コードを変換
        var string = textStorage.string
        string = convertLineEndings(in: string, to: saveLineEnding)

        // 4.5. 保存時のエンコーディング変換（読み込み時の逆変換）
        string = applyEncodingSaveConversions(string, encoding: saveEncoding)

        // 5. 指定エンコーディングでエンコード
        var encodedData: Data?
        var usedEncoding = saveEncoding
        var needsFallback = false

        encodedData = string.data(using: saveEncoding)

        // エンコード成功してもラウンドトリップで確認（ロスレス変換かどうか）
        if let data = encodedData {
            // デコードして元のテキストと一致するか確認
            if let decoded = String(data: data, encoding: saveEncoding) {
                if decoded != string {
                    // 変換中に文字が失われた
                    needsFallback = true
                }
            } else {
                // デコードに失敗
                needsFallback = true
            }
        } else {
            // エンコード自体が失敗
            needsFallback = true
        }

        // エンコード失敗またはロスのある変換の場合はアラートを表示してUTF-8にフォールバック
        if needsFallback {
            showEncodingFailureAlert(encoding: saveEncoding)
            usedEncoding = .utf8
            encodedData = string.data(using: .utf8)
        }

        guard var data = encodedData else {
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                NSLocalizedDescriptionKey: "Could not encode text"
            ])
        }

        // 6. BOMを付加（必要な場合）
        if shouldAddBOM {
            data = addBOM(to: data, encoding: usedEncoding)
        }

        // 保存に使用したエンコーディングでDocumentのプロパティを更新
        self.documentEncoding = usedEncoding
        self.lineEnding = saveLineEnding
        self.hasBOM = shouldAddBOM

        return data
    }

    /// 改行コードを変換
    func convertLineEndings(in string: String, to lineEnding: LineEnding) -> String {
        // まず全ての改行を統一（CRLF → LF, CR → LF）
        var result = string.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")

        // 目的の改行コードに変換
        switch lineEnding {
        case .lf:
            return result // すでにLF
        case .cr:
            return result.replacingOccurrences(of: "\n", with: "\r")
        case .crlf:
            return result.replacingOccurrences(of: "\n", with: "\r\n")
        }
    }

    /// 改行コードをLFに統一（読み込み時に使用、任意のスレッドから呼び出し可能）
    nonisolated func normalizeLineEndingsToLF(_ string: String) -> String {
        var result = string.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")
        return result
    }

    /// Shift_JIS読み込み時の文字変換（Preferencesの設定に基づく、任意のスレッドから呼び出し可能）
    /// - Parameters:
    ///   - string: 変換対象の文字列
    ///   - encoding: ファイルのエンコーディング
    /// - Returns: 変換後の文字列
    nonisolated func applyEncodingConversions(_ string: String, encoding: String.Encoding) -> String {
        let defaults = UserDefaults.standard
        var result = string

        // Shift_JISエンコーディンググループかどうかを判定
        let isShiftJIS = encoding == .shiftJIS ||
                         encoding.rawValue == CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)) ||
                         encoding.rawValue == CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.shiftJIS_X0213.rawValue))

        // Convert '¥' (0x5c) to Back Slash '\' (U+005C) when Shift_JIS encoding group
        // 直接キー文字列を使用（nonisolatedコンテキストでのアクセス）
        if defaults.bool(forKey: "JOConvertYenToBackSlash") && isShiftJIS {
            // Shift_JISでデコードした際に円記号(U+00A5)になっている可能性がある
            result = result.replacingOccurrences(of: "\u{00A5}", with: "\\")
        }

        // Convert '‾' (0x7e) to Tilde '~' (U+007E) when Shift_JIS encoding group
        if defaults.bool(forKey: "JOConvertOverlineToTilde") && isShiftJIS {
            // Shift_JISでデコードした際にオーバーライン(U+203E)になっている可能性がある
            result = result.replacingOccurrences(of: "\u{203E}", with: "~")
        }

        // Convert FULLWIDTH TILDE '～' (U+FF5E) to WAVE DASH '〜' (U+301C)
        // これはエンコーディングに関係なく適用
        if defaults.bool(forKey: "JOConvertFullWidthTidle") {
            result = result.replacingOccurrences(of: "\u{FF5E}", with: "\u{301C}")
        }

        return result
    }

    /// Shift_JIS保存時の文字変換（読み込み時の逆変換、Preferencesの設定に基づく）
    /// - Parameters:
    ///   - string: 変換対象の文字列
    ///   - encoding: 保存先のエンコーディング
    /// - Returns: 変換後の文字列
    func applyEncodingSaveConversions(_ string: String, encoding: String.Encoding) -> String {
        let defaults = UserDefaults.standard
        var result = string

        // Shift_JISエンコーディンググループかどうかを判定
        let isShiftJIS = encoding == .shiftJIS ||
                         encoding.rawValue == CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)) ||
                         encoding.rawValue == CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.shiftJIS_X0213.rawValue))

        // Convert Back Slash '\' (U+005C) to '¥' (U+00A5) when Shift_JIS encoding group
        // 読み込み時に U+00A5 → U+005C に変換したものを元に戻し、
        // 確実に 0x5c として保存されるようにする
        if defaults.bool(forKey: UserDefaults.Keys.convertYenToBackSlash) && isShiftJIS {
            result = result.replacingOccurrences(of: "\\", with: "\u{00A5}")
        }

        return result
    }

    /// BOMを追加
    func addBOM(to data: Data, encoding: String.Encoding) -> Data {
        var result = Data()

        switch encoding {
        case .utf8:
            // UTF-8 BOM: EF BB BF
            result.append(contentsOf: [0xEF, 0xBB, 0xBF])
        case .utf16BigEndian:
            // UTF-16 BE BOM: FE FF
            result.append(contentsOf: [0xFE, 0xFF])
        case .utf16LittleEndian:
            // UTF-16 LE BOM: FF FE
            result.append(contentsOf: [0xFF, 0xFE])
        case .utf16:
            // UTF-16 (システムのエンディアンに依存、通常はLE)
            result.append(contentsOf: [0xFF, 0xFE])
        case .utf32BigEndian:
            // UTF-32 BE BOM: 00 00 FE FF
            result.append(contentsOf: [0x00, 0x00, 0xFE, 0xFF])
        case .utf32LittleEndian:
            // UTF-32 LE BOM: FF FE 00 00
            result.append(contentsOf: [0xFF, 0xFE, 0x00, 0x00])
        default:
            // その他のエンコーディングはBOMなし
            return data
        }

        result.append(data)
        return result
    }

    /// エンコーディング変換失敗時のアラートを表示（同期的に表示）
    func showEncodingFailureAlert(encoding: String.Encoding) {
        let alert = NSAlert()
        alert.messageText = "Encoding Conversion Failed".localized
        alert.informativeText = String(format: "The text could not be converted to %@. The file will be saved as UTF-8 instead.".localized, String.localizedName(of: encoding))
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK".localized)

        // 常にモーダルで表示（保存処理をブロックしてユーザーの確認を待つ）
        alert.runModal()
    }

    override nonisolated func read(from data: Data, ofType typeName: String) throws {
        // Markdown タイプの場合は RTF として扱う
        // （Duplicate 時に data(ofType:) が RTF を返すため、
        //  read(from data:) でも RTF として読み込む必要がある）
        let effectiveTypeName: String
        if Self.isMarkdownType(typeName) {
            effectiveTypeName = "public.rtf"
        } else if typeName == "public.plain-text" && Self.dataIsRTF(data) {
            // autosave 復元時: .txt 拡張子だが実際のデータが RTF の場合は RTF として読み込む
            // （data(ofType:) は documentType に基づいて RTF データを生成するが、
            //  autosave ファイルの拡張子が .txt のため、復元時に plain text として渡される）
            effectiveTypeName = "public.rtf"
        } else {
            effectiveTypeName = typeName
        }

        // ドキュメントタイプを判定
        let docType: NSAttributedString.DocumentType
        switch effectiveTypeName {
        case "public.rtf":
            docType = .rtf
        case "com.apple.rtfd":
            docType = .rtfd
        default:
            docType = .plain
        }

        // ドキュメントタイプに応じて読み込み
        if docType == .plain {
            // プレーンテキストの場合

            // ファイルURLを取得（MainActorでfileURLにアクセス）
            let currentFileURL = MainActor.assumeIsolated {
                self.fileURL
            }

            // BOMの有無を検出
            let bomDetected = EncodingDetector.shared.hasBOM(data)

            // Preferencesの Opening Encoding 設定を取得（直接キー文字列を使用）
            let preferredEncodingInt = UserDefaults.standard.integer(forKey: "JOPlainTextEncoding")
            let preferredEncoding: String.Encoding? = preferredEncodingInt <= 0 ? nil : String.Encoding(rawValue: UInt(preferredEncodingInt))

            #if DEBUG
            Swift.print("=== Encoding Detection Start ===")
            Swift.print("Data size: \(data.count) bytes")
            Swift.print("File URL: \(currentFileURL?.path ?? "none")")
            Swift.print("Preferred Encoding: \(preferredEncoding.map { String.localizedName(of: $0) } ?? "Automatic")")
            // 先頭バイトを表示（BOM確認用）
            let headerBytes = data.prefix(10).map { String(format: "%02X", $0) }.joined(separator: " ")
            Swift.print("Header bytes: \(headerBytes)")
            #endif

            // 指定されたエンコーディングがある場合はそれを使用
            if let specifiedEncoding = preferredEncoding {
                // 指定エンコーディングでデコードを試行
                if let string = EncodingDetector.shared.decodeData(data, with: specifiedEncoding) {
                    // 信頼度を計算（文字化けしていないかチェック）
                    let confidence = EncodingDetector.shared.calculateConfidence(string: string, data: data, encoding: specifiedEncoding)

                    #if DEBUG
                    Swift.print("Specified encoding decode attempt:")
                    Swift.print("  Encoding: \(String.localizedName(of: specifiedEncoding))")
                    Swift.print("  Decoded string length: \(string.count) characters")
                    Swift.print("  Confidence: \(confidence)%")
                    #endif

                    // 信頼度が閾値以上の場合のみ成功とみなす
                    if confidence >= EncodingDetector.confidenceThreshold {
                        #if DEBUG
                        Swift.print("Result: SUCCESS (specified encoding)")
                        Swift.print("  Has BOM: \(bomDetected)")
                        Swift.print("=== Encoding Detection End ===\n")
                        #endif

                        // 改行コードを判定してからLFに変換、エンコーディング変換を適用
                        let detectedLineEnding = LineEnding.detect(in: string)
                        var normalizedString = self.normalizeLineEndingsToLF(string)
                        normalizedString = self.applyEncodingConversions(normalizedString, encoding: specifiedEncoding)

                        MainActor.assumeIsolated {
                            self.documentType = .plain
                            self.documentEncoding = specifiedEncoding
                            self.hasBOM = bomDetected
                            self.lineEnding = detectedLineEnding
                            self.textStorage.replaceCharacters(in: NSRange(location: 0, length: self.textStorage.length), with: normalizedString)
                            NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
                        }
                        return
                    }

                    #if DEBUG
                    Swift.print("Specified encoding has low confidence (\(confidence)%), asking user for selection")
                    #endif
                } else {
                    #if DEBUG
                    Swift.print("Specified encoding failed to decode, asking user for selection")
                    #endif
                }

                // 指定エンコーディングで開けなかった、または信頼度が低い場合、ユーザーに選択を求める
                // 自動判定で候補を取得
                let candidates = EncodingDetector.shared.detectEncodings(from: data, fileURL: currentFileURL)

                let selectedResult = MainActor.assumeIsolated {
                    self.showEncodingSelectionDialogModal(candidates: candidates)
                }

                guard let selectedEncoding = selectedResult,
                      let string = EncodingDetector.shared.decodeData(data, with: selectedEncoding) else {
                    throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                        NSLocalizedDescriptionKey: "Could not decode text file. No valid encoding found.".localized
                    ])
                }

                #if DEBUG
                Swift.print("User selected encoding: \(String.localizedName(of: selectedEncoding))")
                Swift.print("=== Encoding Detection End ===\n")
                #endif

                // 改行コードを判定してからLFに変換、エンコーディング変換を適用
                let detectedLineEnding = LineEnding.detect(in: string)
                var normalizedString = self.normalizeLineEndingsToLF(string)
                normalizedString = self.applyEncodingConversions(normalizedString, encoding: selectedEncoding)

                MainActor.assumeIsolated {
                    self.documentType = .plain
                    self.documentEncoding = selectedEncoding
                    self.hasBOM = bomDetected
                    self.lineEnding = detectedLineEnding
                    self.textStorage.replaceCharacters(in: NSRange(location: 0, length: self.textStorage.length), with: normalizedString)
                    NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
                }
                return
            }

            // 「自動」の場合：エンコーディングを自動判定

            // 全候補を取得してデバッグ出力
            let allCandidates = EncodingDetector.shared.detectEncodings(from: data, fileURL: currentFileURL)
            #if DEBUG
            Swift.print("--- All Encoding Candidates ---")
            for (index, candidate) in allCandidates.enumerated() {
                Swift.print("  [\(index + 1)] \(candidate.name)")
                Swift.print("      Encoding: \(candidate.encoding) (rawValue: \(candidate.encoding.rawValue))")
                Swift.print("      Confidence: \(candidate.confidence)%")
                Swift.print("      Lossy: \(candidate.usedLossyConversion)")
            }
            Swift.print("-------------------------------")
            #endif

            let outcome = EncodingDetector.shared.detectAndDecode(from: data, fileURL: currentFileURL, precomputedResults: allCandidates)

            switch outcome {
            case .success(let encoding, let string):
                // 自動判定成功
                #if DEBUG
                Swift.print("Result: SUCCESS (auto-detected)")
                Swift.print("  Selected encoding: \(String.localizedName(of: encoding))")
                Swift.print("  Encoding rawValue: \(encoding.rawValue)")
                Swift.print("  Decoded string length: \(string.count) characters")
                Swift.print("  Has BOM: \(bomDetected)")
                Swift.print("=== Encoding Detection End ===\n")
                #endif

                // 改行コードを判定してからLFに変換、エンコーディング変換を適用
                let detectedLineEnding = LineEnding.detect(in: string)
                var normalizedString = self.normalizeLineEndingsToLF(string)
                normalizedString = self.applyEncodingConversions(normalizedString, encoding: encoding)

                MainActor.assumeIsolated {
                    self.documentType = .plain
                    self.documentEncoding = encoding
                    self.hasBOM = bomDetected
                    self.lineEnding = detectedLineEnding
                    self.textStorage.replaceCharacters(in: NSRange(location: 0, length: self.textStorage.length), with: normalizedString)
                    NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
                }

            case .needsUserSelection(let candidates):
                // 信頼度が低い場合、ユーザーに選択を求める
                #if DEBUG
                Swift.print("Result: NEEDS USER SELECTION (low confidence)")
                Swift.print("  Candidates count: \(candidates.count)")
                if let best = candidates.first {
                    Swift.print("  Best candidate: \(best.name) (\(best.confidence)%)")
                }
                Swift.print("=== Encoding Detection End ===\n")
                #endif

                // ドキュメントを開く前にモーダルダイアログでエンコーディングを選択させる
                let selectedResult = MainActor.assumeIsolated {
                    self.showEncodingSelectionDialogModal(candidates: candidates)
                }

                guard let selectedEncoding = selectedResult,
                      let string = EncodingDetector.shared.decodeData(data, with: selectedEncoding) else {
                    throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                        NSLocalizedDescriptionKey: "Could not decode text file. No valid encoding found.".localized
                    ])
                }

                #if DEBUG
                Swift.print("User selected encoding: \(String.localizedName(of: selectedEncoding))")
                #endif

                // 改行コードを判定してからLFに変換、エンコーディング変換を適用
                let detectedLineEnding = LineEnding.detect(in: string)
                var normalizedString = self.normalizeLineEndingsToLF(string)
                normalizedString = self.applyEncodingConversions(normalizedString, encoding: selectedEncoding)

                MainActor.assumeIsolated {
                    self.documentType = .plain
                    self.documentEncoding = selectedEncoding
                    self.hasBOM = bomDetected
                    self.lineEnding = detectedLineEnding
                    self.textStorage.replaceCharacters(in: NSRange(location: 0, length: self.textStorage.length), with: normalizedString)
                    NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
                }

            case .failure:
                #if DEBUG
                Swift.print("Result: FAILURE")
                Swift.print("=== Encoding Detection End ===\n")
                #endif

                throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                    NSLocalizedDescriptionKey: "Could not decode text file.".localized
                ])
            }
        } else {
            // RTFまたはRTFDの場合はNSAttributedStringを使用
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: docType
            ]

            do {
                var documentAttributes: NSDictionary?
                let attributedString = try NSAttributedString(data: data, options: options, documentAttributes: &documentAttributes)

                // メインアクターで実行
                MainActor.assumeIsolated {
                    self.documentType = docType
                    self.textStorage.setAttributedString(attributedString)

                    // すべての画像アタッチメントを ResizableImageAttachmentCell に変換
                    // （デフォルト NSTextAttachmentCell のグレー枠を防止）
                    if docType == .rtfd || docType == .rtf {
                        self.convertAllImageAttachmentsToResizableCell()
                    }

                    // Document attributes から properties を取得して反映
                    if let attrs = documentAttributes as? [NSAttributedString.DocumentAttributeKey: Any] {
                        self.applyDocumentAttributesToProperties(attrs)
                    }

                    NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
                }
            } catch {
                // RTF/RTFDとしてパースできなかった場合、プレーンテキストとしてフォールバック
                // （拡張子が .rtf でも中身がプレーンテキストのファイルに対応）
                if docType == .rtf && !Self.dataIsRTF(data) {
                    try self.read(from: data, ofType: "public.plain-text")
                    return
                }
                throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                    NSLocalizedDescriptionKey: "Could not read \(docType == .rtf ? "RTF" : "RTFD") document: \(error.localizedDescription)"
                ])
            }
        }
    }

    /// Document attributes から properties を取得して presetData に反映
    /// ファイルにプロパティがある場合のみ上書き、ない場合はSettingsの値を維持
    func applyDocumentAttributesToProperties(_ attrs: [NSAttributedString.DocumentAttributeKey: Any]) {
        // presetData がなければ作成
        if presetData == nil {
            presetData = createDefaultPresetDataForCurrentDocumentType()
        }

        // ファイルの属性から値を設定（空でない場合のみ上書き）
        if let author = attrs[.author] as? String, !author.isEmpty {
            presetData?.properties.author = author
        }
        if let company = attrs[.company] as? String, !company.isEmpty {
            presetData?.properties.company = company
        }
        if let copyright = attrs[.copyright] as? String, !copyright.isEmpty {
            presetData?.properties.copyright = copyright
        }
        if let title = attrs[.title] as? String, !title.isEmpty {
            presetData?.properties.title = title
        }
        if let subject = attrs[.subject] as? String, !subject.isEmpty {
            presetData?.properties.subject = subject
        }
        if let keywords = attrs[.keywords] as? [String], !keywords.isEmpty {
            // 配列をカンマ区切りの文字列に変換
            presetData?.properties.keywords = keywords.joined(separator: ", ")
        }
        if let comment = attrs[.comment] as? String, !comment.isEmpty {
            presetData?.properties.comment = comment
        }

        // RTF/RTFDファイルから読み込んだ properties を一時保存
        // 拡張属性読み込み後に適用するため
        loadedDocumentAttributeProperties = presetData?.properties

        // ビュー・ページ設定を Document Attributes から一時保存
        // 拡張属性読み込み後に適用するため（Document Attributes を presetData より優先）
        loadedDocumentAttributeViewSettings = [:]
        let viewSettingKeys: [NSAttributedString.DocumentAttributeKey] = [
            .paperSize, .topMargin, .bottomMargin, .leftMargin, .rightMargin,
            .viewMode, .viewSize, .viewZoom, .backgroundColor, .defaultTabInterval,
            .textLayoutSections, .readOnly
        ]
        for key in viewSettingKeys {
            if let value = attrs[key] {
                loadedDocumentAttributeViewSettings?[key] = value
            }
        }
        // 値が一つもなければnilにする
        if loadedDocumentAttributeViewSettings?.isEmpty == true {
            loadedDocumentAttributeViewSettings = nil
        }
    }

    // MARK: - Word / OpenDocument Support

    /// XML ファイルが Word 2003 XML (WordML) 形式かどうかをファイル先頭の内容で判定
    nonisolated static func isWordMLFile(url: URL) -> Bool {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { fileHandle.closeFile() }
        guard let headerData = try? fileHandle.read(upToCount: 1024),
              let header = String(data: headerData, encoding: .utf8) else { return false }
        // Word 2003 XML は "<?xml" で始まり、"w:wordDocument" または
        // "schemas-microsoft-com:office:word" namespace を含む
        return header.contains("w:wordDocument")
            || header.contains("schemas-microsoft-com:office:word")
            || header.contains("urn:schemas-microsoft-com:office:word")
    }

    /// Word (.doc/.docx) または OpenDocument (.odt) ファイルを読み込む
    /// 元のfileURLを維持し、readOnly（編集ロック）状態で開く
    /// - Parameters:
    ///   - url: ファイルのURL
    ///   - typeName: UTI文字列
    nonisolated func readWordOrODTDocument(from url: URL, ofType typeName: String) throws {
        let data = try Data(contentsOf: url)

        // UTI から NSAttributedString.DocumentType を判定
        let docType: NSAttributedString.DocumentType
        switch typeName {
        case "com.microsoft.word.doc":
            docType = .docFormat
        case "org.openxmlformats.wordprocessingml.document":
            docType = .officeOpenXML
        case "com.microsoft.word.wordml":
            docType = .wordML
        default:
            // .odt など：まず .officeOpenXML で試行する
            docType = .officeOpenXML
        }

        var documentAttributes: NSDictionary?
        var attributedString: NSAttributedString?

        // 指定された DocumentType で読み込みを試行
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: docType
        ]
        attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: &documentAttributes)

        // 失敗した場合、DocumentType を指定せずに自動判定で再試行
        if attributedString == nil {
            documentAttributes = nil
            attributedString = try? NSAttributedString(data: data, options: [:], documentAttributes: &documentAttributes)
        }

        guard let result = attributedString else {
            let formatName: String
            switch typeName {
            case "com.microsoft.word.doc":
                formatName = "Word (.doc)"
            case "org.openxmlformats.wordprocessingml.document":
                formatName = "Word (.docx)"
            case "com.microsoft.word.wordml":
                formatName = "Word 2003 XML (.xml)"
            case "org.oasis-open.opendocument.text":
                formatName = "OpenDocument (.odt)"
            default:
                formatName = typeName
            }
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError, userInfo: [
                NSLocalizedDescriptionKey: String(format: "Could not read %@ document.".localized, formatName)
            ])
        }

        // リッチテキストとして読み込み、readOnly（編集ロック）で開く
        MainActor.assumeIsolated {
            self.documentType = .rtf
            self.textStorage.setAttributedString(result)
            self.convertAllImageAttachmentsToResizableCell()
            self.presetData = NewDocData.richText
            self.isImportedDocument = true

            // 編集ロック状態にする
            self.presetData?.view.preventEditing = true

            // Document attributes から properties を適用
            if let attrs = documentAttributes as? [NSAttributedString.DocumentAttributeKey: Any] {
                self.applyDocumentAttributesToProperties(attrs)
            }

            NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
        }
    }

    // MARK: - Markdown Support

    /// UTI が Markdown タイプかどうかを判定
    nonisolated static func isMarkdownType(_ typeName: String) -> Bool {
        return typeName == "net.daringfireball.markdown"
    }

    /// ファイル拡張子が Markdown かどうかを判定
    nonisolated static func isMarkdownFile(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn"].contains(ext)
    }

    /// ファイルの内容が実際には RTF かどうかを先頭バイトで判定
    /// 拡張子が .md でも中身が RTF の場合にMarkdownパーサーのフリーズを防ぐ
    nonisolated static func isActuallyRTF(url: URL) -> Bool {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { fh.closeFile() }
        guard let header = try? fh.read(upToCount: 6) else { return false }
        // RTF ファイルは "{\\rtf1" で始まる
        return header.starts(with: [0x7B, 0x5C, 0x72, 0x74, 0x66, 0x31])  // {\rtf1
    }

    /// Markdown (.md) ファイルを読み込む
    /// リッチテキストに変換し、readOnly（編集ロック）で開く
    nonisolated func readMarkdownDocument(from url: URL) throws {
        let data = try Data(contentsOf: url)

        // UTF-8 でデコード（Markdown ファイルは通常 UTF-8）
        guard let markdownText = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .ascii) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError, userInfo: [
                NSLocalizedDescriptionKey: "Could not read Markdown document.".localized
            ])
        }

        let baseURL = url.deletingLastPathComponent()

        // Markdownの実際のパースはshowWindows()で行う（テキストコンテナサイズ確定後）
        // ここではメタデータとプリセットのみ設定
        MainActor.assumeIsolated {
            self.documentType = .rtf
            // 仮の空コンテンツを設定（ウインドウ表示後に実際のMarkdownをパースする）
            self.textStorage.setAttributedString(NSAttributedString(string: " "))
            self.presetData = NewDocData.richText
            self.isImportedDocument = true
            self.isMarkdownDocument = true
            self.originalMarkdownText = markdownText

            // Markdown 用の行間設定（lineHeightMultiple = 1.8）
            self.presetData?.format.lineHeightMultiple = 1.8

            // 編集ロック状態にする
            self.presetData?.view.preventEditing = true

            NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
        }
    }

    // MARK: - Text Clipping Support

    /// テキストクリッピングファイルを読み込む
    /// - Parameter url: テキストクリッピングファイルのURL
    nonisolated func readTextClipping(from url: URL) throws {
        // テキストクリッピングファイル（単一ファイルまたはパッケージ）を読み込む
        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: [
                NSLocalizedDescriptionKey: "Text clipping file not found"
            ])
        }

        // パッケージ（ディレクトリ）の場合
        if isDirectory.boolValue {
            try readTextClippingPackage(from: url)
            return
        }

        // 単一ファイルの場合 - バイナリplistを読み込む
        let data = try Data(contentsOf: url)
        try parseTextClippingData(data)
    }

    /// テキストクリッピングパッケージを読み込む
    nonisolated func readTextClippingPackage(from url: URL) throws {
        // パッケージ内のファイルを探索
        // 通常は拡張属性にデータが格納されているか、内部にplistがある

        // まず拡張属性 com.apple.ResourceFork を試す
        if let resourceForkData = try? getExtendedAttribute(named: "com.apple.ResourceFork", at: url) {
            // ResourceForkからデータを読み込む（旧形式）
            // ここでは単純にバイナリplistとして試す
            do {
                try parseTextClippingData(resourceForkData)
                return
            } catch {
                // 続行
            }
        }

        // パッケージ内のplistファイルを探す
        let fileManager = FileManager.default
        if let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            for fileURL in contents {
                if fileURL.pathExtension == "plist" {
                    let plistData = try Data(contentsOf: fileURL)
                    try parseTextClippingData(plistData)
                    return
                }
            }
        }

        throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError, userInfo: [
            NSLocalizedDescriptionKey: "Could not read text clipping package"
        ])
    }

    /// 拡張属性を取得
    nonisolated func getExtendedAttribute(named name: String, at url: URL) throws -> Data? {
        let path = url.path
        let length = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard length > 0 else { return nil }

        var data = Data(count: length)
        let result = data.withUnsafeMutableBytes { buffer in
            getxattr(path, name, buffer.baseAddress, length, 0, XATTR_NOFOLLOW)
        }
        guard result == length else { return nil }
        return data
    }

    /// テキストクリッピングのデータをパースしてテキストを抽出
    nonisolated func parseTextClippingData(_ data: Data) throws {
        // バイナリplistとしてデコード
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError, userInfo: [
                NSLocalizedDescriptionKey: "Could not parse text clipping data as property list"
            ])
        }

        // UTI-Dataディクショナリを取得
        guard let utiData = plist["UTI-Data"] as? [String: Any] else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError, userInfo: [
                NSLocalizedDescriptionKey: "Text clipping does not contain UTI-Data"
            ])
        }

        // ヘルパー関数: 様々な型からDataを取得
        func extractData(from value: Any?) -> Data? {
            if let data = value as? Data {
                return data
            }
            if let nsData = value as? NSData {
                return nsData as Data
            }
            // 文字列の場合はUTF-8でエンコード
            if let string = value as? String {
                return string.data(using: .utf8)
            }
            return nil
        }

        // リッチテキスト（RTF/RTFD）を優先的に試す
        // 1. com.apple.flat-rtfd (RTFD flattened)
        if let rtfdData = extractData(from: utiData["com.apple.flat-rtfd"]) {
            if let attributedString = NSAttributedString(rtfd: rtfdData, documentAttributes: nil) {
                MainActor.assumeIsolated {
                    self.documentType = .rtfd
                    self.textStorage.setAttributedString(attributedString)
                    self.convertAllImageAttachmentsToResizableCell()
                    self.presetData = NewDocData.richText
                    // 新規ファイルとして扱う（fileURLをnilに）
                    self.fileURL = nil
                    NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
                }
                return
            }
        }

        // 2. public.rtf
        if let rtfData = extractData(from: utiData["public.rtf"]),
           let attributedString = try? NSAttributedString(data: rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            MainActor.assumeIsolated {
                self.documentType = .rtf
                self.textStorage.setAttributedString(attributedString)
                self.convertAllImageAttachmentsToResizableCell()
                self.presetData = NewDocData.richText
                // 新規ファイルとして扱う（fileURLをnilに）
                self.fileURL = nil
                NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
            }
            return
        }

        // 3. プレーンテキスト（UTF-8）
        if let utf8Data = extractData(from: utiData["public.utf8-plain-text"]),
           let text = String(data: utf8Data, encoding: .utf8) {
            MainActor.assumeIsolated {
                self.documentType = .plain
                self.textStorage.setAttributedString(NSAttributedString(string: text))
                self.presetData = NewDocData.plainText
                // 新規ファイルとして扱う（fileURLをnilに）
                self.fileURL = nil
                NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
            }
            return
        }

        // 4. UTF-16プレーンテキスト
        if let utf16Data = extractData(from: utiData["public.utf16-plain-text"]),
           let text = String(data: utf16Data, encoding: .utf16) {
            MainActor.assumeIsolated {
                self.documentType = .plain
                self.textStorage.setAttributedString(NSAttributedString(string: text))
                self.presetData = NewDocData.plainText
                // 新規ファイルとして扱う（fileURLをnilに）
                self.fileURL = nil
                NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
            }
            return
        }

        // 5. public.utf16-external-plain-text
        if let utf16ExtData = extractData(from: utiData["public.utf16-external-plain-text"]),
           let text = String(data: utf16ExtData, encoding: .utf16) {
            MainActor.assumeIsolated {
                self.documentType = .plain
                self.textStorage.setAttributedString(NSAttributedString(string: text))
                self.presetData = NewDocData.plainText
                // 新規ファイルとして扱う（fileURLをnilに）
                self.fileURL = nil
                NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
            }
            return
        }

        // データが見つからない場合
        throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError, userInfo: [
            NSLocalizedDescriptionKey: "Text clipping does not contain readable text data"
        ])
    }

    /// 一時保存した document attributes の properties を presetData に適用
    func applyLoadedDocumentAttributeProperties() {
        guard let loadedProperties = loadedDocumentAttributeProperties else { return }

        // RTF/RTFDファイルの document attributes から読み込んだ properties を適用
        // 空でない場合のみ上書き（Settingsの値を維持）
        if !loadedProperties.author.isEmpty {
            presetData?.properties.author = loadedProperties.author
        }
        if !loadedProperties.company.isEmpty {
            presetData?.properties.company = loadedProperties.company
        }
        if !loadedProperties.copyright.isEmpty {
            presetData?.properties.copyright = loadedProperties.copyright
        }
        if !loadedProperties.title.isEmpty {
            presetData?.properties.title = loadedProperties.title
        }
        if !loadedProperties.subject.isEmpty {
            presetData?.properties.subject = loadedProperties.subject
        }
        if !loadedProperties.keywords.isEmpty {
            presetData?.properties.keywords = loadedProperties.keywords
        }
        if !loadedProperties.comment.isEmpty {
            presetData?.properties.comment = loadedProperties.comment
        }

        // 一時保存をクリア
        loadedDocumentAttributeProperties = nil
    }

    /// 一時保存した document attributes のビュー・ページ設定を presetData に適用
    /// Document Attributes の値で presetData を上書きすることで、presetData よりも優先する
    func applyLoadedDocumentAttributeViewSettings() {
        guard let settings = loadedDocumentAttributeViewSettings else { return }

        // 用紙サイズ
        if let paperSize = settings[.paperSize] as? NSSize {
            if presetData?.printInfo == nil {
                presetData?.printInfo = .default
            }
            presetData?.printInfo?.paperWidth = paperSize.width
            presetData?.printInfo?.paperHeight = paperSize.height
        }

        // マージン
        if let top = settings[.topMargin] as? CGFloat {
            presetData?.pageLayout.topMarginPoints = top
        }
        if let bottom = settings[.bottomMargin] as? CGFloat {
            presetData?.pageLayout.bottomMarginPoints = bottom
        }
        if let left = settings[.leftMargin] as? CGFloat {
            presetData?.pageLayout.leftMarginPoints = left
        }
        if let right = settings[.rightMargin] as? CGFloat {
            presetData?.pageLayout.rightMarginPoints = right
        }

        // 表示モード（0=continuous, 1=page）
        if let viewMode = settings[.viewMode] as? Int {
            presetData?.view.pageMode = (viewMode == 1)
        }

        // ウィンドウサイズ
        if let viewSize = settings[.viewSize] as? NSSize {
            presetData?.view.windowWidth = viewSize.width
            presetData?.view.windowHeight = viewSize.height
        }

        // ズーム（100 = 100%）
        if let viewZoom = settings[.viewZoom] as? CGFloat, viewZoom > 0 {
            presetData?.view.scale = viewZoom / 100.0
        }

        // 背景色
        if let bgColor = settings[.backgroundColor] as? NSColor {
            presetData?.fontAndColors.colors.background = CodableColor(bgColor)
        }

        // タブ幅
        if let tabInterval = settings[.defaultTabInterval] as? CGFloat, tabInterval > 0 {
            presetData?.format.tabWidthPoints = tabInterval
        }

        // 縦書き/横書き（.textLayoutSections）
        if let sections = settings[.textLayoutSections] as? [[String: Any]],
           let first = sections.first,
           let orientation = first["NSTextLayoutSectionOrientation"] as? Int {
            presetData?.format.editingDirection = (orientation == 1) ? .rightToLeft : .leftToRight
        }

        // 編集ロック状態（.readOnly）
        if let readOnly = settings[.readOnly] as? Int {
            presetData?.view.preventEditing = (readOnly > 0)
        }

        // 一時保存をクリア
        loadedDocumentAttributeViewSettings = nil
    }

    /// presetData のビュー・ページ設定を document attributes に設定する（保存時に使用）
    func setViewAndPageLayoutDocumentAttributes(_ documentAttributes: inout [NSAttributedString.DocumentAttributeKey: Any]) {
        // ページレイアウト設定（マージン）
        if let pageLayout = presetData?.pageLayout {
            documentAttributes[.topMargin] = pageLayout.topMarginPoints
            documentAttributes[.bottomMargin] = pageLayout.bottomMarginPoints
            documentAttributes[.leftMargin] = pageLayout.leftMarginPoints
            documentAttributes[.rightMargin] = pageLayout.rightMarginPoints
        }

        // 用紙サイズ
        if let printInfoData = presetData?.printInfo {
            documentAttributes[.paperSize] = NSSize(width: printInfoData.paperWidth, height: printInfoData.paperHeight)
        }

        // 表示モード（0=continuous, 1=page）
        if let viewData = presetData?.view {
            documentAttributes[.viewMode] = viewData.pageMode ? 1 : 0
            documentAttributes[.viewSize] = NSSize(width: viewData.windowWidth, height: viewData.windowHeight)
            documentAttributes[.viewZoom] = viewData.scale * 100  // 1.0 → 100
        }

        // 背景色（システムデフォルト以外の場合のみ）
        if let bgColor = presetData?.fontAndColors.colors.background {
            if !bgColor.isDynamic || bgColor.systemColorName != "textBackgroundColor" {
                documentAttributes[.backgroundColor] = bgColor.nsColor
            }
        }

        // タブ幅
        if let tabWidth = presetData?.format.tabWidthPoints, tabWidth > 0 {
            documentAttributes[.defaultTabInterval] = tabWidth
        }

        // 縦書き/横書き（.textLayoutSections）
        if let editingDirection = presetData?.format.editingDirection {
            let orientation = (editingDirection == .rightToLeft) ? 1 : 0
            let section: [String: Any] = [
                "NSTextLayoutSectionOrientation": orientation,
                "NSTextLayoutSectionRange": NSValue(range: NSRange(location: 0, length: textStorage.length))
            ]
            documentAttributes[.textLayoutSections] = [section]
        }

        // 編集ロック状態（.readOnly）
        if let preventEditing = presetData?.view.preventEditing, preventEditing {
            documentAttributes[.readOnly] = 1
        }
    }

    /// presetData から printInfo を復元
    func applyPrintInfoFromPresetData() {
        guard let printInfoData = presetData?.printInfo else { return }
        printInfoData.apply(to: self.printInfo)
    }

    /// プレーンテキストの場合、全文にBasic Fontを適用
    func applyBasicFontIfPlainText() {
        guard documentType == .plain else { return }
        guard let presetData = self.presetData else { return }

        let fontData = presetData.fontAndColors
        if let basicFont = NSFont(name: fontData.baseFontName, size: fontData.baseFontSize) {
            let range = NSRange(location: 0, length: textStorage.length)
            textStorage.addAttribute(.font, value: basicFont, range: range)
        }
    }

    /// 現在のドキュメントタイプに応じたデフォルトのNewDocDataを作成
    /// まず書類タイプテーブルからUTI/正規表現でマッチングを試み、
    /// マッチしなければドキュメントタイプに応じたデフォルト値を使用
    func createDefaultPresetDataForCurrentDocumentType(url: URL? = nil, typeName: String? = nil) -> NewDocData {
        // 書類タイプテーブルからマッチするプリセットを検索（最後から順にテスト）
        if let url = url, let typeName = typeName,
           let matchedPreset = DocumentPresetManager.shared.findMatchingPreset(url: url, typeName: typeName) {
            return matchedPreset.data
        }

        // マッチしなかった場合: ドキュメントタイプに応じたデフォルト値
        switch documentType {
        case .plain:
            return NewDocData.plainText
        case .rtf, .rtfd:
            return NewDocData.richText
        default:
            return NewDocData.richText
        }
    }

    // MARK: - RTF Data Detection

    /// データの先頭が RTF シグネチャ "{\rtf" で始まるかチェックする
    /// autosave 復元時に .txt 拡張子のファイルが実際には RTF データかどうかを判定するために使用
    nonisolated static func dataIsRTF(_ data: Data) -> Bool {
        let rtfSignature: [UInt8] = [0x7B, 0x5C, 0x72, 0x74, 0x66]  // "{\rtf"
        guard data.count >= rtfSignature.count else { return false }
        return data.prefix(rtfSignature.count).elementsEqual(rtfSignature)
    }
}
