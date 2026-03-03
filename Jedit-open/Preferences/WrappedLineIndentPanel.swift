//
//  WrappedLineIndentPanel.swift
//  Jedit-open
//
//  Created by Claude on 2026/01/27.
//

import Cocoa

/// Wrapped Line Indent を設定するためのパネル
class WrappedLineIndentPanel: NSPanel {

    // MARK: - Properties

    private var enableCheckbox: NSButton!
    private var indentField: NSTextField!
    private var unitLabel: NSTextField!
    private var completionHandler: ((Bool, CGFloat) -> Void)?
    private weak var sheetParentWindow: NSWindow?

    // MARK: - Initialization

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )

        self.title = "Wrapped Line Indent".localized
        self.isReleasedWhenClosed = false

        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = self.contentView else { return }

        // Indent Wrapped Lines by: チェックボックス付きラベル
        enableCheckbox = NSButton(checkboxWithTitle: "Indent Wrapped Lines by:".localized, target: self, action: #selector(checkboxChanged(_:)))
        enableCheckbox.frame = NSRect(x: 20, y: 58, width: 175, height: 18)
        contentView.addSubview(enableCheckbox)

        // インデント値入力フィールド
        indentField = NSTextField(frame: NSRect(x: 195, y: 55, width: 50, height: 22))
        indentField.alignment = .right
        indentField.doubleValue = 0.0

        // NumberFormatterを設定
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 0
        formatter.maximum = 999
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        indentField.formatter = formatter

        contentView.addSubview(indentField)

        // pt. ラベル
        unitLabel = NSTextField(labelWithString: "pt.".localized)
        unitLabel.frame = NSRect(x: 248, y: 58, width: 25, height: 17)
        contentView.addSubview(unitLabel)

        // Cancel ボタン
        let cancelButton = NSButton(title: "Cancel".localized, target: self, action: #selector(cancelClicked(_:)))
        cancelButton.frame = NSRect(x: 95, y: 13, width: 82, height: 32)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}" // Escape
        contentView.addSubview(cancelButton)

        // Set ボタン
        let setButton = NSButton(title: "Set".localized, target: self, action: #selector(setClicked(_:)))
        setButton.frame = NSRect(x: 182, y: 13, width: 82, height: 32)
        setButton.bezelStyle = .rounded
        setButton.keyEquivalent = "\r" // Return
        contentView.addSubview(setButton)
    }

    // MARK: - Public Methods

    /// シートとして表示
    /// - Parameters:
    ///   - window: 親ウィンドウ
    ///   - enabled: インデントが有効かどうか
    ///   - indentValue: 現在のインデント値（ポイント）
    ///   - completionHandler: 完了時のコールバック（有効フラグと値を返す）
    func beginSheet(
        for window: NSWindow,
        enabled: Bool,
        indentValue: CGFloat,
        completionHandler: @escaping (Bool, CGFloat) -> Void
    ) {
        self.sheetParentWindow = window
        self.completionHandler = completionHandler

        // 現在の値を設定
        enableCheckbox.state = enabled ? .on : .off
        indentField.doubleValue = Double(indentValue)
        indentField.isEnabled = enabled

        window.beginSheet(self) { _ in }
    }

    // MARK: - Actions

    @objc private func checkboxChanged(_ sender: NSButton) {
        indentField.isEnabled = sender.state == .on
    }

    @objc private func cancelClicked(_ sender: Any) {
        sheetParentWindow?.endSheet(self)
        orderOut(nil)
    }

    @objc private func setClicked(_ sender: Any) {
        let enabled = enableCheckbox.state == .on
        let value = CGFloat(indentField.doubleValue)

        // 範囲チェック
        if value < 0 || value > 999 {
            let alert = NSAlert()
            alert.messageText = "Invalid Value".localized
            alert.informativeText = "Specify a value between 0 and 999.".localized
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK".localized)
            alert.beginSheetModal(for: self, completionHandler: nil)
            return
        }

        sheetParentWindow?.endSheet(self)
        orderOut(nil)
        completionHandler?(enabled, value)
    }
}
