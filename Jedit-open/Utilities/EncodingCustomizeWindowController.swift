//
//  EncodingCustomizeWindowController.swift
//  Jedit-open
//
//  Created by Claude on 2026/01/16.
//

import Cocoa

/// エンコーディングリストのカスタマイズウィンドウコントローラー
class EncodingCustomizeWindowController: NSWindowController {

    // MARK: - Singleton

    private static var sharedController: EncodingCustomizeWindowController?

    static func showPanel() {
        if sharedController == nil {
            sharedController = EncodingCustomizeWindowController()
        }
        sharedController?.showWindow(nil)
        sharedController?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Properties

    private var scrollView: NSScrollView!
    private var tableView: NSTableView!
    private var selectAllButton: NSButton!
    private var deselectAllButton: NSButton!
    private var revertButton: NSButton!

    /// 利用可能な全てのエンコーディング
    private var allEncodings: [String.Encoding] = []

    /// 有効化されているエンコーディングのセット
    private var enabledEncodings: Set<String.Encoding> = []

    // MARK: - Initialization

    convenience init() {
        self.init(windowNibName: "")
    }

    override init(window: NSWindow?) {
        super.init(window: nil)
        setupWindow()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupWindow()
    }

    // MARK: - Window Setup

    private func setupWindow() {
        // ウィンドウを作成
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("Customize Encoding List", comment: "Window title for encoding customization")
        window.minSize = NSSize(width: 300, height: 300)
        window.center()

        self.window = window

        setupUI()
        loadEncodings()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // 説明ラベル
        let descriptionLabel = NSTextField(wrappingLabelWithString: NSLocalizedString("Select the encodings to display in the Text Encoding menu.", comment: "Description for encoding customization"))
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(descriptionLabel)

        // スクロールビュー & テーブルビュー
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        contentView.addSubview(scrollView)

        tableView = NSTableView()
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsMultipleSelection = true
        tableView.rowHeight = 20

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("EncodingColumn"))
        column.width = 350
        tableView.addTableColumn(column)

        scrollView.documentView = tableView

        // ボタン
        selectAllButton = NSButton(title: NSLocalizedString("Select All", comment: "Button to select all encodings"), target: self, action: #selector(selectAllClicked(_:)))
        selectAllButton.translatesAutoresizingMaskIntoConstraints = false
        selectAllButton.bezelStyle = .rounded
        contentView.addSubview(selectAllButton)

        deselectAllButton = NSButton(title: NSLocalizedString("Deselect All", comment: "Button to deselect all encodings"), target: self, action: #selector(deselectAllClicked(_:)))
        deselectAllButton.translatesAutoresizingMaskIntoConstraints = false
        deselectAllButton.bezelStyle = .rounded
        contentView.addSubview(deselectAllButton)

        revertButton = NSButton(title: NSLocalizedString("Revert to Default", comment: "Button to revert to default encodings"), target: self, action: #selector(revertToDefaultClicked(_:)))
        revertButton.translatesAutoresizingMaskIntoConstraints = false
        revertButton.bezelStyle = .rounded
        contentView.addSubview(revertButton)

        // レイアウト制約
        NSLayoutConstraint.activate([
            descriptionLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            descriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            descriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: selectAllButton.topAnchor, constant: -12),

            selectAllButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            selectAllButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            deselectAllButton.leadingAnchor.constraint(equalTo: selectAllButton.trailingAnchor, constant: 8),
            deselectAllButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            revertButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            revertButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
    }

    // MARK: - Data Loading

    private func loadEncodings() {
        allEncodings = EncodingManager.allAvailableStringEncodings()
        enabledEncodings = Set(EncodingManager.shared.enabledEncodings())
        tableView.reloadData()
    }

    // MARK: - Actions

    @objc private func selectAllClicked(_ sender: Any) {
        enabledEncodings = Set(allEncodings)
        tableView.reloadData()
        saveEncodings()
    }

    @objc private func deselectAllClicked(_ sender: Any) {
        enabledEncodings.removeAll()
        tableView.reloadData()
        saveEncodings()
    }

    @objc private func revertToDefaultClicked(_ sender: Any) {
        EncodingManager.shared.revertToDefault()
        loadEncodings()
    }

    private func saveEncodings() {
        // 現在の順序を維持しながら有効なエンコーディングのみを保存
        let orderedEncodings = allEncodings.filter { enabledEncodings.contains($0) }
        EncodingManager.shared.setEnabledEncodings(orderedEncodings)
    }
}

// MARK: - NSTableViewDataSource

extension EncodingCustomizeWindowController: NSTableViewDataSource {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return allEncodings.count
    }
}

// MARK: - NSTableViewDelegate

extension EncodingCustomizeWindowController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let encoding = allEncodings[row]
        let name = String.localizedName(of: encoding)

        let cellIdentifier = NSUserInterfaceItemIdentifier("EncodingCell")
        var cellView = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView

        if cellView == nil {
            cellView = NSTableCellView()
            cellView?.identifier = cellIdentifier

            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(checkboxClicked(_:)))
            checkbox.translatesAutoresizingMaskIntoConstraints = false
            cellView?.addSubview(checkbox)

            NSLayoutConstraint.activate([
                checkbox.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 4),
                checkbox.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
            ])
        }

        // チェックボックスを設定
        if let checkbox = cellView?.subviews.first as? NSButton {
            checkbox.title = name
            checkbox.state = enabledEncodings.contains(encoding) ? .on : .off
            checkbox.tag = row
        }

        return cellView
    }

    @objc private func checkboxClicked(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0 && row < allEncodings.count else { return }

        let encoding = allEncodings[row]

        if sender.state == .on {
            enabledEncodings.insert(encoding)
        } else {
            enabledEncodings.remove(encoding)
        }

        saveEncodings()
    }
}
