//
//  DocumentInfoPanelController.swift
//  Jedit-open
//
//  Created by Claude on 2026/02/10.
//

import Cocoa

/// Document Info パネルのコントローラー
/// AppDelegate からシングルトンとして管理され、最前面ドキュメントの情報を表示する
class DocumentInfoPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    // MARK: - Singleton

    static let shared = DocumentInfoPanelController()

    // MARK: - Properties

    /// XIBからロードされるパネル（NSPanel: utility スタイル）
    @IBOutlet var documentInfoPanel: NSPanel!

    /// タブビュー
    @IBOutlet var tabView: NSTabView!

    /// Location タブのテーブルビュー
    @IBOutlet var infoTableView: NSTableView!

    /// Document Info タブのコントロール
    @IBOutlet var bomCheckBox: NSButton!
    @IBOutlet var encodingPopUpButton: EncodingPopUpButton!
    @IBOutlet var encodingPopUpCell: EncodingPopUpButtonCell!
    @IBOutlet var lineEndingPopUpButton: NSPopUpButton!
    @IBOutlet var docTypeName: NSTextField!
    @IBOutlet var dotLine1: NSTextField!
    @IBOutlet var dotLine2: NSTextField!
    @IBOutlet var pathTextView: NSTextView!
    @IBOutlet var chkboxCountHalfAs05: NSButton!

    /// パネルがロード済みかどうか
    private var isLoaded = false

    /// UserDefaults キー: 半角文字を0.5として数えるか
    private static let countHalfAs05Key = "DocumentInfoCountHalfAs05"

    /// 半角文字を0.5として数えるかどうか
    var countHalfWidthAs05: Bool {
        return UserDefaults.standard.bool(forKey: Self.countHalfAs05Key)
    }

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Panel Loading

    /// XIBからパネルをロード
    private func loadPanelIfNeeded() {
        guard !isLoaded else { return }

        let nibName = "DocumentInfoPanel"
        guard Bundle.main.loadNibNamed(nibName, owner: self, topLevelObjects: nil) else {
            print("Failed to load \(nibName).xib")
            return
        }

        isLoaded = true

        // パネルのタイトルを設定
        documentInfoPanel?.title = "Document Info"
        // NSPanel (utility) はデフォルトで floating level + hidesOnDeactivate
        // becomesKeyOnlyIfNeeded により、ドキュメントウィンドウのフォーカスを奪わない
        documentInfoPanel?.becomesKeyOnlyIfNeeded = true

        // ポップアップが開く瞬間に変換不能エンコーディングを disable するクロージャを設定
        encodingPopUpButton?.textForValidation = { [weak self] in
            return self?.currentDocument()?.textStorage.string
        }

        // Location[Size] テーブルの dataSource / delegate を設定
        infoTableView?.dataSource = self
        infoTableView?.delegate = self

        // 統計情報変更通知を監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(statisticsDidChange(_:)),
            name: Document.statisticsDidChangeNotification,
            object: nil
        )

        // チェックボックスの状態を UserDefaults から復元
        chkboxCountHalfAs05?.state = countHalfWidthAs05 ? .on : .off
    }

    // MARK: - Public Methods

    /// パネルを表示（トグル動作）
    func showPanel() {
        loadPanelIfNeeded()

        guard let panel = documentInfoPanel else { return }

        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            // 最前面ドキュメントの情報を更新（パネル表示前なので直接更新）
            updatePanelContents()
            // orderFront を使用してドキュメントウィンドウのメイン/キー状態を維持
            panel.orderFront(nil)
            // 統計計算をトリガー
            triggerStatisticsUpdate()
        }
    }

    /// パネルが表示されているかどうか
    var isPanelVisible: Bool {
        return isLoaded && (documentInfoPanel?.isVisible ?? false)
    }

    /// パネルを閉じる
    func closePanel() {
        guard isLoaded, let panel = documentInfoPanel, panel.isVisible else { return }
        panel.orderOut(nil)
    }

    // MARK: - Document Info Update

    /// 現在の最前面ドキュメントの情報でパネルを更新（パネルが表示中の場合のみ）
    func updateForCurrentDocument() {
        guard isLoaded, let panel = documentInfoPanel, panel.isVisible else { return }
        updatePanelContents()
    }

    /// 指定されたドキュメントの情報でパネルを更新（パネルが表示中の場合のみ）
    /// 通知元ウィンドウから直接ドキュメントを特定できる場合に使用
    func updateForDocument(_ document: Document) {
        guard isLoaded, let panel = documentInfoPanel, panel.isVisible else { return }

        let displayName = document.displayName ?? "Untitled"
        panel.title = "Document Info — \(displayName)"
        updateDocumentInfoTab(for: document)
        // 統計計算をトリガー（ウィンドウ切り替え時に最新情報を表示）
        triggerStatisticsUpdate(for: document)
    }

    /// パネルの内容を実際に更新する（isVisible チェックなし）
    private func updatePanelContents() {
        guard isLoaded, let panel = documentInfoPanel else { return }

        // 最前面のドキュメントを取得
        guard let document = currentDocument() else {
            // ドキュメントがない場合はパネルタイトルをリセット
            panel.title = "Document Info"
            clearDocumentInfoTab()
            return
        }

        // パネルタイトルにドキュメント名を表示
        let displayName = document.displayName ?? "Untitled"
        panel.title = "Document Info — \(displayName)"

        // Document Info タブを更新
        updateDocumentInfoTab(for: document)
    }

    /// Document Info タブの内容を更新
    private func updateDocumentInfoTab(for document: Document) {
        let isPlainText = (document.documentType == .plain)

        // Document Type
        docTypeName?.stringValue = documentTypeName(for: document)

        // Encoding（Plain Text のみ表示）
        if isPlainText {
            encodingPopUpButton?.isHidden = false
            dotLine1?.isHidden = true
            // 現在のエンコーディングを選択
            let encodingRawValue = document.documentEncoding.rawValue
            EncodingManager.shared.setupPopUpCell(
                encodingPopUpCell,
                selectedEncoding: UInt(encodingRawValue),
                withDefaultEntry: false
            )
            // 変換不能エンコーディングの disable は EncodingPopUpButton.willOpenMenu で行う
        } else {
            encodingPopUpButton?.isHidden = true
            dotLine1?.isHidden = false
            dotLine1?.stringValue = "-----"
        }

        // Line Endings（Plain Text のみ表示）
        if isPlainText {
            lineEndingPopUpButton?.isHidden = false
            dotLine2?.isHidden = true
            // 現在の改行コードを選択
            lineEndingPopUpButton?.selectItem(withTag: document.lineEnding.rawValue)
        } else {
            lineEndingPopUpButton?.isHidden = true
            dotLine2?.isHidden = false
            dotLine2?.stringValue = "-----"
        }

        // BOM（Plain Text のみ表示）
        if isPlainText {
            bomCheckBox?.isHidden = false
            bomCheckBox?.state = document.hasBOM ? .on : .off
            // BOM は Unicode 系エンコーディングの場合のみ有効
            let isUnicode = EncodingManager.isUnicodeEncoding(document.documentEncoding)
            bomCheckBox?.isEnabled = isUnicode
            if !isUnicode {
                bomCheckBox?.state = .off
            }
        } else {
            bomCheckBox?.isHidden = true
        }

        // パス名を表示
        if let fileURL = document.fileURL {
            pathTextView?.string = fileURL.path
        } else {
            pathTextView?.string = "Untitled"
        }
    }

    /// ドキュメントタイプの表示名を返す
    private func documentTypeName(for document: Document) -> String {
        switch document.documentType {
        case .plain:
            return "Plain Text"
        case .rtf:
            // Markdown ドキュメントの場合
            if document.isMarkdownDocument {
                return "Markdown (.md)"
            }
            // インポートされた Word/ODT ドキュメントの場合、ファイル拡張子で判別
            if document.isImportedDocument, let fileURL = document.fileURL {
                switch fileURL.pathExtension.lowercased() {
                case "doc":
                    return "Word (.doc)"
                case "docx":
                    return "Word (.docx)"
                case "xml":
                    return "Word 2003 XML (.xml)"
                case "odt":
                    return "OpenDocument (.odt)"
                default:
                    break
                }
            }
            return "Rich Text (RTF)"
        case .rtfd:
            return "Rich Text with Attachments (RTFD)"
        case .docFormat:
            return "Word (.doc)"
        case .officeOpenXML:
            return "Word (.docx)"
        case .wordML:
            return "Word 2003 XML (.xml)"
        default:
            return "Rich Text"
        }
    }

    /// Document Info タブの内容をクリア
    private func clearDocumentInfoTab() {
        docTypeName?.stringValue = ""
        dotLine1?.stringValue = "-----"
        dotLine2?.stringValue = "-----"
        bomCheckBox?.state = .off
        pathTextView?.string = ""
    }

    /// 最前面のドキュメントウィンドウに対応するDocumentを返す
    private func currentDocument() -> Document? {
        // メインウィンドウから Document を取得
        // Document Info Panel 自身がメインウィンドウの場合はスキップ
        for window in NSApp.orderedWindows {
            // Document Info Panel 自身はスキップ
            if window === documentInfoPanel { continue }

            // NSPanel（他のユーティリティパネル）はスキップ
            if window is NSPanel { continue }

            // ウィンドウコントローラーからドキュメントを取得
            if let windowController = window.windowController,
               let document = windowController.document as? Document {
                return document
            }
        }
        return nil
    }

    // MARK: - IBActions

    @IBAction func bomFlagChanged(_ sender: Any?) {
        guard let checkBox = sender as? NSButton,
              let document = currentDocument(),
              document.documentType == .plain else { return }

        let newBOM = (checkBox.state == .on)
        if document.hasBOM != newBOM {
            document.hasBOM = newBOM
            document.updateChangeCount(.changeDone)
            notifyEditorWindowController(for: document)
        }
    }

    @IBAction func encodingChanged(_ sender: Any?) {
        guard let popup = sender as? NSPopUpButton,
              let selectedItem = popup.selectedItem,
              let document = currentDocument(),
              document.documentType == .plain else { return }

        // representedObject から選択されたエンコーディングを取得
        guard let encodingNumber = selectedItem.representedObject as? NSNumber else { return }
        let newEncoding = String.Encoding(rawValue: encodingNumber.uintValue)

        // 現在のエンコーディングと同じ場合は何もしない
        if document.documentEncoding == newEncoding { return }

        // 現在のテキストを新しいエンコーディングで再エンコードできるか確認
        let currentText = document.textStorage.string
        guard let data = currentText.data(using: newEncoding) else {
            // 変換できない場合はアラートを表示し、選択を元に戻す
            let alert = NSAlert()
            alert.messageText = "Cannot Convert".localized
            alert.informativeText = String(format: "The document contains characters that cannot be represented in %@.".localized, String.localizedName(of: newEncoding))
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK".localized)
            if let panel = documentInfoPanel {
                alert.beginSheetModal(for: panel) { [weak self] _ in
                    self?.updateDocumentInfoTab(for: document)
                }
            }
            return
        }

        // ラウンドトリップテスト
        let reconverted = String(data: data, encoding: newEncoding)
        if reconverted != currentText {
            // ラウンドトリップできない場合は確認アラートを表示
            let alert = NSAlert()
            alert.messageText = "Encoding Warning".localized
            alert.informativeText = String(format: "Converting to %@ may result in data loss. Do you want to continue?".localized, String.localizedName(of: newEncoding))
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Convert".localized)
            alert.addButton(withTitle: "Cancel".localized)
            if let panel = documentInfoPanel {
                alert.beginSheetModal(for: panel) { [weak self] response in
                    if response == .alertFirstButtonReturn {
                        self?.applyEncodingChange(newEncoding, to: document)
                    } else {
                        // キャンセル - 選択を元に戻す
                        self?.updateDocumentInfoTab(for: document)
                    }
                }
            }
            return
        }

        // エンコーディングを変更
        applyEncodingChange(newEncoding, to: document)
    }

    @IBAction func lineEndingChanged(_ sender: Any?) {
        guard let popup = sender as? NSPopUpButton,
              let selectedItem = popup.selectedItem,
              let newLineEnding = LineEnding(rawValue: selectedItem.tag),
              let document = currentDocument(),
              document.documentType == .plain else { return }

        // 現在の改行コードと同じ場合は何もしない
        if document.lineEnding == newLineEnding { return }

        document.lineEnding = newLineEnding
        document.updateChangeCount(.changeDone)
        notifyEditorWindowController(for: document)
    }

    @IBAction func changedCountHalfAs05(_ sender: Any?) {
        guard let checkBox = sender as? NSButton else { return }
        let newValue = (checkBox.state == .on)
        UserDefaults.standard.set(newValue, forKey: Self.countHalfAs05Key)
        // 統計を再計算
        triggerStatisticsUpdate()
    }

    // MARK: - Private Helpers

    /// エンコーディング変更を適用
    private func applyEncodingChange(_ newEncoding: String.Encoding, to document: Document) {
        document.documentEncoding = newEncoding
        document.updateChangeCount(.changeDone)
        notifyEditorWindowController(for: document)
    }

    /// ドキュメントの EditorWindowController にツールバー更新を通知
    private func notifyEditorWindowController(for document: Document) {
        if let windowController = document.windowControllers.first as? EditorWindowController {
            windowController.updateEncodingToolbarItem()
            windowController.updateLineEndingToolbarItem()
        }
    }

    // MARK: - Statistics Update

    /// 統計計算をトリガー（現在のドキュメント）
    private func triggerStatisticsUpdate() {
        guard let document = currentDocument() else { return }
        triggerStatisticsUpdate(for: document)
    }

    /// 統計計算をトリガー（指定ドキュメント）
    private func triggerStatisticsUpdate(for document: Document) {
        if let windowController = document.windowControllers.first as? EditorWindowController {
            windowController.scheduleStatisticsUpdate()
        }
    }

    /// 統計情報変更通知ハンドラ
    @objc private func statisticsDidChange(_ notification: Notification) {
        guard isPanelVisible else { return }
        // 現在のドキュメントの通知のみ処理
        if let notifiedDocument = notification.object as? Document,
           let currentDoc = currentDocument(),
           notifiedDocument === currentDoc {
            infoTableView?.reloadData()
        }
    }

    // MARK: - NSTableViewDataSource

    /// Location[Size] テーブルの行名
    private static let rowNames = [
        "Location",
        "Characters",
        "Visible Chars",
        "Words",
        "Rows",
        "Paragraphs",
        "Pages",
        "Char. Code"
    ]

    func numberOfRows(in tableView: NSTableView) -> Int {
        return Self.rowNames.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let columnIdentifier = tableColumn?.identifier.rawValue else { return nil }

        let cellIdentifier = NSUserInterfaceItemIdentifier("InfoCell_\(columnIdentifier)")
        var cellView = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView

        if cellView == nil {
            cellView = NSTableCellView()
            cellView?.identifier = cellIdentifier
            let textField = NSTextField(labelWithString: "")
            textField.font = NSFont.systemFont(ofSize: 11)
            textField.isSelectable = true
            textField.isEditable = false
            textField.isBordered = false
            textField.drawsBackground = false
            textField.translatesAutoresizingMaskIntoConstraints = false
            cellView?.addSubview(textField)
            cellView?.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 2),
                textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -2),
                textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
            ])
        }

        let stats = currentDocument()?.statistics ?? DocumentStatistics()
        let text: String

        let isCharCodeRow = (row == 7)

        switch columnIdentifier {
        case "NAME":
            text = Self.rowNames[row]
            cellView?.textField?.alignment = .right
            cellView?.textField?.font = NSFont.systemFont(ofSize: 11)
        case "SELECTION":
            text = selectionValue(for: row, stats: stats)
            cellView?.textField?.alignment = isCharCodeRow ? .left : .right
            cellView?.textField?.font = NSFont.monospacedSystemFont(
                ofSize: isCharCodeRow ? 11 : 13, weight: .regular)
        case "WHOLE":
            text = wholeDocValue(for: row, stats: stats)
            cellView?.textField?.alignment = .right
            cellView?.textField?.font = NSFont.systemFont(ofSize: 13)
        default:
            text = ""
        }

        cellView?.textField?.stringValue = text
        return cellView
    }

    // MARK: - Table Value Formatting

    /// Selection 列の値を返す
    private func selectionValue(for row: Int, stats: DocumentStatistics) -> String {
        let f: (Int) -> String = DocumentStatistics.formatted
        let fd: (Double) -> String = DocumentStatistics.formatted
        let hasSelection = (stats.selectionLength > 0)

        switch row {
        case 0: // Location
            if stats.totalCharacters > 0 {
                let percent = Int(round(Double(stats.selectionLocation) / Double(stats.totalCharacters) * 100))
                return "\(percent) %"
            }
            return "0 %"

        case 1: // Characters
            if hasSelection {
                return "\(f(stats.selectionLocation)) [\(f(stats.selectionCharacters))]"
            }
            return f(stats.selectionLocation)

        case 2: // Visible Chars
            if hasSelection {
                return "[\(fd(stats.selectionVisibleChars))]"
            }
            return ""

        case 3: // Words
            if hasSelection {
                return "\(f(stats.locationWords)) [\(f(stats.selectionWords))]"
            }
            return f(stats.locationWords)

        case 4: // Rows
            if !stats.showRows { return "–" }
            if hasSelection {
                return "\(f(stats.locationRows)) [\(f(stats.selectionRows))]"
            }
            return f(stats.locationRows)

        case 5: // Paragraphs
            if hasSelection {
                return "\(f(stats.locationParagraphs)) [\(f(stats.selectionParagraphs))]"
            }
            return f(stats.locationParagraphs)

        case 6: // Pages
            if !stats.showPages { return "–" }
            if hasSelection {
                return "\(f(stats.locationPages)) [\(f(stats.selectionPages))]"
            }
            return f(stats.locationPages)

        case 7: // Char. Code
            return stats.charCode

        default:
            return ""
        }
    }

    /// Whole Doc. 列の値を返す
    private func wholeDocValue(for row: Int, stats: DocumentStatistics) -> String {
        let f: (Int) -> String = DocumentStatistics.formatted
        let fd: (Double) -> String = DocumentStatistics.formatted

        switch row {
        case 0: // Location
            return "100 %"

        case 1: // Characters
            return f(stats.totalCharacters)

        case 2: // Visible Chars
            return fd(stats.totalVisibleChars)

        case 3: // Words
            return f(stats.totalWords)

        case 4: // Rows
            if !stats.showRows { return "–" }
            return f(stats.totalRows)

        case 5: // Paragraphs
            return f(stats.totalParagraphs)

        case 6: // Pages
            if !stats.showPages { return "–" }
            return f(stats.totalPages)

        case 7: // Char. Code
            return ""

        default:
            return ""
        }
    }
}
