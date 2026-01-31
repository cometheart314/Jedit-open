//
//  UserDefaults+Keys.swift
//  Jedit-open
//
//  Created by Claude on 2026/01/13.
//

import Foundation

// MARK: - UserDefaults Keys

extension UserDefaults {
    enum Keys {
        static let autoStartOption = "autoStartOption"
        static let startupOption = "startupOption"
        static let appearanceOption = "appearanceOption"
        static let richTextAlwaysUsesLightMode = "richTextAlwaysUsesLightMode"
        static let scaleMenuArray = "scaleMenuArray"
        static let dateFormatType = "dateFormatType"
        static let timeFormatType = "timeFormatType"
        static let customDateFormat = "customDateFormat"
        static let customTimeFormat = "customTimeFormat"

        // Text Editing Options (Edit Menu)
        static let checkSpellingAsYouType = "checkSpellingAsYouType"
        static let checkGrammarWithSpelling = "checkGrammarWithSpelling"
        static let dataDetectors = "dataDetectors"
        static let smartLinks = "smartLinks"
        static let smartSeparationEnglishJapanese = "smartSeparationEnglishJapanese"
        static let smartCopyPaste = "smartCopyPaste"
        static let dontShowContextMenuDefaultItems = "dontShowContextMenuDefaultItems"
        static let richTextSubstitutionsEnabled = "richTextSubstitutionsEnabled"
        static let textReplacements = "textReplacements"
        static let smartQuotes = "smartQuotes"
        static let smartDashes = "smartDashes"
        static let correctSpellingAutomatically = "correctSpellingAutomatically"
    }

    /// スケールメニューのデフォルト値
    static let defaultScaleMenuArray: [Int] = [25, 50, 75, 100, 125, 150, 200, 300, 400]

    /// デフォルト値を登録
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.autoStartOption: false,
            Keys.startupOption: 0,
            Keys.appearanceOption: 0,
            Keys.richTextAlwaysUsesLightMode: false,
            Keys.scaleMenuArray: defaultScaleMenuArray,
            Keys.dateFormatType: 0,
            Keys.timeFormatType: 0,
            Keys.customDateFormat: "yyyy-MM-dd",
            Keys.customTimeFormat: "HH:mm:ss",
            // Text Editing Options - all default to false
            Keys.checkSpellingAsYouType: false,
            Keys.checkGrammarWithSpelling: false,
            Keys.dataDetectors: false,
            Keys.smartLinks: false,
            Keys.smartSeparationEnglishJapanese: false,
            Keys.smartCopyPaste: false,
            Keys.dontShowContextMenuDefaultItems: false,
            Keys.richTextSubstitutionsEnabled: true,
            Keys.textReplacements: false,
            Keys.smartQuotes: false,
            Keys.smartDashes: false,
            Keys.correctSpellingAutomatically: false
        ])
    }
}
