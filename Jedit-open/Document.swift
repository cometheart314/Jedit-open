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

    // MARK: - Extended Attribute Keys

    /// プリセットデータを保存する拡張属性キー
    static let presetDataExtendedAttributeKey = "jp.co.artman21.jedit.presetData"

    // MARK: - Properties

    var textStorage: JOTextStorage = JOTextStorage()
    var documentType: NSAttributedString.DocumentType = .plain
    var containerInset = NSSize(width: 10, height: 10)

    /// ドキュメントのエンコーディング（プレーンテキスト用）
    var documentEncoding: String.Encoding = .utf8

    /// ドキュメントの改行コード（プレーンテキスト用）
    var lineEnding: LineEnding = .lf

    /// BOM（Byte Order Mark）の有無（プレーンテキスト用）
    var hasBOM: Bool = false

    /// プリセットから適用されたドキュメント設定データ
    var presetData: NewDocData?

    /// presetData が変更されたかどうか（保存時に拡張属性を更新するためのフラグ）
    var presetDataEdited: Bool = false

    /// フォントフォールバック復帰用のDelegate
    private var fontFallbackRecoveryDelegate: FontFallbackRecoveryDelegate?

    /// RTF/RTFDファイルから読み込んだ document attributes のプロパティ
    /// 拡張属性読み込み後に適用するために一時保存
    private var loadedDocumentAttributeProperties: NewDocData.PropertiesData?

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

    /// documentTypeに応じてNSDocumentのfileTypeを更新
    private func updateFileTypeFromDocumentType() {
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

        // 1. エンコーディングを決定
        let encodingForWriteInt = defaults.integer(forKey: UserDefaults.Keys.plainTextEncodingForWrite)
        let saveEncoding: String.Encoding
        if encodingForWriteInt <= 0 {
            // Automatic: Documentのプロパティを使用
            saveEncoding = documentEncoding
        } else {
            // 指定されたエンコーディングを使用
            saveEncoding = String.Encoding(rawValue: UInt(encodingForWriteInt))
        }

        // 2. 改行コードを決定
        let lineEndingForWriteInt = defaults.integer(forKey: UserDefaults.Keys.plainTextLineEndingForWrite)
        let saveLineEnding: LineEnding
        if lineEndingForWriteInt < 0 {
            // Automatic: Documentのプロパティを使用
            saveLineEnding = lineEnding
        } else {
            // 指定された改行コードを使用
            saveLineEnding = LineEnding(rawValue: lineEndingForWriteInt) ?? .lf
        }

        // 3. BOMを付加するかどうかを決定
        let bomForWriteInt = defaults.integer(forKey: UserDefaults.Keys.plainTextBomForWrite)
        let shouldAddBOM: Bool
        if bomForWriteInt < 0 {
            // Automatic: Documentのプロパティを使用
            shouldAddBOM = hasBOM
        } else {
            // 0 = OFF, 1 = ON
            shouldAddBOM = bomForWriteInt == 1
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
            }
        } else {
            // 拡張属性がない場合は、ファイルタイプに応じたデフォルトのNewDocDataを設定
            MainActor.assumeIsolated {
                self.presetData = self.createDefaultPresetDataForCurrentDocumentType()
                // プレーンテキストの場合はBasic Fontを適用
                self.applyBasicFontIfPlainText()

                // RTF/RTFDファイルから読み込んだ document attributes の properties を適用
                self.applyLoadedDocumentAttributeProperties()
            }
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
        // EditorWindowControllerからテキストビューを取得
        guard let windowController = windowControllers.first as? EditorWindowController,
              let textView = windowController.currentTextView() else {
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

        // テキストビューの印刷操作を作成
        let printOperation = NSPrintOperation(view: textView, printInfo: printInfo)
        printOperation.showsPrintPanel = true
        printOperation.showsProgressPanel = true

        return printOperation
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
        // 新規ドキュメント（fileURLがnil）の場合
        if fileURL == nil {
            let nameType = presetData?.format.newDocNameType ?? .untitled

            // newDocNameTypeがuntitledの場合のみファイル名を提案
            if nameType == .untitled {
                let suggestedName = generateSuggestedFileName()
                if !suggestedName.isEmpty {
                    savePanel.nameFieldStringValue = suggestedName
                }
            }

            // プレーンテキストの場合、FormatData.fileExtensionを使用
            if documentType == .plain,
               let fileExtension = presetData?.format.fileExtension,
               !fileExtension.isEmpty {
                // allowedContentTypesを設定してファイル拡張子を強制
                if let utType = UTType(filenameExtension: fileExtension) {
                    savePanel.allowedContentTypes = [utType]
                }
            }
        }
        return super.prepareSavePanel(savePanel)
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
