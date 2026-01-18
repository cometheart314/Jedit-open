//
//  GeneralPreferencesViewController.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/29.
//

import Cocoa
import ServiceManagement

// MARK: - GeneralPreferencesViewController

class GeneralPreferencesViewController: NSViewController {

    @IBOutlet weak var autoStartCheckBox: NSButton!
    @IBOutlet weak var startupOptionPopupButton: NSPopUpButton!
    @IBOutlet weak var appearancePopupButton: NSPopUpButton!
    @IBOutlet weak var dateFormatPopupButton: NSPopUpButton!
    @IBOutlet weak var timeFormatPopupButton: NSPopUpButton!
    @IBOutlet weak var dateFormatField: NSTextField!  // プレビュー表示、カスタム時のみ編集可能
    @IBOutlet weak var timeFormatField: NSTextField!  // プレビュー表示、カスタム時のみ編集可能

    // Text Editing Options
    @IBOutlet weak var checkSpellingAsYouTypeCheckBox: NSButton!
    @IBOutlet weak var checkGrammarWithSpellingCheckBox: NSButton!
    @IBOutlet weak var dataDetectorsCheckBox: NSButton!
    @IBOutlet weak var smartLinksCheckBox: NSButton!
    @IBOutlet weak var smartSeparationCheckBox: NSButton!
    @IBOutlet weak var smartCopyPasteCheckBox: NSButton!
    @IBOutlet weak var dontShowContextMenuDefaultItemsCheckBox: NSButton!
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
        // Auto Start at Login
        let autoStart = defaults.bool(forKey: UserDefaults.Keys.autoStartOption)
        autoStartCheckBox?.state = autoStart ? .on : .off

        // Startup Option (0: Do Nothing, 1: Open New Document, 2: Show Open Panel)
        let startupOption = defaults.integer(forKey: UserDefaults.Keys.startupOption)
        startupOptionPopupButton?.selectItem(withTag: startupOption)

        // Appearance (0: System, 1: Light, 2: Dark)
        let appearanceOption = defaults.integer(forKey: UserDefaults.Keys.appearanceOption)
        appearancePopupButton?.selectItem(withTag: appearanceOption)

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
        dontShowContextMenuDefaultItemsCheckBox?.state = defaults.bool(forKey: UserDefaults.Keys.dontShowContextMenuDefaultItems) ? .on : .off

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

    @IBAction func dontShowContextMenuDefaultItemsClicked(_ sender: Any) {
        guard let button = sender as? NSButton else { return }
        let isOn = button.state == .on
        defaults.set(isOn, forKey: UserDefaults.Keys.dontShowContextMenuDefaultItems)
        // This setting affects context menu, no immediate action needed
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
