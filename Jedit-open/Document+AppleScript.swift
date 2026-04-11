//
//  Document+AppleScript.swift
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

extension Document {

    // MARK: - AppleScript Support

    /// AppleScript 用の textStorage アクセサ（SDEF の cocoa key="scriptingTextStorage" に対応）
    /// getter: textStorage を返す
    @objc var scriptingTextStorage: NSTextStorage {
        return textStorage
    }

    // MARK: - AppleScript Element Accessors (characters, words, paragraphs, attributeRuns)
    // contents タグの要素透過が class-extension で動作しない場合のため、
    // Document に直接 KVC アクセサを実装して textStorage に委譲する

    @objc var characters: NSArray {
        return textStorage.value(forKey: "characters") as? NSArray ?? NSArray()
    }

    @objc var words: NSArray {
        return textStorage.value(forKey: "words") as? NSArray ?? NSArray()
    }

    @objc var paragraphs: NSArray {
        return textStorage.value(forKey: "paragraphs") as? NSArray ?? NSArray()
    }

    @objc var attributeRuns: NSArray {
        return textStorage.value(forKey: "attributeRuns") as? NSArray ?? NSArray()
    }

    /// 現在のテキストビューを取得するヘルパー
    var currentTextView: NSTextView? {
        return windowControllers.first.flatMap { ($0 as? EditorWindowController)?.currentTextView() }
    }

    /// AppleScript select コマンドから呼ばれる選択範囲設定メソッド
    func setSelectionRange(_ range: NSRange) {
        guard let textView = currentTextView else { return }
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
    }

    /// AppleScript 用の選択テキスト（rich text）アクセサ
    /// getter: 選択範囲に対応するプロキシ NSTextStorage を返す
    ///         属性の変更（font, size, color）は元の textStorage に直接反映される
    /// setter: 選択範囲のテキストを置き換える
    @objc var scriptingSelection: NSTextStorage {
        get {
            guard let textView = currentTextView else { return NSTextStorage() }
            let range = textView.selectedRange()
            if range.length == 0 { return NSTextStorage() }
            return createSelectionProxy(backingStorage: textStorage, range: range, textView: textView)
        }
        set {
            guard let textView = currentTextView else { return }
            let range = textView.selectedRange()
            // Undo 可能にするため textView 経由で挿入する
            if textView.shouldChangeText(in: range, replacementString: newValue.string) {
                textStorage.beginEditing()
                textStorage.replaceCharacters(in: range, with: newValue)
                textStorage.endEditing()
                textView.didChangeText()
            }
            // 置き換え後、カーソルを置き換えテキストの末尾に移動
            textView.setSelectedRange(NSRange(location: range.location + newValue.length, length: 0))
        }
    }

    /// AppleScript 用の選択位置アクセサ（0-based）
    @objc var scriptingSelectionLocation: Int {
        get {
            guard let textView = currentTextView else { return 0 }
            return textView.selectedRange().location
        }
        set {
            guard let textView = currentTextView else { return }
            let currentRange = textView.selectedRange()
            let maxLen = textStorage.length
            let safeLoc = min(max(newValue, 0), maxLen)
            let safeLen = min(currentRange.length, maxLen - safeLoc)
            let range = NSRange(location: safeLoc, length: safeLen)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
        }
    }

    /// AppleScript 用の選択長さアクセサ
    @objc var scriptingSelectionLength: Int {
        get {
            guard let textView = currentTextView else { return 0 }
            return textView.selectedRange().length
        }
        set {
            guard let textView = currentTextView else { return }
            let currentRange = textView.selectedRange()
            let maxLen = textStorage.length
            let safeLen = min(max(newValue, 0), maxLen - currentRange.location)
            let range = NSRange(location: currentRange.location, length: safeLen)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
        }
    }

    /// AppleScript 用の書類タイプアクセサ
    /// "plain text" / "RTF" / "RTFD" を返す・設定する
    @objc var scriptingDocumentType: String {
        get {
            switch documentType {
            case .rtf: return "RTF"
            case .rtfd: return "RTFD"
            default: return "plain text"
            }
        }
        set {
            switch newValue.lowercased() {
            case "rtf":
                documentType = .rtf
            case "rtfd":
                documentType = .rtfd
            case "plain text", "plain", "text":
                documentType = .plain
            default:
                return
            }
            updateFileTypeFromDocumentType()
            NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
        }
    }

    /// AppleScript 用のデフォルトフォント名（読み取り専用）
    @objc var scriptingCharFont: String {
        let fontData = presetData?.fontAndColors ?? NewDocData.FontAndColorsData.default
        return fontData.baseFontName
    }

    /// AppleScript 用のデフォルトフォントサイズ（読み取り専用）
    @objc var scriptingCharSize: Double {
        let fontData = presetData?.fontAndColors ?? NewDocData.FontAndColorsData.default
        return Double(fontData.baseFontSize)
    }

    /// AppleScript 用のデフォルトテキスト色（読み取り専用）
    @objc var scriptingCharColor: NSColor {
        let fontData = presetData?.fontAndColors ?? NewDocData.FontAndColorsData.default
        return fontData.colors.character.nsColor
    }

    /// AppleScript 用のデフォルト背景色（読み取り専用）
    @objc var scriptingCharBackColor: NSColor {
        let fontData = presetData?.fontAndColors ?? NewDocData.FontAndColorsData.default
        return fontData.colors.background.nsColor
    }

    /// AppleScript 用のリッチテキスト判定プロパティ
    /// true ならリッチテキスト（RTF/RTFD）、false ならプレーンテキスト
    @objc var scriptingIsRichText: Bool {
        get {
            return documentType != .plain
        }
        set {
            if newValue {
                // プレーンテキスト → リッチテキスト
                if documentType == .plain {
                    documentType = .rtf
                    updateFileTypeFromDocumentType()
                    NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
                }
            } else {
                // リッチテキスト → プレーンテキスト
                if documentType != .plain {
                    documentType = .plain
                    updateFileTypeFromDocumentType()
                    NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
                }
            }
        }
    }

    // MARK: - AppleScript Print Command
    // AppleScript の print コマンドは AppDelegate.swift の handlePrintAppleEvent で
    // Apple Event レベルで処理する（Cocoa Scripting のルーティングが機能しないため）

    /// KVC 経由で AppleScript からテキストがセットされた際に、
    /// NSString / NSAttributedString を適切に textStorage の内容として反映する
    override func setValue(_ value: Any?, forKey key: String) {
        if key == "scriptingTextStorage" {
            let fullRange = NSRange(location: 0, length: textStorage.length)
            textStorage.beginEditing()
            if let attrStr = value as? NSAttributedString {
                textStorage.replaceCharacters(in: fullRange, with: attrStr)
            } else if let str = value as? String {
                textStorage.replaceCharacters(in: fullRange, with: str)
            } else if let nsStr = value as? NSString {
                textStorage.replaceCharacters(in: fullRange, with: nsStr as String)
            }
            textStorage.endEditing()
            // テキストが空でなければ dirty にする
            // NSCreateCommand の書類作成プロセス完了後に反映するため遅延実行
            if textStorage.length > 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.updateChangeCount(.changeDone)
                }
            }
            return
        }
        if key == "scriptingSelection" {
            guard let textView = currentTextView else { return }
            let range = textView.selectedRange()
            let replacementString: String
            if let attrStr = value as? NSAttributedString {
                replacementString = attrStr.string
            } else if let str = value as? String {
                replacementString = str
            } else {
                return
            }
            // Undo 可能にするため textView 経由で挿入する
            if textView.shouldChangeText(in: range, replacementString: replacementString) {
                textStorage.beginEditing()
                if let attrStr = value as? NSAttributedString {
                    textStorage.replaceCharacters(in: range, with: attrStr)
                } else {
                    textStorage.replaceCharacters(in: range, with: replacementString)
                }
                textStorage.endEditing()
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: range.location + replacementString.count, length: 0))
            }
            return
        }
        if key == "scriptingIsRichText" {
            if let boolValue = value as? Bool {
                scriptingIsRichText = boolValue
            } else if let numValue = value as? NSNumber {
                scriptingIsRichText = numValue.boolValue
            }
            return
        }
        super.setValue(value, forKey: key)
    }
}
