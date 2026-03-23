//
//  OtherScalePanel.swift
//  Jedit-open
//
//  Created by Claude on 2025/01/16.
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

/// カスタムスケール値を入力するためのパネル
class OtherScalePanel: NSPanel {

    // MARK: - Properties

    private var scaleField: NSTextField!
    private var completionHandler: ((Int?) -> Void)?
    private weak var sheetParentWindow: NSWindow?

    // MARK: - Initialization

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 334, height: 126),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )

        self.title = "Add a new scale".localized
        self.isReleasedWhenClosed = false

        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = self.contentView else { return }

        // New Scale: ラベル
        let label = NSTextField(labelWithString: "New Scale:".localized)
        label.frame = NSRect(x: 17, y: 94, width: 76, height: 17)
        contentView.addSubview(label)

        // スケール入力フィールド
        scaleField = NSTextField(frame: NSRect(x: 98, y: 91, width: 63, height: 22))
        scaleField.alignment = .right
        scaleField.integerValue = 100

        // NumberFormatterを設定
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 25
        formatter.maximum = 999
        formatter.allowsFloats = false
        scaleField.formatter = formatter

        contentView.addSubview(scaleField)

        // % ラベル
        let percentLabel = NSTextField(labelWithString: "%")
        percentLabel.frame = NSRect(x: 166, y: 94, width: 22, height: 17)
        contentView.addSubview(percentLabel)

        // 説明テキスト
        let descLabel = NSTextField(wrappingLabelWithString: "If you want to remove an existing menu item, choose it with pressing Option key.".localized)
        descLabel.frame = NSRect(x: 17, y: 43, width: 300, height: 40)
        descLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        contentView.addSubview(descLabel)

        // Cancel ボタン
        let cancelButton = NSButton(title: "Cancel".localized, target: self, action: #selector(cancelClicked(_:)))
        cancelButton.frame = NSRect(x: 172, y: 13, width: 82, height: 32)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}" // Escape
        contentView.addSubview(cancelButton)

        // Add ボタン
        let addButton = NSButton(title: "Add".localized, target: self, action: #selector(addClicked(_:)))
        addButton.frame = NSRect(x: 254, y: 13, width: 66, height: 32)
        addButton.bezelStyle = .rounded
        addButton.keyEquivalent = "\r" // Return
        contentView.addSubview(addButton)
    }

    // MARK: - Public Methods

    /// シートとして表示
    func beginSheet(for window: NSWindow, completionHandler: @escaping (Int?) -> Void) {
        self.sheetParentWindow = window
        self.completionHandler = completionHandler
        scaleField.integerValue = 100

        window.beginSheet(self) { _ in }
    }

    // MARK: - Actions

    @objc private func cancelClicked(_ sender: Any) {
        endSheet(with: nil)
    }

    @objc private func addClicked(_ sender: Any) {
        let newScale = scaleField.integerValue

        // 範囲チェック
        if newScale < 25 || newScale > 999 {
            let alert = NSAlert()
            alert.messageText = "Invalid Scale".localized
            alert.informativeText = "Specify a scale between 25% and 999%.".localized
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK".localized)
            alert.beginSheetModal(for: self, completionHandler: nil)
            return
        }

        // 既存のスケールと重複チェック
        let scalesArray = UserDefaults.standard.array(forKey: UserDefaults.Keys.scaleMenuArray) as? [Int]
            ?? UserDefaults.defaultScaleMenuArray

        if scalesArray.contains(newScale) {
            let alert = NSAlert()
            alert.messageText = "Duplicate Scale".localized
            alert.informativeText = "Same scale already exists in the menu.".localized
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK".localized)
            alert.beginSheetModal(for: self, completionHandler: nil)
            return
        }

        endSheet(with: newScale)
    }

    private func endSheet(with scale: Int?) {
        sheetParentWindow?.endSheet(self)
        orderOut(nil)
        completionHandler?(scale)
    }
}
