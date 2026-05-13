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

// MARK: - Markdown 編集ロック中のキー入力ガイダンス
//
// .md を開いた直後の書類は「リッチテキスト表示・編集ロック」状態になっており、
// 初見のユーザーは「タイプしても反応しない」のを不具合と勘違いしてしまう。
// 編集ロック中の書類に対してキー入力が来たらアラートを出し、プレーンテキスト
// モードへの切り替えを案内する。

extension JeditTextView {

    /// keyDown を奪って Markdown 編集ロック状態を判定する。
    /// 編集ロック中の Markdown リッチテキストに typing 系のキー入力が来た場合のみ
    /// アラートを表示し、それ以外は Pro フックを経由して super に流す。
    override func keyDown(with event: NSEvent) {
        if shouldPromptForMarkdownReadOnlyEdit(event: event) {
            presentMarkdownReadOnlyEditPrompt()
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
    /// - 書類が Markdown かつ現在リッチテキストモード
    /// - イベントが Cmd / Ctrl ショートカットでなく、テキスト入力系
    private func shouldPromptForMarkdownReadOnlyEdit(event: NSEvent) -> Bool {
        if isEditable { return false }

        guard let wc = window?.windowController as? EditorWindowController,
              let document = wc.textDocument,
              document.isMarkdownDocument,
              document.documentType != .plain else {
            return false
        }

        // Cmd / Control が押されていれば、ショートカットなので素通り
        let mods = event.modifierFlags
        if mods.contains(.command) || mods.contains(.control) {
            return false
        }

        // 修飾キー単独 (Shift / Option / Function 単独) も素通り
        guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else {
            return false
        }

        // 矢印キーなどファンクションキー領域 (0xF700–0xF8FF) は編集行為ではないので素通り。
        // それ以外 (英数字、記号、Return、Backspace 等) を「編集しようとした」と見なす。
        let hasTextInput = chars.unicodeScalars.contains { scalar in
            scalar.value < 0xF700
        }
        return hasTextInput
    }

    /// 編集ロック中の Markdown 書類向けのガイダンスアラートを表示する。
    /// アラートは現在のウィンドウにシート表示する。
    private func presentMarkdownReadOnlyEditPrompt() {
        guard let wc = window?.windowController as? EditorWindowController,
              let parentWindow = window else { return }

        // 連打防止: シートが既に出ているならスキップ
        if parentWindow.attachedSheet != nil { return }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Markdown documents are read-only in rich text mode.".localized
        alert.informativeText = "Markdown documents are kept read-only while shown as rich text so the original Markdown source is preserved. To edit, switch to plain text.".localized
        alert.addButton(withTitle: "Switch to Plain Text".localized)  // .alertFirstButtonReturn
        alert.addButton(withTitle: "Cancel".localized)                 // .alertSecondButtonReturn

        alert.beginSheetModal(for: parentWindow) { [weak wc] response in
            guard let wc = wc else { return }
            if response == .alertFirstButtonReturn {
                // プレーンテキストに切り替え (toggleRichText が isRich→plain で
                // Markdown ソース復元 + 編集ロック解除をまとめて行う)
                wc.performToggleRichText(newFileType: nil)
            }
        }
    }
}
