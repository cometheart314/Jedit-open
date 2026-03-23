//
//  TabWidthPanel.swift
//  Jedit-open
//
//  Created by Claude on 2026/01/26.
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

/// タブ幅を設定するためのパネル
class TabWidthPanel: NSPanel {

    // MARK: - Properties

    private var widthField: NSTextField!
    private var widthStepper: NSStepper!
    private var unitPopup: NSPopUpButton!
    private var completionHandler: ((CGFloat?, NewDocData.FormatData.TabWidthUnit?) -> Void)?
    private weak var sheetParentWindow: NSWindow?

    // MARK: - Initialization

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )

        self.title = "Tab Width".localized
        self.isReleasedWhenClosed = false

        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = self.contentView else { return }

        // Tab Width: ラベル
        let label = NSTextField(labelWithString: "Tab Width:".localized)
        label.frame = NSRect(x: 20, y: 80, width: 80, height: 17)
        contentView.addSubview(label)

        // 幅入力フィールド
        widthField = NSTextField(frame: NSRect(x: 105, y: 77, width: 60, height: 22))
        widthField.alignment = .right
        widthField.doubleValue = 32.0

        // NumberFormatterを設定
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 1
        formatter.maximum = 999
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        widthField.formatter = formatter

        contentView.addSubview(widthField)

        // Stepper
        widthStepper = NSStepper(frame: NSRect(x: 170, y: 77, width: 19, height: 22))
        widthStepper.minValue = 1
        widthStepper.maxValue = 999
        widthStepper.increment = 1
        widthStepper.valueWraps = false
        widthStepper.doubleValue = 32.0
        widthStepper.target = self
        widthStepper.action = #selector(stepperChanged(_:))
        contentView.addSubview(widthStepper)

        // 単位ポップアップ（Points / Spaces）
        unitPopup = NSPopUpButton(frame: NSRect(x: 195, y: 75, width: 85, height: 25), pullsDown: false)
        unitPopup.addItem(withTitle: "points".localized)
        unitPopup.addItem(withTitle: "spaces".localized)
        unitPopup.item(at: 0)?.tag = 0  // points
        unitPopup.item(at: 1)?.tag = 1  // spaces
        unitPopup.target = self
        unitPopup.action = #selector(unitChanged(_:))
        contentView.addSubview(unitPopup)

        // Cancel ボタン
        let cancelButton = NSButton(title: "Cancel".localized, target: self, action: #selector(cancelClicked(_:)))
        cancelButton.frame = NSRect(x: 110, y: 13, width: 82, height: 32)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}" // Escape
        contentView.addSubview(cancelButton)

        // Change ボタン
        let changeButton = NSButton(title: "Change".localized, target: self, action: #selector(changeClicked(_:)))
        changeButton.frame = NSRect(x: 197, y: 13, width: 82, height: 32)
        changeButton.bezelStyle = .rounded
        changeButton.keyEquivalent = "\r" // Return
        contentView.addSubview(changeButton)
    }

    // MARK: - Public Methods

    /// シートとして表示
    /// - Parameters:
    ///   - window: 親ウィンドウ
    ///   - currentValue: 現在の値（pointsならポイント数、spacesならスペース数）
    ///   - currentUnit: 現在の単位
    ///   - completionHandler: 完了時のコールバック（値と単位を返す）
    func beginSheet(
        for window: NSWindow,
        currentValue: CGFloat,
        currentUnit: NewDocData.FormatData.TabWidthUnit,
        completionHandler: @escaping (CGFloat?, NewDocData.FormatData.TabWidthUnit?) -> Void
    ) {
        self.sheetParentWindow = window
        self.completionHandler = completionHandler

        // 単位を設定
        unitPopup.selectItem(withTag: currentUnit.rawValue)

        // 値を表示（そのまま）
        widthField.doubleValue = Double(currentValue)
        widthStepper.doubleValue = Double(currentValue)

        window.beginSheet(self) { _ in }
    }

    // MARK: - Actions

    @objc private func stepperChanged(_ sender: NSStepper) {
        widthField.doubleValue = sender.doubleValue
    }

    @objc private func unitChanged(_ sender: NSPopUpButton) {
        // 単位が変わったらデフォルト値を設定
        let newUnit = NewDocData.FormatData.TabWidthUnit(rawValue: sender.selectedTag()) ?? .points

        if newUnit == .points {
            widthField.doubleValue = 32.0
            widthStepper.doubleValue = 32.0
        } else {
            widthField.doubleValue = 4.0
            widthStepper.doubleValue = 4.0
        }
    }

    @objc private func cancelClicked(_ sender: Any) {
        endSheet(with: nil, unit: nil)
    }

    @objc private func changeClicked(_ sender: Any) {
        let value = CGFloat(widthField.doubleValue)
        let unit = NewDocData.FormatData.TabWidthUnit(rawValue: unitPopup.selectedTag()) ?? .points

        // 範囲チェック
        if value < 1 || value > 999 {
            let alert = NSAlert()
            alert.messageText = "Invalid Width".localized
            alert.informativeText = "Specify a width between 1 and 999.".localized
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK".localized)
            alert.beginSheetModal(for: self, completionHandler: nil)
            return
        }

        // 値をそのまま返す（変換なし）
        endSheet(with: value, unit: unit)
    }

    private func endSheet(with width: CGFloat?, unit: NewDocData.FormatData.TabWidthUnit?) {
        sheetParentWindow?.endSheet(self)
        orderOut(nil)
        completionHandler?(width, unit)
    }
}
