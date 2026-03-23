//
//  EncodingManager.swift
//  Jedit-open
//
//  Based on Apple's TextEdit EncodingManager
//  Converted to Swift by Claude on 2026/01/16.
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

// MARK: - Global Constants for EncodingPopUpButtonCell compatibility

/// Indicates no encoding (Automatic) - used by EncodingPopUpButtonCell
let NoStringEncoding: UInt = 0xFFFFFFFF

/// Tag value indicating the popup wants an "Automatic" entry
let WantsAutomaticTag: Int = -1

/// エンコーディング管理クラス
/// ポップアップメニューへのエンコーディング一覧の設定と、カスタマイズ機能を提供
class EncodingManager: NSObject {

    // MARK: - Constants

    /// 無効なエンコーディングを表す定数
    static let noStringEncoding: String.Encoding = String.Encoding(rawValue: 0xFFFFFFFF)

    /// 「自動」を選択する際のタグ
    static let wantsAutomaticTag = -1

    /// 「カスタマイズ...」を選択する際のタグ
    static let customizeEncodingsTag = -2

    // MARK: - Singleton

    static let shared = EncodingManager()

    // MARK: - Properties

    /// 有効化されているエンコーディングのリスト
    private var encodings: [String.Encoding]?

    /// デフォルトでサポートするエンコーディング（CFStringEncoding値）
    private static let defaultEncodings: [CFStringEncoding] = [
        CFStringEncoding(CFStringBuiltInEncodings.UTF8.rawValue),
        CFStringEncoding(CFStringBuiltInEncodings.macRoman.rawValue),
        CFStringEncoding(CFStringBuiltInEncodings.windowsLatin1.rawValue),
        CFStringEncoding(CFStringEncodings.macJapanese.rawValue),
        CFStringEncoding(CFStringEncodings.shiftJIS.rawValue),
        CFStringEncoding(CFStringEncodings.macChineseTrad.rawValue),
        CFStringEncoding(CFStringEncodings.macKorean.rawValue),
        CFStringEncoding(CFStringEncodings.macChineseSimp.rawValue),
        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
    ]

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Public Methods

    /// 利用可能な全てのエンコーディングをソートして返す
    static func allAvailableStringEncodings() -> [String.Encoding] {
        var encodings: [String.Encoding] = []

        // CFStringGetListOfAvailableEncodingsを使用して利用可能なエンコーディングを取得
        guard let cfEncodings = CFStringGetListOfAvailableEncodings() else {
            return encodings
        }

        var index = 0
        while cfEncodings[index] != kCFStringEncodingInvalidId {
            let cfEncoding = cfEncodings[index]
            let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
            let encoding = String.Encoding(rawValue: nsEncoding)

            // 有効なエンコーディングで、ローカライズ名があるもののみ追加
            if nsEncoding != UInt(kCFStringEncodingInvalidId),
               !String.localizedName(of: encoding).isEmpty {
                encodings.append(encoding)
            }
            index += 1
        }

        let unicodeEncoding = CFStringEncoding(CFStringBuiltInEncodings.unicode.rawValue)

        // Mac互換エンコーディングでソート、Unicodeを先頭に
        encodings.sort { first, second in
            let cfFirst = CFStringConvertNSStringEncodingToEncoding(first.rawValue)
            let cfSecond = CFStringConvertNSStringEncodingToEncoding(second.rawValue)
            let macFirst = CFStringGetMostCompatibleMacStringEncoding(cfFirst)
            let macSecond = CFStringGetMostCompatibleMacStringEncoding(cfSecond)

            // Unicodeを先頭に
            if macFirst == unicodeEncoding || macSecond == unicodeEncoding {
                if macFirst == macSecond {
                    return first.rawValue < second.rawValue
                }
                return macFirst == unicodeEncoding
            }

            if macFirst != macSecond {
                return macFirst < macSecond
            }
            return first.rawValue < second.rawValue
        }

        return encodings
    }

    /// 有効化されているエンコーディングのリストを返す
    func enabledEncodings() -> [String.Encoding] {
        if let encodings = encodings {
            return encodings
        }

        // UserDefaultsから読み込み
        if let savedEncodings = UserDefaults.standard.array(forKey: "Encodings") as? [UInt] {
            let encs = savedEncodings.map { String.Encoding(rawValue: $0) }
            encodings = encs
            return encs
        }

        // デフォルトのエンコーディングリストを生成
        var encs: [String.Encoding] = []

        // UTF-8を先頭に追加
        encs.append(.utf8)

        // デフォルトエンコーディングを追加
        for cfEnc in Self.defaultEncodings {
            let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEnc)
            if nsEncoding != UInt(kCFStringEncodingInvalidId) {
                let encoding = String.Encoding(rawValue: nsEncoding)
                if !encs.contains(encoding) {
                    encs.append(encoding)
                }
            }
        }

        // システムのデフォルトエンコーディングを追加
        let defaultEncoding = String.defaultCStringEncoding
        if !encs.contains(defaultEncoding) {
            encs.append(defaultEncoding)
        }

        encodings = encs
        return encs
    }

    /// ポップアップボタンセル（NSPopUpButtonCell）にエンコーディングを設定
    /// EncodingPopUpButtonCellから呼び出される
    /// - Parameters:
    ///   - popup: 設定するポップアップボタンセル
    ///   - selectedEncoding: 初期選択するエンコーディング（UInt）
    ///   - includeDefaultItem: 「自動」項目を含めるかどうか
    func setupPopUpCell(_ popup: NSPopUpButtonCell,
                        selectedEncoding: UInt,
                        withDefaultEntry includeDefaultItem: Bool) {
        var encs = enabledEncodings()
        var itemToSelect = 0

        // Clear existing items
        popup.removeAllItems()

        // Add "Automatic" item if requested
        if includeDefaultItem {
            popup.addItem(withTitle: "Automatic".localized)
            if let item = popup.item(at: 0) {
                item.representedObject = NSNumber(value: NoStringEncoding)
                item.tag = WantsAutomaticTag
            }
        }

        // Make sure the selected encoding appears in the list
        if !includeDefaultItem && selectedEncoding != NoStringEncoding {
            let selectedEnc = String.Encoding(rawValue: selectedEncoding)
            if !encs.contains(selectedEnc) {
                encs.append(selectedEnc)
            }
        }

        // Fill with encodings
        for encoding in encs {
            if encoding.rawValue != 0 {
                let encodingName = String.localizedName(of: encoding)
                popup.addItem(withTitle: encodingName)
                if let lastItem = popup.lastItem {
                    lastItem.representedObject = NSNumber(value: encoding.rawValue)
                    lastItem.isEnabled = true
                    if encoding.rawValue == selectedEncoding {
                        itemToSelect = popup.numberOfItems - 1
                    }
                }
            }
        }

        // Add separator and "Customize" item
        if popup.numberOfItems > 0 {
            popup.menu?.addItem(NSMenuItem.separator())
        }
        popup.addItem(withTitle: "Customize Encodings List...".localized)
        if let lastItem = popup.lastItem {
            lastItem.action = #selector(showPanel(_:))
            lastItem.target = self
        }

        popup.selectItem(at: itemToSelect)
    }

    /// ポップアップボタンにエンコーディングを設定
    /// - Parameters:
    ///   - popup: 設定するポップアップボタン
    ///   - selectedEncoding: 初期選択するエンコーディング（nilの場合は先頭を選択）
    ///   - includeDefaultItem: 「自動」項目を含めるかどうか
    ///   - includeCustomizeItem: 「カスタマイズ...」項目を含めるかどうか
    ///   - target: カスタマイズアクションのターゲット
    ///   - action: カスタマイズアクションのセレクタ
    func setupPopUp(_ popup: NSPopUpButton, selectedEncoding: String.Encoding?, withDefaultEntry includeDefaultItem: Bool, includeCustomizeItem: Bool = false, target: AnyObject? = nil, action: Selector? = nil) {
        var encs = enabledEncodings()
        var itemToSelect = 0

        popup.removeAllItems()

        // 「自動」項目を追加
        if includeDefaultItem {
            popup.addItem(withTitle: "Automatic".localized)
            popup.lastItem?.tag = Self.wantsAutomaticTag
            popup.lastItem?.representedObject = Self.noStringEncoding
        }

        // 選択されたエンコーディングがリストにない場合は追加
        if let selected = selectedEncoding,
           selected != Self.noStringEncoding,
           !includeDefaultItem,
           !encs.contains(selected) {
            encs.append(selected)
        }

        // エンコーディングを追加
        for encoding in encs {
            let name = String.localizedName(of: encoding)
            if !name.isEmpty {
                popup.addItem(withTitle: name)
                popup.lastItem?.representedObject = encoding
                popup.lastItem?.tag = Int(encoding.rawValue)

                if let selected = selectedEncoding, encoding == selected {
                    itemToSelect = popup.numberOfItems - 1
                }
            }
        }

        // 「カスタマイズ...」項目を追加
        if includeCustomizeItem {
            popup.menu?.addItem(NSMenuItem.separator())
            let customizeTitle = "Customize Encoding List...".localized
            popup.addItem(withTitle: customizeTitle)
            popup.lastItem?.tag = Self.customizeEncodingsTag
            popup.lastItem?.target = target
            popup.lastItem?.action = action
        }

        popup.selectItem(at: itemToSelect)
    }

    /// ポップアップボタンのメニューにエンコーディングを設定（NSMenu用）
    func setupMenu(_ menu: NSMenu, selectedEncoding: String.Encoding?, withDefaultEntry includeDefaultItem: Bool) {
        var encs = enabledEncodings()

        menu.removeAllItems()

        // 「自動」項目を追加
        if includeDefaultItem {
            let item = NSMenuItem(title: "Automatic".localized, action: nil, keyEquivalent: "")
            item.tag = Self.wantsAutomaticTag
            item.representedObject = Self.noStringEncoding
            menu.addItem(item)
        }

        // 選択されたエンコーディングがリストにない場合は追加
        if let selected = selectedEncoding,
           selected != Self.noStringEncoding,
           !includeDefaultItem,
           !encs.contains(selected) {
            encs.append(selected)
        }

        // エンコーディングを追加
        for encoding in encs {
            let name = String.localizedName(of: encoding)
            if !name.isEmpty {
                let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                item.representedObject = encoding
                item.tag = Int(encoding.rawValue)
                menu.addItem(item)
            }
        }
    }

    /// エンコーディングリストの変更を保存・通知
    func noteEncodingListChange(writeDefault: Bool, postNotification: Bool) {
        if writeDefault, let encodings = encodings {
            let encodingValues = encodings.map { $0.rawValue }
            UserDefaults.standard.set(encodingValues, forKey: "Encodings")
        }

        if postNotification {
            NotificationCenter.default.post(name: .encodingsListChanged, object: nil)
        }
    }

    /// エンコーディングリストをリセット
    func revertToDefault() {
        encodings = nil
        UserDefaults.standard.removeObject(forKey: "Encodings")
        _ = enabledEncodings()  // デフォルトリストを再生成
        noteEncodingListChange(writeDefault: false, postNotification: true)
    }

    /// エンコーディングリストを設定
    func setEnabledEncodings(_ newEncodings: [String.Encoding]) {
        encodings = newEncodings
        noteEncodingListChange(writeDefault: true, postNotification: true)
    }

    // MARK: - Encoding Validation

    /// メニュー項目から String.Encoding を取得する
    /// representedObject が String.Encoding の場合と NSNumber の場合の両方に対応
    private func encoding(from item: NSMenuItem) -> String.Encoding? {
        if let enc = item.representedObject as? String.Encoding {
            return enc
        }
        if let encNumber = item.representedObject as? NSNumber {
            return String.Encoding(rawValue: encNumber.uintValue)
        }
        return nil
    }

    /// メニュー内のエンコーディング項目のうち、テキストを変換できないものを disable する
    /// - Parameters:
    ///   - menu: エンコーディングメニュー（NSMenu）
    ///   - text: 変換可否を判定するテキスト
    func disableIncompatibleEncodings(in menu: NSMenu, for text: String) {
        for i in 0..<menu.numberOfItems {
            guard let item = menu.item(at: i),
                  let enc = encoding(from: item) else { continue }
            item.isEnabled = canConvert(text: text, to: enc)
        }
    }

    /// メニューセル内のエンコーディング項目のうち、テキストを変換できないものを disable する
    /// - Parameters:
    ///   - cell: エンコーディングポップアップセル（NSPopUpButtonCell）
    ///   - text: 変換可否を判定するテキスト
    func disableIncompatibleEncodings(in cell: NSPopUpButtonCell, for text: String) {
        for i in 0..<cell.numberOfItems {
            guard let item = cell.item(at: i),
                  let enc = encoding(from: item) else { continue }
            item.isEnabled = canConvert(text: text, to: enc)
        }
    }

    /// テキストが指定エンコーディングで変換可能かを安全に判定する
    /// NSTextAttachment の特殊文字 (U+FFFC) 等が含まれる場合に NSException が発生するため、
    /// NSString の canBeConverted(to:) を使用してクラッシュを防止する
    private func canConvert(text: String, to encoding: String.Encoding) -> Bool {
        return (text as NSString).canBeConverted(to: encoding.rawValue)
    }

    /// エンコーディングが Unicode 系かどうかを判定
    /// BOM チェックボックスの有効/無効判定に使用
    static func isUnicodeEncoding(_ encoding: String.Encoding) -> Bool {
        return encoding == .utf8 || encoding == .utf16
            || encoding == .utf16BigEndian || encoding == .utf16LittleEndian
            || encoding == .utf32 || encoding == .utf32BigEndian
            || encoding == .utf32LittleEndian
    }

    // MARK: - Actions

    /// カスタマイズパネルを表示（Preferencesウィンドウを開いてEncodingsカテゴリを選択）
    @objc func showPanel(_ sender: Any?) {
        // AppDelegateからPreferencesウィンドウを取得して表示
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showPreferencesWindow(selectingCategory: "encodings")
        }
    }
}

// MARK: - Notification Name Extension

extension Notification.Name {
    static let encodingsListChanged = Notification.Name("EncodingsListChanged")
}
