//
//  EditorWindowController+SplitView.swift
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

    // MARK: - Split View Actions

    @IBAction func toggleSplitView(_ sender: Any?) {
        // 現在のモードに応じてトグル
        if splitMode == .none {
            setSplitMode(.vertical)
        } else {
            setSplitMode(.none)
        }
    }

    @IBAction func setNoSplit(_ sender: Any?) {
        setSplitMode(.none)
    }

    @IBAction func setHorizontalSplit(_ sender: Any?) {
        setSplitMode(.horizontal)
    }

    @IBAction func setVerticalSplit(_ sender: Any?) {
        setSplitMode(.vertical)
    }

    /// スプリットボタンから呼び出す: 単一ビューに戻す
    @objc func collapseViews(_ sender: Any?) {
        setSplitMode(.none)
    }

    /// スプリットボタンから呼び出す: 水平分割
    @objc func splitHorizontally(_ sender: Any?) {
        setSplitMode(.horizontal)
    }

    /// スプリットボタンから呼び出す: 垂直分割
    @objc func splitVertically(_ sender: Any?) {
        setSplitMode(.vertical)
    }

    internal func setSplitMode(_ mode: SplitMode) {
        guard let splitView = splitView, !isSettingUpSplit else { return }
        isSettingUpSplit = true
        defer { isSettingUpSplit = false }

        splitMode = mode

        switch mode {
        case .none:
            // 2つ目のペインを折りたたむ
            if splitView.subviews.count > 1 {
                splitView.subviews[1].isHidden = true
            }
        case .horizontal:
            // 水平スプリット（上下に分割）
            splitView.isVertical = false
            if splitView.subviews.count > 1 {
                splitView.subviews[1].isHidden = false
            }
        case .vertical:
            // 垂直スプリット（左右に分割）
            splitView.isVertical = true
            if splitView.subviews.count > 1 {
                splitView.subviews[1].isHidden = false
            }
        }

        splitView.adjustSubviews()

        // splitViewの状態に合わせてtextViewsを再設定
        if let textDocument = self.textDocument {
            setupTextViews(with: textDocument.textStorage)
        }

        // 分割時、新しいビューの倍率を元のビューに合わせる
        if mode != .none,
           let sv1 = scrollView1,
           let sv2 = scrollView2 {
            sv2.setZoomLevel(sv1.magnification)
        }

        // ルーラーの表示状態を更新（updateContinuousModeRuler内でtile()とupdateTextViewSizeが呼ばれる）
        updateRulerVisibility()

        // スプリット直後はcontentViewのフレームがまだ更新されていない場合があるため、
        // 次のランループでもう一度ルーラーとテキストビューサイズを更新
        DispatchQueue.main.async { [weak self] in
            self?.updateRulerVisibility()
        }
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, shouldHideDividerAt dividerIndex: Int) -> Bool {
        // 2つ目のビューが非表示の場合、スプリットバーを非表示にする
        if splitView.subviews.count > 1 {
            return splitView.subviews[1].isHidden
        }
        return false
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        // 通常モードの場合、テキストビューのサイズを更新
        guard displayMode == .continuous else { return }

        // ルーラーの表示状態を更新
        updateRulerVisibility()

        // ルーラー更新後にテキストビューのサイズを更新
        if let scrollView = scrollView1 {
            updateTextViewSize(for: scrollView)
        }

        if let scrollView = scrollView2, !scrollView.isHidden {
            updateTextViewSize(for: scrollView)
        }
    }
}
