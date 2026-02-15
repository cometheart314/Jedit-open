//
//  Document.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/25.
//

import Cocoa
import UniformTypeIdentifiers

// MARK: - LineEnding

/// 改行コードの種類
enum LineEnding: Int, CaseIterable {
    case lf = 0      // Unix (LF: \n)
    case cr = 1      // Classic Mac (CR: \r)
    case crlf = 2    // Windows (CRLF: \r\n)

    var description: String {
        switch self {
        case .lf: return "LF (Unix)"
        case .cr: return "CR (Classic Mac)"
        case .crlf: return "CRLF (Windows)"
        }
    }

    var shortDescription: String {
        switch self {
        case .lf: return "LF"
        case .cr: return "CR"
        case .crlf: return "CRLF"
        }
    }

    /// 改行文字列
    var string: String {
        switch self {
        case .lf: return "\n"
        case .cr: return "\r"
        case .crlf: return "\r\n"
        }
    }

    /// 文字列から改行コードを検出（任意のスレッドから呼び出し可能）
    static nonisolated func detect(in string: String) -> LineEnding {
        var lfCount = 0
        var crCount = 0
        var crlfCount = 0

        let chars = Array(string)
        var i = 0
        while i < chars.count {
            if chars[i] == "\r" {
                if i + 1 < chars.count && chars[i + 1] == "\n" {
                    crlfCount += 1
                    i += 2
                    continue
                } else {
                    crCount += 1
                }
            } else if chars[i] == "\n" {
                lfCount += 1
            }
            i += 1
        }

        // 最も多い改行コードを返す（デフォルトはLF）
        if crlfCount >= lfCount && crlfCount >= crCount && crlfCount > 0 {
            return .crlf
        } else if crCount >= lfCount && crCount > 0 {
            return .cr
        } else {
            return .lf
        }
    }
}

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
    static let printInfoDidChangeNotification = Notification.Name("PrintInfoDidChange")
    static let statisticsDidChangeNotification = Notification.Name("DocumentStatisticsDidChange")

    // MARK: - Extended Attribute Keys

    /// プリセットデータを保存する拡張属性キー
    static let presetDataExtendedAttributeKey = "jp.co.artman21.jedit.presetData"

    // MARK: - Properties

    var textStorage: JOTextStorage = JOTextStorage()

    // MARK: - AppleScript Support

    /// AppleScript 用の textStorage アクセサ（SDEF の cocoa key="scriptingTextStorage" に対応）
    /// getter: textStorage を返す
    @objc var scriptingTextStorage: NSTextStorage {
        return textStorage
    }

    /// 現在のテキストビューを取得するヘルパー
    private var currentTextView: NSTextView? {
        return windowControllers.first.flatMap { ($0 as? EditorWindowController)?.currentTextView() }
    }

    /// AppleScript 用の選択テキスト（rich text）アクセサ
    /// getter: 選択範囲のテキストを NSTextStorage として返す
    /// setter: 選択範囲のテキストを置き換える
    @objc var scriptingSelection: NSTextStorage {
        get {
            guard let textView = currentTextView else { return NSTextStorage() }
            let range = textView.selectedRange()
            if range.length == 0 { return NSTextStorage() }
            let sub = textStorage.attributedSubstring(from: range)
            return NSTextStorage(attributedString: sub)
        }
        set {
            guard let textView = currentTextView else { return }
            let range = textView.selectedRange()
            textStorage.beginEditing()
            textStorage.replaceCharacters(in: range, with: newValue)
            textStorage.endEditing()
            // 置き換え後、カーソルを置き換えテキストの末尾に移動
            textView.setSelectedRange(NSRange(location: range.location + newValue.length, length: 0))
        }
    }

    /// AppleScript 用の選択範囲（{location, length}）アクセサ
    @objc var scriptingSelectionRange: [String: Int] {
        get {
            guard let textView = currentTextView else { return ["location": 0, "length": 0] }
            let range = textView.selectedRange()
            return ["location": range.location, "length": range.length]
        }
        set {
            guard let textView = currentTextView else { return }
            let loc = newValue["location"] ?? 0
            let len = newValue["length"] ?? 0
            let maxLen = textStorage.length
            let safeLoc = min(loc, maxLen)
            let safeLen = min(len, maxLen - safeLoc)
            textView.setSelectedRange(NSRange(location: safeLoc, length: safeLen))
            textView.scrollRangeToVisible(NSRange(location: safeLoc, length: safeLen))
        }
    }

    /// KVC 経由で AppleScript からテキストがセットされた際に、
    /// NSString / NSAttributedString を適切に textStorage の内容として反映する
    override func setValue(_ value: Any?, forKey key: String) {
        if key == "scriptingTextStorage" {
            let fullRange = NSRange(location: 0, length: textStorage.length)
            textStorage.beginEditing()
            if let attrStr = value as? NSAttributedString {
                textStorage.replaceCharacters(in: fullRange, with: attrStr)
            } else if let str = value as? String {
                textStorage.replaceCharacters(in: fullRange, with: str)
            } else if let nsStr = value as? NSString {
                textStorage.replaceCharacters(in: fullRange, with: nsStr as String)
            }
            textStorage.endEditing()
            return
        }
        if key == "scriptingSelection" {
            guard let textView = currentTextView else { return }
            let range = textView.selectedRange()
            textStorage.beginEditing()
            if let attrStr = value as? NSAttributedString {
                textStorage.replaceCharacters(in: range, with: attrStr)
                textStorage.endEditing()
                textView.setSelectedRange(NSRange(location: range.location + attrStr.length, length: 0))
            } else if let str = value as? String {
                textStorage.replaceCharacters(in: range, with: str)
                textStorage.endEditing()
                textView.setSelectedRange(NSRange(location: range.location + str.count, length: 0))
            } else {
                textStorage.endEditing()
            }
            return
        }
        super.setValue(value, forKey: key)
    }

    var documentType: NSAttributedString.DocumentType = .plain
    var containerInset = NSSize(width: 10, height: 10)

    /// ドキュメントのエンコーディング（プレーンテキスト用）
    var documentEncoding: String.Encoding = .utf8

    /// ドキュメントの改行コード（プレーンテキスト用）
    var lineEnding: LineEnding = .lf

    /// BOM（Byte Order Mark）の有無（プレーンテキスト用）
    var hasBOM: Bool = false

    /// Word/ODTからインポートした書類かどうか（編集ロック解除時の警告表示に使用）
    var isImportedDocument: Bool = false

    /// Markdownファイルから読み込んだ書類かどうか（保存時にMarkdown形式で保存するために使用）
    var isMarkdownDocument: Bool = false

    /// 元の Markdown テキスト（将来の拡張用に保持）
    var originalMarkdownText: String?

    /// プリセットから適用されたドキュメント設定データ
    var presetData: NewDocData?

    /// presetData が変更されたかどうか（保存時に拡張属性を更新するためのフラグ）
    var presetDataEdited: Bool = false

    /// 印刷パネルアクセサリコントローラ（印刷操作中の保持用）
    private var printAccessoryController: PrintPanelAccessoryController?

    // MARK: - Save Panel Format Selection

    /// Save Panel のフォーマットポップアップで選択されたフォーマットタグ
    /// nil の場合は通常の保存（現在のドキュメントタイプを使用）
    private var savePanelFormatTag: Int?

    /// Save Panel のエンコーディングポップアップ参照（プレーンテキスト保存時に使用）
    private weak var savePanelEncodingPopUp: NSPopUpButton?

    /// Save Panel の改行コードポップアップ参照（プレーンテキスト保存時に使用）
    private weak var savePanelLineEndingPopUp: NSPopUpButton?

    /// Save Panel の BOM チェックボックス参照（プレーンテキスト保存時に使用）
    private weak var savePanelBOMCheckbox: NSButton?

    /// Save Panel のフォーマットポップアップ変更時コールバック
    private var saveFormatAction: (() -> Void)?

    /// Save Panel のエンコーディングポップアップ変更時コールバック
    private var saveEncodingAction: (() -> Void)?

    /// ドキュメント統計情報（Location[Size] タブ表示用）
    var statistics = DocumentStatistics()

    /// フォントフォールバック復帰用のDelegate
    private var fontFallbackRecoveryDelegate: FontFallbackRecoveryDelegate?

    /// RTF/RTFDファイルから読み込んだ document attributes のプロパティ
    /// 拡張属性読み込み後に適用するために一時保存
    private var loadedDocumentAttributeProperties: NewDocData.PropertiesData?

    /// RTF/RTFDファイルから読み込んだ document attributes のビュー・ページ設定
    /// 拡張属性読み込み後に適用するために一時保存（Document Attributesを優先するため）
    private var loadedDocumentAttributeViewSettings: [NSAttributedString.DocumentAttributeKey: Any]?

    /// 新規ドキュメントの表示名（fileURLがない場合に使用）
    private var untitledDocumentName: String?

    /// 新規ドキュメントのシリアル番号管理（日付別）
    private static var dailySerialNumbers: [String: Int] = [:]
    /// 新規ドキュメントの通し番号（Untitled用）
    private static var untitledCounter: Int = 0

    // MARK: - Initialization

    override init() {
        super.init()
        setupFontFallbackRecoveryDelegate()

        // Preferencesで選択されているプリセットを適用（新規書類作成時）
        // ドキュメント名はdisplayName getterで遅延生成される
        if let selectedPreset = DocumentPresetManager.shared.selectedPreset() {
            applyPresetData(selectedPreset.data)
        }

        // NSDocumentのfileTypeをdocumentTypeに応じて設定
        // これにより保存時に正しいファイルタイプが使用される
        updateFileTypeFromDocumentType()
    }

    /// Save Panel のフォーマットタグに基づいてドキュメントタイプを更新
    private func applyFormatTagForSave(_ formatTag: Int) {
        switch formatTag {
        case 0: // Plain Text
            documentType = .plain
            isMarkdownDocument = false
            // Save Panel のエンコーディング設定を適用
            if let encodingCell = savePanelEncodingPopUp?.cell as? NSPopUpButtonCell,
               let selectedItem = encodingCell.selectedItem,
               let enc = selectedItem.representedObject as? NSNumber {
                let rawValue = enc.uintValue
                if rawValue != NoStringEncoding {
                    documentEncoding = String.Encoding(rawValue: UInt(rawValue))
                }
            }
            // 改行コード
            if let lineEndingTag = savePanelLineEndingPopUp?.selectedTag() {
                lineEnding = LineEnding(rawValue: lineEndingTag) ?? .lf
            }
            // BOM
            hasBOM = savePanelBOMCheckbox?.state == .on
        case 1: // RTF
            documentType = .rtf
            isMarkdownDocument = false
        case 2: // RTFD
            documentType = .rtfd
            isMarkdownDocument = false
        case 3, 4, 5, 6: // Word/ODT — 内部的には RTF として管理
            documentType = .rtf
            isMarkdownDocument = false
        case 7: // Markdown
            documentType = .rtf
            isMarkdownDocument = true
        default:
            break
        }
        updateFileTypeFromDocumentType()
    }

    /// documentTypeに応じてNSDocumentのfileTypeを更新
    func updateFileTypeFromDocumentType() {
        switch documentType {
        case .rtf:
            fileType = "public.rtf"
        case .rtfd:
            fileType = "com.apple.rtfd"
        case .plain:
            fileType = "public.plain-text"
        default:
            fileType = "public.rtf"
        }
    }

    /// フォントフォールバック復帰Delegateをセットアップ
    private func setupFontFallbackRecoveryDelegate() {
        fontFallbackRecoveryDelegate = FontFallbackRecoveryDelegate(document: self)
        textStorage.delegate = fontFallbackRecoveryDelegate
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

        // ウィンドウ復元のために復元状態を保存対象としてマーク
        invalidateRestorableState()
        windowController.window?.invalidateRestorableState()
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

            MainActor.assumeIsolated {
                self.documentType = .rtfd
                self.textStorage.setAttributedString(attributedString)

                // bounds情報を適用
                if !boundsInfoList.isEmpty {
                    self.applyAttachmentBoundsMetadata(boundsInfoList)
                }

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

            guard let fileWrapper = textStorage.rtfdFileWrapper(from: range, documentAttributes: documentAttributes) else {
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

    /// プレーンテキストの保存データを生成
    private func dataForPlainText() throws -> Data {
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
    private func convertLineEndings(in string: String, to lineEnding: LineEnding) -> String {
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
    private nonisolated func normalizeLineEndingsToLF(_ string: String) -> String {
        var result = string.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")
        return result
    }

    /// Shift_JIS読み込み時の文字変換（Preferencesの設定に基づく、任意のスレッドから呼び出し可能）
    /// - Parameters:
    ///   - string: 変換対象の文字列
    ///   - encoding: ファイルのエンコーディング
    /// - Returns: 変換後の文字列
    private nonisolated func applyEncodingConversions(_ string: String, encoding: String.Encoding) -> String {
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

    /// BOMを追加
    private func addBOM(to data: Data, encoding: String.Encoding) -> Data {
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
    private func showEncodingFailureAlert(encoding: String.Encoding) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Encoding Conversion Failed", comment: "")
        alert.informativeText = String(format: NSLocalizedString("The text could not be converted to %@. The file will be saved as UTF-8 instead.", comment: ""), String.localizedName(of: encoding))
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))

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
                        NSLocalizedDescriptionKey: NSLocalizedString("Could not decode text file. No valid encoding found.", comment: "")
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
                        NSLocalizedDescriptionKey: NSLocalizedString("Could not decode text file. No valid encoding found.", comment: "")
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
                    NSLocalizedDescriptionKey: NSLocalizedString("Could not decode text file.", comment: "")
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

                    // Document attributes から properties を取得して反映
                    if let attrs = documentAttributes as? [NSAttributedString.DocumentAttributeKey: Any] {
                        self.applyDocumentAttributesToProperties(attrs)
                    }

    
                    NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
                }
            } catch {
                throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                    NSLocalizedDescriptionKey: "Could not read \(docType == .rtf ? "RTF" : "RTFD") document: \(error.localizedDescription)"
                ])
            }
        }
    }

    /// Document attributes から properties を取得して presetData に反映
    /// ファイルにプロパティがある場合のみ上書き、ない場合はSettingsの値を維持
    private func applyDocumentAttributesToProperties(_ attrs: [NSAttributedString.DocumentAttributeKey: Any]) {
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

    // MARK: - Encoding Selection

    /// エンコーディング選択ダイアログをモーダルで表示（ドキュメントを開く前に使用）
    /// - Parameter candidates: エンコーディング候補リスト
    /// - Returns: ユーザーが選択したエンコーディング、キャンセル時は最初の候補
    private func showEncodingSelectionDialogModal(candidates: [EncodingDetectionResult]) -> String.Encoding? {
        guard !candidates.isEmpty else { return nil }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Text Encoding", comment: "")
        alert.informativeText = NSLocalizedString("The text encoding could not be determined with high confidence. Please select the correct encoding:", comment: "")
        alert.alertStyle = .warning

        // ポップアップボタンを作成
        let popupButton = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 25), pullsDown: false)
        for candidate in candidates {
            let title = "\(candidate.name) (\(candidate.confidence)%)"
            popupButton.addItem(withTitle: title)
            popupButton.lastItem?.representedObject = candidate.encoding
        }
        alert.accessoryView = popupButton

        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

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

            // プレーンテキストの場合のみ、エンコーディング・改行コード・BOMを設定
            // エンコーディングを設定
            self.documentEncoding = String.Encoding(rawValue: data.format.textEncoding)

            // 改行コードを設定（NewDocData.FormatData.LineEndingType → LineEnding）
            switch data.format.lineEndingType {
            case .lf:
                self.lineEnding = .lf
            case .cr:
                self.lineEnding = .cr
            case .crlf:
                self.lineEnding = .crlf
            }

            // BOMを設定
            self.hasBOM = data.format.bom
        }

        // printInfo を適用（用紙サイズ、向き、マージンなど）
        if let printInfoData = data.printInfo {
            printInfoData.apply(to: self.printInfo)
        }

        // 新規ドキュメント（fileURLがnil）の場合、ドキュメント名をリセット
        // （displayName getterで遅延生成される）
        if fileURL == nil {
            untitledDocumentName = nil
        }

        // TextStorageに行折り返しタイプを設定
        textStorage.setLineBreakingType(data.format.wordWrappingType.rawValue)
    }

    // MARK: - Duplicate

    /// 複製されたドキュメントの isMarkdownDocument をリセットする
    /// （Duplicate で作られた書類は通常の RTF として扱う）
    override func duplicate() throws -> NSDocument {
        let newDoc = try super.duplicate()
        if let newDocument = newDoc as? Document {
            newDocument.isMarkdownDocument = false
        }
        return newDoc
    }

    // MARK: - Extended Attributes for Preset Data

    /// 保存完了後にプリセットデータを拡張属性に書き込む
    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, completionHandler: @escaping (Error?) -> Void) {
        // 保存前にプリセットデータを現在のウィンドウ状態で更新
        updatePresetDataFromCurrentState()

        // Save Panel のフォーマット選択に基づいてドキュメントタイプを一時的に変更（Save As のみ）
        // 保存完了後は元のタイプに復元する（書類タイプは変更しない）
        let originalDocumentType = self.documentType
        let originalIsMarkdownDocument = self.isMarkdownDocument
        let originalEncoding = self.documentEncoding
        let originalLineEnding = self.lineEnding
        let originalHasBOM = self.hasBOM
        let originalFileType = self.fileType
        var formatChanged = false

        if let formatTag = savePanelFormatTag, saveOperation == .saveAsOperation {
            formatChanged = true
            applyFormatTagForSave(formatTag)
        }

        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            guard let self = self else {
                completionHandler(error)
                return
            }

            if error == nil {
                // 保存成功後にプリセットデータを拡張属性に書き込む
                self.writePresetDataToExtendedAttribute(at: url)
                // Open Recent に登録
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
            }

            // フォーマット変更は一時的なもの。成功・失敗に関わらず常に元のタイプに復元する
            if formatChanged {
                self.documentType = originalDocumentType
                self.isMarkdownDocument = originalIsMarkdownDocument
                self.documentEncoding = originalEncoding
                self.lineEnding = originalLineEnding
                self.hasBOM = originalHasBOM
                self.fileType = originalFileType
            }

            // Save Panel の参照をクリーンアップ
            self.savePanelFormatTag = nil
            self.savePanelEncodingPopUp = nil
            self.savePanelLineEndingPopUp = nil
            self.savePanelBOMCheckbox = nil
            self.saveFormatAction = nil
            self.saveEncodingAction = nil

            completionHandler(error)
        }
    }

    /// Markdown ドキュメントの場合は Markdown 形式でファイルに書き込む
    /// NSDocument の保存チェーンの中で最終的にファイルに書き込むメソッド。
    /// ここで RTF の代わりに Markdown を書き込むことで、
    /// NSDocument の内部状態（textStorage等）を壊さずにファイルだけ Markdown にできる。
    override nonisolated func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, originalContentsURL absoluteOriginalContentsURL: URL?) throws {
        let isMarkdown = MainActor.assumeIsolated { self.isMarkdownDocument }
        if isMarkdown,
           saveOperation == .saveOperation
            || saveOperation == .saveAsOperation
            || saveOperation == .autosaveInPlaceOperation
            || saveOperation == .autosaveElsewhereOperation {
            // 元の Markdown テキストがあればそのまま使う（編集許可時にクリアされる）
            // なければ NSAttributedString → Markdown 逆変換
            let markdown = MainActor.assumeIsolated {
                self.originalMarkdownText ?? MarkdownParser.markdownString(from: self.textStorage)
            }
            guard let markdownData = markdown.data(using: .utf8) else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteInapplicableStringEncodingError, userInfo: [
                    NSLocalizedDescriptionKey: "Could not encode Markdown text as UTF-8."
                ])
            }
            try markdownData.write(to: url, options: .atomic)
            return
        }

        // Save Panel で Word/ODT フォーマット（tag 3-6）が選択された場合、
        // generateExportData() を使用してファイルに書き込む
        let formatTag = MainActor.assumeIsolated { self.savePanelFormatTag }
        if let tag = formatTag,
           (saveOperation == .saveAsOperation || saveOperation == .saveOperation),
           [3, 4, 5, 6].contains(tag) {
            let data = try MainActor.assumeIsolated {
                try self.generateExportData(
                    formatTag: tag,
                    selectionOnly: false,
                    encodingPopUp: nil,
                    lineEndingPopUp: nil,
                    bomCheckbox: nil
                )
            }
            try data.write(to: url, options: .atomic)
            return
        }

        try super.write(to: url, ofType: typeName, for: saveOperation, originalContentsURL: absoluteOriginalContentsURL)
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

        // ツールバー displayMode を保存
        if let toolbar = window.toolbar {
            presetData?.view.toolbarDisplayMode = Int(toolbar.displayMode.rawValue)
        }

        // printInfo を presetData に保存
        presetData?.printInfo = NewDocData.PrintInfoData(from: self.printInfo)
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
        // テキストクリッピングファイルの場合は専用の処理
        if typeName == "com.apple.finder.textclipping" {
            try readTextClipping(from: url)
            return
        }

        // Word / OpenDocument ファイルの場合は新規リッチテキスト書類として読み込む
        let wordODTTypes = [
            "com.microsoft.word.doc",
            "org.openxmlformats.wordprocessingml.document",
            "com.microsoft.word.wordml",
            "org.oasis-open.opendocument.text"
        ]
        if wordODTTypes.contains(typeName) {
            try readWordOrODTDocument(from: url, ofType: typeName)
            return
        }

        // .xml ファイルが Word 2003 XML (WordML) かどうかを内容で判定
        if typeName == "public.xml" || url.pathExtension.lowercased() == "xml" {
            if Self.isWordMLFile(url: url) {
                try readWordOrODTDocument(from: url, ofType: "com.microsoft.word.wordml")
                return
            }
        }

        // Markdown ファイルの場合
        if Self.isMarkdownType(typeName) || Self.isMarkdownFile(url: url) {
            if !UserDefaults.standard.bool(forKey: "openMarkdownAsPlainText") {
                try readMarkdownDocument(from: url)
                return
            }
            // プレーンテキストとして読み込む場合は通常のフローへ
        }

        // まず通常のファイル読み込みを行う
        try super.read(from: url, ofType: typeName)

        // Open Recent に登録（nonisolatedコンテキストのため明示的に呼び出す）
        MainActor.assumeIsolated {
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        }

        // 拡張属性からプリセットデータのJSONを読み込む
        if let jsonData = Document.readPresetDataRaw(at: url) {
            MainActor.assumeIsolated {
                // MainActorでデコードして適用
                if let loadedPresetData = Document.decodePresetData(from: jsonData) {
                    self.presetData = loadedPresetData
                    // Note: プリセットデータのdocumentType設定は読み込んだファイルのタイプを優先する
                    // （ファイル自体のフォーマットが正）

                    // printInfo を復元
                    self.applyPrintInfoFromPresetData()
                }
                // プレーンテキストの場合はBasic Fontを適用
                self.applyBasicFontIfPlainText()

                // RTF/RTFDファイルから読み込んだ document attributes の properties を適用
                // （拡張属性よりも RTF document attributes の properties を優先）
                self.applyLoadedDocumentAttributeProperties()
                // ビュー・ページ設定も Document Attributes から適用（presetData より優先）
                self.applyLoadedDocumentAttributeViewSettings()
            }
        } else {
            // 拡張属性がない場合は、ファイルタイプに応じたデフォルトのNewDocDataを設定
            MainActor.assumeIsolated {
                self.presetData = self.createDefaultPresetDataForCurrentDocumentType()
                // プレーンテキストの場合はBasic Fontを適用
                self.applyBasicFontIfPlainText()

                // RTF/RTFDファイルから読み込んだ document attributes の properties を適用
                self.applyLoadedDocumentAttributeProperties()
                // ビュー・ページ設定も Document Attributes から適用（presetData より優先）
                self.applyLoadedDocumentAttributeViewSettings()
            }
        }
    }

    // MARK: - Word / OpenDocument Support

    /// XML ファイルが Word 2003 XML (WordML) 形式かどうかをファイル先頭の内容で判定
    private static func isWordMLFile(url: URL) -> Bool {
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
    private nonisolated func readWordOrODTDocument(from url: URL, ofType typeName: String) throws {
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
                NSLocalizedDescriptionKey: String(format: NSLocalizedString("Could not read %@ document.", comment: "Error message when Word/ODT file cannot be read"), formatName)
            ])
        }

        // リッチテキストとして読み込み、readOnly（編集ロック）で開く
        MainActor.assumeIsolated {
            self.documentType = .rtf
            self.textStorage.setAttributedString(result)
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
    private nonisolated static func isMarkdownType(_ typeName: String) -> Bool {
        return typeName == "net.daringfireball.markdown"
    }

    /// ファイル拡張子が Markdown かどうかを判定
    private nonisolated static func isMarkdownFile(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn"].contains(ext)
    }

    /// Markdown (.md) ファイルを読み込む
    /// リッチテキストに変換し、readOnly（編集ロック）で開く
    private nonisolated func readMarkdownDocument(from url: URL) throws {
        let data = try Data(contentsOf: url)

        // UTF-8 でデコード（Markdown ファイルは通常 UTF-8）
        guard let markdownText = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .ascii) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString(
                    "Could not read Markdown document.",
                    comment: "Error when Markdown file cannot be decoded"
                )
            ])
        }

        let baseURL = url.deletingLastPathComponent()

        // リッチテキストとして読み込み、readOnly（編集ロック）で開く
        MainActor.assumeIsolated {
            // Markdown をパースしてリッチテキストに変換
            let attributedString = MarkdownParser.attributedString(from: markdownText, baseURL: baseURL)
            self.documentType = .rtf
            self.textStorage.setAttributedString(attributedString)
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
    private nonisolated func readTextClipping(from url: URL) throws {
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
    private nonisolated func readTextClippingPackage(from url: URL) throws {
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
    private nonisolated func getExtendedAttribute(named name: String, at url: URL) throws -> Data? {
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
    private nonisolated func parseTextClippingData(_ data: Data) throws {
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
    private func applyLoadedDocumentAttributeProperties() {
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
    private func applyLoadedDocumentAttributeViewSettings() {
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
    private func setViewAndPageLayoutDocumentAttributes(_ documentAttributes: inout [NSAttributedString.DocumentAttributeKey: Any]) {
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
    private func applyPrintInfoFromPresetData() {
        guard let printInfoData = presetData?.printInfo else { return }
        printInfoData.apply(to: self.printInfo)
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

    // MARK: - Properties Panel

    /// プロパティパネル（ドキュメントごとに1つ）
    private var propertyPanel: PropertyPanel?

    /// プロパティパネルを表示
    @IBAction func showProperties(_ sender: Any?) {
        if propertyPanel == nil {
            propertyPanel = PropertyPanel.loadFromNib()
        }
        propertyPanel?.showPanel(for: self)
    }

    // MARK: - Menu Validation

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(showProperties(_:)) {
            // 書類ウィンドウがある場合のみ有効
            return windowControllers.first?.window != nil
        }
        return super.validateUserInterfaceItem(item)
    }

    // MARK: - Page Setup

    override func runPageLayout(_ sender: Any?) {
        #if DEBUG
        Swift.print("=== runPageLayout called ===")
        Swift.print("Before: paperSize=\(self.printInfo.paperSize), orientation=\(self.printInfo.orientation.rawValue)")
        #endif

        // NSPageLayout を作成してモーダルで表示
        let pageLayout = NSPageLayout()

        // ウィンドウがあればシートとして表示、なければモーダルダイアログ
        if let window = self.windowControllers.first?.window {
            pageLayout.beginSheet(with: self.printInfo, modalFor: window, delegate: self, didEnd: #selector(pageLayoutDidEnd(_:returnCode:contextInfo:)), contextInfo: nil)
        } else {
            let result = pageLayout.runModal(with: self.printInfo)
            pageLayoutDidEnd(pageLayout, returnCode: result, contextInfo: nil)
        }
    }

    @objc private func pageLayoutDidEnd(_ pageLayout: NSPageLayout, returnCode: Int, contextInfo: UnsafeMutableRawPointer?) {
        #if DEBUG
        Swift.print("=== pageLayoutDidEnd called ===")
        Swift.print("returnCode: \(returnCode) (OK=1, Cancel=0)")
        Swift.print("After: paperSize=\(self.printInfo.paperSize), orientation=\(self.printInfo.orientation.rawValue)")
        Swift.print("topMargin=\(self.printInfo.topMargin), bottomMargin=\(self.printInfo.bottomMargin)")
        Swift.print("leftMargin=\(self.printInfo.leftMargin), rightMargin=\(self.printInfo.rightMargin)")
        #endif

        // OKボタンが押された場合のみ通知
        if returnCode == NSApplication.ModalResponse.OK.rawValue {
            NotificationCenter.default.post(name: Document.printInfoDidChangeNotification, object: self)
        }
    }

    // MARK: - Printing

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        // EditorWindowControllerから印刷設定を取得
        guard let windowController = windowControllers.first as? EditorWindowController,
              let config = windowController.printPageViewConfiguration() else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("Cannot print: No text view available", comment: "Print error")
            ])
        }

        // 印刷情報を取得
        let printInfo = self.printInfo.copy() as! NSPrintInfo

        // 印刷設定を適用
        for (key, value) in printSettings {
            printInfo.dictionary()[key] = value
        }

        // 印刷パネルアクセサリコントローラを作成
        let accessoryController = PrintPanelAccessoryController(
            nibName: "PrintPanelAccessoryView",
            bundle: nil
        )
        // 保存された印刷オプションから初期値を設定
        accessoryController.configureDefaults(
            from: presetData?.printOptions,
            hasHeader: config.headerAttributedString != nil,
            hasFooter: config.footerAttributedString != nil,
            hasInvisibles: config.invisibleCharacterOptions != .none
        )
        // ビューのロードを強制（プロパティアクセスのため）
        _ = accessoryController.view

        // PrintPageViewを作成（ヘッダー・フッター付きのカスタム印刷ビュー）
        // printInfoの更新を反映するため、configのprintInfoを上書き
        let updatedConfig = PrintPageView.Configuration(
            textStorage: config.textStorage,
            printInfo: printInfo,
            isVerticalLayout: config.isVerticalLayout,
            headerAttributedString: config.headerAttributedString,
            footerAttributedString: config.footerAttributedString,
            headerColor: config.headerColor,
            footerColor: config.footerColor,
            documentName: config.documentName,
            filePath: config.filePath,
            dateModified: config.dateModified,
            documentProperties: config.documentProperties,
            textBackgroundColor: config.textBackgroundColor,
            isPlainText: config.isPlainText,
            defaultFont: config.defaultFont,
            defaultTextColor: config.defaultTextColor,
            invisibleCharacterOptions: config.invisibleCharacterOptions,
            invisibleCharacterColor: config.invisibleCharacterColor,
            lineBreakingType: config.lineBreakingType,
            lineNumberMode: config.lineNumberMode,
            lineNumberColor: config.lineNumberColor
        )
        let printView = PrintPageView(configuration: updatedConfig)

        // アクセサリコントローラとPrintPageViewを相互接続
        printView.accessoryController = accessoryController
        accessoryController.printPageView = printView

        // 初期状態で不可視文字の表示を同期
        printView.updateInvisibleCharacterDisplay()

        // カスタムビューの印刷操作を作成
        let printOperation = NSPrintOperation(view: printView, printInfo: printInfo)
        printOperation.showsPrintPanel = true
        printOperation.showsProgressPanel = true

        // アクセサリコントローラを印刷パネルに追加
        printOperation.printPanel.addAccessoryController(accessoryController)

        // 印刷操作中にアクセサリコントローラを保持
        self.printAccessoryController = accessoryController

        return printOperation
    }

    /// 印刷ダイアログ表示と完了処理をオーバーライド
    /// 印刷操作完了後にアクセサリコントローラの設定をpresetDataに保存する
    @IBAction override func printDocument(_ sender: Any?) {
        self.print(withSettings: [:], showPrintPanel: true, delegate: self,
                   didPrint: #selector(documentDidPrint(_:success:contextInfo:)),
                   contextInfo: nil)
    }

    @objc private func documentDidPrint(_ document: NSDocument, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        // アクセサリコントローラの設定をpresetDataに保存（印刷/キャンセルに関わらず）
        if let ctrl = printAccessoryController {
            presetData?.printOptions = ctrl.toPrintOptionsData()
        }
        // アクセサリコントローラの参照を解放
        printAccessoryController = nil
    }

    // MARK: - Display Name

    override var displayName: String! {
        get {
            // ファイルがある場合は通常の表示名
            if fileURL != nil {
                return super.displayName
            }
            // 新規ドキュメントの場合はカスタム名を使用（遅延生成）
            if untitledDocumentName == nil {
                generateUntitledDocumentName()
            }
            return untitledDocumentName ?? super.displayName
        }
        set {
            super.displayName = newValue
        }
    }

    /// 新規ドキュメント名を生成（presetDataの設定に基づく）
    private func generateUntitledDocumentName() {
        guard let presetData = self.presetData else {
            // presetDataがない場合はデフォルト（Untitled）
            Document.untitledCounter += 1
            if Document.untitledCounter > 1 {
                untitledDocumentName = "Untitled \(Document.untitledCounter)"
            } else {
                untitledDocumentName = "Untitled"
            }
            return
        }

        let nameType = presetData.format.newDocNameType

        switch nameType {
        case .untitled:
            // Untitled #
            Document.untitledCounter += 1
            if Document.untitledCounter > 1 {
                untitledDocumentName = "Untitled \(Document.untitledCounter)"
            } else {
                untitledDocumentName = "Untitled"
            }

        case .dateTime:
            // YYYY-MM-DD HHmmss
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HHmmss"
            untitledDocumentName = formatter.string(from: Date())

        case .dateWithSerial:
            // YYYY-MM-DD-###
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: Date())

            // その日のシリアル番号を取得・更新
            let serial = (Document.dailySerialNumbers[dateString] ?? 0) + 1
            Document.dailySerialNumbers[dateString] = serial
            untitledDocumentName = "\(dateString)-\(String(format: "%03d", serial))"

        case .systemShortDate:
            // System Short Date #
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            let dateString = formatter.string(from: Date())

            // シリアル番号を追加
            Document.untitledCounter += 1
            if Document.untitledCounter > 1 {
                untitledDocumentName = "\(dateString) \(Document.untitledCounter)"
            } else {
                untitledDocumentName = dateString
            }

        case .systemLongDate:
            // System Long Date #
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            let dateString = formatter.string(from: Date())

            // シリアル番号を追加
            Document.untitledCounter += 1
            if Document.untitledCounter > 1 {
                untitledDocumentName = "\(dateString) \(Document.untitledCounter)"
            } else {
                untitledDocumentName = dateString
            }

        case .preferencesDate:
            // Preferences General Date #
            // CalendarDateHelperを使用して日付フォーマットを取得
            let dateType = UserDefaults.standard.integer(forKey: UserDefaults.Keys.dateFormatType)
            let dateString = CalendarDateHelper.descriptionOfDateType(dateType)

            // シリアル番号を追加
            Document.untitledCounter += 1
            if Document.untitledCounter > 1 {
                untitledDocumentName = "\(dateString) \(Document.untitledCounter)"
            } else {
                untitledDocumentName = dateString
            }
        }
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

        // 新規ドキュメント（fileURLがnil）の場合、ファイル名を提案
        if fileURL == nil {
            let nameType = presetData?.format.newDocNameType ?? .untitled
            if nameType == .untitled {
                let suggestedName = generateSuggestedFileName()
                if !suggestedName.isEmpty {
                    savePanel.nameFieldStringValue = suggestedName
                }
            }
        }

        return super.prepareSavePanel(savePanel)
    }

    @objc private func saveFormatPopUpChanged(_ sender: Any?) {
        saveFormatAction?()
    }

    @objc private func saveEncodingPopUpChanged(_ sender: Any?) {
        saveEncodingAction?()
    }

    // MARK: - Export

    /// エクスポートパネルのフォーマットポップアップ変更時コールバック
    private var exportFormatAction: (() -> Void)?
    /// エクスポートパネルのエンコーディングポップアップ変更時コールバック
    private var exportEncodingAction: (() -> Void)?

    @objc private func exportFormatPopUpChanged(_ sender: Any?) {
        exportFormatAction?()
    }

    @objc private func exportEncodingPopUpChanged(_ sender: Any?) {
        exportEncodingAction?()
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
        savePanel.title = NSLocalizedString("Export", comment: "Export panel title")

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
        exportFormatAction = { [weak self, weak savePanel] in
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
        exportEncodingAction = {
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
            self?.exportFormatAction = nil
            self?.exportEncodingAction = nil

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
    private func updateExportPanelContentTypes(savePanel: NSSavePanel, formatTag: Int) {
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
    private func generateExportData(
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
    private func generateExportFileWrapper(selectionOnly: Bool) throws -> FileWrapper {
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
    private func generateExportPlainTextData(
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
    private func generateExportMarkdownData(range: NSRange) throws -> Data {
        // 対象範囲の NSAttributedString を取得
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
    private func generateSuggestedFileName() -> String {
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
