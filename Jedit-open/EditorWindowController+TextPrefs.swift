//
//  EditorWindowController+TextPrefs.swift
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

extension EditorWindowController {

    // MARK: - Text Editing Preferences

    /// テキスト編集設定の変更通知を監視開始
    func observeTextEditingPreferences() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textEditingPreferencesDidChange(_:)),
            name: .textEditingPreferencesDidChange,
            object: nil
        )
    }

    @objc internal func textEditingPreferencesDidChange(_ notification: Notification) {
        applyTextEditingPreferences()
    }

    /// テキスト編集設定をすべてのテキストビューに適用
    func applyTextEditingPreferences() {
        let defaults = UserDefaults.standard

        // 設定値を取得
        let checkSpelling = defaults.bool(forKey: UserDefaults.Keys.checkSpellingAsYouType)
        let checkGrammar = defaults.bool(forKey: UserDefaults.Keys.checkGrammarWithSpelling)
        let dataDetectors = defaults.bool(forKey: UserDefaults.Keys.dataDetectors)
        let smartLinks = defaults.bool(forKey: UserDefaults.Keys.smartLinks)
        let smartCopyPaste = defaults.bool(forKey: UserDefaults.Keys.smartCopyPaste)
        let smartSeparation = defaults.bool(forKey: UserDefaults.Keys.smartSeparationEnglishJapanese)

        // Rich Text Substitutions の設定
        let richTextSubstitutionsOnly = defaults.bool(forKey: UserDefaults.Keys.richTextSubstitutionsEnabled)
        let isPlainText = textDocument?.documentType == .plain

        // richTextSubstitutionsOnly が true で、かつプレーンテキストの場合は置換を無効にする
        let shouldApplySubstitutions = !richTextSubstitutionsOnly || !isPlainText
        let textReplacements = shouldApplySubstitutions && defaults.bool(forKey: UserDefaults.Keys.textReplacements)
        let smartQuotes = shouldApplySubstitutions && defaults.bool(forKey: UserDefaults.Keys.smartQuotes)
        let smartDashes = shouldApplySubstitutions && defaults.bool(forKey: UserDefaults.Keys.smartDashes)
        let correctSpelling = shouldApplySubstitutions && defaults.bool(forKey: UserDefaults.Keys.correctSpellingAutomatically)

        // Continuousモードのテキストビュー
        if let scrollView = scrollView1,
           let textView = scrollView.documentView as? NSTextView {
            applyTextEditingSettings(to: textView,
                                     checkSpelling: checkSpelling,
                                     checkGrammar: checkGrammar,
                                     dataDetectors: dataDetectors,
                                     smartLinks: smartLinks,
                                     smartCopyPaste: smartCopyPaste,
                                     smartSeparation: smartSeparation,
                                     textReplacements: textReplacements,
                                     smartQuotes: smartQuotes,
                                     smartDashes: smartDashes,
                                     correctSpelling: correctSpelling)
        }

        if let scrollView = scrollView2,
           let textView = scrollView.documentView as? NSTextView {
            applyTextEditingSettings(to: textView,
                                     checkSpelling: checkSpelling,
                                     checkGrammar: checkGrammar,
                                     dataDetectors: dataDetectors,
                                     smartLinks: smartLinks,
                                     smartCopyPaste: smartCopyPaste,
                                     smartSeparation: smartSeparation,
                                     textReplacements: textReplacements,
                                     smartQuotes: smartQuotes,
                                     smartDashes: smartDashes,
                                     correctSpelling: correctSpelling)
        }

        // Pageモードのテキストビュー
        for textView in textViews1 {
            applyTextEditingSettings(to: textView,
                                     checkSpelling: checkSpelling,
                                     checkGrammar: checkGrammar,
                                     dataDetectors: dataDetectors,
                                     smartLinks: smartLinks,
                                     smartCopyPaste: smartCopyPaste,
                                     smartSeparation: smartSeparation,
                                     textReplacements: textReplacements,
                                     smartQuotes: smartQuotes,
                                     smartDashes: smartDashes,
                                     correctSpelling: correctSpelling)
        }

        for textView in textViews2 {
            applyTextEditingSettings(to: textView,
                                     checkSpelling: checkSpelling,
                                     checkGrammar: checkGrammar,
                                     dataDetectors: dataDetectors,
                                     smartLinks: smartLinks,
                                     smartCopyPaste: smartCopyPaste,
                                     smartSeparation: smartSeparation,
                                     textReplacements: textReplacements,
                                     smartQuotes: smartQuotes,
                                     smartDashes: smartDashes,
                                     correctSpelling: correctSpelling)
        }
    }

    /// 個別のテキストビューに設定を適用
    internal func applyTextEditingSettings(to textView: NSTextView,
                                          checkSpelling: Bool,
                                          checkGrammar: Bool,
                                          dataDetectors: Bool,
                                          smartLinks: Bool,
                                          smartCopyPaste: Bool,
                                          smartSeparation: Bool,
                                          textReplacements: Bool,
                                          smartQuotes: Bool,
                                          smartDashes: Bool,
                                          correctSpelling: Bool) {
        textView.isContinuousSpellCheckingEnabled = checkSpelling
        textView.isGrammarCheckingEnabled = checkGrammar
        textView.isAutomaticDataDetectionEnabled = dataDetectors
        textView.isAutomaticLinkDetectionEnabled = smartLinks
        textView.smartInsertDeleteEnabled = smartCopyPaste
        textView.isAutomaticTextReplacementEnabled = textReplacements
        textView.isAutomaticQuoteSubstitutionEnabled = smartQuotes
        textView.isAutomaticDashSubstitutionEnabled = smartDashes
        textView.isAutomaticSpellingCorrectionEnabled = correctSpelling
        if let jeditTextView = textView as? JeditTextView {
            jeditTextView.isSmartSeparationEnglishJapaneseEnabled = smartSeparation
        }
    }

    // MARK: - Basic Font

    /// Format > Font > Basic Font... メニューアクション
    @IBAction func showBasicFont(_ sender: Any?) {
        BasicFontPanelController.shared.showBasicFontInfo(for: self)
    }

    /// Basic Font が変更された時に呼び出される
    /// ルーラーの文字幅目盛りとドキュメント幅（文字幅指定時）を更新する
    func basicFontDidChange(_ font: NSFont) {
        // 文字幅を再計算
        let charWidth = basicCharWidth(from: font)

        // プレーンテキストの場合、全文にBasic Fontを適用し、typingAttributesも更新
        if textDocument?.documentType == .plain {
            applyFontToTextViews(font)
            if let textStorage = textDocument?.textStorage {
                let range = NSRange(location: 0, length: textStorage.length)
                textStorage.addAttribute(.font, value: font, range: range)
            }
        }

        // ルーラーの単位を更新（character単位の場合）
        if rulerType == .character {
            registerCharacterRulerUnit(charWidth: charWidth)

            // ルーラーを再設定
            updateRulerVisibility()
        }

        // 固定幅モードの場合、ドキュメントレイアウトを更新
        // （フォント変更によるレイアウト更新なので、presetDataは更新しない）
        if lineWrapMode == .fixedWidth && displayMode == .continuous {
            applyLineWrapMode(updatePresetData: false)
        }

        // ドキュメントに変更をマーク
        textDocument?.updateChangeCount(.changeDone)
    }

    /// 現在の Basic Font を取得
    func currentBasicFont() -> NSFont {
        if let presetData = textDocument?.presetData {
            let fontData = presetData.fontAndColors
            if let font = NSFont(name: fontData.baseFontName, size: fontData.baseFontSize) {
                return font
            }
        }
        return NSFont.systemFont(ofSize: 14)
    }

    /// 現在の Basic Character Width を取得
    func currentBasicCharWidth() -> CGFloat {
        return basicCharWidth(from: currentBasicFont())
    }

    // MARK: - Tab Width

    /// Format > Text > Tab Width... メニューアクション
    @IBAction func showTabWidthPanel(_ sender: Any?) {
        guard let window = self.window,
              let presetData = textDocument?.presetData else { return }

        let currentValue = presetData.format.tabWidthPoints
        let currentUnit = presetData.format.tabWidthUnit

        tabWidthPanel.beginSheet(
            for: window,
            currentValue: currentValue,
            currentUnit: currentUnit
        ) { [weak self] newValue, newUnit in
            guard let self = self,
                  let newValue = newValue,
                  let newUnit = newUnit else { return }

            // presetDataを更新
            self.textDocument?.presetData?.format.tabWidthPoints = newValue
            self.textDocument?.presetData?.format.tabWidthUnit = newUnit

            // ポイントモードの場合のみタブ幅を適用
            // スペースモードではタブキー押下時にスペース文字を挿入するため、タブ幅は変更しない
            if newUnit == .points {
                self.applyTabWidth(newValue)

                // プレーンテキストの場合、全文にタブ幅を適用
                if self.textDocument?.documentType == .plain {
                    self.applyTabWidthToAllText(newValue)
                }
            }

            // presetDataの変更をマーク
            self.textDocument?.presetDataEdited = true
        }
    }

    /// 全文にタブ幅を適用（プレーンテキスト用）
    internal func applyTabWidthToAllText(_ tabWidthPoints: CGFloat) {
        guard let textStorage = textDocument?.textStorage, textStorage.length > 0 else { return }

        textStorage.beginEditing()
        textStorage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, _ in
            let newStyle: NSMutableParagraphStyle
            if let existingStyle = value as? NSParagraphStyle {
                newStyle = existingStyle.mutableCopy() as! NSMutableParagraphStyle
            } else {
                newStyle = NSMutableParagraphStyle()
            }
            newStyle.defaultTabInterval = tabWidthPoints
            newStyle.tabStops = []
            textStorage.addAttribute(.paragraphStyle, value: newStyle, range: range)
        }
        textStorage.endEditing()
    }

    // MARK: - Line Spacing

    /// Format > Text > Line Spacing... メニューアクション
    @IBAction func showLineSpacingPanel(_ sender: Any?) {
        guard let window = self.window,
              let presetData = textDocument?.presetData else { return }

        // 現在の値を取得（選択範囲があればその範囲の値を使用）
        var currentData = LineSpacingPanel.LineSpacingData(
            lineHeightMultiple: presetData.format.lineHeightMultiple,
            lineHeightMinimum: presetData.format.lineHeightMinimum,
            lineHeightMaximum: presetData.format.lineHeightMaximum,
            interLineSpacing: presetData.format.interLineSpacing,
            paragraphSpacingBefore: presetData.format.paragraphSpacingBefore,
            paragraphSpacingAfter: presetData.format.paragraphSpacingAfter
        )

        // RTFで選択範囲がある場合、選択範囲のパラグラフスタイルから値を取得
        let isPlainText = textDocument?.documentType == .plain
        if !isPlainText,
           let textView = currentTextView(),
           let textStorage = textDocument?.textStorage,
           textStorage.length > 0 {
            let selectedRange = textView.selectedRange()
            if selectedRange.length > 0 {
                // 選択範囲の先頭のパラグラフスタイルを取得
                let checkLocation = min(selectedRange.location, textStorage.length - 1)
                if let paragraphStyle = textStorage.attribute(.paragraphStyle, at: checkLocation, effectiveRange: nil) as? NSParagraphStyle {
                    currentData = LineSpacingPanel.LineSpacingData(
                        lineHeightMultiple: paragraphStyle.lineHeightMultiple,
                        lineHeightMinimum: paragraphStyle.minimumLineHeight,
                        lineHeightMaximum: paragraphStyle.maximumLineHeight,
                        interLineSpacing: paragraphStyle.lineSpacing,
                        paragraphSpacingBefore: paragraphStyle.paragraphSpacingBefore,
                        paragraphSpacingAfter: paragraphStyle.paragraphSpacing
                    )
                }
            }
        }

        lineSpacingPanel.beginSheet(
            for: window,
            currentData: currentData
        ) { [weak self] newData in
            guard let self = self,
                  let newData = newData else { return }

            let isPlainText = self.textDocument?.documentType == .plain

            if isPlainText {
                // プレーンテキストの場合：presetDataを更新し、全文に適用
                self.textDocument?.presetData?.format.lineHeightMultiple = newData.lineHeightMultiple
                self.textDocument?.presetData?.format.lineHeightMinimum = newData.lineHeightMinimum
                self.textDocument?.presetData?.format.lineHeightMaximum = newData.lineHeightMaximum
                self.textDocument?.presetData?.format.interLineSpacing = newData.interLineSpacing
                self.textDocument?.presetData?.format.paragraphSpacingBefore = newData.paragraphSpacingBefore
                self.textDocument?.presetData?.format.paragraphSpacingAfter = newData.paragraphSpacingAfter

                // デフォルトのパラグラフスタイルを適用（新規入力用のみ、既存テキストはapplyLineSpacingToRangeで適用）
                let tabWidthPoints = self.textDocument?.presetData?.format.tabWidthPoints ?? 28.0
                self.applyParagraphStyle(
                    tabWidthPoints: tabWidthPoints,
                    interLineSpacing: newData.interLineSpacing,
                    paragraphSpacingBefore: newData.paragraphSpacingBefore,
                    paragraphSpacingAfter: newData.paragraphSpacingAfter,
                    lineHeightMultiple: newData.lineHeightMultiple,
                    lineHeightMinimum: newData.lineHeightMinimum,
                    lineHeightMaximum: newData.lineHeightMaximum,
                    applyToExistingText: false  // 既存テキストへの適用はapplyLineSpacingToRangeで行う（Undo対応）
                )

                // 全文にも適用（Undo対応）
                self.applyLineSpacingToRange(newData, range: nil)
            } else {
                // RTFの場合：選択範囲に適用（選択がなければ全文に適用）
                if let textView = self.currentTextView() {
                    let selectedRange = textView.selectedRange()
                    if selectedRange.length > 0 {
                        // 選択範囲に適用
                        self.applyLineSpacingToRange(newData, range: selectedRange)
                    } else {
                        // 選択がない場合は全文に適用し、presetDataも更新
                        self.textDocument?.presetData?.format.lineHeightMultiple = newData.lineHeightMultiple
                        self.textDocument?.presetData?.format.lineHeightMinimum = newData.lineHeightMinimum
                        self.textDocument?.presetData?.format.lineHeightMaximum = newData.lineHeightMaximum
                        self.textDocument?.presetData?.format.interLineSpacing = newData.interLineSpacing
                        self.textDocument?.presetData?.format.paragraphSpacingBefore = newData.paragraphSpacingBefore
                        self.textDocument?.presetData?.format.paragraphSpacingAfter = newData.paragraphSpacingAfter

                        let tabWidthPoints = self.textDocument?.presetData?.format.tabWidthPoints ?? 28.0
                        self.applyParagraphStyle(
                            tabWidthPoints: tabWidthPoints,
                            interLineSpacing: newData.interLineSpacing,
                            paragraphSpacingBefore: newData.paragraphSpacingBefore,
                            paragraphSpacingAfter: newData.paragraphSpacingAfter,
                            lineHeightMultiple: newData.lineHeightMultiple,
                            lineHeightMinimum: newData.lineHeightMinimum,
                            lineHeightMaximum: newData.lineHeightMaximum,
                            applyToExistingText: false  // 既存テキストへの適用はapplyLineSpacingToRangeで行う（Undo対応）
                        )

                        self.applyLineSpacingToRange(newData, range: nil)
                    }
                }
            }

            // presetDataの変更をマーク
            self.textDocument?.presetDataEdited = true
        }
    }

    /// 現在アクティブなテキストビューを取得
    func currentTextView() -> NSTextView? {
        // Continuous モードの場合
        if let scrollView = scrollView1,
           let textView = scrollView.documentView as? NSTextView,
           textView.window?.firstResponder === textView {
            return textView
        }
        if let scrollView = scrollView2,
           !scrollView.isHidden,
           let textView = scrollView.documentView as? NSTextView,
           textView.window?.firstResponder === textView {
            return textView
        }

        // Page モードの場合
        for textView in textViews1 {
            if textView.window?.firstResponder === textView {
                return textView
            }
        }
        for textView in textViews2 {
            if textView.window?.firstResponder === textView {
                return textView
            }
        }

        // どれもfirstResponderでない場合、最初のテキストビューを返す
        if let scrollView = scrollView1,
           let textView = scrollView.documentView as? NSTextView {
            return textView
        }
        if !textViews1.isEmpty {
            return textViews1[0]
        }

        return nil
    }

    /// 指定範囲（またはnilで全文）に行間設定を適用（Undo/Redo対応）
    internal func applyLineSpacingToRange(_ data: LineSpacingPanel.LineSpacingData, range: NSRange?) {
        guard let textStorage = textDocument?.textStorage, textStorage.length > 0 else { return }
        guard let textView = currentTextView() else { return }
        guard let undoManager = textView.undoManager else { return }

        let targetRange = range ?? NSRange(location: 0, length: textStorage.length)

        // Undo登録のため、変更前の属性を保存
        var oldAttributes: [(range: NSRange, style: NSParagraphStyle)] = []
        textStorage.enumerateAttribute(.paragraphStyle, in: targetRange, options: []) { value, attrRange, _ in
            let style: NSParagraphStyle
            if let existingStyle = value as? NSParagraphStyle {
                style = existingStyle.copy() as! NSParagraphStyle
            } else {
                style = NSParagraphStyle.default
            }
            oldAttributes.append((range: attrRange, style: style))
        }

        // Undoアクションを登録（Undo時にRedoも登録される）
        undoManager.registerUndo(withTarget: self) { [weak self, oldAttributes, data, targetRange] target in
            self?.restoreLineSpacing(oldAttributes: oldAttributes, newData: data, range: targetRange)
        }

        if !undoManager.isUndoing && !undoManager.isRedoing {
            undoManager.setActionName("Line Spacing".localized)
        }

        // 新しい行間設定を適用
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.paragraphStyle, in: targetRange, options: []) { value, attrRange, _ in
            let newStyle: NSMutableParagraphStyle
            if let existingStyle = value as? NSParagraphStyle {
                newStyle = existingStyle.mutableCopy() as! NSMutableParagraphStyle
            } else {
                newStyle = NSMutableParagraphStyle()
            }
            newStyle.lineHeightMultiple = data.lineHeightMultiple
            newStyle.minimumLineHeight = data.lineHeightMinimum
            newStyle.maximumLineHeight = data.lineHeightMaximum
            newStyle.lineSpacing = data.interLineSpacing
            newStyle.paragraphSpacingBefore = data.paragraphSpacingBefore
            newStyle.paragraphSpacing = data.paragraphSpacingAfter
            textStorage.addAttribute(.paragraphStyle, value: newStyle, range: attrRange)
        }
        textStorage.endEditing()
    }

    /// 行間設定を復元（Undo/Redo用）
    internal func restoreLineSpacing(
        oldAttributes: [(range: NSRange, style: NSParagraphStyle)],
        newData: LineSpacingPanel.LineSpacingData,
        range: NSRange
    ) {
        guard let textStorage = textDocument?.textStorage, textStorage.length > 0 else { return }
        guard let textView = currentTextView() else { return }
        guard let undoManager = textView.undoManager else { return }

        // 現在の属性を保存（Redo用）
        var currentAttributes: [(range: NSRange, style: NSParagraphStyle)] = []
        let targetRange = NSRange(location: 0, length: min(range.location + range.length, textStorage.length))
        if targetRange.length > 0 {
            textStorage.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, attrRange, _ in
                let style: NSParagraphStyle
                if let existingStyle = value as? NSParagraphStyle {
                    style = existingStyle.copy() as! NSParagraphStyle
                } else {
                    style = NSParagraphStyle.default
                }
                currentAttributes.append((range: attrRange, style: style))
            }
        }

        // Redo用のUndoアクションを登録
        undoManager.registerUndo(withTarget: self) { [weak self, currentAttributes, newData, range] target in
            self?.restoreLineSpacing(oldAttributes: currentAttributes, newData: newData, range: range)
        }

        if !undoManager.isUndoing && !undoManager.isRedoing {
            undoManager.setActionName("Line Spacing".localized)
        }

        // 古い属性を復元
        textStorage.beginEditing()
        for attr in oldAttributes {
            // 範囲がtextStorageの範囲内にあることを確認
            let safeRange = NSRange(
                location: attr.range.location,
                length: min(attr.range.length, textStorage.length - attr.range.location)
            )
            if safeRange.length > 0 {
                textStorage.addAttribute(.paragraphStyle, value: attr.style, range: safeRange)
            }
        }
        textStorage.endEditing()
    }

    // MARK: - Plain Text Font Change

    /// プレーンテキスト全文にフォントを適用（Undo/Redo対応）
    /// - Parameter font: 適用するフォント
    func applyFontToEntireDocument(_ font: NSFont) {
        guard let textStorage = textDocument?.textStorage, textStorage.length > 0 else { return }
        guard let textView = currentTextView() as? JeditTextView else { return }

        let targetRange = NSRange(location: 0, length: textStorage.length)

        // 全文のテキストを取得してフォントを適用
        let currentAttributedString = textStorage.attributedSubstring(from: targetRange)
        let mutableString = NSMutableAttributedString(attributedString: currentAttributedString)
        mutableString.addAttribute(.font, value: font, range: NSRange(location: 0, length: mutableString.length))

        // replaceStringを使って置換（Undo対応）
        textView.replaceString(in: targetRange, with: mutableString)

        // presetData を更新
        textDocument?.presetData?.fontAndColors.baseFontName = font.fontName
        textDocument?.presetData?.fontAndColors.baseFontSize = font.pointSize
        textDocument?.presetDataEdited = true

        // ルーラーの更新などを行う
        basicFontDidChange(font)
    }

    /// プレーンテキスト全文に下線をトグル適用（Undo/Redo対応）
    func applyUnderlineToEntireDocument() {
        guard let textStorage = textDocument?.textStorage, textStorage.length > 0 else { return }
        guard let textView = currentTextView() as? JeditTextView else { return }

        let targetRange = NSRange(location: 0, length: textStorage.length)

        // 現在の下線状態を確認（最初の文字で判定）
        let currentUnderline = textStorage.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int ?? 0
        let hasUnderline = currentUnderline != 0

        // 全文のテキストを取得して下線を適用/削除
        let currentAttributedString = textStorage.attributedSubstring(from: targetRange)
        let mutableString = NSMutableAttributedString(attributedString: currentAttributedString)
        let fullRange = NSRange(location: 0, length: mutableString.length)

        if hasUnderline {
            mutableString.removeAttribute(.underlineStyle, range: fullRange)
        } else {
            mutableString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: fullRange)
        }

        // replaceStringを使って置換（Undo対応）
        textView.replaceString(in: targetRange, with: mutableString)

        // タイピングアトリビュートも更新（新規入力文字に反映）
        var attrs = textView.typingAttributes
        if hasUnderline {
            attrs.removeValue(forKey: .underlineStyle)
        } else {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        textView.typingAttributes = attrs
    }

    // MARK: - Kern Support

    /// プレーンテキスト全文にカーニングを適用（Undo/Redo対応）
    func applyKernToEntireDocument(value: Float?) {
        guard let textStorage = textDocument?.textStorage, textStorage.length > 0 else { return }
        guard let textView = currentTextView() as? JeditTextView else { return }

        let targetRange = NSRange(location: 0, length: textStorage.length)

        // 全文のテキストを取得してカーニングを適用/削除
        let currentAttributedString = textStorage.attributedSubstring(from: targetRange)
        let mutableString = NSMutableAttributedString(attributedString: currentAttributedString)
        let fullRange = NSRange(location: 0, length: mutableString.length)

        if let kernValue = value {
            mutableString.addAttribute(.kern, value: kernValue, range: fullRange)
        } else {
            mutableString.removeAttribute(.kern, range: fullRange)
        }

        // replaceStringを使って置換（Undo対応）
        textView.replaceString(in: targetRange, with: mutableString)

        // タイピングアトリビュートも更新
        var attrs = textView.typingAttributes
        if let kernValue = value {
            attrs[.kern] = kernValue
        } else {
            attrs.removeValue(forKey: .kern)
        }
        textView.typingAttributes = attrs
    }

    /// プレーンテキスト全文のカーニングを調整（Undo/Redo対応）
    func adjustKernToEntireDocument(delta: Float) {
        guard let textStorage = textDocument?.textStorage, textStorage.length > 0 else { return }
        guard let textView = currentTextView() as? JeditTextView else { return }

        let targetRange = NSRange(location: 0, length: textStorage.length)

        // 現在のカーニング値を取得
        let currentKern = textStorage.attribute(.kern, at: 0, effectiveRange: nil) as? Float ?? 0
        let newKern = currentKern + delta

        // 全文のテキストを取得してカーニングを適用
        let currentAttributedString = textStorage.attributedSubstring(from: targetRange)
        let mutableString = NSMutableAttributedString(attributedString: currentAttributedString)
        mutableString.addAttribute(.kern, value: newKern, range: NSRange(location: 0, length: mutableString.length))

        // replaceStringを使って置換（Undo対応）
        textView.replaceString(in: targetRange, with: mutableString)

        // タイピングアトリビュートも更新
        var attrs = textView.typingAttributes
        attrs[.kern] = newKern
        textView.typingAttributes = attrs
    }

    // MARK: - Ligature Support

    /// プレーンテキスト全文に合字設定を適用（Undo/Redo対応）
    func applyLigatureToEntireDocument(value: Int) {
        guard let textStorage = textDocument?.textStorage, textStorage.length > 0 else { return }
        guard let textView = currentTextView() as? JeditTextView else { return }

        let targetRange = NSRange(location: 0, length: textStorage.length)

        // 全文のテキストを取得して合字設定を適用
        let currentAttributedString = textStorage.attributedSubstring(from: targetRange)
        let mutableString = NSMutableAttributedString(attributedString: currentAttributedString)
        mutableString.addAttribute(.ligature, value: value, range: NSRange(location: 0, length: mutableString.length))

        // replaceStringを使って置換（Undo対応）
        textView.replaceString(in: targetRange, with: mutableString)

        // タイピングアトリビュートも更新
        var attrs = textView.typingAttributes
        attrs[.ligature] = value
        textView.typingAttributes = attrs
    }

    // MARK: - Text Alignment Support

    /// プレーンテキスト全文にアラインメントを適用（Undo/Redo対応）
    func applyAlignmentToEntireDocument(_ alignment: NSTextAlignment) {
        guard let textStorage = textDocument?.textStorage, textStorage.length > 0 else { return }
        guard let textView = currentTextView() as? JeditTextView else { return }

        let targetRange = NSRange(location: 0, length: textStorage.length)

        // 全文のテキストを取得してアラインメントを適用
        let currentAttributedString = textStorage.attributedSubstring(from: targetRange)
        let mutableString = NSMutableAttributedString(attributedString: currentAttributedString)
        let fullRange = NSRange(location: 0, length: mutableString.length)

        // 既存のパラグラフスタイルを取得または新規作成
        let existingStyle = mutableString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let mutableStyle = (existingStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        mutableStyle.alignment = alignment
        mutableString.addAttribute(.paragraphStyle, value: mutableStyle, range: fullRange)

        // replaceStringを使って置換（Undo対応）
        textView.replaceString(in: targetRange, with: mutableString)
    }

    // MARK: - Character Color Support

    /// プレーンテキスト全文に前景色を適用（Undo/Redo対応）
    func applyForeColorToEntireDocument(_ color: NSColor) {
        guard let textStorage = textDocument?.textStorage, textStorage.length > 0 else { return }
        guard let textView = currentTextView() as? JeditTextView else { return }

        let targetRange = NSRange(location: 0, length: textStorage.length)

        // 全文のテキストを取得して前景色を適用
        let currentAttributedString = textStorage.attributedSubstring(from: targetRange)
        let mutableString = NSMutableAttributedString(attributedString: currentAttributedString)
        mutableString.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: mutableString.length))

        // replaceStringを使って置換（Undo対応）
        textView.replaceString(in: targetRange, with: mutableString)

        // タイピングアトリビュートも更新
        var attrs = textView.typingAttributes
        attrs[.foregroundColor] = color
        textView.typingAttributes = attrs
    }

    /// プレーンテキスト全文に背景色を適用（Undo/Redo対応）
    func applyBackColorToEntireDocument(_ color: NSColor?) {
        guard let textStorage = textDocument?.textStorage, textStorage.length > 0 else { return }
        guard let textView = currentTextView() as? JeditTextView else { return }

        let targetRange = NSRange(location: 0, length: textStorage.length)

        // 全文のテキストを取得して背景色を適用/削除
        let currentAttributedString = textStorage.attributedSubstring(from: targetRange)
        let mutableString = NSMutableAttributedString(attributedString: currentAttributedString)
        let fullRange = NSRange(location: 0, length: mutableString.length)

        if let color = color {
            mutableString.addAttribute(.backgroundColor, value: color, range: fullRange)
        } else {
            mutableString.removeAttribute(.backgroundColor, range: fullRange)
        }

        // replaceStringを使って置換（Undo対応）
        textView.replaceString(in: targetRange, with: mutableString)

        // タイピングアトリビュートも更新
        var attrs = textView.typingAttributes
        if let color = color {
            attrs[.backgroundColor] = color
        } else {
            attrs.removeValue(forKey: .backgroundColor)
        }
        textView.typingAttributes = attrs
    }

    // MARK: - Auto Indent

    /// Format > Auto Indent メニューアクション
    @IBAction func toggleAutoIndent(_ sender: Any?) {
        guard let presetData = textDocument?.presetData else { return }

        // トグル
        let newValue = !presetData.format.autoIndent
        textDocument?.presetData?.format.autoIndent = newValue

        // presetDataの変更をマーク
        textDocument?.presetDataEdited = true

        // 設定との同期
        syncAutoIndentToPreferences(newValue)
    }

    /// Auto Indent メニューの状態を検証
    func validateAutoIndentMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let presetData = textDocument?.presetData else { return false }
        menuItem.state = presetData.format.autoIndent ? .on : .off
        return true
    }

    /// Auto Indent 設定をプリファレンスに同期
    internal func syncAutoIndentToPreferences(_ enabled: Bool) {
        // 現在選択されているプリセットの autoIndent を更新
        let presetManager = DocumentPresetManager.shared
        if let selectedID = presetManager.selectedPresetID,
           let index = presetManager.presets.firstIndex(where: { $0.id == selectedID }) {
            var preset = presetManager.presets[index]
            preset.data.format.autoIndent = enabled
            presetManager.updatePreset(preset)
        }
    }

    // MARK: - Prevent Editing

    /// 編集のロック/アンロックをトグル
    @IBAction func togglePreventEditing(_ sender: Any?) {
        let isCurrentlyEditable = currentTextView()?.isEditable ?? true

        if isCurrentlyEditable {
            // 編集可能 → 読み取り専用にする場合は確認アラートを表示
            guard let window = self.window else { return }
            let alert = NSAlert()
            alert.messageText = "Are you sure?".localized
            alert.informativeText = "Make the current document read-only.".localized
            alert.addButton(withTitle: "OK".localized)
            alert.addButton(withTitle: "Cancel".localized)
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    self?.performSetPreventEditing(editable: false)
                }
            }
        } else {
            // 読み取り専用 → 編集可能にする
            if textDocument?.isImportedDocument == true {
                // Word/ODTからインポートした書類の場合は互換性に関する警告を表示
                guard let window = self.window else { return }
                let alert = NSAlert()
                alert.messageText = "Allow Editing?".localized
                alert.informativeText = "This document was imported from a format with limited compatibility. Some formatting may not be fully preserved when saved.".localized
                alert.addButton(withTitle: "Allow Editing".localized)
                alert.addButton(withTitle: "Cancel".localized)
                alert.beginSheetModal(for: window) { [weak self] response in
                    if response == .alertFirstButtonReturn {
                        self?.performSetPreventEditing(editable: true)
                    }
                }
            } else {
                performSetPreventEditing(editable: true)
            }
        }
    }

    /// 全テキストビューの isEditable を設定する（Finder ロックファイル対応で Document から呼ばれる）
    func setAllTextViewsEditable(_ editable: Bool) {
        var views: [NSTextView] = []
        if let tv = scrollView1?.documentView as? NSTextView { views.append(tv) }
        if let tv = scrollView2?.documentView as? NSTextView { views.append(tv) }
        views.append(contentsOf: textViews1)
        views.append(contentsOf: textViews2)
        for textView in views {
            textView.isEditable = editable
        }
        updateEditLockButtons()
    }

    /// 編集ロック状態を実際に変更する
    internal func performSetPreventEditing(editable: Bool) {
        var views: [NSTextView] = []
        if let tv = scrollView1?.documentView as? NSTextView { views.append(tv) }
        if let tv = scrollView2?.documentView as? NSTextView { views.append(tv) }
        views.append(contentsOf: textViews1)
        views.append(contentsOf: textViews2)

        for textView in views {
            textView.isEditable = editable
        }

        // 編集許可時に originalMarkdownText をクリア（編集後は逆変換を使う）
        if editable {
            textDocument?.originalMarkdownText = nil
        }

        // presetDataに状態を保存
        textDocument?.presetData?.view.preventEditing = !editable
        markDocumentAsEdited()

        // 編集ロックボタンを更新
        updateEditLockButtons()
    }

    // MARK: - Wrapped Line Indent

    /// Format > Wrapped Line Indent... メニューアクション
    @IBAction func showWrappedLineIndentPanel(_ sender: Any?) {
        guard let window = self.window,
              let presetData = textDocument?.presetData else { return }

        let currentEnabled = presetData.format.indentWrappedLines
        let currentValue = presetData.format.wrappedLineIndent

        wrappedLineIndentPanel.beginSheet(
            for: window,
            enabled: currentEnabled,
            indentValue: currentValue
        ) { [weak self] newEnabled, newValue in
            guard let self = self else { return }

            // presetData を更新
            self.textDocument?.presetData?.format.indentWrappedLines = newEnabled
            self.textDocument?.presetData?.format.wrappedLineIndent = newValue

            // wrapped line indent を適用
            self.applyWrappedLineIndent(enabled: newEnabled, indent: newValue)

            // presetData の変更をマーク
            self.textDocument?.presetDataEdited = true

            // 設定との同期
            self.syncWrappedLineIndentToPreferences(enabled: newEnabled, indent: newValue)
        }
    }

    /// Wrapped Line Indent を適用
    internal func applyWrappedLineIndent(enabled: Bool, indent: CGFloat) {
        guard let textStorage = textDocument?.textStorage else { return }

        let headIndent: CGFloat = enabled ? indent : 0

        // 全てのテキストビューに適用
        func applyToTextView(_ textView: NSTextView) {
            textView.defaultParagraphStyle = {
                let style = (textView.defaultParagraphStyle?.mutableCopy() as? NSMutableParagraphStyle)
                    ?? NSMutableParagraphStyle()
                style.headIndent = headIndent
                return style
            }()
        }

        // Continuous モードのテキストビュー
        if let scrollView = scrollView1,
           let textView = scrollView.documentView as? NSTextView {
            applyToTextView(textView)
        }
        if let scrollView = scrollView2,
           let textView = scrollView.documentView as? NSTextView {
            applyToTextView(textView)
        }

        // Page モードのテキストビュー
        for textView in textViews1 {
            applyToTextView(textView)
        }
        for textView in textViews2 {
            applyToTextView(textView)
        }

        // 既存のテキストにも適用
        if textStorage.length > 0 {
            textStorage.beginEditing()
            textStorage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, _ in
                let newStyle: NSMutableParagraphStyle
                if let existingStyle = value as? NSParagraphStyle {
                    newStyle = existingStyle.mutableCopy() as! NSMutableParagraphStyle
                } else {
                    newStyle = NSMutableParagraphStyle()
                }
                newStyle.headIndent = headIndent
                textStorage.addAttribute(.paragraphStyle, value: newStyle, range: range)
            }
            textStorage.endEditing()
        }
    }

    /// Wrapped Line Indent 設定をプリファレンスに同期
    internal func syncWrappedLineIndentToPreferences(enabled: Bool, indent: CGFloat) {
        // 現在選択されているプリセットの wrappedLineIndent を更新
        let presetManager = DocumentPresetManager.shared
        if let selectedID = presetManager.selectedPresetID,
           let index = presetManager.presets.firstIndex(where: { $0.id == selectedID }) {
            var preset = presetManager.presets[index]
            preset.data.format.indentWrappedLines = enabled
            preset.data.format.wrappedLineIndent = indent
            presetManager.updatePreset(preset)
        }
    }

    // MARK: - Document Colors

    /// View > Document Colors... メニューアクション
    @IBAction func showDocumentColorsPanel(_ sender: Any?) {
        guard let window = self.window,
              let presetData = textDocument?.presetData,
              let panel = documentColorsPanel else { return }

        let currentColors = presetData.fontAndColors.colors

        panel.beginSheet(
            for: window,
            currentColors: currentColors
        ) { [weak self] newColors in
            guard let self = self else { return }

            // Setボタンが押された場合のみ色を適用
            if let colors = newColors {
                self.textDocument?.presetData?.fontAndColors.colors = colors
                self.applyColorsToTextViews(colors)
            }
            // Cancelの場合は何もしない（元の色のまま）
        }
    }

    // MARK: - Page Layout

    /// View > Page Layout... メニューアクション
    @IBAction func showPageLayoutPanel(_ sender: Any?) {
        guard let document = textDocument,
              let panel = pageLayoutPanel else { return }

        panel.showPanel(for: document)
    }

    // MARK: - Print Configuration

    /// 印刷用のPrintPageView設定を作成
    func printPageViewConfiguration() -> PrintPageView.Configuration? {
        guard let document = textDocument else { return nil }

        // ヘッダー・フッターのAttributedStringを取得
        var headerAttrString: NSAttributedString?
        var footerAttrString: NSAttributedString?
        if let headerFooterData = document.presetData?.headerFooter {
            if let headerData = headerFooterData.headerRTFData {
                headerAttrString = NewDocData.HeaderFooterData.attributedString(from: headerData)
            }
            if let footerData = headerFooterData.footerRTFData {
                footerAttrString = NewDocData.HeaderFooterData.attributedString(from: footerData)
            }
        }

        // 色を取得
        let colors = document.presetData?.fontAndColors.colors
        let bgColor: NSColor = colors?.background.nsColor ?? .textBackgroundColor

        // プレーンテキストの場合のデフォルトフォントと色
        let defaultFont: NSFont? = document.documentType == .plain ? currentBasicFont() : nil
        let defaultTextColor: NSColor? = document.documentType == .plain ? (colors?.character.nsColor ?? .textColor) : nil

        // 不可視文字の設定を取得
        let invisibleOptions = invisibleCharacterOptions
        let invisibleColor = colors?.invisible.nsColor ?? .tertiaryLabelColor

        return PrintPageView.Configuration(
            textStorage: document.textStorage,
            printInfo: document.printInfo,
            isVerticalLayout: isVerticalLayout,
            headerAttributedString: headerAttrString,
            footerAttributedString: footerAttrString,
            headerColor: colors?.header.nsColor,
            footerColor: colors?.footer.nsColor,
            documentName: document.displayName ?? "",
            filePath: document.fileURL?.path,
            dateModified: document.fileModificationDate,
            documentProperties: document.presetData?.properties,
            textBackgroundColor: bgColor,
            isPlainText: document.documentType == .plain,
            defaultFont: defaultFont,
            defaultTextColor: defaultTextColor,
            invisibleCharacterOptions: invisibleOptions,
            invisibleCharacterColor: invisibleColor,
            lineBreakingType: Int(document.presetData?.format.wordWrappingType.rawValue ?? 0),
            lineNumberMode: lineNumberMode,
            lineNumberColor: colors?.lineNumber.nsColor ?? .secondaryLabelColor
        )
    }
}
