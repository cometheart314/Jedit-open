//
//  JeditDocumentController.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/25.
//

import Cocoa

class JeditDocumentController: NSDocumentController {

    // MARK: - Properties

    /// キャンセル用に保持する現在表示中の Open パネル
    private(set) weak var currentOpenPanel: NSOpenPanel?

    /// ポップアップで選択されたプリセットインデックス（-1 = 未選択、-2 = Clipboard）
    private var selectedPresetIndex: Int = -1

    /// 起動処理が完了するまで openDocument を抑制するフラグ
    var suppressOpenPanel = true

    // MARK: - Open Document Override

    override func openDocument(_ sender: Any?) {
        if suppressOpenPanel { return }

        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true

        // アクセサリビューに「New」ポップアップボタンと「Show Hidden Files」チェックボックスを設定
        openPanel.accessoryView = createNewDocumentAccessoryView()
        openPanel.isAccessoryViewDisclosed = true

        // ポップアップアクションから cancel できるようにパネルの参照を保持
        currentOpenPanel = openPanel
        selectedPresetIndex = -1

        // 非同期でパネルを表示（メニューバーをブロックしない）
        openPanel.begin { [weak self] response in
            guard let self = self else { return }

            // クリーンアップ
            self.currentOpenPanel = nil
            let presetIndex = self.selectedPresetIndex
            self.selectedPresetIndex = -1

            if presetIndex == -2 {
                // Clipboard から新規書類を作成
                (NSApp.delegate as? AppDelegate)?.newDocumentFromClipboard(nil)
            } else if presetIndex >= 0 {
                // プリセットから新規書類を作成
                let menuItem = NSMenuItem()
                menuItem.tag = presetIndex
                (NSApp.delegate as? AppDelegate)?.newDocumentWithPreset(menuItem)
            } else if response == .OK {
                // 選択されたファイルを開く
                for url in openPanel.urls {
                    self.openDocument(withContentsOf: url, display: true) { _, _, error in
                        if let error = error {
                            NSApp.presentError(error)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Open Recent (Option+クリックで削除)

    override func openDocument(withContentsOf url: URL, display displayDocument: Bool, completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void) {
        // Option キーが押されている場合、ファイルを開かずに Recents から削除
        if NSEvent.modifierFlags.contains(.option) {
            removeFromRecents(url: url)
            completionHandler(nil, false, nil)
            return
        }
        super.openDocument(withContentsOf: url, display: displayDocument, completionHandler: completionHandler)
    }

    /// 指定 URL を Recent Documents から削除
    private func removeFromRecents(url: URL) {
        let currentURLs = recentDocumentURLs
        clearRecentDocuments(nil)
        // 逆順で再登録して順序を保持
        for recentURL in currentURLs.reversed() where recentURL != url {
            noteNewRecentDocumentURL(recentURL)
        }
    }

    // MARK: - Open Panel Override (State Restoration 用)

    override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
        // 起動時の自動呼び出しを抑制
        // macOS の State Restoration 完了ハンドラから非同期で呼ばれるケースに対応
        if suppressOpenPanel {
            return NSApplication.ModalResponse.cancel.rawValue
        }
        return super.runModalOpenPanel(openPanel, forTypes: types)
    }

    // MARK: - Accessory View

    /// 「New Document」ポップアップボタンと「Show Hidden Files」チェックボックスを含むアクセサリビューを作成
    private func createNewDocumentAccessoryView() -> NSView {
        // New Document ポップアップボタン
        let popupButton = NSPopUpButton(frame: .zero, pullsDown: true)
        popupButton.translatesAutoresizingMaskIntoConstraints = false
        popupButton.autoenablesItems = false
        populatePopupButton(popupButton)

        // Show Hidden Files チェックボックス
        let checkbox = NSButton(checkboxWithTitle: "Show Hidden Files".localized, target: self, action: #selector(showHiddenFilesToggled(_:)))
        checkbox.translatesAutoresizingMaskIntoConstraints = false

        // コンテナビュー
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 32))
        containerView.addSubview(popupButton)
        containerView.addSubview(checkbox)

        NSLayoutConstraint.activate([
            popupButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            popupButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 0),
            checkbox.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            checkbox.leadingAnchor.constraint(equalTo: popupButton.trailingAnchor, constant: 16),
            containerView.heightAnchor.constraint(equalToConstant: 32),
        ])

        return containerView
    }

    /// pull-down ボタンにプリセット項目を追加
    private func populatePopupButton(_ popupButton: NSPopUpButton) {
        popupButton.removeAllItems()

        // pull-down ボタンの先頭項目はボタンタイトルとして表示される
        popupButton.addItem(withTitle: "New Document".localized)

        // プリセット項目を追加（個別に target/action を設定）
        let presets = DocumentPresetManager.shared.presets
        for (index, preset) in presets.enumerated() {
            let item = NSMenuItem(title: preset.displayName, action: #selector(openPanelNewDocumentSelected(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            item.isEnabled = true
            popupButton.menu?.addItem(item)
        }

        // セパレータと Clipboard 項目
        popupButton.menu?.addItem(NSMenuItem.separator())
        let clipboardItem = NSMenuItem(
            title: "Clipboard".localized,
            action: #selector(openPanelNewDocumentSelected(_:)),
            keyEquivalent: ""
        )
        clipboardItem.tag = -2
        clipboardItem.target = self
        clipboardItem.isEnabled = true
        popupButton.menu?.addItem(clipboardItem)
    }

    // MARK: - Actions

    @objc private func showHiddenFilesToggled(_ sender: NSButton) {
        currentOpenPanel?.showsHiddenFiles = (sender.state == .on)
    }

    @objc private func openPanelNewDocumentSelected(_ sender: Any) {
        let tag: Int
        if let menuItem = sender as? NSMenuItem {
            tag = menuItem.tag
        } else if let popupButton = sender as? NSPopUpButton, let selectedItem = popupButton.selectedItem {
            tag = selectedItem.tag
        } else {
            return
        }
        selectedPresetIndex = tag
        currentOpenPanel?.cancel(self)
    }
}
