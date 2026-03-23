//
//  GeneralPreferencesViewController.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/29.
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
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - GeneralPreferencesViewController

class GeneralPreferencesViewController: NSViewController {

    @IBOutlet weak var autoStartCheckBox: NSButton!
    @IBOutlet weak var startupOptionPopupButton: NSPopUpButton!
    @IBOutlet weak var appearancePopupButton: NSPopUpButton!
    @IBOutlet weak var richTextAlwaysUsesLightModeCheckBox: NSButton!
    @IBOutlet weak var dateFormatPopupButton: NSPopUpButton!
    @IBOutlet weak var timeFormatPopupButton: NSPopUpButton!
    @IBOutlet weak var dateFormatField: NSTextField!  // プレビュー表示、カスタム時のみ編集可能
    @IBOutlet weak var timeFormatField: NSTextField!  // プレビュー表示、カスタム時のみ編集可能

    // Advanced Options
    @IBOutlet weak var openMarkdownAsPlainTextCheckBox: NSButton!

    // Text Editing Options
    @IBOutlet weak var checkSpellingAsYouTypeCheckBox: NSButton!
    @IBOutlet weak var checkGrammarWithSpellingCheckBox: NSButton!
    @IBOutlet weak var dataDetectorsCheckBox: NSButton!
    @IBOutlet weak var smartLinksCheckBox: NSButton!
    @IBOutlet weak var smartSeparationCheckBox: NSButton!
    @IBOutlet weak var smartCopyPasteCheckBox: NSButton!
    @IBOutlet weak var richTextSubstitutionsCheckBox: NSButton!
    @IBOutlet weak var textReplacementsCheckBox: NSButton!
    @IBOutlet weak var smartQuotesCheckBox: NSButton!
    @IBOutlet weak var smartDashesCheckBox: NSButton!
    @IBOutlet weak var correctSpellingAutomaticallyCheckBox: NSButton!

    private let defaults = UserDefaults.standard

    override func viewDidLoad() {
        super.viewDidLoad()
        setupDateTimeFormatMenus()
        loadPreferences()
    }

    // MARK: - Setup

    private func setupDateTimeFormatMenus() {
        // Date Format Popup
        dateFormatPopupButton?.removeAllItems()
        for i in 0..<CalendarDateHelper.numberOfDateTypes {
            let name = CalendarDateHelper.nameOfDateType(i)
            dateFormatPopupButton?.addItem(withTitle: name)
            dateFormatPopupButton?.lastItem?.tag = i
        }

        // Time Format Popup
        timeFormatPopupButton?.removeAllItems()
        for i in 0..<CalendarDateHelper.numberOfTimeTypes {
            let name = CalendarDateHelper.nameOfTimeType(i)
            timeFormatPopupButton?.addItem(withTitle: name)
            timeFormatPopupButton?.lastItem?.tag = i
        }
    }

    private func updateDateFormatDisplay() {
        let selectedTag = dateFormatPopupButton?.selectedTag() ?? 0
        let isCustom = selectedTag == CalendarDateHelper.DateFormatType.custom.rawValue

        if isCustom {
            // カスタムフォーマットの場合は保存されているフォーマット文字列を表示（編集可能）
            let customFormat = defaults.string(forKey: UserDefaults.Keys.customDateFormat) ?? "yyyy-MM-dd"
            dateFormatField?.stringValue = customFormat
            dateFormatField?.isEditable = true
            dateFormatField?.isSelectable = true
            dateFormatField?.drawsBackground = true
            dateFormatField?.isBezeled = true
        } else {
            // 通常フォーマットの場合はプレビューを表示（編集不可）
            let preview = CalendarDateHelper.descriptionOfDateType(selectedTag)
            dateFormatField?.stringValue = preview
            dateFormatField?.isEditable = false
            dateFormatField?.isSelectable = false
            dateFormatField?.drawsBackground = false
            dateFormatField?.isBezeled = false
        }
    }

    private func updateTimeFormatDisplay() {
        let selectedTag = timeFormatPopupButton?.selectedTag() ?? 0
        let isCustom = selectedTag == CalendarDateHelper.TimeFormatType.custom.rawValue

        if isCustom {
            // カスタムフォーマットの場合は保存されているフォーマット文字列を表示（編集可能）
            let customFormat = defaults.string(forKey: UserDefaults.Keys.customTimeFormat) ?? "HH:mm:ss"
            timeFormatField?.stringValue = customFormat
            timeFormatField?.isEditable = true
            timeFormatField?.isSelectable = true
            timeFormatField?.drawsBackground = true
            timeFormatField?.isBezeled = true
        } else {
            // 通常フォーマットの場合はプレビューを表示（編集不可）
            let preview = CalendarDateHelper.descriptionOfTimeType(selectedTag)
            timeFormatField?.stringValue = preview
            timeFormatField?.isEditable = false
            timeFormatField?.isSelectable = false
            timeFormatField?.drawsBackground = false
            timeFormatField?.isBezeled = false
        }
    }

    /// UserDefaultsから設定を読み込んでUIに反映
    private func loadPreferences() {
        // Markdown
        let openMarkdownAsPlainText = defaults.bool(forKey: UserDefaults.Keys.openMarkdownAsPlainText)
        openMarkdownAsPlainTextCheckBox?.state = openMarkdownAsPlainText ? .on : .off

        // Auto Start at Login
        let autoStart = defaults.bool(forKey: UserDefaults.Keys.autoStartOption)
        autoStartCheckBox?.state = autoStart ? .on : .off

        // Startup Option (0: Do Nothing, 1: Open New Document, 2: Show Open Panel)
        let startupOption = defaults.integer(forKey: UserDefaults.Keys.startupOption)
        startupOptionPopupButton?.selectItem(withTag: startupOption)

        // Appearance (0: System, 1: Light, 2: Dark)
        let appearanceOption = defaults.integer(forKey: UserDefaults.Keys.appearanceOption)
        appearancePopupButton?.selectItem(withTag: appearanceOption)

        // Rich Text Always Uses Light Mode
        let richTextLightMode = defaults.bool(forKey: UserDefaults.Keys.richTextAlwaysUsesLightMode)
        richTextAlwaysUsesLightModeCheckBox?.state = richTextLightMode ? .on : .off

        // Date Format
        let dateFormatType = defaults.integer(forKey: UserDefaults.Keys.dateFormatType)
        dateFormatPopupButton?.selectItem(withTag: dateFormatType)
        updateDateFormatDisplay()

        // Time Format
        let timeFormatType = defaults.integer(forKey: UserDefaults.Keys.timeFormatType)
        timeFormatPopupButton?.selectItem(withTag: timeFormatType)
        updateTimeFormatDisplay()

        // Text Editing Options
        checkSpellingAsYouTypeCheckBox?.state = defaults.bool(forKey: UserDefaults.Keys.checkSpellingAsYouType) ? .on : .off
        checkGrammarWithSpellingCheckBox?.state = defaults.bool(forKey: UserDefaults.Keys.checkGrammarWithSpelling) ? .on : .off
        dataDetectorsCheckBox?.state = defaults.bool(forKey: UserDefaults.Keys.dataDetectors) ? .on : .off
        smartLinksCheckBox?.state = defaults.bool(forKey: UserDefaults.Keys.smartLinks) ? .on : .off
        smartSeparationCheckBox?.state = defaults.bool(forKey: UserDefaults.Keys.smartSeparationEnglishJapanese) ? .on : .off
        smartCopyPasteCheckBox?.state = defaults.bool(forKey: UserDefaults.Keys.smartCopyPaste) ? .on : .off

        // Rich Text Substitutions
        // オン: 以下の置換オプションはリッチテキストのみに適用
        // オフ: 以下の置換オプションはプレーンテキストにも適用
        let richTextSubstitutionsEnabled = defaults.bool(forKey: UserDefaults.Keys.richTextSubstitutionsEnabled)
        richTextSubstitutionsCheckBox?.state = richTextSubstitutionsEnabled ? .on : .off
        textReplacementsCheckBox?.state = defaults.bool(forKey: UserDefaults.Keys.textReplacements) ? .on : .off
        smartQuotesCheckBox?.state = defaults.bool(forKey: UserDefaults.Keys.smartQuotes) ? .on : .off
        smartDashesCheckBox?.state = defaults.bool(forKey: UserDefaults.Keys.smartDashes) ? .on : .off
        correctSpellingAutomaticallyCheckBox?.state = defaults.bool(forKey: UserDefaults.Keys.correctSpellingAutomatically) ? .on : .off
    }

    @IBAction func autoStartCheckBoxClicked(_ sender: Any) {
        guard let button = sender as? NSButton else { return }
        let isOn = button.state == .on

        do {
            if isOn {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            defaults.set(isOn, forKey: UserDefaults.Keys.autoStartOption)
        } catch {
            // エラー時はチェック状態を元に戻す
            button.state = isOn ? .off : .on

            // ユーザーにアラートを表示
            let alert = NSAlert()
            alert.messageText = "Login Item Error"
            alert.informativeText = "Could not configure login item. This feature requires the app to be properly signed and sandboxed.\n\nError: \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            if let window = self.view.window {
                alert.beginSheetModal(for: window, completionHandler: nil)
            } else {
                alert.runModal()
            }
        }
    }

    @IBAction func startupOptionSelected(_ sender: Any) {
        guard let popup = sender as? NSPopUpButton else { return }
        let selectedTag = popup.selectedTag()
        defaults.set(selectedTag, forKey: UserDefaults.Keys.startupOption)
    }

    @IBAction func appearancePopupSelected(_ sender: Any) {
        guard let popup = sender as? NSPopUpButton else { return }
        let selectedTag = popup.selectedTag()
        defaults.set(selectedTag, forKey: UserDefaults.Keys.appearanceOption)

        // 外観を即座に適用
        AppDelegate.applyAppearance(selectedTag)
    }

    @IBAction func richTextAlwaysUsesLightModeChanged(_ sender: Any) {
        guard let checkBox = sender as? NSButton else { return }
        let isOn = checkBox.state == .on
        defaults.set(isOn, forKey: UserDefaults.Keys.richTextAlwaysUsesLightMode)

        // 開いているすべてのリッチテキストドキュメントに即座に適用
        NotificationCenter.default.post(
            name: NSNotification.Name("RichTextLightModeSettingChanged"),
            object: nil
        )
    }

    @IBAction func dateFormatPopupSelected(_ sender: Any) {
        guard let popup = sender as? NSPopUpButton else { return }
        let selectedTag = popup.selectedTag()
        defaults.set(selectedTag, forKey: UserDefaults.Keys.dateFormatType)
        updateDateFormatDisplay()
    }

    @IBAction func timeFormatPopupSelected(_ sender: Any) {
        guard let popup = sender as? NSPopUpButton else { return }
        let selectedTag = popup.selectedTag()
        defaults.set(selectedTag, forKey: UserDefaults.Keys.timeFormatType)
        updateTimeFormatDisplay()
    }

    @IBAction func dateFormatFieldChanged(_ sender: Any) {
        guard let field = sender as? NSTextField else { return }
        let format = field.stringValue
        defaults.set(format, forKey: UserDefaults.Keys.customDateFormat)
    }

    @IBAction func timeFormatFieldChanged(_ sender: Any) {
        guard let field = sender as? NSTextField else { return }
        let format = field.stringValue
        defaults.set(format, forKey: UserDefaults.Keys.customTimeFormat)
    }

    // MARK: - Text Editing Options Actions

    @IBAction func checkSpellingAsYouTypeClicked(_ sender: Any) {
        guard let button = sender as? NSButton else { return }
        let isOn = button.state == .on
        defaults.set(isOn, forKey: UserDefaults.Keys.checkSpellingAsYouType)
        applyTextEditingSettingsToAllWindows()
    }

    @IBAction func checkGrammarWithSpellingClicked(_ sender: Any) {
        guard let button = sender as? NSButton else { return }
        let isOn = button.state == .on
        defaults.set(isOn, forKey: UserDefaults.Keys.checkGrammarWithSpelling)
        applyTextEditingSettingsToAllWindows()
    }

    @IBAction func dataDetectorsClicked(_ sender: Any) {
        guard let button = sender as? NSButton else { return }
        let isOn = button.state == .on
        defaults.set(isOn, forKey: UserDefaults.Keys.dataDetectors)
        applyTextEditingSettingsToAllWindows()
    }

    @IBAction func smartLinksClicked(_ sender: Any) {
        guard let button = sender as? NSButton else { return }
        let isOn = button.state == .on
        defaults.set(isOn, forKey: UserDefaults.Keys.smartLinks)
        applyTextEditingSettingsToAllWindows()
    }

    @IBAction func smartSeparationClicked(_ sender: Any) {
        guard let button = sender as? NSButton else { return }
        let isOn = button.state == .on
        defaults.set(isOn, forKey: UserDefaults.Keys.smartSeparationEnglishJapanese)
        applyTextEditingSettingsToAllWindows()
    }

    @IBAction func smartCopyPasteClicked(_ sender: Any) {
        guard let button = sender as? NSButton else { return }
        let isOn = button.state == .on
        defaults.set(isOn, forKey: UserDefaults.Keys.smartCopyPaste)
        applyTextEditingSettingsToAllWindows()
    }

    @IBAction func richTextSubstitutionsClicked(_ sender: Any) {
        guard let button = sender as? NSButton else { return }
        let isOn = button.state == .on
        defaults.set(isOn, forKey: UserDefaults.Keys.richTextSubstitutionsEnabled)
        applyTextEditingSettingsToAllWindows()
    }

    @IBAction func textReplacementsClicked(_ sender: Any) {
        guard let button = sender as? NSButton else { return }
        let isOn = button.state == .on
        defaults.set(isOn, forKey: UserDefaults.Keys.textReplacements)
        applyTextEditingSettingsToAllWindows()
    }

    @IBAction func smartQuotesClicked(_ sender: Any) {
        guard let button = sender as? NSButton else { return }
        let isOn = button.state == .on
        defaults.set(isOn, forKey: UserDefaults.Keys.smartQuotes)
        applyTextEditingSettingsToAllWindows()
    }

    @IBAction func smartDashesClicked(_ sender: Any) {
        guard let button = sender as? NSButton else { return }
        let isOn = button.state == .on
        defaults.set(isOn, forKey: UserDefaults.Keys.smartDashes)
        applyTextEditingSettingsToAllWindows()
    }

    @IBAction func correctSpellingAutomaticallyClicked(_ sender: Any) {
        guard let button = sender as? NSButton else { return }
        let isOn = button.state == .on
        defaults.set(isOn, forKey: UserDefaults.Keys.correctSpellingAutomatically)
        applyTextEditingSettingsToAllWindows()
    }

    // MARK: - Advanced Options Actions

    @IBAction func openMarkdownAsPlainTextClicked(_ sender: Any) {
        guard let button = sender as? NSButton else { return }
        let isOn = button.state == .on
        defaults.set(isOn, forKey: UserDefaults.Keys.openMarkdownAsPlainText)
    }

    // MARK: - Revert to Defaults Actions

    @IBAction func revertEditToDefaults(_ sender: Any) {
        // Reset all Edit tab settings to defaults
        defaults.set(false, forKey: UserDefaults.Keys.checkSpellingAsYouType)
        defaults.set(false, forKey: UserDefaults.Keys.checkGrammarWithSpelling)
        defaults.set(false, forKey: UserDefaults.Keys.dataDetectors)
        defaults.set(false, forKey: UserDefaults.Keys.smartLinks)
        defaults.set(false, forKey: UserDefaults.Keys.smartSeparationEnglishJapanese)
        defaults.set(false, forKey: UserDefaults.Keys.smartCopyPaste)
        defaults.set(true, forKey: UserDefaults.Keys.richTextSubstitutionsEnabled)
        defaults.set(false, forKey: UserDefaults.Keys.textReplacements)
        defaults.set(false, forKey: UserDefaults.Keys.smartQuotes)
        defaults.set(false, forKey: UserDefaults.Keys.smartDashes)
        defaults.set(false, forKey: UserDefaults.Keys.correctSpellingAutomatically)

        // Update UI
        checkSpellingAsYouTypeCheckBox?.state = .off
        checkGrammarWithSpellingCheckBox?.state = .off
        dataDetectorsCheckBox?.state = .off
        smartLinksCheckBox?.state = .off
        smartSeparationCheckBox?.state = .off
        smartCopyPasteCheckBox?.state = .off
        richTextSubstitutionsCheckBox?.state = .on
        textReplacementsCheckBox?.state = .off
        smartQuotesCheckBox?.state = .off
        smartDashesCheckBox?.state = .off
        correctSpellingAutomaticallyCheckBox?.state = .off

        applyTextEditingSettingsToAllWindows()
    }

    @IBAction func revertViewToDefaults(_ sender: Any) {
        // Reset all View tab settings to defaults
        defaults.set(0, forKey: UserDefaults.Keys.appearanceOption)
        defaults.set(false, forKey: UserDefaults.Keys.richTextAlwaysUsesLightMode)
        defaults.set(0, forKey: UserDefaults.Keys.dateFormatType)
        defaults.set(0, forKey: UserDefaults.Keys.timeFormatType)
        defaults.set("yyyy-MM-dd", forKey: UserDefaults.Keys.customDateFormat)
        defaults.set("HH:mm:ss", forKey: UserDefaults.Keys.customTimeFormat)

        // Update UI
        appearancePopupButton?.selectItem(withTag: 0)
        richTextAlwaysUsesLightModeCheckBox?.state = .off
        dateFormatPopupButton?.selectItem(withTag: 0)
        timeFormatPopupButton?.selectItem(withTag: 0)
        updateDateFormatDisplay()
        updateTimeFormatDisplay()

        // Apply appearance change
        AppDelegate.applyAppearance(0)

        // Notify rich text light mode change
        NotificationCenter.default.post(
            name: NSNotification.Name("RichTextLightModeSettingChanged"),
            object: nil
        )
    }

    // MARK: - Export / Import / Revert All Settings

    /// すべてのアプリ設定キーの一覧
    private static var allSettingsKeys: [String] {
        return [
            // 一般設定
            UserDefaults.Keys.autoStartOption,
            UserDefaults.Keys.startupOption,
            UserDefaults.Keys.appearanceOption,
            UserDefaults.Keys.richTextAlwaysUsesLightMode,
            UserDefaults.Keys.scaleMenuArray,
            UserDefaults.Keys.infoFieldRow,
            UserDefaults.Keys.dateFormatType,
            UserDefaults.Keys.timeFormatType,
            UserDefaults.Keys.customDateFormat,
            UserDefaults.Keys.customTimeFormat,
            // テキスト編集
            UserDefaults.Keys.checkSpellingAsYouType,
            UserDefaults.Keys.checkGrammarWithSpelling,
            UserDefaults.Keys.dataDetectors,
            UserDefaults.Keys.smartLinks,
            UserDefaults.Keys.smartSeparationEnglishJapanese,
            UserDefaults.Keys.smartCopyPaste,
            UserDefaults.Keys.dontShowContextMenuDefaultItems,
            UserDefaults.Keys.richTextSubstitutionsEnabled,
            UserDefaults.Keys.textReplacements,
            UserDefaults.Keys.smartQuotes,
            UserDefaults.Keys.smartDashes,
            UserDefaults.Keys.correctSpellingAutomatically,
            // エンコーディング
            UserDefaults.Keys.enabledEncodings,
            UserDefaults.Keys.defaultEncoding,
            UserDefaults.Keys.plainTextEncodingForRead,
            UserDefaults.Keys.plainTextEncodingForWrite,
            UserDefaults.Keys.plainTextLineEndingForWrite,
            UserDefaults.Keys.plainTextBomForWrite,
            UserDefaults.Keys.convertYenToBackSlash,
            UserDefaults.Keys.convertOverlineToTilde,
            UserDefaults.Keys.convertFullWidthTilde,
            "Encodings",  // EncodingManager のエンコーディングリスト
            // Markdown
            UserDefaults.Keys.openMarkdownAsPlainText,
            // 禁則処理
            UserDefaults.Keys.cantBeTopChars,
            UserDefaults.Keys.cantBeEndChars,
            UserDefaults.Keys.burasagariChars,
            UserDefaults.Keys.cantSeparateChars,
            // コンテキストメニュー
            UserDefaults.Keys.hiddenContextMenuActions,
            // 検索バー
            UserDefaults.Keys.findSearchHistory,
            UserDefaults.Keys.findReplaceHistory,
            UserDefaults.Keys.findRecentSearchEntries,
            UserDefaults.Keys.findSavedPatterns,
            UserDefaults.Keys.findCaseSensitive,
            UserDefaults.Keys.findUseRegex,
            UserDefaults.Keys.findWholeWord,
            UserDefaults.Keys.findWrapAround,
            // 新規書類プリセット (DocumentPresetManager)
            "documentPresets",
            "selectedDocumentPresetID",
            // テーマカラー (JOThemeColorPopupButton)
            "userThemeArray",
            // 書類情報パネル
            "DocumentInfoCountHalfAs05",
        ]
    }

    @IBAction func exportAllSettings(_ sender: Any) {
        let savePanel = NSSavePanel()
        savePanel.title = NSLocalizedString("Export All Settings", comment: "")
        savePanel.nameFieldStringValue = "JeditSettings.plist"
        savePanel.allowedContentTypes = [.propertyList]

        guard let window = self.view.window else { return }
        savePanel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = savePanel.url else { return }

            var dict = [String: Any]()
            for key in Self.allSettingsKeys {
                if let value = self.defaults.object(forKey: key) {
                    dict[key] = value
                }
            }

            let plistData = NSDictionary(dictionary: dict)
            plistData.write(to: url, atomically: true)
        }
    }

    @IBAction func importAllSettings(_ sender: Any) {
        let openPanel = NSOpenPanel()
        openPanel.title = NSLocalizedString("Import All Settings", comment: "")
        openPanel.allowedContentTypes = [.propertyList]
        openPanel.allowsMultipleSelection = false

        guard let window = self.view.window else { return }
        openPanel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = openPanel.url else { return }
            guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Import Failed", comment: "")
                alert.informativeText = NSLocalizedString("The selected file is not a valid settings file.", comment: "")
                alert.alertStyle = .warning
                alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
                alert.beginSheetModal(for: window, completionHandler: nil)
                return
            }

            // 確認アラートを表示
            let confirm = NSAlert()
            confirm.messageText = NSLocalizedString("Import All Settings", comment: "")
            confirm.informativeText = NSLocalizedString("Current settings will be overwritten. Jedit will quit after importing. Do you want to continue?", comment: "")
            confirm.alertStyle = .warning
            confirm.addButton(withTitle: NSLocalizedString("Continue", comment: ""))
            confirm.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
            confirm.beginSheetModal(for: window) { confirmResponse in
                guard confirmResponse == .alertFirstButtonReturn else { return }

                for (key, value) in dict {
                    self.defaults.set(value, forKey: key)
                }

                // インポートした設定を確実にディスクに書き込む
                self.defaults.synchronize()

                // メモリ上のキャッシュと競合するため、アプリを終了する
                NSApplication.shared.terminate(nil)
            }
        }
    }

    @IBAction func revertAllSettingsToFactory(_ sender: Any) {
        guard let window = self.view.window else { return }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Revert All Settings to Factory Settings", comment: "")
        alert.informativeText = NSLocalizedString("All settings will be reset to their default values. Jedit will quit after resetting. This cannot be undone.", comment: "")
        alert.alertStyle = .critical
        alert.addButton(withTitle: NSLocalizedString("Revert", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }

            // すべての設定キーを削除
            for key in Self.allSettingsKeys {
                self.defaults.removeObject(forKey: key)
            }

            // デフォルト値を再登録
            UserDefaults.registerDefaults()

            // ログインアイテムの登録を解除
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                // エラーは無視 - 登録されていない可能性がある
            }

            // 設定を確実にディスクに書き込む
            self.defaults.synchronize()

            // メモリ上のキャッシュと競合するため、アプリを終了する
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Apply Text Editing Settings

    /// すべてのウィンドウのテキストビューに設定を適用
    private func applyTextEditingSettingsToAllWindows() {
        NotificationCenter.default.post(name: .textEditingPreferencesDidChange, object: nil)
    }
}

// MARK: - Notification Name Extension

extension Notification.Name {
    static let textEditingPreferencesDidChange = Notification.Name("textEditingPreferencesDidChange")
}
