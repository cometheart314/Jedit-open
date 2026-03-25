//
//  UserDefaults+Keys.swift
//  Jedit-open
//
//  Created by Claude on 2026/01/13.
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

import Foundation

// MARK: - UserDefaults Keys

extension UserDefaults {
    enum Keys {
        static let autoStartOption = "autoStartOption"
        static let startupOption = "startupOption"
        static let appearanceOption = "appearanceOption"
        static let richTextAlwaysUsesLightMode = "richTextAlwaysUsesLightMode"
        static let scaleMenuArray = "scaleMenuArray"
        static let infoFieldRow = "infoFieldRow"
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

        // Encodings
        static let enabledEncodings = "enabledEncodings"
        static let defaultEncoding = "defaultEncoding"

        // Plain Text File Encoding
        static let plainTextEncodingForRead = "JOPlainTextEncoding"
        static let plainTextEncodingForWrite = "JOPlainTextEncodingForWrite"
        static let plainTextLineEndingForWrite = "JOPlainTextLineEndingForWrite"
        static let plainTextBomForWrite = "JOPlainTextBomForWrite"
        static let convertYenToBackSlash = "JOConvertYenToBackSlash"
        static let convertOverlineToTilde = "JOConvertOverlineToTilde"
        static let convertFullWidthTilde = "JOConvertFullWidthTidle"

        // Window Restoration
        static let openDocumentURLs = "OpenDocumentURLs"

        // Markdown
        static let openMarkdownAsPlainText = "openMarkdownAsPlainText"

        // Save As
        static let useSaveAs = "useSaveAs"

        // Line Breaking
        static let cantBeTopChars = "CantBeTopChars"
        static let cantBeEndChars = "CantBeEndChars"
        static let burasagariChars = "BurasagariChars"
        static let cantSeparateChars = "CantSeparateChars"

        // Context Menu
        static let hiddenContextMenuActions = "hiddenContextMenuActions"

        // App Messages
        static let readMessageIDs = "readMessageIDs"

        // Find Bar
        static let findSearchHistory = "findSearchHistory"
        static let findReplaceHistory = "findReplaceHistory"
        static let findRecentSearchEntries = "findRecentSearchEntries"
        static let findSavedPatterns = "findSavedPatterns"
        static let findCaseSensitive = "findCaseSensitive"
        static let findUseRegex = "findUseRegex"
        static let findWholeWord = "findWholeWord"
        static let findWrapAround = "findWrapAround"
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
            Keys.correctSpellingAutomatically: false,
            // Encodings
            Keys.enabledEncodings: [
                String.Encoding.utf8.rawValue,
                String.Encoding.utf16.rawValue,
                String.Encoding.japaneseEUC.rawValue,
                String.Encoding.shiftJIS.rawValue,
                String.Encoding.iso2022JP.rawValue,
                String.Encoding.isoLatin1.rawValue,
                String.Encoding.ascii.rawValue
            ],
            Keys.defaultEncoding: Int(String.Encoding.utf8.rawValue),
            // Plain Text File Encoding
            Keys.plainTextEncodingForRead: 0,  // 0 = Automatic (NoStringEncoding)
            Keys.plainTextEncodingForWrite: 0, // 0 = Automatic (NoStringEncoding)
            Keys.plainTextLineEndingForWrite: -1, // -1 = Automatic
            Keys.plainTextBomForWrite: -1, // -1 = Automatic
            Keys.convertYenToBackSlash: false,
            Keys.convertOverlineToTilde: false,
            Keys.convertFullWidthTilde: false,
            // Markdown
            Keys.openMarkdownAsPlainText: false,
            // Save As
            Keys.useSaveAs: false,
            // Line Breaking
            Keys.cantBeTopChars: "、。，．・：；？！゛゜´｀¨ヽヾゝゞ々ー）］｝〕〉》」』】°′″℃¢％‰",
            Keys.cantBeEndChars: "（［｛〔〈《「『【",
            Keys.burasagariChars: "、。，．",
            Keys.cantSeparateChars: "—…‥",
            // Context Menu
            Keys.hiddenContextMenuActions: [String](),
            // Find Bar
            Keys.findSearchHistory: [String](),
            Keys.findReplaceHistory: [String](),
            Keys.findCaseSensitive: false,
            Keys.findUseRegex: false,
            Keys.findWholeWord: false,
            Keys.findWrapAround: true
        ])
    }
}
