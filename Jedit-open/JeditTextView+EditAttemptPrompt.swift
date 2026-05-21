//
//  JeditTextView+EditAttemptPrompt.swift
//  Jedit-open
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

import Cocoa

// MARK: - 編集ロック中のキー入力ガイダンス
//
// .md / .doc / .docx / .odt を開いた直後の書類は「リッチテキスト表示・編集ロック」
// 状態になっており、初見のユーザーは「タイプしても反応しない」のを不具合と
// 勘違いしてしまう。編集ロック中の書類に対してキー入力が来たらアラートを出し、
// 適切な解除方法（プレーンテキスト切替 / ロック解除 / 複製編集）を案内する。

extension JeditTextView {

    /// 編集ロック中の書類で、キー入力時にどのプロンプトを出すかを表す。
    fileprivate enum ReadOnlyEditPromptKind {
        /// Markdown リッチテキスト表示中 → プレーンテキストへの切替を案内
        case markdown
        /// .doc / .docx / .odt から読み込んだ書類 → 解除 / 複製を案内
        case imported
    }

    /// keyDown を奪って編集ロック状態を判定する。
    /// 編集ロック中の書類に typing 系のキー入力が来た場合のみアラートを表示し、
    /// それ以外は Pro フックを経由して super に流す。
    override func keyDown(with event: NSEvent) {
        if let kind = readOnlyEditPromptKind(for: event) {
            presentReadOnlyEditPrompt(kind: kind)
            return
        }
        // Pro 拡張: カスタムキーバインドの処理。true なら処理済みとして打ち切る。
        if FeatureProviderRegistry.shared.editorProvider?
            .handleTextViewKeyDown(event, in: self) == true {
            return
        }
        super.keyDown(with: event)
    }

    /// 今回の keyDown がアラート対象かを判定する。
    /// - 編集ロック中 (`isEditable == false`)
    /// - 書類が Markdown リッチテキスト、または Word/ODT インポート
    /// - イベントが Cmd / Ctrl ショートカットでなく、テキスト入力系
    fileprivate func readOnlyEditPromptKind(for event: NSEvent) -> ReadOnlyEditPromptKind? {
        if isEditable { return nil }

        guard let wc = window?.windowController as? EditorWindowController,
              let document = wc.textDocument else {
            return nil
        }

        if !isTextInputEvent(event) { return nil }

        // Markdown はリッチテキスト表示中のみ対象（プレーンに切り替えれば編集可能）
        if document.isMarkdownDocument && document.documentType != .plain {
            return .markdown
        }

        // Word / ODT からインポートされた書類は常に対象
        if document.isImportedDocument {
            return .imported
        }

        return nil
    }

    /// このキーイベントが「編集しようとした」入力かを判定する。
    /// - Cmd / Ctrl 修飾下のショートカットは対象外
    /// - 矢印キーなどファンクションキー領域 (0xF700–0xF8FF) も対象外
    private func isTextInputEvent(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags
        if mods.contains(.command) || mods.contains(.control) {
            return false
        }
        guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else {
            return false
        }
        return chars.unicodeScalars.contains { scalar in
            scalar.value < 0xF700
        }
    }

    /// 編集ロック中書類向けのガイダンスアラートを種類に応じて表示する。
    /// アラートは現在のウィンドウにシート表示する。
    fileprivate func presentReadOnlyEditPrompt(kind: ReadOnlyEditPromptKind) {
        guard let wc = window?.windowController as? EditorWindowController,
              let parentWindow = window else { return }

        // 連打防止: シートが既に出ているならスキップ
        if parentWindow.attachedSheet != nil { return }

        switch kind {
        case .markdown:
            presentMarkdownReadOnlyEditPrompt(in: parentWindow, windowController: wc)
        case .imported:
            presentImportedReadOnlyEditPrompt(in: parentWindow, windowController: wc)
        }
    }

    /// Markdown リッチテキスト表示中のガイダンス。
    /// プレーンテキスト切替で Markdown ソース復元 + 編集ロック解除を行う。
    private func presentMarkdownReadOnlyEditPrompt(in parentWindow: NSWindow,
                                                   windowController wc: EditorWindowController) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Markdown documents are read-only in rich text mode.".localized
        alert.informativeText = "Markdown documents are kept read-only while shown as rich text so the original Markdown source is preserved. To edit, switch to plain text.".localized
        alert.addButton(withTitle: "Switch to Plain Text".localized)  // .alertFirstButtonReturn
        alert.addButton(withTitle: "Cancel".localized)                 // .alertSecondButtonReturn

        alert.beginSheetModal(for: parentWindow) { [weak wc] response in
            guard let wc = wc else { return }
            if response == .alertFirstButtonReturn {
                wc.performToggleRichText(newFileType: nil)
            }
        }
    }

    /// Word / ODT からインポートした書類向けのガイダンス。
    /// 「書き込み禁止を解除して編集」「複製して別の書類で編集」「キャンセル」の 3 択。
    private func presentImportedReadOnlyEditPrompt(in parentWindow: NSWindow,
                                                   windowController wc: EditorWindowController) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "This document is read-only.".localized
        alert.informativeText = "This document was imported from a format with limited compatibility. Some formatting may not be fully preserved when saved.".localized
        alert.addButton(withTitle: "Unlock and Edit".localized)                       // .alertFirstButtonReturn
        alert.addButton(withTitle: "Duplicate and Edit in New Document".localized)   // .alertSecondButtonReturn
        alert.addButton(withTitle: "Cancel".localized)                                // .alertThirdButtonReturn

        alert.beginSheetModal(for: parentWindow) { [weak wc] response in
            guard let wc = wc else { return }
            switch response {
            case .alertFirstButtonReturn:
                // 編集ロック解除 (互換性警告は既にこのダイアログで説明済みなので
                // performSetPreventEditing を直接呼ぶ)
                wc.performSetPreventEditing(editable: true)
            case .alertSecondButtonReturn:
                // 複製: 新しい書類を作って編集可能状態で開く
                wc.duplicateImportedDocumentForEditing()
            default:
                break
            }
        }
    }
}
