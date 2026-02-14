//
//  WritingGoalPanel.swift
//  Jedit-open
//
//  執筆目標を設定するためのパネル
//  目標文字数とカウント方法を入力できるシートダイアログ
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

        self.title = NSLocalizedString("Writing Goal", comment: "Panel title")
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
        let targetLabel = NSTextField(labelWithString: NSLocalizedString("Target:", comment: ""))
        targetLabel.frame = NSRect(x: 20, y: 98, width: 60, height: 17)
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
        let hintLabel = NSTextField(labelWithString: NSLocalizedString("(0 = No goal)", comment: ""))
        hintLabel.frame = NSRect(x: 195, y: 98, width: 150, height: 17)
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        contentView.addSubview(hintLabel)

        // Count Method: ラベル
        let methodLabel = NSTextField(labelWithString: NSLocalizedString("Count:", comment: ""))
        methodLabel.frame = NSRect(x: 20, y: 63, width: 60, height: 17)
        contentView.addSubview(methodLabel)

        // カウント方法ポップアップ
        methodPopup = NSPopUpButton(frame: NSRect(x: 85, y: 59, width: 250, height: 25), pullsDown: false)
        methodPopup.addItem(withTitle: NSLocalizedString("Visible Characters", comment: "Count method"))
        methodPopup.addItem(withTitle: NSLocalizedString("Manuscript Pages (400 chars)", comment: "Count method"))
        contentView.addSubview(methodPopup)

        // Cancel ボタン
        let cancelButton = NSButton(frame: NSRect(x: 175, y: 15, width: 80, height: 32))
        cancelButton.bezelStyle = .rounded
        cancelButton.title = NSLocalizedString("Cancel", comment: "")
        cancelButton.keyEquivalent = "\u{1b}"  // Escape
        cancelButton.target = self
        cancelButton.action = #selector(cancelAction(_:))
        contentView.addSubview(cancelButton)

        // Set ボタン
        let setButton = NSButton(frame: NSRect(x: 260, y: 15, width: 80, height: 32))
        setButton.bezelStyle = .rounded
        setButton.title = NSLocalizedString("Set", comment: "")
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

        window.beginSheet(self) { _ in }
    }

    // MARK: - Actions

    @objc private func stepperChanged(_ sender: NSStepper) {
        goalField.integerValue = sender.integerValue
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
