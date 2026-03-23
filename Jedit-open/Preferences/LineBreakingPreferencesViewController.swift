//
//  LineBreakingPreferencesViewController.swift
//  Jedit-open
//
//  Created by Claude on 2026/02/05.
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

class LineBreakingPreferencesViewController: NSViewController {

    // MARK: - IBOutlets

    @IBOutlet weak var cantBeTopCharsField: NSTextField!
    @IBOutlet weak var cantBeEndCharsField: NSTextField!
    @IBOutlet weak var burasagariCharsField: NSTextField!
    @IBOutlet weak var cantSeparateCharsField: NSTextField!
    @IBOutlet weak var sampleRulesPopUp: NSPopUpButton!

    // MARK: - Properties

    private let defaults = UserDefaults.standard

    // MARK: - Sample Rules Presets

    private struct LineBreakingPreset {
        let cantBeTopChars: String
        let cantBeEndChars: String
        let burasagariChars: String
        let cantSeparateChars: String
    }

    private let simplePreset = LineBreakingPreset(
        cantBeTopChars: ")]}｣ﾞﾟ゛゜'\"）〕］｝〉》」』】°′″",
        cantBeEndChars: "([{｢'\"（〔［｛〈《「『【",
        burasagariChars: ",.｡､、。，．",
        cantSeparateChars: "—‥…"
    )

    private let standardPreset = LineBreakingPreset(
        cantBeTopChars: "!):;?]}｣･・：；？！゛゜ヽヾゝゞ々ー'\"）〕］｝〉》」』】°′″℃¢％‰",
        cantBeEndChars: "$([{｢'\"（〔［｛〈《「『【￥＄£€〒",
        burasagariChars: ",.｡､、。，．",
        cantSeparateChars: "—‥…"
    )

    private let strictPreset = LineBreakingPreset(
        cantBeTopChars: "!):;?]}｣･ｧｨｩｪｫｬｭｮｯｰﾞﾟ・：；？！゛゜ヽヾゝゞ々ー'\"）〕］｝〉》」』】°′″℃¢％‰ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮヵヶ",
        cantBeEndChars: "$([{｢'\"（〔［｛〈《「『【￥＄£€＠〒＼",
        burasagariChars: ",.｡､、。，．",
        cantSeparateChars: "—‥…"
    )

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        displaySettings()
    }

    // MARK: - Display Settings

    /// UserDefaultsから値を読み込んでUIに表示
    private func displaySettings() {
        cantBeTopCharsField?.stringValue = defaults.string(forKey: UserDefaults.Keys.cantBeTopChars) ?? ""
        cantBeEndCharsField?.stringValue = defaults.string(forKey: UserDefaults.Keys.cantBeEndChars) ?? ""
        burasagariCharsField?.stringValue = defaults.string(forKey: UserDefaults.Keys.burasagariChars) ?? ""
        cantSeparateCharsField?.stringValue = defaults.string(forKey: UserDefaults.Keys.cantSeparateChars) ?? ""

        // Sample Rules ポップアップを最初の項目（タイトル）に戻す
        sampleRulesPopUp?.selectItem(at: 0)
    }

    // MARK: - IBActions

    /// テキストフィールドの値が変更された時
    @IBAction func textFieldChanged(_ sender: NSTextField) {
        switch sender {
        case cantBeTopCharsField:
            defaults.set(sender.stringValue, forKey: UserDefaults.Keys.cantBeTopChars)
        case cantBeEndCharsField:
            defaults.set(sender.stringValue, forKey: UserDefaults.Keys.cantBeEndChars)
        case burasagariCharsField:
            defaults.set(sender.stringValue, forKey: UserDefaults.Keys.burasagariChars)
        case cantSeparateCharsField:
            defaults.set(sender.stringValue, forKey: UserDefaults.Keys.cantSeparateChars)
        default:
            break
        }

        // 開いているドキュメントに禁則設定の変更を反映
        applyKinsokuChangesToOpenDocuments()
    }

    /// Sample Rules ポップアップが変更された時
    @IBAction func sampleRulesChanged(_ sender: NSPopUpButton) {
        let tag = sender.selectedTag()

        let preset: LineBreakingPreset
        switch tag {
        case 1:
            preset = simplePreset
        case 2:
            preset = standardPreset
        case 3:
            preset = strictPreset
        default:
            return
        }

        // プリセットの値を適用
        applyPreset(preset)

        // ポップアップを最初の項目に戻す（タイトル表示用）
        sender.selectItem(at: 0)
    }

    /// Revert to Defaults ボタンが押された時
    @IBAction func revertToDefaults(_ sender: Any) {
        // デフォルト値に戻す
        defaults.removeObject(forKey: UserDefaults.Keys.cantBeTopChars)
        defaults.removeObject(forKey: UserDefaults.Keys.cantBeEndChars)
        defaults.removeObject(forKey: UserDefaults.Keys.burasagariChars)
        defaults.removeObject(forKey: UserDefaults.Keys.cantSeparateChars)

        // UIを更新
        displaySettings()

        // 開いているドキュメントに禁則設定の変更を反映
        applyKinsokuChangesToOpenDocuments()
    }

    // MARK: - Helper Methods

    /// プリセットの値をUIとUserDefaultsに適用
    private func applyPreset(_ preset: LineBreakingPreset) {
        // UIを更新
        cantBeTopCharsField?.stringValue = preset.cantBeTopChars
        cantBeEndCharsField?.stringValue = preset.cantBeEndChars
        burasagariCharsField?.stringValue = preset.burasagariChars
        cantSeparateCharsField?.stringValue = preset.cantSeparateChars

        // UserDefaultsに保存
        defaults.set(preset.cantBeTopChars, forKey: UserDefaults.Keys.cantBeTopChars)
        defaults.set(preset.cantBeEndChars, forKey: UserDefaults.Keys.cantBeEndChars)
        defaults.set(preset.burasagariChars, forKey: UserDefaults.Keys.burasagariChars)
        defaults.set(preset.cantSeparateChars, forKey: UserDefaults.Keys.cantSeparateChars)

        // 開いているドキュメントに禁則設定の変更を反映
        applyKinsokuChangesToOpenDocuments()
    }

    /// 開いている全ドキュメントの禁則設定を更新し、レイアウトを再計算する
    private func applyKinsokuChangesToOpenDocuments() {
        for document in NSDocumentController.shared.documents {
            guard let doc = document as? Document else { continue }
            // JOTextStorageにUserDefaultsから禁則パラメータを再読み込みさせる
            doc.textStorage.setKinsokuParamsFromDefaults()
            // レイアウトを無効化して再計算させる
            for layoutManager in doc.textStorage.layoutManagers {
                let fullRange = NSRange(location: 0, length: doc.textStorage.length)
                layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
            }
        }
    }
}
