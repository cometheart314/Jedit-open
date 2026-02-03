//
//  Document.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/25.
//

import Cocoa

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

    /// 文字列から改行コードを検出
    static func detect(in string: String) -> LineEnding {
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

    // MARK: - Extended Attribute Keys

    /// プリセットデータを保存する拡張属性キー
    static let presetDataExtendedAttributeKey = "jp.co.artman21.jedit.presetData"

    // MARK: - Properties

    var textStorage: NSTextStorage = NSTextStorage()
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
    


    // MARK: - Initialization

    override init() {
        super.init()
        setupFontFallbackRecoveryDelegate()
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
            // プレーンテキストの場合
            return try dataForPlainText()
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

    /// 改行コードをLFに統一（読み込み時に使用）
    private func normalizeLineEndingsToLF(_ string: String) -> String {
        var result = string.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")
        return result
    }

    /// Shift_JIS読み込み時の文字変換（Preferencesの設定に基づく）
    /// - Parameters:
    ///   - string: 変換対象の文字列
    ///   - encoding: ファイルのエンコーディング
    /// - Returns: 変換後の文字列
    private func applyEncodingConversions(_ string: String, encoding: String.Encoding) -> String {
        let defaults = UserDefaults.standard
        var result = string

        // Shift_JISエンコーディンググループかどうかを判定
        let isShiftJIS = encoding == .shiftJIS ||
                         encoding.rawValue == CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)) ||
                         encoding.rawValue == CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.shiftJIS_X0213.rawValue))

        // Convert '¥' (0x5c) to Back Slash '\' (U+005C) when Shift_JIS encoding group
        if defaults.bool(forKey: UserDefaults.Keys.convertYenToBackSlash) && isShiftJIS {
            // Shift_JISでデコードした際に円記号(U+00A5)になっている可能性がある
            result = result.replacingOccurrences(of: "\u{00A5}", with: "\\")
        }

        // Convert '‾' (0x7e) to Tilde '~' (U+007E) when Shift_JIS encoding group
        if defaults.bool(forKey: UserDefaults.Keys.convertOverlineToTilde) && isShiftJIS {
            // Shift_JISでデコードした際にオーバーライン(U+203E)になっている可能性がある
            result = result.replacingOccurrences(of: "\u{203E}", with: "~")
        }

        // Convert FULLWIDTH TILDE '～' (U+FF5E) to WAVE DASH '〜' (U+301C)
        // これはエンコーディングに関係なく適用
        if defaults.bool(forKey: UserDefaults.Keys.convertFullWidthTilde) {
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

            // Preferencesの Opening Encoding 設定を取得
            let preferredEncodingInt = UserDefaults.standard.integer(forKey: UserDefaults.Keys.plainTextEncodingForRead)
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

            let outcome = EncodingDetector.shared.detectAndDecode(from: data, fileURL: currentFileURL)

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
}
