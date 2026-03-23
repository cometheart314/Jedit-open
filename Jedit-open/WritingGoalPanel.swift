//
//  WritingGoalPanel.swift
//  Jedit-open
//
//  執筆目標を設定するためのパネル
//  目標文字数とカウント方法を入力できるシートダイアログ
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

/// 執筆目標を設定するためのパネル
class WritingGoalPanel: NSPanel {

    // MARK: - Properties

    private var goalField: NSTextField!
    private var goalStepper: NSStepper!
    private var methodPopup: NSPopUpButton!
    private var completionHandler: ((NewDocData.WritingGoalData?) -> Void)?
    private weak var sheetParentWindow: NSWindow?

    // MARK: - Initialization

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 140),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )

        self.title = "Writing Goal".localized
        self.isReleasedWhenClosed = false

        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = self.contentView else { return }

        // Target: ラベル
        let targetLabel = NSTextField(labelWithString: "Target:".localized)
        targetLabel.frame = NSRect(x: 20, y: 98, width: 60, height: 17)
        targetLabel.alignment = .right
        contentView.addSubview(targetLabel)

        // 目標文字数入力フィールド
        goalField = NSTextField(frame: NSRect(x: 85, y: 95, width: 80, height: 22))
        goalField.alignment = .right
        goalField.integerValue = 0

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 0
        formatter.maximum = 9999999
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        goalField.formatter = formatter
        contentView.addSubview(goalField)

        // ステッパー
        goalStepper = NSStepper(frame: NSRect(x: 170, y: 95, width: 19, height: 22))
        goalStepper.minValue = 0
        goalStepper.maxValue = 9999999
        goalStepper.increment = 100
        goalStepper.valueWraps = false
        goalStepper.integerValue = 0
        goalStepper.target = self
        goalStepper.action = #selector(stepperChanged(_:))
        contentView.addSubview(goalStepper)

        // 0 = 無効 のヒントラベル
        let hintLabel = NSTextField(labelWithString: "(0 = No goal)".localized)
        hintLabel.frame = NSRect(x: 195, y: 98, width: 150, height: 17)
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        contentView.addSubview(hintLabel)

        // Count Method: ラベル
        let methodLabel = NSTextField(labelWithString: "Count:".localized)
        methodLabel.frame = NSRect(x: 20, y: 63, width: 60, height: 17)
        methodLabel.alignment = .right
        contentView.addSubview(methodLabel)

        // カウント方法ポップアップ
        methodPopup = NSPopUpButton(frame: NSRect(x: 85, y: 59, width: 250, height: 25), pullsDown: false)
        methodPopup.addItem(withTitle: "Visible Characters".localized)
        methodPopup.addItem(withTitle: "Manuscript Pages (400 chars)".localized)
        methodPopup.target = self
        methodPopup.action = #selector(countMethodChanged(_:))
        contentView.addSubview(methodPopup)

        // Cancel ボタン
        let cancelButton = NSButton(frame: NSRect(x: 175, y: 15, width: 80, height: 32))
        cancelButton.bezelStyle = .rounded
        cancelButton.title = "Cancel".localized
        cancelButton.keyEquivalent = "\u{1b}"  // Escape
        cancelButton.target = self
        cancelButton.action = #selector(cancelAction(_:))
        contentView.addSubview(cancelButton)

        // Set ボタン
        let setButton = NSButton(frame: NSRect(x: 260, y: 15, width: 80, height: 32))
        setButton.bezelStyle = .rounded
        setButton.title = "Set".localized
        setButton.keyEquivalent = "\r"  // Return
        setButton.target = self
        setButton.action = #selector(setAction(_:))
        contentView.addSubview(setButton)
    }

    // MARK: - Sheet Display

    /// シートとして表示
    /// - Parameters:
    ///   - window: 親ウィンドウ
    ///   - currentGoal: 現在の執筆目標（nilの場合はデフォルト）
    ///   - completionHandler: 完了ハンドラ（nilの場合はキャンセル）
    func beginSheet(for window: NSWindow, currentGoal: NewDocData.WritingGoalData?, completionHandler: @escaping (NewDocData.WritingGoalData?) -> Void) {
        self.completionHandler = completionHandler
        self.sheetParentWindow = window

        // 現在の設定を復元
        let goal = currentGoal ?? .default
        goalField.integerValue = goal.targetCount
        goalStepper.integerValue = goal.targetCount
        methodPopup.selectItem(at: goal.countMethod)
        updateStepperIncrement()

        window.beginSheet(self) { _ in }
    }

    // MARK: - Actions

    @objc private func stepperChanged(_ sender: NSStepper) {
        goalField.integerValue = sender.integerValue
    }

    @objc private func countMethodChanged(_ sender: NSPopUpButton) {
        updateStepperIncrement()
        goalField.integerValue = 0
        goalStepper.integerValue = 0
    }

    /// カウント方法に応じてステッパーの刻みを更新
    private func updateStepperIncrement() {
        if methodPopup.indexOfSelectedItem == 1 {
            // Manuscript Pages: 1ページごと
            goalStepper.increment = 1
        } else {
            // Visible Characters: 100文字ごと
            goalStepper.increment = 100
        }
    }

    @objc private func cancelAction(_ sender: Any?) {
        sheetParentWindow?.endSheet(self, returnCode: .cancel)
        completionHandler?(nil)
        completionHandler = nil
    }

    @objc private func setAction(_ sender: Any?) {
        let target = goalField.integerValue
        let method = methodPopup.indexOfSelectedItem

        sheetParentWindow?.endSheet(self, returnCode: .OK)

        let goalData = NewDocData.WritingGoalData(
            targetCount: max(0, target),
            countMethod: method
        )
        completionHandler?(goalData)
        completionHandler = nil
    }
}
