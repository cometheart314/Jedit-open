//
//  Document.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/25.
//

import Cocoa

// MARK: - AttachmentBoundsInfo

/// 画像attachmentのbounds情報を保存するための構造体
struct AttachmentBoundsInfo: Codable {
    let location: Int
    let filename: String
    let width: CGFloat
    let height: CGFloat
}

class Document: NSDocument {

    // MARK: - Notifications

    static let documentTypeDidChangeNotification = Notification.Name("DocumentTypeDidChange")

    // MARK: - Extended Attribute Keys

    /// プリセットデータを保存する拡張属性キー
    static let presetDataExtendedAttributeKey = "jp.co.artman21.jedit.presetData"

    // MARK: - Properties

    var textStorage: NSTextStorage = NSTextStorage()
    var documentType: NSAttributedString.DocumentType = .plain
    var containerInset = NSSize(width: 10, height: 10)

    /// プリセットから適用されたドキュメント設定データ
    var presetData: NewDocData?

    /// presetData が変更されたかどうか（保存時に拡張属性を更新するためのフラグ）
    var presetDataEdited: Bool = false
    


    // MARK: - Initialization

    override init() {
        super.init()
    }

    override nonisolated class var autosavesInPlace: Bool {
        return true
    }

    // MARK: - Window Controllers

    override func makeWindowControllers() {
        // Document.xibからEditorWindowControllerを読み込む
        let windowController = EditorWindowController(windowNibName: NSNib.Name("Document"))
        self.addWindowController(windowController)
    }

    override func windowControllerDidLoadNib(_ windowController: NSWindowController) {
        super.windowControllerDidLoadNib(windowController)

        // TextStorageを設定
        // ウィンドウコントローラーのcontentViewからNSTextViewを探して、textStorageを設定する
        if let window = windowController.window,
           let contentView = window.contentView {
            if let textView = findTextView(in: contentView) {
                textView.layoutManager?.replaceTextStorage(textStorage)
            }
        }

        // プリセットデータがあればEditorWindowControllerに適用を依頼
        // （windowDidLoadの時点ではdocumentがまだ関連付けられていないため、ここで呼び出す）
        if presetData != nil, let editorWC = windowController as? EditorWindowController {
            editorWC.applyPresetData()
        }
    }

    // MARK: - Helper Methods

    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView {
            return textView
        }

        for subview in view.subviews {
            if let textView = findTextView(in: subview) {
                return textView
            }
        }

        return nil
    }

    // MARK: - Reading and Writing

    // RTFDファイルパッケージの読み込みをサポート
    override nonisolated func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
        // RTFDとして読み込むかどうかを判定
        // 1. typeNameがcom.apple.rtfdの場合
        // 2. ディレクトリパッケージでTXT.rtfを含む場合（RTFD構造）
        let isRTFD = typeName == "com.apple.rtfd" || isRTFDPackage(fileWrapper)

        if isRTFD && fileWrapper.isDirectory {
            // RTFDはFileWrapperから直接読み込む
            guard let attributedString = NSAttributedString(rtfdFileWrapper: fileWrapper, documentAttributes: nil) else {
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

            MainActor.assumeIsolated {
                self.documentType = .rtfd
                self.textStorage.setAttributedString(attributedString)

                // bounds情報を適用
                if !boundsInfoList.isEmpty {
                    self.applyAttachmentBoundsMetadata(boundsInfoList)
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
    private nonisolated func isRTFDPackage(_ fileWrapper: FileWrapper) -> Bool {
        guard fileWrapper.isDirectory,
              let fileWrappers = fileWrapper.fileWrappers else {
            return false
        }
        // RTFDパッケージは必ずTXT.rtfを含む
        return fileWrappers["TXT.rtf"] != nil
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
            guard let fileWrapper = textStorage.rtfdFileWrapper(from: range, documentAttributes: [:]) else {
                throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                    NSLocalizedDescriptionKey: "Could not create RTFD file wrapper"
                ])
            }

            // 画像のbounds情報をメタデータとして保存
            let boundsMetadata = collectAttachmentBoundsMetadata()
            if !boundsMetadata.isEmpty {
                if let metadataData = try? JSONEncoder().encode(boundsMetadata) {
                    let metadataWrapper = FileWrapper(regularFileWithContents: metadataData)
                    metadataWrapper.preferredFilename = ".attachment_bounds.json"
                    fileWrapper.addFileWrapper(metadataWrapper)
                }
            }

            return fileWrapper
        } else {
            // その他のファイルタイプは通常のdata(ofType:)を使用
            let data = try data(ofType: typeName)
            return FileWrapper(regularFileWithContents: data)
        }
    }

    // MARK: - Attachment Bounds Metadata

    /// 画像attachmentのbounds情報を収集
    private func collectAttachmentBoundsMetadata() -> [AttachmentBoundsInfo] {
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

    /// 画像attachmentにbounds情報を適用
    private func applyAttachmentBoundsMetadata(_ boundsInfoList: [AttachmentBoundsInfo]) {
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
                let attrs = textStorage.attributes(at: info.location, effectiveRange: nil)
                if let attachment = attrs[.attachment] as? NSTextAttachment {
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
            if let fileWrapper = replacement.attachment.fileWrapper,
               let data = fileWrapper.regularFileContents,
               let image = NSImage(data: data) {
                let cell = ResizableImageAttachmentCell(image: image, displaySize: replacement.bounds.size)
                newAttachment.attachmentCell = cell
            }

            let attachmentString = NSAttributedString(attachment: newAttachment)
            textStorage.replaceCharacters(in: replacement.range, with: attachmentString)
        }
        textStorage.endEditing()
    }

    override func data(ofType typeName: String) throws -> Data {
        // ドキュメントタイプを判定
        let docType: NSAttributedString.DocumentType
        switch typeName {
        case "public.rtf":
            docType = .rtf
        case "com.apple.rtfd":
            docType = .rtfd
        default:
            docType = .plain
        }

        // ドキュメントタイプを保存
        self.documentType = docType

        // ドキュメントタイプに応じて保存
        if docType == .plain {
            // プレーンテキストの場合はUTF-8でエンコード
            let string = textStorage.string
            guard let data = string.data(using: .utf8) else {
                throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                    NSLocalizedDescriptionKey: "Could not encode text as UTF-8"
                ])
            }
            return data
        } else {
            // RTFまたはRTFDの場合はNSAttributedStringを使用
            let range = NSRange(location: 0, length: textStorage.length)
            let options: [NSAttributedString.DocumentAttributeKey: Any] = [
                .documentType: docType
            ]

            do {
                let data = try textStorage.data(from: range, documentAttributes: options)
                return data
            } catch {
                throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                    NSLocalizedDescriptionKey: "Could not write \(docType == .rtf ? "RTF" : "RTFD") document: \(error.localizedDescription)"
                ])
            }
        }
    }

    override nonisolated func read(from data: Data, ofType typeName: String) throws {
        // ドキュメントタイプを判定
        let docType: NSAttributedString.DocumentType
        switch typeName {
        case "public.rtf":
            docType = .rtf
        case "com.apple.rtfd":
            docType = .rtfd
        default:
            docType = .plain
        }

        // ドキュメントタイプに応じて読み込み
        if docType == .plain {
            // プレーンテキストの場合はUTF-8でデコード
            guard let string = String(data: data, encoding: .utf8) else {
                throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                    NSLocalizedDescriptionKey: "Could not decode text as UTF-8"
                ])
            }

            // メインアクターで実行
            MainActor.assumeIsolated {
                self.documentType = .plain
                self.textStorage.replaceCharacters(in: NSRange(location: 0, length: self.textStorage.length), with: string)
                NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
            }
        } else {
            // RTFまたはRTFDの場合はNSAttributedStringを使用
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: docType
            ]

            do {
                let attributedString = try NSAttributedString(data: data, options: options, documentAttributes: nil)

                // メインアクターで実行
                MainActor.assumeIsolated {
                    self.documentType = docType
                    self.textStorage.setAttributedString(attributedString)
                    NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
                }
            } catch {
                throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                    NSLocalizedDescriptionKey: "Could not read \(docType == .rtf ? "RTF" : "RTFD") document: \(error.localizedDescription)"
                ])
            }
        }
    }

    // MARK: - Preset Data Application

    /// プリセットデータを適用する（ドキュメント作成時に一度だけ呼ばれる）
    /// Note: プリセットデータはコピーされ、以降Preferencesの変更とは同期しない
    func applyPresetData(_ data: NewDocData) {
        self.presetData = data

        // ドキュメントタイプを設定
        if data.format.richText {
            self.documentType = .rtf
        } else {
            self.documentType = .plain
        }
    }

    // MARK: - Extended Attributes for Preset Data

    /// 保存完了後にプリセットデータを拡張属性に書き込む
    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, completionHandler: @escaping (Error?) -> Void) {
        // 保存前にプリセットデータを現在のウィンドウ状態で更新
        updatePresetDataFromCurrentState()

        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            if error == nil {
                // 保存成功後にプリセットデータを拡張属性に書き込む
                self?.writePresetDataToExtendedAttribute(at: url)
            }
            completionHandler(error)
        }
    }

    /// 現在のウィンドウ状態でプリセットデータを更新
    private func updatePresetDataFromCurrentState() {
        guard presetData != nil else { return }

        // 最初のウィンドウコントローラからウィンドウ情報を取得
        guard let windowController = windowControllers.first as? EditorWindowController,
              let window = windowController.window else { return }

        // ウィンドウのフレームを取得
        let frame = window.frame

        // プリセットデータを更新
        presetData?.view.windowX = frame.origin.x
        presetData?.view.windowY = frame.origin.y
        presetData?.view.windowWidth = frame.size.width
        presetData?.view.windowHeight = frame.size.height
    }

    /// プリセットデータを拡張属性に書き込む
    private func writePresetDataToExtendedAttribute(at url: URL) {
        guard let presetData = self.presetData else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(presetData)

            // 拡張属性に書き込む
            let result = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Int32 in
                return setxattr(
                    url.path,
                    Document.presetDataExtendedAttributeKey,
                    bytes.baseAddress,
                    data.count,
                    0,
                    0
                )
            }

            if result != 0 {
                Swift.print("Failed to write preset data to extended attribute: \(errno)")
            }
        } catch {
            Swift.print("Failed to encode preset data: \(error)")
        }
    }

    /// 修正日付を保持したままプリセットデータを拡張属性に書き込む（外部から呼び出し可能）
    func savePresetDataToExtendedAttribute(at url: URL) {
        guard let presetData = self.presetData else { return }

        // 現在の修正日付を取得
        let originalModificationDate: Date?
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            originalModificationDate = attrs[.modificationDate] as? Date
        } catch {
            originalModificationDate = nil
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(presetData)

            // 拡張属性に書き込む
            let result = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Int32 in
                return setxattr(
                    url.path,
                    Document.presetDataExtendedAttributeKey,
                    bytes.baseAddress,
                    data.count,
                    0,
                    0
                )
            }

            if result != 0 {
                Swift.print("Failed to write preset data to extended attribute: \(errno)")
            } else {
                // 拡張属性の書き込み成功後、修正日付を元に戻す
                if let originalDate = originalModificationDate {
                    try? FileManager.default.setAttributes(
                        [.modificationDate: originalDate],
                        ofItemAtPath: url.path
                    )
                }
                // フラグをリセット
                presetDataEdited = false
            }
        } catch {
            Swift.print("Failed to encode preset data: \(error)")
        }
    }

    /// 拡張属性からプリセットデータのJSONデータを読み込む（nonisolated）
    private nonisolated static func readPresetDataRaw(at url: URL) -> Data? {
        let key = "jp.co.artman21.jedit.presetData"
        // 拡張属性のサイズを取得
        let size = getxattr(url.path, key, nil, 0, 0, 0)
        guard size > 0 else { return nil }

        // データを読み込む
        var data = Data(count: size)
        let result = data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) -> ssize_t in
            return getxattr(
                url.path,
                key,
                bytes.baseAddress,
                size,
                0,
                0
            )
        }

        guard result > 0 else { return nil }
        return data
    }

    /// 拡張属性からプリセットデータをデコードする（MainActor）
    private static func decodePresetData(from data: Data) -> NewDocData? {
        do {
            let decoder = JSONDecoder()
            let presetData = try decoder.decode(NewDocData.self, from: data)
            return presetData
        } catch {
            Swift.print("Failed to decode preset data from extended attribute: \(error)")
            return nil
        }
    }

    /// ファイル読み込み後にプリセットデータを拡張属性から読み込んで適用
    override nonisolated func read(from url: URL, ofType typeName: String) throws {
        // まず通常のファイル読み込みを行う
        try super.read(from: url, ofType: typeName)

        // 拡張属性からプリセットデータのJSONを読み込む
        if let jsonData = Document.readPresetDataRaw(at: url) {
            MainActor.assumeIsolated {
                // MainActorでデコードして適用
                if let loadedPresetData = Document.decodePresetData(from: jsonData) {
                    self.presetData = loadedPresetData
                    // Note: プリセットデータのdocumentType設定は読み込んだファイルのタイプを優先する
                    // （ファイル自体のフォーマットが正）
                }
                // プレーンテキストの場合はBasic Fontを適用
                self.applyBasicFontIfPlainText()
            }
        } else {
            // 拡張属性がない場合は、ファイルタイプに応じたデフォルトのNewDocDataを設定
            MainActor.assumeIsolated {
                self.presetData = self.createDefaultPresetDataForCurrentDocumentType()
                // プレーンテキストの場合はBasic Fontを適用
                self.applyBasicFontIfPlainText()
            }
        }
    }

    /// プレーンテキストの場合、全文にBasic Fontを適用
    private func applyBasicFontIfPlainText() {
        guard documentType == .plain else { return }
        guard let presetData = self.presetData else { return }

        let fontData = presetData.fontAndColors
        if let basicFont = NSFont(name: fontData.baseFontName, size: fontData.baseFontSize) {
            let range = NSRange(location: 0, length: textStorage.length)
            textStorage.addAttribute(.font, value: basicFont, range: range)
        }
    }

    /// 現在のドキュメントタイプに応じたデフォルトのNewDocDataを作成
    /// Preferencesで選択されているプリセットの設定をコピーして使用
    private func createDefaultPresetDataForCurrentDocumentType() -> NewDocData {
        // Preferencesで選択されているプリセットを取得
        if let selectedPreset = DocumentPresetManager.shared.selectedPreset() {
            return selectedPreset.data
        }

        // フォールバック: プリセットがない場合はドキュメントタイプに応じたデフォルト値
        switch documentType {
        case .plain:
            return NewDocData.plainText
        case .rtf, .rtfd:
            return NewDocData.richText
        default:
            // その他のタイプはリッチテキストとして扱う
            return NewDocData.richText
        }
    }
}
