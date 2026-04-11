//
//  EditorWindowController+FindBar.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/26.
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

extension EditorWindowController {

    // MARK: - Find Bar

    @objc func showFindBar(_ sender: Any?) {
        if findBarViewController?.view.superview != nil {
            dismissFindBar()
        } else {
            presentFindBar(replaceMode: false)
        }
    }

    /// FindBar を表示して指定テキストで検索を実行する（Help 検索用）
    func showFindBarAndSearch(_ searchText: String) {
        presentFindBar(replaceMode: false)
        findBarViewController?.setSearchTextCaseInsensitive(searchText)

        // 新規ドキュメントの場合、ウィンドウ表示とテキストレイアウトの完了を待ってからスクロール
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.findBarViewController?.scrollToCurrentMatch()
        }
    }

    @objc func showFindAndReplaceBar(_ sender: Any?) {
        presentFindBar(replaceMode: true)
    }

    @objc func performFindNext(_ sender: Any?) {
        if let findBar = findBarViewController, findBar.view.superview != nil {
            findBar.findNext()
        } else {
            presentFindBar(replaceMode: false)
        }
    }

    @objc func performFindPrevious(_ sender: Any?) {
        if let findBar = findBarViewController, findBar.view.superview != nil {
            findBar.findPrevious()
        } else {
            presentFindBar(replaceMode: false)
        }
    }

    @objc func useSelectionForFind(_ sender: Any?) {
        guard let textView = currentTextView() else { return }
        let selectedRange = textView.selectedRange()
        guard selectedRange.length > 0 else { return }

        let selectedText = (textView.string as NSString).substring(with: selectedRange)

        // macOS 標準の Find Pasteboard にコピー
        let findPasteboard = NSPasteboard(name: .find)
        findPasteboard.clearContents()
        findPasteboard.setString(selectedText, forType: .string)

        if let findBar = findBarViewController, findBar.view.superview != nil {
            findBar.setSearchText(selectedText)
        }
    }

    internal func presentFindBar(replaceMode: Bool) {
        guard let contentView = window?.contentView, let splitView = self.splitView else { return }

        if findBarViewController == nil {
            findBarViewController = FindBarViewController()
            findBarViewController!.delegate = self
        }

        let findBar = findBarViewController!

        if findBar.view.superview == nil {
            let findBarView = findBar.view
            findBarView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(findBarView)

            // 既存の splitView.top = contentView.top 制約を無効化
            splitViewTopConstraint?.isActive = false

            // Find Bar の制約を設定
            NSLayoutConstraint.activate([
                findBarView.topAnchor.constraint(equalTo: contentView.topAnchor),
                findBarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                findBarView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                splitView.topAnchor.constraint(equalTo: findBarView.bottomAnchor),
            ])

            // テキストストレージの変更を監視
            findBar.observeTextStorage(textDocument?.textStorage)
        }

        findBar.setReplaceMode(replaceMode)

        // 選択テキストがあれば検索フィールドにセット
        if let textView = currentTextView() {
            let selectedRange = textView.selectedRange()
            if selectedRange.length > 0 && selectedRange.length < 200 {
                let selectedText = (textView.string as NSString).substring(with: selectedRange)
                if !selectedText.contains("\n") {
                    findBar.setSearchText(selectedText)
                }
            }
        }

        // レイアウト完了後にフォーカスをセット（メニューからの呼び出し時にも確実に動作させるため）
        DispatchQueue.main.async {
            findBar.focusSearchField()
        }
    }

    internal func dismissFindBar() {
        guard let findBarView = findBarViewController?.view,
              findBarView.superview != nil,
              let contentView = window?.contentView,
              let splitView = self.splitView else { return }

        // ハイライトをクリア
        findBarViewController?.clearSearch()

        // Find Bar を削除
        findBarView.removeFromSuperview()

        // 元の制約を復元: splitView.top = contentView.top
        let newTopConstraint = splitView.topAnchor.constraint(equalTo: contentView.topAnchor)
        newTopConstraint.isActive = true
        splitViewTopConstraint = newTopConstraint

        // テキストビューにフォーカスを戻す
        if let textView = currentTextView() {
            window?.makeFirstResponder(textView)
        }
    }
}

// MARK: - FindBarDelegate

extension EditorWindowController: FindBarDelegate {

    func findBarCurrentTextView() -> NSTextView? {
        return currentTextView()
    }

    func findBarTextStorage() -> NSTextStorage? {
        return textDocument?.textStorage
    }

    func findBarAllLayoutManagers() -> [NSLayoutManager] {
        return textDocument?.textStorage.layoutManagers ?? []
    }

    func findBarDidClose() {
        dismissFindBar()
    }
}
