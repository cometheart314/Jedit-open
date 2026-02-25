//
//  LinkPanelController.swift
//  Jedit-open
//
//  カスタムリンクパネルのコントローラー。
//  テキスト選択範囲にリンク属性を設定/削除する。
//  ブックマークパネルからのドラッグ＆ドロップや、
//  ブックマーク一覧ポップアップからの選択でアンカーリンクを設定可能。
//

import Cocoa

/// ブックマークのドラッグ＆ドロップ用パステボードタイプ（BookmarkPanelController と共有）
private let bookmarkDragType = NSPasteboard.PasteboardType("jp.co.artman21.Jedit-open.bookmark")

/// カスタムリンクパネルのコントローラー。
/// シングルトンとして管理され、テキスト選択範囲にリンク属性を設定する。
class LinkPanelController: NSObject, NSTextFieldDelegate {

    // MARK: - Singleton

    static let shared = LinkPanelController()

    // MARK: - IBOutlets

    /// LinkPanel.xib からロードされるフローティングパネル
    @IBOutlet var linkPanel: NSPanel!

    /// URL / アンカー ID 入力フィールド
    @IBOutlet var urlField: NSTextField!

    /// 表示テキストフィールド
    @IBOutlet var displayTextField: NSTextField!

    /// ブックマーク一覧ポップアップボタン
    @IBOutlet var bookmarkPopUpButton: NSPopUpButton!

    /// 「Set Link」ボタン
    @IBOutlet var setLinkButton: NSButton!

    /// 「Delete」ボタン
    @IBOutlet var deleteLinkButton: NSButton!

    // MARK: - Properties

    /// パネルがロード済みかどうか
    private var isLoaded = false

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

        // ブックマークポップアップを pullDown モードに設定
        // （先頭項目がボタンタイトルとして常に表示される）
        bookmarkPopUpButton.pullsDown = true

        // URL フィールドでブックマークのドロップを受け付ける
        urlField.registerForDraggedTypes([bookmarkDragType])

        // ウィンドウ切り替え監視（ブックマーク一覧の更新用）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentWindowDidChange(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentWindowDidChange(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    // MARK: - Public Methods

    /// パネルを表示し、現在の選択範囲の情報で初期化する
    func showPanel() {
        loadPanelIfNeeded()
        guard let panel = linkPanel else { return }

        updateFieldsFromSelection()
        updateBookmarkPopUp()
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
    }

    /// ブックマークポップアップから選択された時
    @IBAction func bookmarkPopUpChanged(_ sender: Any?) {
        guard let popup = bookmarkPopUpButton,
              let selectedItem = popup.selectedItem,
              let uuid = selectedItem.representedObject as? String else { return }

        urlField.stringValue = uuid

        // ポップアップを先頭項目（ラベル）に戻す
        popup.selectItem(at: 0)
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

    /// ブックマークポップアップの内容を更新する
    private func updateBookmarkPopUp() {
        guard let popup = bookmarkPopUpButton else { return }

        popup.removeAllItems()

        // メニューが nil の場合は明示的に作成
        if popup.menu == nil {
            popup.menu = NSMenu()
        }

        // 先頭にタイトル項目（pullDown モードではボタンに常に表示される）
        popup.addItem(withTitle: NSLocalizedString("Bookmarks", comment: "Link panel bookmark popup label"))

        guard let document = currentDocument() else { return }

        let root = document.rootBookmark
        guard !root.childBookmarks.isEmpty else { return }
        guard let menu = popup.menu else { return }

        menu.addItem(NSMenuItem.separator())

        // ブックマークを再帰的に追加
        addBookmarksToPopUp(root.childBookmarks, menu: menu, indent: 0)
    }

    /// ブックマークをポップアップメニューに再帰的に追加する
    private func addBookmarksToPopUp(_ bookmarks: [Bookmark], menu: NSMenu, indent: Int) {
        for bookmark in bookmarks {
            let prefix = String(repeating: "  ", count: indent)
            let item = NSMenuItem(
                title: prefix + bookmark.displayName,
                action: #selector(bookmarkMenuItemSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = bookmark.uuid
            menu.addItem(item)

            // 子ブックマークを再帰的に追加
            if !bookmark.childBookmarks.isEmpty {
                addBookmarksToPopUp(bookmark.childBookmarks, menu: menu, indent: indent + 1)
            }
        }
    }

    /// ブックマークメニュー項目が選択された時
    @objc private func bookmarkMenuItemSelected(_ sender: NSMenuItem) {
        guard let uuid = sender.representedObject as? String else { return }
        urlField.stringValue = uuid
    }

    // MARK: - Drag & Drop Support for URL Field

    /// URL フィールドへのブックマークドロップを処理するため、
    /// NSDraggingDestination をカスタムビューではなくコントローラーレベルで処理する。
    /// urlField に対して draggingEntered / performDragOperation を呼び出すため、
    /// カスタム NSTextField サブクラスを使うか、パネル自体で処理する。
    ///
    /// ここではパネルのコンテンツビューレベルでドロップを受け付ける。

    // MARK: - Window Notifications

    @objc private func documentWindowDidChange(_ notification: Notification) {
        guard isPanelVisible else { return }
        guard let window = notification.object as? NSWindow,
              !(window is NSPanel) else { return }
        updateBookmarkPopUp()
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

// MARK: - Droppable Text Field

/// ブックマークのドラッグ＆ドロップを受け付ける NSTextField サブクラス。
/// URL フィールドでブックマークパネルからのドロップを処理する。
class DroppableTextField: NSTextField {

    /// ドロップ完了時に呼ばれるコールバック
    var onDrop: ((String) -> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()
        registerForDraggedTypes([
            NSPasteboard.PasteboardType("jp.co.artman21.Jedit-open.bookmark")
        ])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        if pboard.string(forType: NSPasteboard.PasteboardType("jp.co.artman21.Jedit-open.bookmark")) != nil {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        if pboard.string(forType: NSPasteboard.PasteboardType("jp.co.artman21.Jedit-open.bookmark")) != nil {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pboard = sender.draggingPasteboard
        if let uuid = pboard.string(forType: NSPasteboard.PasteboardType("jp.co.artman21.Jedit-open.bookmark")) {
            stringValue = uuid
            onDrop?(uuid)
            return true
        }
        return super.performDragOperation(sender)
    }
}
