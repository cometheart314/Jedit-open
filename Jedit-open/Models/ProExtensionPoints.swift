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
    /// JeditTextView の keyDown を Pro 側でフックする拡張点。
    /// Pro のカスタムキーバインド設定がこの event を処理した場合は true を返し、
    /// その場合 Open 側は super.keyDown を呼ばずに終わる。
    /// 既定実装は false (= 何もしない)。
    func handleTextViewKeyDown(_ event: NSEvent, in textView: NSTextView) -> Bool
}

extension EditorFeatureProvider {
    func handleTextViewKeyDown(_ event: NSEvent, in textView: NSTextView) -> Bool {
        return false
    }
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

/// Pro 版が提供する代替の読み上げエンジン (例: Google Cloud Text-to-Speech)。
///
/// Open の `startSpeaking(_:)` 内で、発話対象の attributed string から speechText
/// (ルビ置換適用済み) と SpeechSegment 列を組み立てた後、本プロトコルが登録されて
/// いれば `startSpeaking(...)` に渡して引き継ぐ。Provider が true を返したら
/// Open は AVSpeechSynthesizer 経路を走らせず、Pro 側に発話を委任する。
/// false を返した場合は従来の Apple 経路にフォールバックする。
///
/// 発話進行時のハイライトや、終了時の選択範囲復元は、Provider から
/// `JeditTextView.beginExternalSpeechSession(...)` /
/// `updateExternalSpeechHighlight(docRange:)` /
/// `endExternalSpeechSession()` を呼び出すことで Open 側に反映する。
protocol SpeechEngineProvider {
    /// この Provider が現在発話セッションを所有しているか。
    /// JeditTextView.isSpeechActive 判定で参照される。
    var isSpeaking: Bool { get }

    /// 発話開始。Open 側で組み立てた speechText (ルビ置換適用済み) と
    /// SpeechSegment 列を受け取って、自前エンジンで再生する。
    /// 成功した (= 引き受けた) 場合は true を返す。false を返した場合、
    /// 呼び出し側 (Open) は Apple フォールバックを実行する。
    func startSpeaking(on textView: NSTextView,
                       speechText: String,
                       segments: [SpeechSegment],
                       safeRange: NSRange,
                       hadSelection: Bool) -> Bool

    /// 発話を停止する。stopSpeaking(_:) や cleanup から呼ばれる。
    /// silently=true なら UI への通知をスキップ (再入防止用)。
    func stopSpeaking(silently: Bool)
}

/// 機能プロバイダーのレジストリ（シングルトン）
/// Pro版は起動時にプロバイダーを登録する
class FeatureProviderRegistry {
    static let shared = FeatureProviderRegistry()
    var editorProvider: EditorFeatureProvider?
    var documentProvider: DocumentFeatureProvider?
    /// サイドバーに差し込むプロバイダー一覧。先頭から順に上から並ぶ。
    var sidebarPaneProviders: [SidebarPaneProvider] = []
    /// 代替読み上げエンジン (Google TTS 等)。Pro が起動時に注入する。
    var speechEngineProvider: SpeechEngineProvider?
    private init() {}
}
