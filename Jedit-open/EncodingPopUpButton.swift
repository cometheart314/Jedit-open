//
//  EncodingPopUpButton.swift
//  Jedit-open
//
//  Created by Claude on 2026/02/10.
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
