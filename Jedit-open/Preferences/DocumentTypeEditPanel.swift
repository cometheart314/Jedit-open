//
//  DocumentTypeEditPanel.swift
//  Jedit-open
//
//  Created by Claude on 2026/03/15.
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

/// 書類タイプの編集結果
struct DocumentTypeEditResult {
    var name: String
    var uti: String
    var regex: String
}

/// 書類タイプ（名前・UTI・正規表現）を編集するためのパネル
class DocumentTypeEditPanel: NSPanel {

    // MARK: - Properties

    private var nameField: NSTextField!
    private var utiField: NSTextField!
    private var utiSamplePopup: NSPopUpButton!
    private var regexField: NSTextField!
    private var okButton: NSButton!
    private var cancelButton: NSButton!

    private var completionHandler: ((DocumentTypeEditResult?) -> Void)?
    private weak var sheetParentWindow: NSWindow?

    // MARK: - Initialization

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 180),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )

        self.title = "Edit Document Type".localized
        self.isReleasedWhenClosed = false

        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = self.contentView else { return }

        let labelWidth: CGFloat = 100
        let leftMargin: CGFloat = 20
        let rightMargin: CGFloat = 20
        let panelWidth: CGFloat = 500
        let fieldLeft: CGFloat = leftMargin + labelWidth + 8
        let rowHeight: CGFloat = 30
        let fieldHeight: CGFloat = 22
        let popupWidth: CGFloat = 140
        let utiFieldWidth: CGFloat = panelWidth - fieldLeft - rightMargin - popupWidth - 4

        var currentY: CGFloat = 140

        // Row 1: 書類タイプ名
        let nameLabel = NSTextField(labelWithString: "Document Type Name:".localized)
        nameLabel.frame = NSRect(x: leftMargin, y: currentY + 2, width: labelWidth, height: 17)
        nameLabel.alignment = .right
        nameLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        contentView.addSubview(nameLabel)

        nameField = NSTextField(frame: NSRect(x: fieldLeft, y: currentY, width: panelWidth - fieldLeft - rightMargin, height: fieldHeight))
        nameField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        nameField.placeholderString = nil
        contentView.addSubview(nameField)

        currentY -= rowHeight

        // Row 2: 対応UTI + サンプルUTIポップアップ
        let utiLabel = NSTextField(labelWithString: "UTI:".localized)
        utiLabel.frame = NSRect(x: leftMargin, y: currentY + 2, width: labelWidth, height: 17)
        utiLabel.alignment = .right
        utiLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        contentView.addSubview(utiLabel)

        utiField = NSTextField(frame: NSRect(x: fieldLeft, y: currentY, width: utiFieldWidth, height: fieldHeight))
        utiField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        utiField.placeholderString = nil
        contentView.addSubview(utiField)

        utiSamplePopup = NSPopUpButton(frame: NSRect(x: fieldLeft + utiFieldWidth + 4, y: currentY - 2, width: popupWidth, height: 24), pullsDown: true)
        utiSamplePopup.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        setupUTISamplePopup()
        utiSamplePopup.target = self
        utiSamplePopup.action = #selector(utiSampleSelected(_:))
        contentView.addSubview(utiSamplePopup)

        currentY -= rowHeight

        // Row 3: 正規表現
        let regexLabel = NSTextField(labelWithString: "Regex:".localized)
        regexLabel.frame = NSRect(x: leftMargin, y: currentY + 2, width: labelWidth, height: 17)
        regexLabel.alignment = .right
        regexLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        contentView.addSubview(regexLabel)

        regexField = NSTextField(frame: NSRect(x: fieldLeft, y: currentY, width: panelWidth - fieldLeft - rightMargin, height: fieldHeight))
        regexField.font = NSFont.userFixedPitchFont(ofSize: NSFont.systemFontSize) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        regexField.placeholderString = nil
        contentView.addSubview(regexField)

        currentY -= (rowHeight + 10)

        // Buttons
        let buttonWidth: CGFloat = 80
        let buttonHeight: CGFloat = 32
        let buttonSpacing: CGFloat = 8

        okButton = NSButton(title: "OK".localized, target: self, action: #selector(okClicked(_:)))
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"
        okButton.frame = NSRect(x: panelWidth - rightMargin - buttonWidth, y: currentY, width: buttonWidth, height: buttonHeight)
        contentView.addSubview(okButton)

        cancelButton = NSButton(title: "Cancel".localized, target: self, action: #selector(cancelClicked(_:)))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.frame = NSRect(x: panelWidth - rightMargin - buttonWidth - buttonSpacing - buttonWidth, y: currentY, width: buttonWidth, height: buttonHeight)
        contentView.addSubview(cancelButton)
    }

    // MARK: - UTI Sample Popup

    private func setupUTISamplePopup() {
        utiSamplePopup.removeAllItems()

        // pullsDown モードのタイトル項目
        utiSamplePopup.addItem(withTitle: "Sample UTIs".localized)

        // テキスト系
        let textGroup = [
            "public.text",
            "public.plain-text",
            "public.utf8-plain-text",
            "public.rtf",
            "public.html",
            "public.xml",
        ]

        // ソースコード系
        let sourceGroup = [
            "public.source-code",
            "public.c-source",
            "public.objective-c-source",
            "public.c-plus-plus-source",
            "public.objective-c-plus-plus-source",
            "public.c-header",
            "public.c-plus-plus-header",
            "com.sun.java-source",
        ]

        // スクリプト系
        let scriptGroup = [
            "public.script",
            "public.shell-script",
            "public.csh-script",
            "public.perl-script",
            "public.python-script",
            "public.ruby-script",
            "public.php-script",
            "com.netscape.javascript-source",
            "com.apple.applescript.text",
        ]

        // その他コード系
        let otherCodeGroup = [
            "public.assembly-source",
            "net.daringfireball.markdown",
        ]

        // ドキュメント系
        let documentGroup = [
            "com.adobe.pdf",
            "com.microsoft.word.doc",
            "org.openxmlformats.wordprocessingml.document",
            "com.apple.rtfd",
        ]

        // セパレーター付きでグループを追加
        addUTIGroup(textGroup, header: "— Text —")
        addUTIGroup(sourceGroup, header: "— Source Code —")
        addUTIGroup(scriptGroup, header: "— Scripts —")
        addUTIGroup(otherCodeGroup, header: "— Other Code —")
        addUTIGroup(documentGroup, header: "— Documents —")
    }

    private func addUTIGroup(_ utis: [String], header: String) {
        let menu = utiSamplePopup.menu!
        let headerItem = NSMenuItem(title: header, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        for uti in utis {
            menu.addItem(NSMenuItem(title: uti, action: #selector(utiSampleSelected(_:)), keyEquivalent: ""))
        }
    }

    // MARK: - Actions

    @objc private func utiSampleSelected(_ sender: Any) {
        guard let selectedTitle = utiSamplePopup.selectedItem?.title,
              !selectedTitle.hasPrefix("—") else { return }
        utiField.stringValue = selectedTitle
    }

    @objc private func okClicked(_ sender: Any) {
        let result = DocumentTypeEditResult(
            name: nameField.stringValue,
            uti: utiField.stringValue,
            regex: regexField.stringValue
        )
        endSheet(result: result)
    }

    @objc private func cancelClicked(_ sender: Any) {
        endSheet(result: nil)
    }

    // MARK: - Sheet Management

    /// パネルをシートとして表示する
    /// - Parameters:
    ///   - window: 親ウィンドウ
    ///   - name: 現在の書類タイプ名
    ///   - uti: 現在のUTI
    ///   - regex: 現在の正規表現
    ///   - isBuiltIn: ビルトインプリセットの場合 true（編集禁止）
    ///   - completionHandler: 完了ハンドラ（キャンセル時は nil）
    func beginSheet(for window: NSWindow,
                    name: String = "",
                    uti: String = "",
                    regex: String = "",
                    isBuiltIn: Bool = false,
                    completionHandler: @escaping (DocumentTypeEditResult?) -> Void) {
        self.sheetParentWindow = window
        self.completionHandler = completionHandler

        // 値をセット
        nameField.stringValue = name
        utiField.stringValue = uti
        regexField.stringValue = regex

        // ビルトインの場合は編集禁止
        nameField.isEditable = !isBuiltIn
        utiField.isEditable = !isBuiltIn
        regexField.isEditable = !isBuiltIn
        utiSamplePopup.isEnabled = !isBuiltIn

        if isBuiltIn {
            cancelButton.isHidden = true
            okButton.title = "OK".localized
        } else {
            cancelButton.isHidden = false
            okButton.title = "OK".localized
        }

        window.beginSheet(self) { _ in }
    }

    private func endSheet(result: DocumentTypeEditResult?) {
        sheetParentWindow?.endSheet(self)
        orderOut(nil)
        completionHandler?(result)
    }
}
