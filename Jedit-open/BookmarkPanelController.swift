//
//  BookmarkPanelController.swift
//  Jedit-open
//
//  ブックマークパネルのコントローラー。
//  BookmarkPanel.xib から NSPanel をロードし、NSOutlineView でブックマークツリーを表示する。
//  DocumentInfoPanelController と同じシングルトン・フローティングパネルパターンを使用。
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

/// ブックマークのドラッグ＆ドロップ用パステボードタイプ
private let bookmarkDragType = NSPasteboard.PasteboardType("jp.co.artman21.Jedit-open.bookmark")

/// ブックマークパネルのコントローラー。
/// シングルトンとして管理され、最前面ドキュメントのブックマークツリーを表示する。
class BookmarkPanelController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate {

    // MARK: - Singleton

    static let shared = BookmarkPanelController()

    // MARK: - IBOutlets

    /// BookmarkPanel.xib からロードされるフローティングパネル
    @IBOutlet var bookmarkPanel: NSPanel!

    /// ブックマークツリーを表示するアウトラインビュー
    @IBOutlet var bookmarkOutlineView: NSOutlineView!

    /// 追加（+）ボタン
    @IBOutlet var addButton: NSButton!

    /// 削除（-）ボタン
    @IBOutlet var deleteButton: NSButton!

    /// 左矢印ボタン（昇格：親レベルに移動）
    @IBOutlet var leftArrowButton: NSButton!

    /// 右矢印ボタン（降格：前の兄弟の子に移動）
    @IBOutlet var rightArrowButton: NSButton!

    /// アクションポップアップボタン
    @IBOutlet var actionPopUpButton: NSPopUpButton!

    // MARK: - Properties

    /// パネルがロード済みかどうか
    private var isLoaded = false

    /// リロード中フラグ（選択変更通知の抑制に使用）
    private var isReloading = false

    /// 現在表示中のルートブックマーク（データソースの一貫性を保つために強参照で保持）
    private var displayedRootBookmark: Bookmark?

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Panel Loading

    /// XIB からパネルをロード
    private func loadPanelIfNeeded() {
        guard !isLoaded else { return }

        let nibName = "BookmarkPanel"
        guard Bundle.main.loadNibNamed(nibName, owner: self, topLevelObjects: nil) else {
            print("Failed to load \(nibName).xib")
            return
        }

        isLoaded = true

        // パネル設定
        bookmarkPanel.becomesKeyOnlyIfNeeded = false
        bookmarkPanel.level = .floating
        bookmarkPanel.isReleasedWhenClosed = false

        // アウトラインビュー設定
        bookmarkOutlineView.dataSource = self
        bookmarkOutlineView.delegate = self
        bookmarkOutlineView.doubleAction = nil

        // ドラッグ＆ドロップの設定
        bookmarkOutlineView.registerForDraggedTypes([bookmarkDragType, .string])
        bookmarkOutlineView.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        bookmarkOutlineView.setDraggingSourceOperationMask(.copy, forLocal: false)

        // アクションポップアップメニューを設定
        setupActionPopUpMenu()

        // ウィンドウ切り替えの通知を監視
        // didBecomeMainNotification だけでは、パネルがキーウィンドウの時に
        // 書類ウィンドウが既にメインだと通知が発火しないケースがある。
        // didBecomeKeyNotification も監視することで確実に書類切替を検出する。
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    // MARK: - Public Methods

    /// パネルを表示/非表示（トグル動作）
    func showPanel() {
        loadPanelIfNeeded()
        guard let panel = bookmarkPanel else { return }

        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            reloadOutlineView()
            panel.orderFront(nil)
        }
    }

    /// パネルが表示されているかどうか
    var isPanelVisible: Bool {
        return isLoaded && (bookmarkPanel?.isVisible ?? false)
    }

    /// パネルを閉じる
    func closePanel() {
        guard isLoaded, let panel = bookmarkPanel, panel.isVisible else { return }
        panel.orderOut(nil)
        displayedRootBookmark = nil
    }

    /// アウトラインビューを再読み込み
    /// 同一ドキュメント内のリロードでは選択状態を保存・復元する。
    /// ドキュメント切替時は旧ブックマークが新ツリーに存在しないため、選択は自然にクリアされる。
    /// - Parameter document: 表示対象のドキュメント。nil の場合は currentDocument() を使用。
    ///   通知ハンドラからは通知のウィンドウのドキュメントを直接渡すことで、
    ///   NSApp.orderedWindows の順序に依存しない正確な切替を行う。
    func reloadOutlineView(for document: Document? = nil) {
        guard isLoaded, let outlineView = bookmarkOutlineView else { return }
        isReloading = true

        // リロード前の選択を保存（Bookmark オブジェクト参照）
        let previouslySelected = selectedBookmarks()

        let targetDocument = document ?? currentDocument()
        displayedRootBookmark = targetDocument?.rootBookmark
        outlineView.reloadData()

        // ブックマーク非対応書類（md/Word/ODT）ではUI要素を無効化
        let isEnabled = !(targetDocument?.isBookmarkUnsupported ?? false)
        addButton?.isEnabled = isEnabled
        deleteButton?.isEnabled = isEnabled
        leftArrowButton?.isEnabled = isEnabled
        rightArrowButton?.isEnabled = isEnabled
        actionPopUpButton?.isEnabled = isEnabled
        outlineView.isEnabled = isEnabled

        // 選択を復元（同一ドキュメントの場合のみ有効）
        if !previouslySelected.isEmpty {
            var rowIndexes = IndexSet()
            for bookmark in previouslySelected {
                let row = outlineView.row(forItem: bookmark)
                if row >= 0 {
                    rowIndexes.insert(row)
                }
            }
            if !rowIndexes.isEmpty {
                outlineView.selectRowIndexes(rowIndexes, byExtendingSelection: false)
            }
        }

        isReloading = false
    }

    /// 現在選択されているブックマークを返す（単一選択用）
    func selectedBookmark() -> Bookmark? {
        let row = bookmarkOutlineView?.selectedRow ?? -1
        guard row >= 0 else { return nil }
        return bookmarkOutlineView?.item(atRow: row) as? Bookmark
    }

    /// 現在選択されている全ブックマークを返す（複数選択対応）
    func selectedBookmarks() -> [Bookmark] {
        guard let outlineView = bookmarkOutlineView else { return [] }
        return outlineView.selectedRowIndexes.compactMap { row in
            outlineView.item(atRow: row) as? Bookmark
        }
    }

    // MARK: - IBActions

    /// ブックマーク追加ボタン
    @IBAction func addBookmark(_ sender: Any?) {
        guard let document = currentDocument() else { return }
        // パネルを表示していない場合は表示
        if !isPanelVisible {
            showPanel()
        }
        document.bookmarkSelection(sender)
    }

    /// ブックマーク削除ボタン（複数選択対応）
    @IBAction func deleteBookmark(_ sender: Any?) {
        let bookmarks = selectedBookmarks()
        guard !bookmarks.isEmpty,
              let document = currentDocument() else { return }

        // 選択中のブックマークとその子孫を全て削除
        for bookmark in bookmarks {
            // 他の選択項目の子孫でない場合のみ処理（二重削除を防ぐ）
            let isDescendantOfAnotherSelected = bookmarks.contains { other in
                other !== bookmark && other.isAncestor(bookmark)
            }
            guard !isDescendantOfAnotherSelected else { continue }

            // textStorage からアンカー属性を削除（子孫も含む）
            removeAnchorsRecursively(bookmark, from: document)

            // ツリーから削除
            bookmark.removeFromParent()
        }

        reloadOutlineView()
        document.updateChangeCount(.changeDone)
    }

    /// ブックマークとその子孫のアンカーを再帰的に削除
    private func removeAnchorsRecursively(_ bookmark: Bookmark, from document: Document) {
        document.removeAnchor(identifier: bookmark.uuid)
        for child in bookmark.childBookmarks {
            removeAnchorsRecursively(child, from: document)
        }
    }

    /// 左矢印ボタン（昇格：親レベルに移動）複数選択対応
    @IBAction func moveLeft(_ sender: Any?) {
        let bookmarks = selectedBookmarks()
        guard !bookmarks.isEmpty else { return }

        // 同じ親を持つ項目のみ処理（全て同じ親で、かつ昇格可能であること）
        guard let parent = bookmarks.first?.parentBookmark,
              let grandparent = parent.parentBookmark else { return }
        guard bookmarks.allSatisfy({ $0.parentBookmark === parent }) else { return }

        // 親の childBookmarks 内のインデックス順にソート
        let sorted = bookmarks.sorted { a, b in
            let ai = parent.childBookmarks.firstIndex(where: { $0 === a }) ?? 0
            let bi = parent.childBookmarks.firstIndex(where: { $0 === b }) ?? 0
            return ai < bi
        }

        // 全て親から削除してから、grandparent の parent の後に順番に挿入
        for bookmark in sorted {
            bookmark.removeFromParent()
        }
        var afterSibling: Bookmark = parent
        for bookmark in sorted {
            grandparent.insertChild(bookmark, after: afterSibling)
            afterSibling = bookmark
        }

        reloadOutlineView()
        selectBookmarks(sorted)
        currentDocument()?.updateChangeCount(.changeDone)
    }

    /// 右矢印ボタン（降格：前の兄弟の子に移動）複数選択対応
    @IBAction func moveRight(_ sender: Any?) {
        let bookmarks = selectedBookmarks()
        guard !bookmarks.isEmpty else { return }

        // 同じ親を持つ項目のみ処理
        guard let parent = bookmarks.first?.parentBookmark else { return }
        guard bookmarks.allSatisfy({ $0.parentBookmark === parent }) else { return }

        // 親の childBookmarks 内のインデックス順にソート
        let sorted = bookmarks.sorted { a, b in
            let ai = parent.childBookmarks.firstIndex(where: { $0 === a }) ?? 0
            let bi = parent.childBookmarks.firstIndex(where: { $0 === b }) ?? 0
            return ai < bi
        }

        // 先頭項目の直前の兄弟が新しい親になる
        guard let firstIndex = parent.childBookmarks.firstIndex(where: { $0 === sorted.first }),
              firstIndex > 0 else { return }
        let newParent = parent.childBookmarks[firstIndex - 1]

        // 選択項目が newParent 自体を含んでいないことを確認
        guard !sorted.contains(where: { $0 === newParent }) else { return }

        // 全て親から削除してから、新しい親の末尾に順番に追加
        for bookmark in sorted {
            bookmark.removeFromParent()
        }
        for bookmark in sorted {
            newParent.addChild(bookmark)
        }

        reloadOutlineView()
        bookmarkOutlineView?.expandItem(newParent)
        selectBookmarks(sorted)
        currentDocument()?.updateChangeCount(.changeDone)
    }

    // MARK: - Action Popup Menu

    /// アクションポップアップメニューを設定
    private func setupActionPopUpMenu() {
        guard let popup = actionPopUpButton else { return }
        popup.pullsDown = true
        popup.removeAllItems()

        // 先頭にアイコンのみの項目（タイトル空）— pullsDown モードでは常にこの項目が表示される
        popup.addItem(withTitle: "")
        popup.item(at: 0)?.image = NSImage(named: NSImage.actionTemplateName)

        // メニュー項目を追加
        let menu = popup.menu!

        let expandAllItem = NSMenuItem(title: "Expand All".localized, action: #selector(expandAll(_:)), keyEquivalent: "")
        expandAllItem.target = self
        menu.addItem(expandAllItem)

        let collapseAllItem = NSMenuItem(title: "Collapse All".localized, action: #selector(collapseAll(_:)), keyEquivalent: "")
        collapseAllItem.target = self
        menu.addItem(collapseAllItem)

        menu.addItem(NSMenuItem.separator())

        let sortByNameItem = NSMenuItem(title: "Sort by Name".localized, action: #selector(sortByName(_:)), keyEquivalent: "")
        sortByNameItem.target = self
        menu.addItem(sortByNameItem)

        let sortByLocationItem = NSMenuItem(title: "Sort by Location".localized, action: #selector(sortByLocation(_:)), keyEquivalent: "")
        sortByLocationItem.target = self
        menu.addItem(sortByLocationItem)

        menu.addItem(NSMenuItem.separator())

        let resetStructureItem = NSMenuItem(title: "Reset Structure".localized, action: #selector(resetStructure(_:)), keyEquivalent: "")
        resetStructureItem.target = self
        menu.addItem(resetStructureItem)

        let clearAllItem = NSMenuItem(title: "Clear All".localized, action: #selector(clearAll(_:)), keyEquivalent: "")
        clearAllItem.target = self
        menu.addItem(clearAllItem)

        menu.addItem(NSMenuItem.separator())

        let importFromFindItem = NSMenuItem(title: "Import from Find Results".localized, action: #selector(importFromFindResults(_:)), keyEquivalent: "")
        importFromFindItem.target = self
        menu.addItem(importFromFindItem)
    }

    @objc private func expandAll(_ sender: Any?) {
        bookmarkOutlineView?.expandItem(nil, expandChildren: true)
    }

    @objc private func collapseAll(_ sender: Any?) {
        bookmarkOutlineView?.collapseItem(nil, collapseChildren: true)
    }

    @objc private func sortByName(_ sender: Any?) {
        guard let document = currentDocument() else { return }
        document.rootBookmark.sortByName()
        reloadOutlineView()
        document.updateChangeCount(.changeDone)
    }

    @objc private func sortByLocation(_ sender: Any?) {
        guard let document = currentDocument() else { return }
        document.refreshBookmarkRanges()
        document.rootBookmark.sortByLocation()
        reloadOutlineView()
        document.updateChangeCount(.changeDone)
    }

    /// ブックマークツリーを textStorage のアンカーから再構築
    @objc private func resetStructure(_ sender: Any?) {
        guard let document = currentDocument() else { return }

        let root = document.rootBookmark
        root.childBookmarks.removeAll()

        let textStorage = document.textStorage
        let fullRange = NSRange(location: 0, length: textStorage.length)

        textStorage.enumerateAttribute(.anchor, in: fullRange, options: []) { value, attrRange, _ in
            if let anchorUUID = value as? String {
                let text = (textStorage.string as NSString).substring(with: attrRange)
                let name = text.components(separatedBy: .newlines).first?
                    .trimmingCharacters(in: .whitespaces) ?? "Bookmark"
                let bookmark = Bookmark(uuid: anchorUUID, displayName: name, range: attrRange)
                root.addChild(bookmark)
            }
        }

        reloadOutlineView()
        document.updateChangeCount(.changeDone)
    }

    /// 検索結果からブックマークを一括作成
    @objc private func importFromFindResults(_ sender: Any?) {
        guard let document = currentDocument() else {
            NSSound.beep()
            return
        }

        // EditorWindowController から検索結果を取得
        guard let editorWC = document.windowControllers.first as? EditorWindowController else {
            NSSound.beep()
            return
        }

        let ranges = editorWC.currentFindResultRanges
        guard !ranges.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No Find Results".localized
            alert.informativeText = "Perform a search first to import results as bookmarks.".localized
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK".localized)
            alert.runModal()
            return
        }

        let root = document.rootBookmark
        let textStorage = document.textStorage
        let string = textStorage.string as NSString
        var createdBookmarks: [Bookmark] = []

        for range in ranges {
            // 範囲を行全体に拡張
            let lineRange = string.lineRange(for: range)

            // 表示名を取得（マッチしたテキスト、最大50文字）
            let matchedText = string.substring(with: range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let maxLength = 50
            let displayName: String
            if matchedText.count > maxLength {
                displayName = String(matchedText.prefix(maxLength)) + "…"
            } else if matchedText.isEmpty {
                displayName = "Bookmark"
            } else {
                displayName = matchedText
            }

            // アンカーを作成（確認ダイアログなし）
            guard let uuid = document.createAnchor(for: lineRange, ask: false) else { continue }

            let bookmark = Bookmark(uuid: uuid, displayName: displayName, range: lineRange)
            root.addChild(bookmark)
            createdBookmarks.append(bookmark)
        }

        if !createdBookmarks.isEmpty {
            reloadOutlineView()
            document.updateChangeCount(.changeDone)
        }
    }

    /// 全ブックマークとアンカーをクリア
    @objc private func clearAll(_ sender: Any?) {
        guard let document = currentDocument() else { return }

        // 確認アラート
        let alert = NSAlert()
        alert.messageText = "Clear All Bookmarks?".localized
        alert.informativeText = "This will remove all bookmarks and their anchors from the document.".localized
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear All".localized)
        alert.addButton(withTitle: "Cancel".localized)

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        // 全アンカーを削除
        let textStorage = document.textStorage
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        textStorage.removeAttribute(.anchor, range: fullRange)
        textStorage.endEditing()

        // ブックマークツリーをクリア
        document.rootBookmark.childBookmarks.removeAll()

        reloadOutlineView()
        document.updateChangeCount(.changeDone)
    }

    // MARK: - Private Helpers

    /// アウトラインビューでブックマークを選択（外部公開用）
    /// リロード中フラグを立ててアンカーへのナビゲーションを抑制する。
    func selectBookmarkInOutlineView(_ bookmark: Bookmark) {
        isReloading = true
        selectBookmark(bookmark)
        isReloading = false
    }

    /// アウトラインビューでブックマークを選択
    private func selectBookmark(_ bookmark: Bookmark) {
        let row = bookmarkOutlineView.row(forItem: bookmark)
        if row >= 0 {
            bookmarkOutlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    /// アウトラインビューで複数ブックマークを選択
    private func selectBookmarks(_ bookmarks: [Bookmark]) {
        var rowIndexes = IndexSet()
        for bookmark in bookmarks {
            let row = bookmarkOutlineView.row(forItem: bookmark)
            if row >= 0 {
                rowIndexes.insert(row)
            }
        }
        if !rowIndexes.isEmpty {
            isReloading = true
            bookmarkOutlineView.selectRowIndexes(rowIndexes, byExtendingSelection: false)
            isReloading = false
        }
    }

    /// 最前面のドキュメントを取得（DocumentInfoPanelController と同じパターン）
    private func currentDocument() -> Document? {
        for window in NSApp.orderedWindows {
            if window === bookmarkPanel { continue }
            if window is NSPanel { continue }
            if let windowController = window.windowController,
               let document = windowController.document as? Document {
                return document
            }
        }
        return nil
    }

    // MARK: - Notifications

    /// ドキュメントウィンドウがメイン/キーになった時にアウトラインビューを更新
    /// didBecomeMainNotification と didBecomeKeyNotification の両方から呼ばれる。
    @objc private func documentWindowDidChange(_ notification: Notification) {
        guard isPanelVisible else { return }
        // ドキュメントウィンドウの場合のみ更新（パネル自体の通知は無視）
        if let window = notification.object as? NSWindow,
           !(window is NSPanel),
           let document = window.windowController?.document as? Document {
            // 表示中のドキュメントと同じ場合は不要なリロードを避ける
            if document.rootBookmark !== displayedRootBookmark {
                // 通知のウィンドウからドキュメントを直接渡す（NSApp.orderedWindows に依存しない）
                reloadOutlineView(for: document)
            }
        }
    }

    /// ドキュメントウィンドウが閉じられる時の処理
    @objc private func documentWindowWillClose(_ notification: Notification) {
        guard isPanelVisible else { return }
        let closingWindow = notification.object as? NSWindow
        DispatchQueue.main.async { [weak self] in
            // 閉じるウィンドウ以外のドキュメントウィンドウを探す
            var remainingDocument: Document?
            for window in NSApp.orderedWindows {
                if window is NSPanel { continue }
                if window === closingWindow { continue }
                if let doc = window.windowController?.document as? Document {
                    remainingDocument = doc
                    break
                }
            }
            if let document = remainingDocument {
                self?.reloadOutlineView(for: document)
            } else {
                self?.closePanel()
            }
        }
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            // ルートレベル: displayedRootBookmark の子の数を返す
            return displayedRootBookmark?.childBookmarks.count ?? 0
        }
        if let bookmark = item as? Bookmark {
            return bookmark.childBookmarks.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let bookmark = item as? Bookmark {
            return !bookmark.childBookmarks.isEmpty
        }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return displayedRootBookmark?.childBookmarks[index] as Any
        }
        if let bookmark = item as? Bookmark {
            return bookmark.childBookmarks[index]
        }
        return NSNull()
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let bookmark = item as? Bookmark else { return nil }

        let cellIdentifier = NSUserInterfaceItemIdentifier("AutomaticTableColumnIdentifier.0")
        let cellView = outlineView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView
        cellView?.textField?.stringValue = bookmark.displayName
        cellView?.textField?.isEditable = true
        cellView?.textField?.delegate = self
        return cellView
    }

    /// アウトラインビューの選択変更時にドキュメント内のアンカーに移動
    func outlineViewSelectionDidChange(_ notification: Notification) {
        // リロード中（書類切替時など）は選択変更を無視
        guard !isReloading else { return }
        // Optionキーを押しながらクリックした場合はジャンプせず選択のみ
        guard !NSEvent.modifierFlags.contains(.option) else { return }
        guard let bookmark = selectedBookmark(),
              let document = currentDocument() else { return }
        document.selectAnchor(identifier: bookmark.uuid)
        // selectAnchor が書類ウィンドウにフォーカスを移すため、パネルのキー状態を復元
        bookmarkPanel?.makeKey()
    }

    // MARK: - インライン編集（NSTextFieldDelegate）

    /// テキストフィールドの編集完了時にブックマークの displayName を更新する
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField,
              let outlineView = bookmarkOutlineView else { return }

        let row = outlineView.row(for: textField)
        guard row >= 0,
              let bookmark = outlineView.item(atRow: row) as? Bookmark else { return }

        let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != bookmark.displayName else {
            // 空文字の場合は元に戻す
            textField.stringValue = bookmark.displayName
            return
        }

        bookmark.displayName = newName

        // ドキュメントの変更を記録
        if let document = currentDocument() {
            document.updateChangeCount(.changeDone)
        }
    }

    // MARK: - Drag & Drop (NSOutlineViewDataSource)

    /// ドラッグ開始: ドラッグ対象のブックマークの UUID をパステボードに書き込む。
    /// パネル内ドラッグ用に bookmarkDragType、書類へのドロップ用に RTF データも書き込む。
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let bookmark = item as? Bookmark else { return nil }
        let pasteboardItem = NSPasteboardItem()

        // パネル内の並べ替え用
        pasteboardItem.setString(bookmark.uuid, forType: bookmarkDragType)

        // 書類へのドロップ用: ブックマーク名にアンカーリンクを付けた RTF データ
        let linkText = NSAttributedString(
            string: bookmark.displayName,
            attributes: [.link: bookmark.uuid]
        )
        if let rtfData = try? linkText.data(
            from: NSRange(location: 0, length: linkText.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) {
            pasteboardItem.setData(rtfData, forType: .rtf)
        }

        // プレーンテキストのフォールバック
        pasteboardItem.setString(bookmark.displayName, forType: .string)

        return pasteboardItem
    }

    /// ドロップ先のバリデーション
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        let pasteboard = info.draggingPasteboard

        // 内部ブックマークドラッグの場合
        if let pasteboardItem = pasteboard.pasteboardItems?.first,
           let draggedUUID = pasteboardItem.string(forType: bookmarkDragType),
           let root = displayedRootBookmark,
           let draggedBookmark = root.findBookmark(withUUID: draggedUUID) {

            let targetParent = item as? Bookmark ?? root

            // 自分自身の上にはドロップできない
            if targetParent === draggedBookmark { return [] }

            // 自分の子孫にはドロップできない（循環参照を防ぐ）
            if targetParent.isAncestor(draggedBookmark) { return [] }

            return .move
        }

        // 書類テキストビューからの文字列ドラッグの場合
        if pasteboard.availableType(from: [.string]) != nil,
           info.draggingSource is NSTextView,
           currentDocument() != nil {
            return .copy
        }

        return []
    }

    /// ドロップ受入: ブックマークの移動、または書類テキストからのブックマーク作成
    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let pasteboard = info.draggingPasteboard

        // 内部ブックマークドラッグの場合: 移動処理
        if let pasteboardItem = pasteboard.pasteboardItems?.first,
           let draggedUUID = pasteboardItem.string(forType: bookmarkDragType),
           let root = displayedRootBookmark,
           let draggedBookmark = root.findBookmark(withUUID: draggedUUID) {
            return acceptBookmarkDrop(draggedBookmark, targetItem: item, childIndex: index, outlineView: outlineView)
        }

        // 書類テキストビューからの文字列ドラッグの場合: ブックマーク作成
        if pasteboard.availableType(from: [.string]) != nil,
           let textView = info.draggingSource as? NSTextView,
           let document = currentDocument() {
            return acceptTextDrop(from: textView, document: document, targetItem: item, childIndex: index, outlineView: outlineView)
        }

        return false
    }

    /// 内部ブックマークのドロップ処理（並び替え）
    private func acceptBookmarkDrop(_ draggedBookmark: Bookmark, targetItem item: Any?, childIndex index: Int, outlineView: NSOutlineView) -> Bool {
        guard let root = displayedRootBookmark else { return false }
        let targetParent = item as? Bookmark ?? root

        // 同じ親内での移動の場合、削除後のインデックスを補正する
        let oldParent = draggedBookmark.parentBookmark
        var adjustedIndex = index

        if let oldParent = oldParent, oldParent === targetParent,
           let oldIndex = oldParent.childBookmarks.firstIndex(where: { $0 === draggedBookmark }) {
            if adjustedIndex > oldIndex {
                adjustedIndex -= 1
            }
        }

        // 元の位置から削除
        draggedBookmark.removeFromParent()

        // 新しい位置に挿入
        if adjustedIndex >= 0 {
            targetParent.insertChild(draggedBookmark, at: adjustedIndex)
        } else {
            targetParent.addChild(draggedBookmark)
        }

        // アウトラインビューを更新して移動先を選択
        reloadOutlineView()
        if targetParent !== root {
            outlineView.expandItem(targetParent)
        }
        selectBookmark(draggedBookmark)

        currentDocument()?.updateChangeCount(.changeDone)
        return true
    }

    /// 書類テキストからのドロップ処理（ブックマーク作成）
    private func acceptTextDrop(from textView: NSTextView, document: Document, targetItem item: Any?, childIndex index: Int, outlineView: NSOutlineView) -> Bool {
        let selectedRange = textView.selectedRange()

        // 選択範囲からブックマークを作成
        guard let bookmark = document.createBookmarkFromRange(selectedRange) else {
            NSSound.beep()
            return false
        }

        let root = document.rootBookmark
        let targetParent = item as? Bookmark ?? root

        // ドロップ位置に挿入
        if index >= 0 {
            targetParent.insertChild(bookmark, at: index)
        } else {
            targetParent.addChild(bookmark)
        }

        // アウトラインビューを更新して新しいブックマークを選択
        reloadOutlineView()
        if targetParent !== root {
            outlineView.expandItem(targetParent)
        }
        selectBookmarkInOutlineView(bookmark)

        return true
    }
}
