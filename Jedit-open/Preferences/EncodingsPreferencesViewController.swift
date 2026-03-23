//
//  EncodingsPreferencesViewController.swift
//  Jedit-open
//
//  Created by Claude on 2026/02/02.
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

class EncodingsPreferencesViewController: NSViewController {

    // MARK: - IBOutlets

    @IBOutlet weak var plainTextEncodingForReadPopUp: NSPopUpButton!
    @IBOutlet weak var plainTextEncodingForWritePopUp: NSPopUpButton!
    @IBOutlet weak var lineEndingForWritePopUp: NSPopUpButton!
    @IBOutlet weak var bomForWritePopUp: NSPopUpButton!
    @IBOutlet weak var convertYenToBackSlashCheckBox: NSButton!
    @IBOutlet weak var convertOverlineToTildeCheckBox: NSButton!
    @IBOutlet weak var convertFullWidthTildeCheckBox: NSButton!

    // MARK: - Properties

    private let defaults = UserDefaults.standard

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupEncodingPopups()
        displaySettings()
    }

    // MARK: - Setup

    /// エンコーディングポップアップの初期設定
    private func setupEncodingPopups() {
        // Opening files のエンコーディングポップアップ（Automatic付き、カスタマイズ項目付き）
        if let popup = plainTextEncodingForReadPopUp {
            EncodingManager.shared.setupPopUp(
                popup,
                selectedEncoding: nil,  // displaySettings()で設定
                withDefaultEntry: true,  // "Automatic"項目を含める
                includeCustomizeItem: true,
                target: self,
                action: #selector(customizeEncodingList(_:))
            )
        }

        // Saving files のエンコーディングポップアップ（Automatic付き、カスタマイズ項目付き）
        if let popup = plainTextEncodingForWritePopUp {
            EncodingManager.shared.setupPopUp(
                popup,
                selectedEncoding: nil,  // displaySettings()で設定
                withDefaultEntry: true,  // "Automatic"項目を含める
                includeCustomizeItem: true,
                target: self,
                action: #selector(customizeEncodingList(_:))
            )
        }

        // エンコーディングリスト変更通知を監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(encodingsListDidChange(_:)),
            name: .encodingsListChanged,
            object: nil
        )
    }

    /// カスタマイズパネルを表示
    @objc private func customizeEncodingList(_ sender: Any) {
        // カスタマイズパネルを表示
        EncodingCustomizeWindowController.showPanel()

        // 元のエンコーディングを再選択（「カスタマイズ...」項目が選択されたままにならないように）
        displayEncodingSelections()
    }

    /// エンコーディングリストが変更されたとき
    @objc private func encodingsListDidChange(_ notification: Notification) {
        // 現在の設定を取得
        let encodingForReadInt = defaults.integer(forKey: UserDefaults.Keys.plainTextEncodingForRead)
        let encodingForRead: String.Encoding? = encodingForReadInt <= 0 ? nil : String.Encoding(rawValue: UInt(encodingForReadInt))

        let encodingForWriteInt = defaults.integer(forKey: UserDefaults.Keys.plainTextEncodingForWrite)
        let encodingForWrite: String.Encoding? = encodingForWriteInt <= 0 ? nil : String.Encoding(rawValue: UInt(encodingForWriteInt))

        // ポップアップを再構築
        if let popup = plainTextEncodingForReadPopUp {
            EncodingManager.shared.setupPopUp(
                popup,
                selectedEncoding: encodingForRead,
                withDefaultEntry: true,
                includeCustomizeItem: true,
                target: self,
                action: #selector(customizeEncodingList(_:))
            )
        }

        if let popup = plainTextEncodingForWritePopUp {
            EncodingManager.shared.setupPopUp(
                popup,
                selectedEncoding: encodingForWrite,
                withDefaultEntry: true,
                includeCustomizeItem: true,
                target: self,
                action: #selector(customizeEncodingList(_:))
            )
        }
    }

    // MARK: - Display Settings

    private func displaySettings() {
        // Encoding Selections
        displayEncodingSelections()

        // Line Ending for Write
        let lineEnding = defaults.integer(forKey: UserDefaults.Keys.plainTextLineEndingForWrite)
        lineEndingForWritePopUp?.selectItem(withTag: lineEnding)

        // BOM for Write
        let bom = defaults.integer(forKey: UserDefaults.Keys.plainTextBomForWrite)
        bomForWritePopUp?.selectItem(withTag: bom)

        // Checkboxes
        convertYenToBackSlashCheckBox?.state = defaults.bool(forKey: UserDefaults.Keys.convertYenToBackSlash) ? .on : .off
        convertOverlineToTildeCheckBox?.state = defaults.bool(forKey: UserDefaults.Keys.convertOverlineToTilde) ? .on : .off
        convertFullWidthTildeCheckBox?.state = defaults.bool(forKey: UserDefaults.Keys.convertFullWidthTilde) ? .on : .off
    }

    /// エンコーディングポップアップの選択を設定
    private func displayEncodingSelections() {
        // Plain Text Encoding for Read
        let encodingForReadInt = defaults.integer(forKey: UserDefaults.Keys.plainTextEncodingForRead)
        selectEncodingInPopUp(plainTextEncodingForReadPopUp, encodingInt: encodingForReadInt)

        // Plain Text Encoding for Write
        let encodingForWriteInt = defaults.integer(forKey: UserDefaults.Keys.plainTextEncodingForWrite)
        selectEncodingInPopUp(plainTextEncodingForWritePopUp, encodingInt: encodingForWriteInt)
    }

    /// Select encoding in popup by finding the item with matching representedObject or tag
    private func selectEncodingInPopUp(_ popUp: NSPopUpButton?, encodingInt: Int) {
        guard let popUp = popUp else { return }

        // 0 or negative means Automatic - select first item (which has tag -1)
        if encodingInt <= 0 {
            popUp.selectItem(withTag: EncodingManager.wantsAutomaticTag)
            return
        }

        // Try to find item with matching tag (encoding rawValue)
        if popUp.selectItem(withTag: encodingInt) {
            return
        }

        // Try to find item with matching represented object
        for (index, item) in popUp.itemArray.enumerated() {
            if let encoding = item.representedObject as? String.Encoding,
               encoding.rawValue == UInt(encodingInt) {
                popUp.selectItem(at: index)
                return
            }
        }

        // Default to first item (Automatic)
        popUp.selectItem(at: 0)
    }

    // MARK: - IBActions

    @IBAction func plainTextEncodingForReadChanged(_ sender: Any) {
        guard let popUp = sender as? NSPopUpButton,
              let selectedItem = popUp.selectedItem else { return }

        // カスタマイズ項目が選択されたらスキップ
        if selectedItem.tag == EncodingManager.customizeEncodingsTag {
            return
        }

        let encoding: Int
        if selectedItem.tag == EncodingManager.wantsAutomaticTag {
            encoding = 0  // Automatic
        } else if let representedEncoding = selectedItem.representedObject as? String.Encoding {
            encoding = Int(representedEncoding.rawValue)
        } else {
            encoding = selectedItem.tag
        }

        defaults.set(encoding, forKey: UserDefaults.Keys.plainTextEncodingForRead)
        NotificationCenter.default.post(name: .encodingPreferencesDidChange, object: nil)
    }

    @IBAction func plainTextEncodingForWriteChanged(_ sender: Any) {
        guard let popUp = sender as? NSPopUpButton,
              let selectedItem = popUp.selectedItem else { return }

        // カスタマイズ項目が選択されたらスキップ
        if selectedItem.tag == EncodingManager.customizeEncodingsTag {
            return
        }

        let encoding: Int
        if selectedItem.tag == EncodingManager.wantsAutomaticTag {
            encoding = 0  // Automatic
        } else if let representedEncoding = selectedItem.representedObject as? String.Encoding {
            encoding = Int(representedEncoding.rawValue)
        } else {
            encoding = selectedItem.tag
        }

        defaults.set(encoding, forKey: UserDefaults.Keys.plainTextEncodingForWrite)
        NotificationCenter.default.post(name: .encodingPreferencesDidChange, object: nil)
    }

    @IBAction func lineEndingForWriteChanged(_ sender: Any) {
        guard let popUp = sender as? NSPopUpButton else { return }
        let tag = popUp.selectedTag()
        defaults.set(tag, forKey: UserDefaults.Keys.plainTextLineEndingForWrite)
        NotificationCenter.default.post(name: .encodingPreferencesDidChange, object: nil)
    }

    @IBAction func bomForWriteChanged(_ sender: Any) {
        guard let popUp = sender as? NSPopUpButton else { return }
        let tag = popUp.selectedTag()
        defaults.set(tag, forKey: UserDefaults.Keys.plainTextBomForWrite)
        NotificationCenter.default.post(name: .encodingPreferencesDidChange, object: nil)
    }

    @IBAction func convertYenToBackSlashChanged(_ sender: Any) {
        guard let checkBox = sender as? NSButton else { return }
        defaults.set(checkBox.state == .on, forKey: UserDefaults.Keys.convertYenToBackSlash)
        NotificationCenter.default.post(name: .encodingPreferencesDidChange, object: nil)
    }

    @IBAction func convertOverlineToTildeChanged(_ sender: Any) {
        guard let checkBox = sender as? NSButton else { return }
        defaults.set(checkBox.state == .on, forKey: UserDefaults.Keys.convertOverlineToTilde)
        NotificationCenter.default.post(name: .encodingPreferencesDidChange, object: nil)
    }

    @IBAction func convertFullWidthTildeChanged(_ sender: Any) {
        guard let checkBox = sender as? NSButton else { return }
        defaults.set(checkBox.state == .on, forKey: UserDefaults.Keys.convertFullWidthTilde)
        NotificationCenter.default.post(name: .encodingPreferencesDidChange, object: nil)
    }

    @IBAction func revertToDefaults(_ sender: Any) {
        // Remove all encoding-related keys to reset to defaults
        defaults.removeObject(forKey: UserDefaults.Keys.plainTextEncodingForRead)
        defaults.removeObject(forKey: UserDefaults.Keys.plainTextEncodingForWrite)
        defaults.removeObject(forKey: UserDefaults.Keys.plainTextLineEndingForWrite)
        defaults.removeObject(forKey: UserDefaults.Keys.plainTextBomForWrite)
        defaults.removeObject(forKey: UserDefaults.Keys.convertYenToBackSlash)
        defaults.removeObject(forKey: UserDefaults.Keys.convertOverlineToTilde)
        defaults.removeObject(forKey: UserDefaults.Keys.convertFullWidthTilde)

        // Refresh display
        displaySettings()

        NotificationCenter.default.post(name: .encodingPreferencesDidChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Notification Name Extension

extension Notification.Name {
    static let encodingPreferencesDidChange = Notification.Name("encodingPreferencesDidChange")
}
