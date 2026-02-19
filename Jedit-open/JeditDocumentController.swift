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
    private weak var currentOpenPanel: NSOpenPanel?

    /// ポップアップで選択されたプリセットインデックス（-1 = 未選択、-2 = Clipboard）
    private var selectedPresetIndex: Int = -1

    /// 起動処理が完了するまで openDocument を抑制するフラグ
    var suppressOpenPanel = true

    // MARK: - Open Document Override

    override func openDocument(_ sender: Any?) {
        if suppressOpenPanel { return }
        super.openDocument(sender)
    }

    // MARK: - Open Panel Override

    override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
        // 起動時の自動呼び出しを抑制
        // macOS の State Restoration 完了ハンドラから非同期で呼ばれるケースに対応
        if suppressOpenPanel {
            return NSApplication.ModalResponse.cancel.rawValue
        }

        // アクセサリビューに「New」ポップアップボタンを設定
        openPanel.accessoryView = createNewDocumentAccessoryView()
        openPanel.isAccessoryViewDisclosed = true

        // ポップアップアクションから cancel できるようにパネルの参照を保持
        currentOpenPanel = openPanel
        selectedPresetIndex = -1

        // モーダルでパネルを表示（ユーザーが閉じるまでブロック）
        let result = super.runModalOpenPanel(openPanel, forTypes: types)

        // クリーンアップ
        currentOpenPanel = nil

        // プリセットが選択された場合（ポップアップから cancel された場合）、
        // パネルが完全に閉じた後に新規書類を作成
        let presetIndex = selectedPresetIndex
        selectedPresetIndex = -1

        if presetIndex == -2 {
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.newDocumentFromClipboard(nil)
            }
        } else if presetIndex >= 0 {
            DispatchQueue.main.async {
                let menuItem = NSMenuItem()
                menuItem.tag = presetIndex
                (NSApp.delegate as? AppDelegate)?.newDocumentWithPreset(menuItem)
            }
        }

        return result
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
        let checkbox = NSButton(checkboxWithTitle: NSLocalizedString("Show Hidden Files", comment: "Show hidden files checkbox in open panel"), target: self, action: #selector(showHiddenFilesToggled(_:)))
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
        popupButton.addItem(withTitle: NSLocalizedString("New Document", comment: "New document pull-down button title in open panel"))

        // プリセット項目を追加（個別に target/action を設定）
        let presets = DocumentPresetManager.shared.presets
        for (index, preset) in presets.enumerated() {
            let item = NSMenuItem(title: preset.name, action: #selector(openPanelNewDocumentSelected(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            item.isEnabled = true
            popupButton.menu?.addItem(item)
        }

        // セパレータと Clipboard 項目
        popupButton.menu?.addItem(NSMenuItem.separator())
        let clipboardItem = NSMenuItem(
            title: NSLocalizedString("Clipboard", comment: "New document from clipboard in open panel"),
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
