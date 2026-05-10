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

/// Pro 版が注入する追加設定ペインの記述子
struct PreferencePaneDescriptor {
    /// ペインの一意識別子（PreferencesWindowController#selectCategory(identifier:) で使用）
    let identifier: String
    /// サイドバーに表示するタイトル
    let title: String
    /// サイドバーに表示するアイコン
    let icon: NSImage
    /// ペイン表示時に NSViewController を生成するファクトリ
    /// （表示の度に新規生成することで状態の取り回しを単純化）
    let makeViewController: () -> NSViewController
}

/// Pro版で追加のツールバー項目やメニュー項目を提供するプロトコル
protocol EditorFeatureProvider {
    /// アプリ起動時に呼ばれる（メニュー追加、初期設定など）
    func applicationDidFinishLaunching()
    /// 追加のツールバー項目識別子
    func additionalToolbarItemIdentifiers() -> [NSToolbarItem.Identifier]
    /// 追加のメニュー項目
    func additionalMenuItems(for menu: NSMenu) -> [NSMenuItem]
    /// 追加の設定ペイン
    func additionalPreferencePanes() -> [PreferencePaneDescriptor]
}

/// Pro版で追加のドキュメント機能を提供するプロトコル
protocol DocumentFeatureProvider {
    /// 追加のドキュメントタイプ
    func additionalDocumentTypes() -> [String]
    /// 追加のエクスポートフォーマット
    func additionalExportFormats() -> [String]
}

/// エディタウィンドウのサイドバー（split view 左ペイン）に
/// Pro 版が独自のビューを差し込むための拡張点。
///
/// 例: スマートインデックス、ブックマーク一覧、検索結果一覧など。
/// 同一ウィンドウに複数のプロバイダーを並べることを想定して
/// レジストリは配列で保持する。
protocol SidebarPaneProvider {
    /// 一意識別子（複数 Provider 区別用、UserDefaults キー、ツールバー項目識別子の生成に使用）
    var identifier: String { get }
    /// メニュー項目やツールバーチップに表示する名前
    var displayName: String { get }
    /// 表示切替ボタンに使うアイコン（SF Symbol 推奨）
    var icon: NSImage { get }
    /// 既定の幅（pt）
    var defaultWidth: CGFloat { get }
    /// 書類ごとに新規生成する NSViewController を返す。
    /// ウィンドウ 1 つにつき 1 インスタンスを保持する想定。
    func makeViewController(for document: Document) -> NSViewController
}

/// 機能プロバイダーのレジストリ（シングルトン）
/// Pro版は起動時にプロバイダーを登録する
class FeatureProviderRegistry {
    static let shared = FeatureProviderRegistry()
    var editorProvider: EditorFeatureProvider?
    var documentProvider: DocumentFeatureProvider?
    /// サイドバーに差し込むプロバイダー一覧。先頭から順に上から並ぶ。
    var sidebarPaneProviders: [SidebarPaneProvider] = []
    private init() {}
}
