//
//  EditorWindowController+Toolbar.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/26.
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

extension EditorWindowController {

    // MARK: - Toolbar Customization

    /// ツールバーの表示状態を返す
    var isToolbarVisible: Bool {
        return window?.toolbar != nil
    }

    /// ツールバーの表示/非表示を切り替える
    /// - Parameter updatePreset: presetData に反映するかどうか（初期ロード時は false）
    internal func setToolbarVisible(_ visible: Bool, updatePreset: Bool = true) {
        guard let window = self.window else { return }
        if visible {
            // cachedToolbar からウィンドウに再設定
            if window.toolbar == nil, let toolbar = cachedToolbar {
                window.toolbar = toolbar
            }
        } else {
            // ウィンドウからツールバーを外す（インスタンスは cachedToolbar で保持）
            if window.toolbar != nil {
                window.toolbar = nil
            }
        }
        if updatePreset {
            textDocument?.presetData?.view.showToolBar = visible
            textDocument?.presetDataEdited = true
        }
    }

    @IBAction func toggleToolbarVisibility(_ sender: Any?) {
        setToolbarVisible(!isToolbarVisible)
    }

    @IBAction func showToolbarCustomizationPalette(_ sender: Any?) {
        // ツールバーが非表示なら表示する
        if !isToolbarVisible {
            setToolbarVisible(true)
        }
        guard let toolbar = window?.toolbar else { return }
        toolbar.runCustomizationPalette(sender)
    }

    // MARK: - Inspector Bar Actions

    @IBAction func toggleInspectorBar(_ sender: Any?) {
        isInspectorBarVisible = !isInspectorBarVisible
        updateInspectorBarVisibility()

        // presetData に反映
        textDocument?.presetData?.view.showInspectorBar = isInspectorBarVisible
        markDocumentAsEdited()
    }

    internal func updateInspectorBarVisibility() {
        switch displayMode {
        case .continuous:
            // scrollView1のtextViewを更新
            if let scrollView = scrollView1,
               let textView = scrollView.documentView as? NSTextView {
                textView.usesInspectorBar = isInspectorBarVisible
            }

            // scrollView2のtextViewを更新（splitViewが表示されている場合）
            if let scrollView = scrollView2,
               !scrollView.isHidden,
               let textView = scrollView.documentView as? NSTextView {
                textView.usesInspectorBar = isInspectorBarVisible
            }

        case .page:
            // ページモード時は全てのtextViewを更新
            for textView in textViews1 {
                textView.usesInspectorBar = isInspectorBarVisible
            }
            for textView in textViews2 {
                textView.usesInspectorBar = isInspectorBarVisible
            }
        }
    }

    // MARK: - Toolbar Encoding Item

    /// ツールバーにエンコーディング表示アイテムをセットアップ
    internal func setupEncodingToolbarItem() {
        guard let window = self.window else { return }

        // ウィンドウごとにユニークな識別子を生成
        // NSToolbarは同じ識別子を持つツールバー間で設定を共有するため、
        // ドキュメントごとに異なる設定を保持するにはユニークな識別子が必要
        let uniqueID = UUID().uuidString
        let toolbarIdentifier = NSToolbar.Identifier("JeditDocumentToolbar-\(uniqueID)")
        let toolbar = NSToolbar(identifier: toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        // showsBaselineSeparator is deprecated in macOS 11+; NSWindow.titlebarSeparatorStyle is used instead
        if #available(macOS 11.0, *) {
            // titlebarSeparatorStyle is set on the window, not toolbar
        } else {
            toolbar.showsBaselineSeparator = false
        }
        toolbar.autosavesConfiguration = false  // 書類ごとに保存するため無効化
        toolbar.allowsUserCustomization = true

        // ウィンドウに設定し、cachedToolbarにも保持
        window.toolbar = toolbar
        cachedToolbar = toolbar

        // 保存されたツールバー設定を復元
        restoreToolbarConfiguration()

        // 初期表示を更新
        updateEncodingToolbarItem()
        updateLineEndingToolbarItem()

        // ツールバー変更通知を監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toolbarDidChange(_:)),
            name: NSNotification.Name("NSToolbarWillAddItemNotification"),
            object: toolbar
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toolbarDidChange(_:)),
            name: NSNotification.Name("NSToolbarDidRemoveItemNotification"),
            object: toolbar
        )
    }

    /// ツールバー変更時の通知ハンドラ
    @objc internal func toolbarDidChange(_ notification: Notification) {
        // 少し遅延させて、ツールバーの変更が完了してから保存
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.saveToolbarConfiguration()
        }
    }

    /// ツールバー設定を保存
    func saveToolbarConfiguration() {
        guard let toolbar = cachedToolbar else { return }
        let identifiers = toolbar.items.map { $0.itemIdentifier.rawValue }
        textDocument?.presetData?.view.toolbarItemIdentifiers = identifiers
        // displayMode を保存
        textDocument?.presetData?.view.toolbarDisplayMode = Int(toolbar.displayMode.rawValue)
        textDocument?.presetDataEdited = true
    }

    /// ツールバー設定を復元
    internal func restoreToolbarConfiguration() {
        guard let toolbar = cachedToolbar else { return }

        // displayMode を復元
        if let displayModeValue = textDocument?.presetData?.view.toolbarDisplayMode,
           let displayMode = NSToolbar.DisplayMode(rawValue: UInt(displayModeValue)) {
            toolbar.displayMode = displayMode
        }

        // ツールバー項目を復元
        guard let savedIdentifiers = textDocument?.presetData?.view.toolbarItemIdentifiers,
              !savedIdentifiers.isEmpty else {
            return
        }

        // 現在のツールバー項目を全て削除
        while toolbar.items.count > 0 {
            toolbar.removeItem(at: 0)
        }

        // 保存された順序で項目を挿入
        for (index, identifierString) in savedIdentifiers.enumerated() {
            let identifier = NSToolbarItem.Identifier(identifierString)
            toolbar.insertItem(withItemIdentifier: identifier, at: index)
        }
    }

    /// エンコーディングツールバーアイテムを作成（delegateから呼ばれる）
    internal func createEncodingToolbarItem() -> NSToolbarItem {
        // ポップアップボタン作成（EncodingPopUpButton でメニュー表示時に変換不能チェック）
        let popupButton = EncodingPopUpButton(frame: NSRect(x: 0, y: 0, width: 140, height: 22), pullsDown: false)
        popupButton.font = NSFont.systemFont(ofSize: 11)
        popupButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        populateEncodingPopup(popupButton)
        popupButton.target = self
        popupButton.action = #selector(encodingPopupChanged(_:))

        // ポップアップが開く瞬間に変換不能エンコーディングを disable するクロージャを設定
        popupButton.textForValidation = { [weak self] in
            return self?.textDocument?.textStorage.string
        }

        // リッチテキストの場合は無効化
        let isPlainText = textDocument?.documentType == .plain
        popupButton.isEnabled = isPlainText

        // 制約ベースのサイズ設定
        popupButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            popupButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            popupButton.widthAnchor.constraint(lessThanOrEqualToConstant: 180),
            popupButton.heightAnchor.constraint(equalToConstant: 22)
        ])

        // ツールバーアイテム作成
        let item = NSToolbarItem(itemIdentifier: Self.encodingToolbarItemIdentifier)
        item.label = "Encoding".localized
        item.paletteLabel = "Text Encoding".localized
        item.toolTip = "Document text encoding".localized
        item.view = popupButton

        self.encodingToolbarItem = item

        return item
    }

    /// エンコーディングポップアップメニューを構築
    internal func populateEncodingPopup(_ popup: NSPopUpButton) {
        // 現在のドキュメントエンコーディングを取得
        let currentEncoding = textDocument?.documentEncoding ?? .utf8

        // EncodingManagerを使用してポップアップを構築
        // 「自動」項目は不要、「カスタマイズ...」項目を追加
        EncodingManager.shared.setupPopUp(
            popup,
            selectedEncoding: currentEncoding,
            withDefaultEntry: false,
            includeCustomizeItem: true,
            target: self,
            action: #selector(showEncodingCustomizePanel(_:))
        )

    }

    /// エンコーディングカスタマイズパネルを表示
    @objc internal func showEncodingCustomizePanel(_ sender: Any?) {
        EncodingManager.shared.showPanel(sender)
        // パネルを閉じた後にポップアップを更新するため、通知を監視
        // EncodingManagerが更新されたら再構築
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.refreshEncodingPopup()
        }
    }

    /// エンコーディングポップアップを再構築
    internal func refreshEncodingPopup() {
        guard let popup = getEncodingPopupButton() else { return }
        populateEncodingPopup(popup)
    }

    /// エンコーディングリスト変更通知ハンドラ
    @objc internal func encodingsListDidChange(_ notification: Notification) {
        refreshEncodingPopup()
    }

    /// エンコーディングポップアップボタンを取得
    internal func getEncodingPopupButton() -> EncodingPopUpButton? {
        // まずキャッシュされたアイテムから取得を試みる
        if let popup = encodingToolbarItem?.view as? EncodingPopUpButton {
            return popup
        }
        // ツールバーから直接検索
        guard let toolbar = cachedToolbar else { return nil }
        for item in toolbar.items {
            if item.itemIdentifier == Self.encodingToolbarItemIdentifier,
               let popup = item.view as? EncodingPopUpButton {
                // キャッシュを更新
                self.encodingToolbarItem = item
                return popup
            }
        }
        return nil
    }

    /// エンコーディングツールバーアイテムを更新
    func updateEncodingToolbarItem() {
        guard let popup = getEncodingPopupButton() else { return }

        // リッチテキストの場合はエンコーディングポップアップを無効化
        let isPlainText = textDocument?.documentType == .plain
        popup.isEnabled = isPlainText

        // 現在のドキュメントエンコーディングを取得
        let encoding = textDocument?.documentEncoding ?? .utf8

        // ポップアップを再構築して選択を更新
        EncodingManager.shared.setupPopUp(
            popup,
            selectedEncoding: encoding,
            withDefaultEntry: false,
            includeCustomizeItem: true,
            target: self,
            action: #selector(showEncodingCustomizePanel(_:))
        )
        // 変換不能エンコーディングの disable は EncodingPopUpButton.willOpenMenu で行う
    }

    /// エンコーディングポップアップの変更ハンドラ
    @objc internal func encodingPopupChanged(_ sender: NSPopUpButton) {
        // リッチテキストの場合はエンコーディング変更を許可しない
        if textDocument?.documentType != .plain {
            updateEncodingToolbarItem()
            return
        }

        guard let selectedItem = sender.selectedItem else { return }

        // 「カスタマイズ...」が選択された場合
        if selectedItem.tag == EncodingManager.customizeEncodingsTag {
            showEncodingCustomizePanel(sender)
            // 選択を元に戻す
            updateEncodingToolbarItem()
            return
        }

        let newEncoding = String.Encoding(rawValue: UInt(selectedItem.tag))

        guard let document = textDocument else { return }

        // 現在のエンコーディングと同じ場合は何もしない
        if document.documentEncoding == newEncoding {
            return
        }

        // エンコーディングを変更
        changeDocumentEncoding(to: newEncoding)
    }

    /// ドキュメントのエンコーディングを変更
    internal func changeDocumentEncoding(to newEncoding: String.Encoding) {
        guard let document = textDocument,
              let window = self.window else { return }

        // 現在のテキストを新しいエンコーディングで再エンコードできるか確認
        let currentText = document.textStorage.string
        guard let data = currentText.data(using: newEncoding) else {
            // 変換できない場合はアラートをシートとして表示
            let alert = NSAlert()
            alert.messageText = "Cannot Convert".localized
            alert.informativeText = String(format: "The document contains characters that cannot be represented in %@.".localized, String.localizedName(of: newEncoding))
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK".localized)
            alert.beginSheetModal(for: window) { [weak self] _ in
                // ポップアップを元に戻す
                self?.updateEncodingToolbarItem()
            }
            return
        }

        // 再変換して確認（ラウンドトリップテスト）
        let reconverted = String(data: data, encoding: newEncoding)
        if reconverted != currentText {
            // ラウンドトリップできない場合はアラートをシートとして表示
            let alert = NSAlert()
            alert.messageText = "Encoding Warning".localized
            alert.informativeText = String(format: "Converting to %@ may result in data loss. Do you want to continue?".localized, String.localizedName(of: newEncoding))
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Convert".localized)
            alert.addButton(withTitle: "Cancel".localized)

            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    // 変換を実行
                    self?.applyEncodingChange(newEncoding, to: document)
                } else {
                    // キャンセル - ポップアップを元に戻す
                    self?.updateEncodingToolbarItem()
                }
            }
            return
        }

        // エンコーディングを変更（ラウンドトリップテストOKの場合）
        applyEncodingChange(newEncoding, to: document)
    }

    /// エンコーディング変更を適用
    internal func applyEncodingChange(_ newEncoding: String.Encoding, to document: Document) {
        document.documentEncoding = newEncoding
        document.updateChangeCount(.changeDone)

        #if DEBUG
        Swift.print("Encoding changed to: \(String.localizedName(of: newEncoding))")
        #endif
    }

    // MARK: - Toolbar Line Ending Item

    /// 改行コードツールバーアイテムを作成
    internal func createLineEndingToolbarItem() -> NSToolbarItem {
        // ポップアップボタン作成
        let popupButton = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 80, height: 22), pullsDown: false)
        popupButton.font = NSFont.systemFont(ofSize: 11)
        popupButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        populateLineEndingPopup(popupButton)
        popupButton.target = self
        popupButton.action = #selector(lineEndingPopupChanged(_:))

        // リッチテキストの場合は無効化
        let isPlainText = textDocument?.documentType == .plain
        popupButton.isEnabled = isPlainText

        // 制約ベースのサイズ設定
        popupButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            popupButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 70),
            popupButton.widthAnchor.constraint(lessThanOrEqualToConstant: 120),
            popupButton.heightAnchor.constraint(equalToConstant: 22)
        ])

        // ツールバーアイテム作成
        let item = NSToolbarItem(itemIdentifier: Self.lineEndingToolbarItemIdentifier)
        item.label = "Line Ending".localized
        item.paletteLabel = "Line Ending".localized
        item.toolTip = "Document line ending format".localized
        item.view = popupButton

        self.lineEndingToolbarItem = item

        return item
    }

    /// 改行コードポップアップメニューを構築
    internal func populateLineEndingPopup(_ popup: NSPopUpButton) {
        popup.removeAllItems()

        // 現在の改行コードを取得
        let currentLineEnding = textDocument?.lineEnding ?? .lf

        // 改行コードの選択肢を追加
        for lineEnding in LineEnding.allCases {
            popup.addItem(withTitle: lineEnding.shortDescription)
            popup.lastItem?.tag = lineEnding.rawValue
        }

        // 現在の改行コードを選択
        popup.selectItem(withTag: currentLineEnding.rawValue)
    }

    /// 改行コードポップアップボタンを取得
    internal func getLineEndingPopupButton() -> NSPopUpButton? {
        // まずキャッシュされたアイテムから取得を試みる
        if let popup = lineEndingToolbarItem?.view as? NSPopUpButton {
            return popup
        }
        // ツールバーから直接検索
        guard let toolbar = cachedToolbar else { return nil }
        for item in toolbar.items {
            if item.itemIdentifier == Self.lineEndingToolbarItemIdentifier,
               let popup = item.view as? NSPopUpButton {
                // キャッシュを更新
                self.lineEndingToolbarItem = item
                return popup
            }
        }
        return nil
    }

    /// 改行コードツールバーアイテムを更新
    func updateLineEndingToolbarItem() {
        guard let popup = getLineEndingPopupButton() else { return }

        // リッチテキストの場合は改行コードポップアップを無効化
        let isPlainText = textDocument?.documentType == .plain
        popup.isEnabled = isPlainText

        // 現在の改行コードを取得して選択を更新
        let lineEnding = textDocument?.lineEnding ?? .lf
        popup.selectItem(withTag: lineEnding.rawValue)
    }

    /// 改行コードポップアップの変更ハンドラ
    @objc internal func lineEndingPopupChanged(_ sender: NSPopUpButton) {
        // リッチテキストの場合は改行コード変更を許可しない
        if textDocument?.documentType != .plain {
            updateLineEndingToolbarItem()
            return
        }

        guard let selectedItem = sender.selectedItem,
              let newLineEnding = LineEnding(rawValue: selectedItem.tag),
              let document = textDocument else { return }

        // 現在の改行コードと同じ場合は何もしない
        if document.lineEnding == newLineEnding {
            return
        }

        // 改行コードを変更
        document.lineEnding = newLineEnding
        document.updateChangeCount(.changeDone)

        #if DEBUG
        Swift.print("Line ending changed to: \(newLineEnding.description)")
        #endif
    }

    // MARK: - Writing Progress Toolbar Item

    /// 執筆進捗ツールバーアイテムを作成
    internal func createWritingProgressToolbarItem() -> NSToolbarItem {
        let progressView = WritingProgressView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        progressView.target = self
        progressView.action = #selector(showWritingGoalPanel(_:))

        // 制約ベースのサイズ設定
        progressView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressView.widthAnchor.constraint(equalToConstant: 28),
            progressView.heightAnchor.constraint(equalToConstant: 28)
        ])

        let item = NSToolbarItem(itemIdentifier: Self.writingProgressToolbarItemIdentifier)
        item.label = "Writing Progress".localized
        item.paletteLabel = "Writing Progress".localized
        item.toolTip = "Writing Progress - Click to set goal".localized
        item.view = progressView

        self.writingProgressToolbarItem = item

        // 現在の目標設定で初期化
        updateWritingProgressDisplay()

        return item
    }

    /// 執筆進捗表示を更新
    func updateWritingProgressDisplay() {
        guard let progressView = getWritingProgressView() else { return }
        guard let document = textDocument else { return }

        let goal = document.presetData?.writingGoal
        let targetCount = goal?.targetCount ?? 0
        let countMethod = goal?.countMethod ?? 0

        if targetCount > 0 {
            progressView.isGoalSet = true
            let totalVisibleChars = document.statistics.totalVisibleChars

            let currentCount: Int
            if countMethod == 1 {
                // 原稿用紙換算（400字詰め）
                currentCount = Int(ceil(totalVisibleChars / 400.0))
            } else {
                // 可視文字数
                currentCount = Int(totalVisibleChars)
            }

            progressView.currentCount = currentCount
            progressView.targetCount = targetCount
            progressView.countMethod = countMethod
            progressView.progress = Double(currentCount) / Double(targetCount)
        } else {
            progressView.isGoalSet = false
            progressView.progress = 0
            progressView.currentCount = 0
            progressView.targetCount = 0
            progressView.countMethod = 0
        }
    }

    /// WritingProgressView を取得
    internal func getWritingProgressView() -> WritingProgressView? {
        // キャッシュされたアイテムから取得
        if let view = writingProgressToolbarItem?.view as? WritingProgressView {
            return view
        }
        // ツールバーから直接検索
        guard let toolbar = cachedToolbar else { return nil }
        for item in toolbar.items {
            if item.itemIdentifier == Self.writingProgressToolbarItemIdentifier,
               let view = item.view as? WritingProgressView {
                self.writingProgressToolbarItem = item
                return view
            }
        }
        return nil
    }

    /// 執筆目標設定パネルを表示
    @IBAction func showWritingGoalPanel(_ sender: Any?) {
        guard let window = self.window,
              let document = textDocument else { return }

        let currentGoal = document.presetData?.writingGoal

        writingGoalPanel.beginSheet(for: window, currentGoal: currentGoal) { [weak self] goalData in
            guard let self = self, let goalData = goalData else { return }

            // presetData に保存
            self.textDocument?.presetData?.writingGoal = goalData
            self.textDocument?.presetDataEdited = true

            // 目標が設定された場合、ツールバーを表示し執筆進捗アイテムを追加
            if goalData.targetCount > 0, let toolbar = self.cachedToolbar {
                // ツールバーが非表示なら表示する
                if !self.isToolbarVisible {
                    self.setToolbarVisible(true)
                }
                // 執筆進捗アイテムがツールバーにない場合は追加
                let hasWritingProgress = toolbar.items.contains {
                    $0.itemIdentifier == Self.writingProgressToolbarItemIdentifier
                }
                if !hasWritingProgress {
                    toolbar.insertItem(withItemIdentifier: Self.writingProgressToolbarItemIdentifier,
                                       at: toolbar.items.count)
                }
            }

            // 表示を更新
            self.updateWritingProgressDisplay()
        }
    }

    // MARK: - Find Toolbar Item

    /// 検索ツールバーアイテムを作成
    internal func createFindToolbarItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: Self.findToolbarItemIdentifier)
        item.label = "Find".localized
        item.paletteLabel = "Find".localized
        item.toolTip = "Show Find Bar".localized
        item.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Find")
        item.target = nil  // レスポンダチェーンを通じて送信
        item.action = #selector(showFindBar(_:))
        return item
    }

    internal func createBookmarkToolbarItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: Self.bookmarkToolbarItemIdentifier)
        item.label = "Bookmarks".localized
        item.paletteLabel = "Bookmarks".localized
        item.toolTip = "Show Bookmarks".localized
        item.image = NSImage(systemSymbolName: "bookmark", accessibilityDescription: "Bookmarks")
        item.target = nil  // レスポンダチェーンを通じて送信
        item.action = #selector(Document.showBookmarkPanel(_:))
        return item
    }

    // MARK: - NSToolbarDelegate

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == Self.findToolbarItemIdentifier {
            return createFindToolbarItem()
        }
        if itemIdentifier == Self.encodingToolbarItemIdentifier {
            return createEncodingToolbarItem()
        }
        if itemIdentifier == Self.lineEndingToolbarItemIdentifier {
            return createLineEndingToolbarItem()
        }
        if itemIdentifier == Self.writingProgressToolbarItemIdentifier {
            return createWritingProgressToolbarItem()
        }
        if itemIdentifier == Self.bookmarkToolbarItemIdentifier {
            return createBookmarkToolbarItem()
        }
        return nil
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .flexibleSpace,
            .space,
            .showColors,
            .showFonts,
            .print,
            Self.findToolbarItemIdentifier,
            Self.encodingToolbarItemIdentifier,
            Self.lineEndingToolbarItemIdentifier,
            Self.writingProgressToolbarItemIdentifier,
            Self.bookmarkToolbarItemIdentifier
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .flexibleSpace,
            .print
        ]
    }
}
