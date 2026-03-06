//
//  LinkPanelController.swift
//  Jedit-open
//
//  カスタムリンクパネルのコントローラー。
//  テキスト選択範囲にリンク属性を設定/削除する。
//  ブックマークパネルからのドラッグ＆ドロップでアンカーリンクを設定可能。
//

import Cocoa

/// ブックマークのドラッグ＆ドロップ用パステボードタイプ（BookmarkPanelController と共有）
private let bookmarkDragType = NSPasteboard.PasteboardType("jp.co.artman21.Jedit-open.bookmark")

/// カスタムリンクパネルのコントローラー。
/// シングルトンとして管理され、テキスト選択範囲にリンク属性を設定する。
class LinkPanelController: NSObject, NSTextFieldDelegate, NSWindowDelegate {

    // MARK: - Singleton

    static let shared = LinkPanelController()

    // MARK: - IBOutlets

    /// LinkPanel.xib からロードされるフローティングパネル
    @IBOutlet var linkPanel: NSPanel!

    /// URL / アンカー ID 入力フィールド
    @IBOutlet var urlField: NSTextField!

    /// 表示テキストフィールド
    @IBOutlet var displayTextField: NSTextField!

    /// 「Set Link」ボタン
    @IBOutlet var setLinkButton: NSButton!

    /// 「Delete」ボタン
    @IBOutlet var deleteLinkButton: NSButton!

    // MARK: - Properties

    /// パネルがロード済みかどうか
    private var isLoaded = false

    /// URL フィールドのクリアボタン
    private var urlClearButton: NSButton?

    /// ブックマークドロップ対応のカスタムフィールドエディタ
    private lazy var bookmarkFieldEditor: BookmarkDropFieldEditor = {
        let editor = BookmarkDropFieldEditor()
        editor.isFieldEditor = true
        return editor
    }()

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Panel Loading

    /// XIB からパネルをロード
    private func loadPanelIfNeeded() {
        guard !isLoaded else { return }

        let nibName = "LinkPanel"
        guard Bundle.main.loadNibNamed(nibName, owner: self, topLevelObjects: nil) else {
            print("Failed to load \(nibName).xib")
            return
        }

        isLoaded = true

        // パネル設定
        linkPanel.becomesKeyOnlyIfNeeded = false
        linkPanel.level = .floating
        linkPanel.isReleasedWhenClosed = false
        linkPanel.delegate = self

        // パネルの背景色を設定（テキストフィールドとのコントラスト確保）
        if let contentView = linkPanel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }

        // テキストフィールドの枠線を設定
        for field in [urlField!, displayTextField!] {
            field.isBordered = true
            field.isBezeled = true
            field.bezelStyle = .roundedBezel
            field.drawsBackground = true
            field.backgroundColor = .textBackgroundColor
        }

        // URL フィールドでブックマークのドロップを受け付ける
        urlField.registerForDraggedTypes([bookmarkDragType])

        // テキスト変更通知でクリアボタンの表示を更新するため delegate を設定
        urlField.delegate = self

        // クリアボタンを URL フィールドの右端に重ねて配置（パネルのコンテンツビューに追加）
        setupClearButton()
    }

    /// URL フィールドのクリアボタンを設定する
    private func setupClearButton() {
        guard let contentView = linkPanel.contentView else { return }

        let button = NSButton(frame: .zero)
        if let image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear") {
            button.image = image
        }
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(clearURLField)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentTintColor = .tertiaryLabelColor
        contentView.addSubview(button)

        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: urlField.trailingAnchor, constant: -4),
            button.centerYAnchor.constraint(equalTo: urlField.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 16),
            button.heightAnchor.constraint(equalToConstant: 16)
        ])

        urlClearButton = button
    }

    /// URL フィールドのクリアボタンの表示・非表示を更新
    func updateClearButtonVisibility() {
        urlClearButton?.isHidden = urlField.stringValue.isEmpty
    }

    /// URL フィールドをクリア
    @objc private func clearURLField() {
        urlField.stringValue = ""
        updateClearButtonVisibility()
        linkPanel.makeFirstResponder(urlField)
    }

    // MARK: - NSWindowDelegate

    /// DroppableTextField 用のカスタムフィールドエディタを返す。
    /// ブックマークドロップ時にフィールドエディタが .string（表示名）を
    /// 挿入してしまう問題を回避する。
    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        if client is DroppableTextField {
            return bookmarkFieldEditor
        }
        return nil
    }

    // MARK: - Public Methods

    /// パネルを表示し、現在の選択範囲の情報で初期化する
    func showPanel() {
        loadPanelIfNeeded()
        guard let panel = linkPanel else { return }

        updateFieldsFromSelection()
        updateClearButtonVisibility()
        panel.orderFront(nil)
    }

    /// パネルが表示中かどうか
    var isPanelVisible: Bool {
        return isLoaded && (linkPanel?.isVisible ?? false)
    }

    // MARK: - IBActions

    /// 「Set Link」ボタン: 選択範囲にリンク属性を設定する
    @IBAction func setLink(_ sender: Any?) {
        guard let textView = currentTextView(),
              let textStorage = textView.textStorage else { return }

        let selectedRange = textView.selectedRange()
        let urlString = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        let displayText = displayTextField.stringValue

        guard !urlString.isEmpty else {
            NSSound.beep()
            return
        }

        if selectedRange.length == 0 && !displayText.isEmpty {
            // 選択範囲がない場合: 表示テキスト付きのリンクを挿入
            let linkAttrString = NSAttributedString(
                string: displayText,
                attributes: [.link: urlString]
            )
            textView.insertText(linkAttrString, replacementRange: selectedRange)
        } else if selectedRange.length > 0 {
            // 選択範囲がある場合: 選択範囲にリンク属性を設定
            let range = selectedRange
            if textView.shouldChangeText(in: range, replacementString: nil) {
                textStorage.beginEditing()
                // 表示テキストが異なる場合はテキストも置き換え
                let currentText = (textStorage.string as NSString).substring(with: range)
                if !displayText.isEmpty && displayText != currentText {
                    let linkAttrString = NSAttributedString(
                        string: displayText,
                        attributes: textStorage.attributes(at: range.location, effectiveRange: nil)
                            .merging([.link: urlString]) { _, new in new }
                    )
                    textStorage.replaceCharacters(in: range, with: linkAttrString)
                } else {
                    textStorage.addAttribute(.link, value: urlString, range: range)
                }
                textStorage.endEditing()
                textView.didChangeText()
            }
        } else {
            NSSound.beep()
            return
        }

        // リンク設定後にパネルを閉じる
        linkPanel?.orderOut(nil)
    }

    /// 「Delete」ボタン: 選択範囲からリンク属性を削除する
    @IBAction func deleteLink(_ sender: Any?) {
        guard let textView = currentTextView(),
              let textStorage = textView.textStorage else { return }

        let selectedRange = textView.selectedRange()
        guard selectedRange.length > 0 else {
            NSSound.beep()
            return
        }

        if textView.shouldChangeText(in: selectedRange, replacementString: nil) {
            textStorage.beginEditing()
            textStorage.removeAttribute(.link, range: selectedRange)
            textStorage.endEditing()
            textView.didChangeText()
        }

        urlField.stringValue = ""
        updateClearButtonVisibility()
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSTextField, field === urlField {
            updateClearButtonVisibility()
        }
    }

    // MARK: - Field Update

    /// 現在の選択範囲の情報でフィールドを更新する
    private func updateFieldsFromSelection() {
        guard let textView = currentTextView(),
              let textStorage = textView.textStorage else {
            urlField.stringValue = ""
            displayTextField.stringValue = ""
            return
        }

        let selectedRange = textView.selectedRange()

        // 表示テキスト: 選択範囲のテキスト
        if selectedRange.length > 0 {
            let selectedText = (textStorage.string as NSString).substring(with: selectedRange)
            displayTextField.stringValue = selectedText
        } else {
            displayTextField.stringValue = ""
        }

        // URL: 選択範囲に既存のリンク属性があればそれを表示
        if selectedRange.length > 0 {
            if let linkValue = textStorage.attribute(.link, at: selectedRange.location, effectiveRange: nil) {
                if let str = linkValue as? String {
                    urlField.stringValue = str
                } else if let url = linkValue as? URL {
                    urlField.stringValue = url.absoluteString
                } else if let url = linkValue as? NSURL {
                    urlField.stringValue = url.absoluteString ?? ""
                } else {
                    urlField.stringValue = ""
                }
            } else {
                urlField.stringValue = ""
            }
        } else {
            urlField.stringValue = ""
        }
    }

    // MARK: - Helpers

    /// 現在のメインドキュメントウィンドウの NSTextView を取得する
    private func currentTextView() -> NSTextView? {
        guard let document = currentDocument() else { return nil }
        return document.currentTextView
    }

    /// 現在のメインドキュメントを取得する
    private func currentDocument() -> Document? {
        for window in NSApp.orderedWindows {
            if isLoaded && window === linkPanel { continue }
            if window is NSPanel { continue }
            if let windowController = window.windowController,
               let document = windowController.document as? Document {
                return document
            }
        }
        return nil
    }
}

// MARK: - Bookmark Drop Field Editor

/// ブックマークドロップを正しく処理するカスタムフィールドエディタ。
/// NSTextField のフィールドエディタとして使用し、ブックマークドラッグ時に
/// .string（表示名）ではなくブックマーク UUID を設定する。
class BookmarkDropFieldEditor: NSTextView {

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pboard = sender.draggingPasteboard
        if let uuid = pboard.string(forType: bookmarkDragType) {
            // フィールドエディタの delegate は NSTextField 自身
            if let textField = delegate as? DroppableTextField {
                textField.stringValue = uuid
                textField.onDrop?(uuid)
                // クリアボタンの表示を更新
                LinkPanelController.shared.updateClearButtonVisibility()
                return true
            }
        }
        return super.performDragOperation(sender)
    }
}

// MARK: - Droppable Text Field

/// ブックマークのドラッグ＆ドロップを受け付ける NSTextField サブクラス。
/// URL フィールドでブックマークパネルからのドロップを処理する。
class DroppableTextField: NSTextField {

    /// ドロップ完了時に呼ばれるコールバック
    var onDrop: ((String) -> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()
        registerForDraggedTypes([bookmarkDragType])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        if pboard.string(forType: bookmarkDragType) != nil {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        if pboard.string(forType: bookmarkDragType) != nil {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pboard = sender.draggingPasteboard
        if let uuid = pboard.string(forType: bookmarkDragType) {
            stringValue = uuid
            onDrop?(uuid)
            LinkPanelController.shared.updateClearButtonVisibility()
            return true
        }
        return super.performDragOperation(sender)
    }
}

// MARK: - Droppable Text Field Cell

/// クリアボタン用の右パディングを確保する NSTextFieldCell サブクラス。
/// テキストの描画・編集領域を右側に縮めて、クリアボタンと重ならないようにする。
class DroppableTextFieldCell: NSTextFieldCell {

    /// クリアボタン用の右パディング
    private let rightPadding: CGFloat = 20

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var result = super.drawingRect(forBounds: rect)
        result.size.width -= rightPadding
        return result
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        var r = rect
        r.size.width -= rightPadding
        super.edit(withFrame: r, in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        var r = rect
        r.size.width -= rightPadding
        super.select(withFrame: r, in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}
