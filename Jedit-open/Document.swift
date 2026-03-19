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

    // MARK: - Selection Proxy for AppleScript

    /// AppleScript の `set font/size/color of selection` で元の textStorage に属性変更を反映するプロキシ
    /// NSTextStorage のサブクラスとして、読み取りは選択範囲のコピーを返し、
    /// 属性の書き込みは元の textStorage の対応範囲に直接適用する
    private class SelectionProxyTextStorage: NSTextStorage {
        private let backingStorage: NSTextStorage
        private let backingRange: NSRange
        private let localStorage: NSMutableAttributedString
        private weak var textView: NSTextView?

        init(backingStorage: NSTextStorage, range: NSRange, textView: NSTextView?) {
            self.backingStorage = backingStorage
            self.backingRange = range
            self.textView = textView
            self.localStorage = NSMutableAttributedString(
                attributedString: backingStorage.attributedSubstring(from: range)
            )
            super.init()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) {
            fatalError("init(pasteboardPropertyList:ofType:) has not been implemented")
        }

        override var string: String {
            return localStorage.string
        }

        override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
            return localStorage.attributes(at: location, effectiveRange: range)
        }

        override func replaceCharacters(in range: NSRange, with str: String) {
            localStorage.replaceCharacters(in: range, with: str)
            edited(.editedCharacters, range: range, changeInLength: str.count - range.length)
        }

        override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
            localStorage.setAttributes(attrs, range: range)
            edited(.editedAttributes, range: range, changeInLength: 0)
            // 元の textStorage にも属性を適用（Undo 対応）
            applyToBackingStorage(range: range) { mappedRange in
                backingStorage.setAttributes(attrs, range: mappedRange)
            }
        }

        override func addAttributes(_ attrs: [NSAttributedString.Key: Any], range: NSRange) {
            localStorage.addAttributes(attrs, range: range)
            edited(.editedAttributes, range: range, changeInLength: 0)
            // 元の textStorage にも属性を適用（Undo 対応）
            applyToBackingStorage(range: range) { mappedRange in
                backingStorage.addAttributes(attrs, range: mappedRange)
            }
        }

        /// backingStorage への変更を Undo 対応で適用するヘルパー
        private func applyToBackingStorage(range: NSRange, apply: (NSRange) -> Void) {
            let mappedRange = NSRange(
                location: backingRange.location + range.location,
                length: range.length
            )
            guard mappedRange.location + mappedRange.length <= backingStorage.length else { return }
            // shouldChangeText で Undo マネージャに変更を登録
            if let tv = textView {
                tv.shouldChangeText(in: mappedRange, replacementString: nil)
            }
            backingStorage.beginEditing()
            apply(mappedRange)
            backingStorage.endEditing()
            if let tv = textView {
                tv.didChangeText()
            }
        }

        // MARK: - KVC for AppleScript (font, size, color)

        @objc var fontName: String {
            get {
                guard localStorage.length > 0 else { return "" }
                let font = localStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                return font?.fontName ?? ""
            }
            set {
                let range = NSRange(location: 0, length: localStorage.length)
                guard range.length > 0 else { return }
                // 各文字のフォントサイズを保持しつつフォント名だけ変更
                localStorage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                    let currentFont = value as? NSFont ?? NSFont.systemFont(ofSize: 12)
                    if let newFont = NSFont(name: newValue, size: currentFont.pointSize) {
                        localStorage.addAttribute(.font, value: newFont, range: attrRange)
                        applyToBackingStorage(range: attrRange) { mappedRange in
                            backingStorage.addAttribute(.font, value: newFont, range: mappedRange)
                        }
                    }
                }
            }
        }

        @objc var fontSize: Int {
            get {
                guard localStorage.length > 0 else { return 12 }
                let font = localStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                return Int(font?.pointSize ?? 12)
            }
            set {
                let range = NSRange(location: 0, length: localStorage.length)
                guard range.length > 0 else { return }
                let newSize = CGFloat(newValue)
                // 各文字のフォント名を保持しつつサイズだけ変更
                localStorage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                    let currentFont = value as? NSFont ?? NSFont.systemFont(ofSize: 12)
                    let newFont = NSFont(name: currentFont.fontName, size: newSize)
                                  ?? NSFont.systemFont(ofSize: newSize)
                    localStorage.addAttribute(.font, value: newFont, range: attrRange)
                    applyToBackingStorage(range: attrRange) { mappedRange in
                        backingStorage.addAttribute(.font, value: newFont, range: mappedRange)
                    }
                }
            }
        }

        override var foregroundColor: NSColor? {
            get {
                guard localStorage.length > 0 else { return .textColor }
                return localStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor ?? .textColor
            }
            set {
                let range = NSRange(location: 0, length: localStorage.length)
                guard range.length > 0, let color = newValue else { return }
                localStorage.addAttribute(.foregroundColor, value: color, range: range)
                applyToBackingStorage(range: range) { mappedRange in
                    backingStorage.addAttribute(.foregroundColor, value: color, range: mappedRange)
                }
            }
        }
    }

    // MARK: - Properties

    var textStorage: JOTextStorage = JOTextStorage()

    // MARK: - AppleScript Support

    /// AppleScript 用の textStorage アクセサ（SDEF の cocoa key="scriptingTextStorage" に対応）
    /// getter: textStorage を返す
    @objc var scriptingTextStorage: NSTextStorage {
        return textStorage
    }

    // MARK: - AppleScript Element Accessors (characters, words, paragraphs, attributeRuns)
    // contents タグの要素透過が class-extension で動作しない場合のため、
    // Document に直接 KVC アクセサを実装して textStorage に委譲する

    @objc var characters: NSArray {
        return textStorage.value(forKey: "characters") as? NSArray ?? NSArray()
    }

    @objc var words: NSArray {
        return textStorage.value(forKey: "words") as? NSArray ?? NSArray()
    }

    @objc var paragraphs: NSArray {
        return textStorage.value(forKey: "paragraphs") as? NSArray ?? NSArray()
    }

    @objc var attributeRuns: NSArray {
        return textStorage.value(forKey: "attributeRuns") as? NSArray ?? NSArray()
    }

    /// 現在のテキストビューを取得するヘルパー
    var currentTextView: NSTextView? {
        return windowControllers.first.flatMap { ($0 as? EditorWindowController)?.currentTextView() }
    }

    /// AppleScript select コマンドから呼ばれる選択範囲設定メソッド
    func setSelectionRange(_ range: NSRange) {
        guard let textView = currentTextView else { return }
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
    }

    /// AppleScript 用の選択テキスト（rich text）アクセサ
    /// getter: 選択範囲に対応するプロキシ NSTextStorage を返す
    ///         属性の変更（font, size, color）は元の textStorage に直接反映される
    /// setter: 選択範囲のテキストを置き換える
    @objc var scriptingSelection: NSTextStorage {
        get {
            guard let textView = currentTextView else { return NSTextStorage() }
            let range = textView.selectedRange()
            if range.length == 0 { return NSTextStorage() }
            return SelectionProxyTextStorage(backingStorage: textStorage, range: range, textView: textView)
        }
        set {
            guard let textView = currentTextView else { return }
            let range = textView.selectedRange()
            // Undo 可能にするため textView 経由で挿入する
            if textView.shouldChangeText(in: range, replacementString: newValue.string) {
                textStorage.beginEditing()
                textStorage.replaceCharacters(in: range, with: newValue)
                textStorage.endEditing()
                textView.didChangeText()
            }
            // 置き換え後、カーソルを置き換えテキストの末尾に移動
            textView.setSelectedRange(NSRange(location: range.location + newValue.length, length: 0))
        }
    }

    /// AppleScript 用の選択位置アクセサ（0-based）
    @objc var scriptingSelectionLocation: Int {
        get {
            guard let textView = currentTextView else { return 0 }
            return textView.selectedRange().location
        }
        set {
            guard let textView = currentTextView else { return }
            let currentRange = textView.selectedRange()
            let maxLen = textStorage.length
            let safeLoc = min(max(newValue, 0), maxLen)
            let safeLen = min(currentRange.length, maxLen - safeLoc)
            let range = NSRange(location: safeLoc, length: safeLen)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
        }
    }

    /// AppleScript 用の選択長さアクセサ
    @objc var scriptingSelectionLength: Int {
        get {
            guard let textView = currentTextView else { return 0 }
            return textView.selectedRange().length
        }
        set {
            guard let textView = currentTextView else { return }
            let currentRange = textView.selectedRange()
            let maxLen = textStorage.length
            let safeLen = min(max(newValue, 0), maxLen - currentRange.location)
            let range = NSRange(location: currentRange.location, length: safeLen)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
        }
    }

    /// AppleScript 用の書類タイプアクセサ
    /// "plain text" / "RTF" / "RTFD" を返す・設定する
    @objc var scriptingDocumentType: String {
        get {
            switch documentType {
            case .rtf: return "RTF"
            case .rtfd: return "RTFD"
            default: return "plain text"
            }
        }
        set {
            switch newValue.lowercased() {
            case "rtf":
                documentType = .rtf
            case "rtfd":
                documentType = .rtfd
            case "plain text", "plain", "text":
                documentType = .plain
            default:
                return
            }
            updateFileTypeFromDocumentType()
            NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
        }
    }

    /// AppleScript 用のデフォルトフォント名（読み取り専用）
    @objc var scriptingCharFont: String {
        let fontData = presetData?.fontAndColors ?? NewDocData.FontAndColorsData.default
        return fontData.baseFontName
    }

    /// AppleScript 用のデフォルトフォントサイズ（読み取り専用）
    @objc var scriptingCharSize: Double {
        let fontData = presetData?.fontAndColors ?? NewDocData.FontAndColorsData.default
        return Double(fontData.baseFontSize)
    }

    /// AppleScript 用のデフォルトテキスト色（読み取り専用）
    @objc var scriptingCharColor: NSColor {
        let fontData = presetData?.fontAndColors ?? NewDocData.FontAndColorsData.default
        return fontData.colors.character.nsColor
    }

    /// AppleScript 用のデフォルト背景色（読み取り専用）
    @objc var scriptingCharBackColor: NSColor {
        let fontData = presetData?.fontAndColors ?? NewDocData.FontAndColorsData.default
        return fontData.colors.background.nsColor
    }

    /// AppleScript 用のリッチテキスト判定プロパティ
    /// true ならリッチテキスト（RTF/RTFD）、false ならプレーンテキスト
    @objc var scriptingIsRichText: Bool {
        get {
            return documentType != .plain
        }
        set {
            if newValue {
                // プレーンテキスト → リッチテキスト
                if documentType == .plain {
                    documentType = .rtf
                    updateFileTypeFromDocumentType()
                    NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
                }
            } else {
                // リッチテキスト → プレーンテキスト
                if documentType != .plain {
                    documentType = .plain
                    updateFileTypeFromDocumentType()
                    NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
                }
            }
        }
    }

    // MARK: - AppleScript Print Command
    // AppleScript の print コマンドは AppDelegate.swift の handlePrintAppleEvent で
    // Apple Event レベルで処理する（Cocoa Scripting のルーティングが機能しないため）

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
            // テキストが空でなければ dirty にする
            // NSCreateCommand の書類作成プロセス完了後に反映するため遅延実行
            if textStorage.length > 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.updateChangeCount(.changeDone)
                }
            }
            return
        }
        if key == "scriptingSelection" {
            guard let textView = currentTextView else { return }
            let range = textView.selectedRange()
            let replacementString: String
            if let attrStr = value as? NSAttributedString {
                replacementString = attrStr.string
            } else if let str = value as? String {
                replacementString = str
            } else {
                return
            }
            // Undo 可能にするため textView 経由で挿入する
            if textView.shouldChangeText(in: range, replacementString: replacementString) {
                textStorage.beginEditing()
                if let attrStr = value as? NSAttributedString {
                    textStorage.replaceCharacters(in: range, with: attrStr)
                } else {
                    textStorage.replaceCharacters(in: range, with: replacementString)
                }
                textStorage.endEditing()
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: range.location + replacementString.count, length: 0))
            }
            return
        }
        if key == "scriptingIsRichText" {
            if let boolValue = value as? Bool {
                scriptingIsRichText = boolValue
            } else if let numValue = value as? NSNumber {
                scriptingIsRichText = numValue.boolValue
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

    /// Finder ロックファイルの処理済みフラグ（updateChangeCount での重複処理防止用）
    private var isLockedFileHandled: Bool = false

    // MARK: - Cascade Window Position

    /// カスケードオフセットのステップ幅（ピクセル）
    private static let cascadeStep: CGFloat = 22

    /// 現在のカスケードカウント（次に開く書類のオフセット番号）
    private static var cascadeCount: Int = 0

    /// 新規書類のウィンドウ位置にカスケードオフセットを適用する
    /// プリセットの基準位置から cascadeCount に応じて右下にずらした位置を設定する
    func applyCascadeOffsetToPresetData() {
        guard var presetData = self.presetData else { return }
        guard let screen = NSScreen.main else { return }

        let visibleFrame = screen.visibleFrame
        let offset = CGFloat(Document.cascadeCount) * Document.cascadeStep

        let newX = presetData.view.windowX + offset
        // macOS座標系: Y原点は画面下端。カスケードで下に移動 = Y値を減らす
        let newY = presetData.view.windowY - offset

        // 画面外に出るかチェック（右端または下端）
        let windowRight = newX + presetData.view.windowWidth
        if windowRight > visibleFrame.maxX || newY < visibleFrame.minY {
            // 画面外に出る場合はカウントをリセット（プリセットの基準位置を使用）
            Document.cascadeCount = 0
        } else if Document.cascadeCount > 0 {
            // オフセットがある場合のみ位置を変更
            presetData.view.windowX = newX
            presetData.view.windowY = newY
            self.presetData = presetData
        }

        Document.cascadeCount += 1
    }

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

    /// エイリアスアタッチメントのセキュリティスコープ付きURL
    /// ドキュメントを閉じる際に stopAccessingSecurityScopedResource() を呼ぶ
    private var securityScopedAttachmentURLs: [URL] = []

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

    /// Duplicate 時に元の書類の presetData を新しい書類へ引き渡すための一時変数
    private static var duplicatingPresetData: NewDocData?

    override init() {
        super.init()
        setupFontFallbackRecoveryDelegate()

        if let sourceData = Self.duplicatingPresetData {
            // Duplicate 中: 元の書類の presetData を適用
            applyPresetData(sourceData)
        } else if let selectedPreset = DocumentPresetManager.shared.selectedPreset() {
            // 通常の新規書類作成: Preferences のプリセットを適用
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

    /// Finder でロックされたファイルの場合は変更カウント更新をブロックし、
    /// _checkAutosavingThenUpdateChangeCount: による autosave 安全性チェック
    /// （Unlock/Duplicate/Cancel ダイアログ）の発生を防ぐ
    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        if self.isLocked {
            if !isLockedFileHandled {
                // 初回のみ編集ロック処理を実行
                isLockedFileHandled = true
                presetData?.view.preventEditing = true
                for wc in windowControllers {
                    if let editorWC = wc as? EditorWindowController {
                        editorWC.setAllTextViewsEditable(false)
                    }
                }
            }
            return  // ロック中は変更カウント更新をすべてブロック → autosave チェックが発生しない
        }
        super.updateChangeCount(change)
    }

    override func close() {
        // エイリアスアタッチメントのセキュリティスコープ付きリソースを解放
        for url in securityScopedAttachmentURLs {
            url.stopAccessingSecurityScopedResource()
        }
        securityScopedAttachmentURLs.removeAll()
        super.close()
    }

    // MARK: - Window Controllers

    override func makeWindowControllers() {
        // Document.xibからEditorWindowControllerを読み込む
        let windowController = EditorWindowController(windowNibName: NSNib.Name("Document"))
        // 既存ファイルの場合、保存されたウィンドウ位置を使用するためカスケードを無効化
        // （shouldCascadeWindows のデフォルトは true で、showWindows() 時にウィンドウ位置が
        //   ずらされてしまい、保存位置ではなくデフォルト位置に一瞬表示される原因になる）
        if fileURL != nil {
            windowController.shouldCascadeWindows = false
        }
        self.addWindowController(windowController)
    }

    override func showWindows() {
        // ウィンドウ表示前にプリセットフレームを適用
        // （windowDidLoad の時点では document が関連付けられていない場合があり、
        //   applyPresetData() でフレームが設定されないことがある。
        //   showWindows() の時点では確実に presetData にアクセスできるため、
        //   ここでフレームを設定してからウィンドウを表示する）
        if let presetData = self.presetData {
            let viewData = presetData.view
            for windowController in windowControllers {
                guard let window = windowController.window else { continue }
                window.setFrameAutosaveName("")
                let newFrame = NSRect(
                    x: viewData.windowX,
                    y: viewData.windowY,
                    width: viewData.windowWidth,
                    height: viewData.windowHeight
                )
                window.setFrame(newFrame, display: false)
            }
        }
        super.showWindows()
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

    /// ファイル読み込み〜初期設定完了後の "Edited" マーク解除をスケジュールする。
    /// EditorWindowController.windowDidLoad() の最後から呼ばれる。
    /// perform(_:with:afterDelay:) で次のイベントループに遅延実行し、
    /// _endTopLevelGroupings による changeDone 発火後に変更カウントをリセットする。
    func scheduleFinishInitialLoading() {
        perform(#selector(finishInitialLoading), with: nil, afterDelay: 0)
    }

    @objc private func finishInitialLoading() {
        updateChangeCount(.changeCleared)
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
    private func saveAttachmentBookmarks(to fileWrapper: FileWrapper) {
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
    private nonisolated static func restoreAttachmentBookmarks(from fileWrapper: FileWrapper) -> [URL] {
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
    private func normalizeListMarkerAttributes() {
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
            guard let fileWrapper = attachment.fileWrapper,
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

            if let data = item.attachment.fileWrapper?.regularFileContents,
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
            if let fileWrapper = replacement.attachment.fileWrapper,
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

    /// Shift_JIS保存時の文字変換（読み込み時の逆変換、Preferencesの設定に基づく）
    /// - Parameters:
    ///   - string: 変換対象の文字列
    ///   - encoding: 保存先のエンコーディング
    /// - Returns: 変換後の文字列
    private func applyEncodingSaveConversions(_ string: String, encoding: String.Encoding) -> String {
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

        // ユーザーが明示的に保存する場合、super.save() を呼ぶ前に untitledDocumentName を
        // クリアする。NSDocument 内部で fileURL がセットされると KVO 経由で displayName が
        // 参照されるが、そのとき untitledDocumentName が残っていると正しいファイル名ではなく
        // カスタム名が返されてしまい、NSDocument の内部的な rename 処理と競合する。
        // 保存失敗時は復元する。
        let savedUntitledName = self.untitledDocumentName
        if saveOperation == .saveOperation || saveOperation == .saveAsOperation {
            self.untitledDocumentName = nil
        }

        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            guard let self = self else {
                completionHandler(error)
                return
            }

            if error == nil {
                // 保存成功後にプリセットデータを拡張属性に書き込む
                // NSDocument の内部処理（autosave 一時ファイルのクリーンアップ等）との
                // ファイルシステム競合を避けるため、実際の fileURL に対して書き込む
                if let actualURL = self.fileURL {
                    self.writePresetDataToExtendedAttribute(at: actualURL)
                }
            } else {
                // 保存失敗時は untitledDocumentName を復元
                if saveOperation == .saveOperation || saveOperation == .saveAsOperation {
                    if self.untitledDocumentName == nil {
                        self.untitledDocumentName = savedUntitledName
                    }
                }
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

        // ドキュメントタイプに基づいてフォーマット情報を同期
        switch documentType {
        case .plain:
            presetData?.format.richText = false
            presetData?.format.textEncoding = documentEncoding.rawValue
            presetData?.format.bom = hasBOM
            switch lineEnding {
            case .lf:
                presetData?.format.lineEndingType = .lf
            case .cr:
                presetData?.format.lineEndingType = .cr
            case .crlf:
                presetData?.format.lineEndingType = .crlf
            }
        case .rtf, .rtfd:
            presetData?.format.richText = true
        default:
            presetData?.format.richText = true
        }

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

        // ブックマークツリーを presetData に保存
        serializeBookmarksToPresetData()
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
    /// Finder ロックファイルの場合は書き込みをスキップする
    func savePresetDataToExtendedAttribute(at url: URL) {
        guard let presetData = self.presetData else { return }

        // 現在のファイル属性を取得（ロック状態）
        let isLocked: Bool
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            isLocked = (attrs[.immutable] as? Bool) ?? false
        } catch {
            isLocked = false
        }

        // Finder ロックされている場合は書き込みをスキップ
        if isLocked { return }

        // stat で元のアクセス日時・修正日時を取得
        var originalStat = stat()
        let statResult = stat(url.path, &originalStat)

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
                if statResult == 0 {
                    var times = [timespec](repeating: timespec(), count: 2)
                    times[0] = originalStat.st_atimespec  // アクセス日時
                    times[1] = originalStat.st_mtimespec  // 修正日時
                    utimensat(AT_FDCWD, url.path, &times, 0)
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

                // ブックマーク復元: presetData にブックマークがあれば復元
                if !self.restoreBookmarksFromPresetData() {
                    // presetData にブックマークがない場合、
                    // RTF/RTFD ならリンク属性から復元を試みる
                    if self.documentType == .rtf || self.documentType == .rtfd {
                        self.restoreBookmarksFromLinkAttributes()
                    }
                }
            }
        } else if let omegaPresetData = JeditOmegaSettingImporter.importSettings(from: url) {
            // JeditΩ の拡張属性が見つかった場合
            MainActor.assumeIsolated {
                self.presetData = omegaPresetData
                // JeditΩ の印刷設定（orientation, margins, scale）を document の printInfo に直接適用
                // paperSize は document の元の値を維持する
                JeditOmegaSettingImporter.applyPrintSettings(from: url, to: self.printInfo)
                // プレーンテキストの場合はBasic Fontを適用
                self.applyBasicFontIfPlainText()
            }
        } else {
            // 拡張属性がない場合は、書類タイプテーブルからマッチングし、
            // マッチしなければファイルタイプに応じたデフォルトのNewDocDataを設定
            MainActor.assumeIsolated {
                self.presetData = self.createDefaultPresetDataForCurrentDocumentType(url: url, typeName: typeName)
                // プレーンテキストの場合はBasic Fontを適用
                self.applyBasicFontIfPlainText()

                // RTF/RTFDファイルから読み込んだ document attributes の properties を適用
                self.applyLoadedDocumentAttributeProperties()
                // ビュー・ページ設定も Document Attributes から適用（presetData より優先）
                self.applyLoadedDocumentAttributeViewSettings()

                // 拡張属性なしの RTF/RTFD の場合、リンク属性からブックマーク復元を試みる
                if self.documentType == .rtf || self.documentType == .rtfd {
                    self.restoreBookmarksFromLinkAttributes()
                }
            }
        }

        // Share Extension からの一時ファイルは新規書類として扱う
        if url.lastPathComponent.hasPrefix("JeditShare-") {
            MainActor.assumeIsolated {
                self.fileURL = nil
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Word / OpenDocument Support

    /// XML ファイルが Word 2003 XML (WordML) 形式かどうかをファイル先頭の内容で判定
    private nonisolated static func isWordMLFile(url: URL) -> Bool {
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
                NSLocalizedDescriptionKey: "Could not read Markdown document.".localized
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

            // リモート画像を非同期で読み込み
            MarkdownParser.loadRemoteImages(in: self.textStorage)

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
    /// まず書類タイプテーブルからUTI/正規表現でマッチングを試み、
    /// マッチしなければドキュメントタイプに応じたデフォルト値を使用
    private func createDefaultPresetDataForCurrentDocumentType(url: URL? = nil, typeName: String? = nil) -> NewDocData {
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

    /// ブックマーク機能をサポートしない書類かどうか（Markdown, Word/ODT）
    var isBookmarkUnsupported: Bool {
        return isMarkdownDocument || isImportedDocument
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(showProperties(_:)) {
            // 書類ウィンドウがある場合のみ有効
            return windowControllers.first?.window != nil
        }
        // ブックマーク関連メニューは md/Word/ODT では無効
        if item.action == #selector(bookmarkSelection(_:)) ||
           item.action == #selector(showBookmarkPanel(_:)) {
            return !isBookmarkUnsupported
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
            // presetData の printInfo も更新
            presetData?.printInfo = NewDocData.PrintInfoData(from: self.printInfo)
            presetDataEdited = true

            NotificationCenter.default.post(name: Document.printInfoDidChangeNotification, object: self)
        }
    }

    // MARK: - Printing

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        // EditorWindowControllerから印刷設定を取得
        guard let windowController = windowControllers.first as? EditorWindowController,
              let config = windowController.printPageViewConfiguration() else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: [
                NSLocalizedDescriptionKey: "Cannot print: No text view available".localized
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
            // untitledDocumentName が設定されている場合は、autosave で fileURL が
            // 設定されていてもカスタム名を優先する（ユーザーが明示的に保存するまで）
            if let customName = untitledDocumentName {
                return customName
            }
            // ファイルがある場合は通常の表示名
            if fileURL != nil {
                return super.displayName
            }
            // 新規ドキュメントの場合はカスタム名を使用（遅延生成）
            generateUntitledDocumentName()
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

    // MARK: - RTF Data Detection

    /// データの先頭が RTF シグネチャ "{\rtf" で始まるかチェックする
    /// autosave 復元時に .txt 拡張子のファイルが実際には RTF データかどうかを判定するために使用
    private nonisolated static func dataIsRTF(_ data: Data) -> Bool {
        let rtfSignature: [UInt8] = [0x7B, 0x5C, 0x72, 0x74, 0x66]  // "{\rtf"
        guard data.count >= rtfSignature.count else { return false }
        return data.prefix(rtfSignature.count).elementsEqual(rtfSignature)
    }
}
