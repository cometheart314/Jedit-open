//
//  Document.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/25.
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

    /// SelectionProxyTextStorage のファクトリメソッド（Document+AppleScript.swift から使用）
    func createSelectionProxy(backingStorage: NSTextStorage, range: NSRange, textView: NSTextView?) -> NSTextStorage {
        return SelectionProxyTextStorage(backingStorage: backingStorage, range: range, textView: textView)
    }

    // MARK: - Properties

    var textStorage: JOTextStorage = JOTextStorage()

    // MARK: - AppleScript Support
    // → Moved to Document+AppleScript.swift

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
    var savePanelFormatTag: Int?

    /// Save Panel のエンコーディングポップアップ参照（プレーンテキスト保存時に使用）
    weak var savePanelEncodingPopUp: NSPopUpButton?

    /// Save Panel の改行コードポップアップ参照（プレーンテキスト保存時に使用）
    weak var savePanelLineEndingPopUp: NSPopUpButton?

    /// Save Panel の BOM チェックボックス参照（プレーンテキスト保存時に使用）
    weak var savePanelBOMCheckbox: NSButton?

    /// Save Panel のフォーマットポップアップ変更時コールバック
    var saveFormatAction: (() -> Void)?

    /// Save Panel のエンコーディングポップアップ変更時コールバック
    var saveEncodingAction: (() -> Void)?

    /// ドキュメント統計情報（Location[Size] タブ表示用）
    var statistics = DocumentStatistics()

    /// エイリアスアタッチメントのセキュリティスコープ付きURL
    /// ドキュメントを閉じる際に stopAccessingSecurityScopedResource() を呼ぶ
    var securityScopedAttachmentURLs: [URL] = []

    /// フォントフォールバック復帰用のDelegate
    private var fontFallbackRecoveryDelegate: FontFallbackRecoveryDelegate?

    /// RTF/RTFDファイルから読み込んだ document attributes のプロパティ
    /// 拡張属性読み込み後に適用するために一時保存
    var loadedDocumentAttributeProperties: NewDocData.PropertiesData?

    /// RTF/RTFDファイルから読み込んだ document attributes のビュー・ページ設定
    /// 拡張属性読み込み後に適用するために一時保存（Document Attributesを優先するため）
    var loadedDocumentAttributeViewSettings: [NSAttributedString.DocumentAttributeKey: Any]?

    /// 新規ドキュメントの表示名（fileURLがない場合に使用）
    var untitledDocumentName: String?

    /// 新規ドキュメントのシリアル番号管理（日付別）
    private static var dailySerialNumbers: [String: Int] = [:]
    /// 新規ドキュメントの通し番号（Untitled用）
    private static var untitledCounter: Int = 0

    // MARK: - Initialization

    /// Duplicate 時に元の書類の presetData を新しい書類へ引き渡すための一時変数
    static var duplicatingPresetData: NewDocData?

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

        // Markdownドキュメントの場合、ウインドウ表示後にMarkdownを再パースして
        // textStorageを再設定する。readMarkdownDocumentはウインドウ作成前に実行
        // されるため、NSTextTableのレイアウトが正しいビュー幅なしで計算される。
        // ウインドウ表示後に再パースすることで、正しいビュー幅でテーブルが配置される。
        // Markdownドキュメントの場合、ウインドウ表示後にパースを実行
        // readMarkdownDocumentではパースせず生テキストのみ保存しているため、
        // ここでテキストコンテナサイズが確定した状態でパースする
        if isMarkdownDocument, let markdownText = originalMarkdownText {
            let baseURL = fileURL?.deletingLastPathComponent()
            let attributedString = MarkdownParser.attributedString(from: markdownText, baseURL: baseURL)
            textStorage.setAttributedString(attributedString)

            // リモート画像を非同期読み込み、全画像ダウンロード完了後に
            // キャッシュ済み画像で再パースしてNSTextTableのレイアウトを確定する
            MarkdownParser.loadRemoteImages(in: textStorage) { [weak self] in
                guard let self = self,
                      let markdownText = self.originalMarkdownText else { return }
                let baseURL = self.fileURL?.deletingLastPathComponent()
                let refreshed = MarkdownParser.attributedString(from: markdownText, baseURL: baseURL)
                self.textStorage.setAttributedString(refreshed)
                // 2回目のパースではキャッシュ済み画像が直接挿入されるため
                // loadRemoteImagesは不要（プレースホルダーが存在しない）
            }
        }
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
    // → Moved to Document+FileIO.swift

    // MARK: - Encoding Selection
    // → Moved to Document+Export.swift

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
    // → Moved to Document+Export.swift

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
    func updatePresetDataFromCurrentState() {
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
                // 拡張子が .md でも実際の内容が RTF の場合はMarkdownとして扱わない
                if Self.isActuallyRTF(url: url) {
                    // RTFとして通常フローで読み込む
                } else {
                    try readMarkdownDocument(from: url)
                    return
                }
            }
            // プレーンテキストとして読み込む場合は通常のフローへ
        }

        // まず通常のファイル読み込みを行う
        // RTFD パッケージでシンボリックリンクがサンドボックス外を指す場合に
        // FileWrapper の作成が失敗することがあるため、フォールバックで再試行する
        let isRTFDType = typeName == "com.apple.rtfd" || url.pathExtension.lowercased() == "rtfd"
        if isRTFDType {
            do {
                try super.read(from: url, ofType: typeName)
            } catch {
                // アクセスできないシンボリックリンクをスキップして FileWrapper を作成し再試行
                let fileWrapper = try Self.createRTFDFileWrapperSkippingInaccessibleSymlinks(from: url)
                try read(from: fileWrapper, ofType: "com.apple.rtfd")
            }
        } else {
            try super.read(from: url, ofType: typeName)
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
    // → Moved to Document+FileIO.swift

    // MARK: - Markdown Support
    // → Moved to Document+FileIO.swift

    // MARK: - Text Clipping Support
    // → Moved to Document+FileIO.swift

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

        let result = super.validateUserInterfaceItem(item)

        // Shift+Cmd+S の動作を設定に応じて切り替え（タイトルを入れ替える）
        let useSaveAs = UserDefaults.standard.bool(forKey: UserDefaults.Keys.useSaveAs)
        if let menuItem = item as? NSMenuItem {
            if menuItem.action == #selector(NSDocument.duplicate(_:)) {
                menuItem.title = useSaveAs
                    ? NSLocalizedString("Save As…", comment: "File menu: Save As")
                    : NSLocalizedString("Duplicate", comment: "File menu: Duplicate")
            } else if menuItem.action == #selector(NSDocument.saveAs(_:)) {
                menuItem.title = useSaveAs
                    ? NSLocalizedString("Duplicate", comment: "File menu: Duplicate")
                    : NSLocalizedString("Save As…", comment: "File menu: Save As")
            }
        }

        return result
    }

    // MARK: - Save As / Duplicate 切り替え

    /// Shift+Cmd+S (Duplicate) のアクションを設定に応じてリダイレクト
    @IBAction override func duplicate(_ sender: Any?) {
        if UserDefaults.standard.bool(forKey: UserDefaults.Keys.useSaveAs) {
            // Save As モード: Save As を実行
            super.saveAs(sender)
        } else {
            super.duplicate(sender)
        }
    }

    /// Option+Shift+Cmd+S (Save As) のアクションを設定に応じてリダイレクト
    @IBAction override func saveAs(_ sender: Any?) {
        if UserDefaults.standard.bool(forKey: UserDefaults.Keys.useSaveAs) {
            // Save As モード: Option 時は Duplicate を実行
            super.duplicate(sender)
        } else {
            super.saveAs(sender)
        }
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
            // タイトルバーからのリネームや保存時に NSDocument が displayName を
            // セットした場合、untitledDocumentName をクリアしてファイル名を優先する
            untitledDocumentName = nil
            super.displayName = newValue
        }
    }

    /// 新規ドキュメント名を生成（presetDataの設定に基づく）
    private func generateUntitledDocumentName() {
        let localizedUntitled = "Untitled".localized

        guard let presetData = self.presetData else {
            // presetDataがない場合はデフォルト（Untitled）
            Document.untitledCounter += 1
            if Document.untitledCounter > 1 {
                untitledDocumentName = "\(localizedUntitled) \(Document.untitledCounter)"
            } else {
                untitledDocumentName = localizedUntitled
            }
            return
        }

        let nameType = presetData.format.newDocNameType

        switch nameType {
        case .untitled:
            // Untitled #
            Document.untitledCounter += 1
            if Document.untitledCounter > 1 {
                untitledDocumentName = "\(localizedUntitled) \(Document.untitledCounter)"
            } else {
                untitledDocumentName = localizedUntitled
            }

        case .dateTime:
            // YYYY-MM-DD HH-mm-ss
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
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
    // → Moved to Document+Export.swift

    // MARK: - Export
    // → Moved to Document+Export.swift

    /// エクスポートパネルのフォーマットポップアップ変更時コールバック（Document+Export.swift から使用）
    var _exportFormatAction: (() -> Void)?
    /// エクスポートパネルのエンコーディングポップアップ変更時コールバック（Document+Export.swift から使用）
    var _exportEncodingAction: (() -> Void)?

    // MARK: - RTF Data Detection
    // → Moved to Document+FileIO.swift
}

