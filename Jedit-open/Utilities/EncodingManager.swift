//
//  EncodingManager.swift
//  Jedit-open
//
//  Based on Apple's TextEdit EncodingManager
//  Converted to Swift by Claude on 2026/01/16.
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
            popup.addItem(withTitle: NSLocalizedString("Automatic", comment: "Encoding popup entry indicating automatic choice of encoding"))
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
        popup.addItem(withTitle: NSLocalizedString("Customize Encodings List...", comment: "Encoding popup entry for bringing up the Customize Encodings List panel"))
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
            popup.addItem(withTitle: NSLocalizedString("Automatic", comment: "Automatic encoding selection"))
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
            let customizeTitle = NSLocalizedString("Customize Encoding List...", comment: "Menu item to customize encoding list")
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
            let item = NSMenuItem(title: NSLocalizedString("Automatic", comment: "Automatic encoding selection"), action: nil, keyEquivalent: "")
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

    // MARK: - Actions

    /// カスタマイズパネルを表示
    @objc func showPanel(_ sender: Any?) {
        // TODO: Implement encoding customization panel if needed
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Customize Encodings", comment: "")
        alert.informativeText = NSLocalizedString("Encoding customization panel is not yet implemented.", comment: "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.runModal()
    }
}

// MARK: - Notification Name Extension

extension Notification.Name {
    static let encodingsListChanged = Notification.Name("EncodingsListChanged")
}
