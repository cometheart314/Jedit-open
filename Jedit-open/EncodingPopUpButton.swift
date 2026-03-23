//
//  EncodingPopUpButton.swift
//  Jedit-open
//
//  Created by Claude on 2026/02/10.
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

/// エンコーディング選択用ポップアップボタン
/// ポップアップが開く瞬間に変換不能エンコーディングを disable する
/// Info Panel、Toolbar などで統一的に使用する
class EncodingPopUpButton: NSPopUpButton {

    // MARK: - Properties

    /// 変換可否判定に使用するテキストを返すクロージャ
    /// ポップアップが開く瞬間に呼び出される
    var textForValidation: (() -> String?)?

    // MARK: - Menu Open Override

    /// 変換不能チェックをスキップするテキストサイズの閾値（バイト数）
    /// これを超えるドキュメントでは、パフォーマンスのためチェックを行わない
    static let validationSizeLimit = 100_000

    /// ポップアップメニューが開く直前に変換不能エンコーディングを disable
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        guard let text = textForValidation?() else { return }

        // 大きなドキュメントではチェックをスキップ（パフォーマンス対策）
        guard text.utf8.count <= Self.validationSizeLimit else { return }

        // autoenablesItems を無効にしないと、AppKit がメニュー表示時に
        // isEnabled を自動的に true に戻してしまう
        menu.autoenablesItems = false
        EncodingManager.shared.disableIncompatibleEncodings(in: menu, for: text)
    }
}
