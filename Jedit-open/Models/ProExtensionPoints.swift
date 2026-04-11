//
//  ProExtensionPoints.swift
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

/// Pro版で追加のツールバー項目やメニュー項目を提供するプロトコル
protocol EditorFeatureProvider {
    /// 追加のツールバー項目識別子
    func additionalToolbarItemIdentifiers() -> [NSToolbarItem.Identifier]
    /// 追加のメニュー項目
    func additionalMenuItems(for menu: NSMenu) -> [NSMenuItem]
    /// 追加の設定パネル
    func additionalPreferencePanes() -> [NSViewController]
}

/// Pro版で追加のドキュメント機能を提供するプロトコル
protocol DocumentFeatureProvider {
    /// 追加のドキュメントタイプ
    func additionalDocumentTypes() -> [String]
    /// 追加のエクスポートフォーマット
    func additionalExportFormats() -> [String]
}

/// 機能プロバイダーのレジストリ（シングルトン）
/// Pro版は起動時にプロバイダーを登録する
class FeatureProviderRegistry {
    static let shared = FeatureProviderRegistry()
    var editorProvider: EditorFeatureProvider?
    var documentProvider: DocumentFeatureProvider?
    private init() {}
}
