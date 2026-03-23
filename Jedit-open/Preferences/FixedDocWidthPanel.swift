//
//  FixedDocWidthPanel.swift
//  Jedit-open
//
//  Created by Claude on 2026/01/16.
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

/// 固定幅を入力するためのパネル
class FixedDocWidthPanel: NSPanel {

    // MARK: - Properties

    private var widthField: NSTextField!
    private var widthStepper: NSStepper!
    private var completionHandler: ((Int?) -> Void)?
    private weak var sheetParentWindow: NSWindow?

    // MARK: - Initialization

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )

        self.title = "Fixed Width".localized
        self.isReleasedWhenClosed = false

        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = self.contentView else { return }

        // Document Width: ラベル
        let label = NSTextField(labelWithString: "Document Width:".localized)
        label.frame = NSRect(x: 20, y: 80, width: 110, height: 17)
        contentView.addSubview(label)

        // 幅入力フィールド
        widthField = NSTextField(frame: NSRect(x: 135, y: 77, width: 60, height: 22))
        widthField.alignment = .right
        widthField.integerValue = 80

        // NumberFormatterを設定
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 10
        formatter.maximum = 9999
        formatter.allowsFloats = false
        widthField.formatter = formatter

        contentView.addSubview(widthField)

        // Stepper
        widthStepper = NSStepper(frame: NSRect(x: 200, y: 77, width: 19, height: 22))
        widthStepper.minValue = 10
        widthStepper.maxValue = 9999
        widthStepper.increment = 1
        widthStepper.valueWraps = false
        widthStepper.integerValue = 80
        widthStepper.target = self
        widthStepper.action = #selector(stepperChanged(_:))
        contentView.addSubview(widthStepper)

        // chars. ラベル
        let charsLabel = NSTextField(labelWithString: "chars.".localized)
        charsLabel.frame = NSRect(x: 225, y: 80, width: 40, height: 17)
        contentView.addSubview(charsLabel)

        // Cancel ボタン
        let cancelButton = NSButton(title: "Cancel".localized, target: self, action: #selector(cancelClicked(_:)))
        cancelButton.frame = NSRect(x: 100, y: 13, width: 82, height: 32)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}" // Escape
        contentView.addSubview(cancelButton)

        // Change ボタン
        let changeButton = NSButton(title: "Change".localized, target: self, action: #selector(changeClicked(_:)))
        changeButton.frame = NSRect(x: 182, y: 13, width: 82, height: 32)
        changeButton.bezelStyle = .rounded
        changeButton.keyEquivalent = "\r" // Return
        contentView.addSubview(changeButton)
    }

    // MARK: - Public Methods

    /// シートとして表示
    func beginSheet(for window: NSWindow, currentWidth: Int, completionHandler: @escaping (Int?) -> Void) {
        self.sheetParentWindow = window
        self.completionHandler = completionHandler

        widthField.integerValue = currentWidth
        widthStepper.integerValue = currentWidth

        window.beginSheet(self) { _ in }
    }

    // MARK: - Actions

    @objc private func stepperChanged(_ sender: NSStepper) {
        widthField.integerValue = sender.integerValue
    }

    @objc private func cancelClicked(_ sender: Any) {
        endSheet(with: nil)
    }

    @objc private func changeClicked(_ sender: Any) {
        let newWidth = widthField.integerValue

        // 範囲チェック
        if newWidth < 10 || newWidth > 9999 {
            let alert = NSAlert()
            alert.messageText = "Invalid Width".localized
            alert.informativeText = "Specify a width between 10 and 9999 characters.".localized
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK".localized)
            alert.beginSheetModal(for: self, completionHandler: nil)
            return
        }

        endSheet(with: newWidth)
    }

    private func endSheet(with width: Int?) {
        sheetParentWindow?.endSheet(self)
        orderOut(nil)
        completionHandler?(width)
    }
}
