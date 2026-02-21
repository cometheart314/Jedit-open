//
//  FontFallbackRecoveryDelegate.swift
//  Jedit-open
//
//  Created by Claude on 2026/01/26.
//

import Cocoa

/// フォントフォールバックからの自動復帰を処理するNSTextStorageDelegate
///
/// 欧文フォントで日本語を入力すると、macOSが自動的に日本語フォントにフォールバックする。
/// このDelegateは、欧文を入力した際に元の欧文フォントに自動的に復帰させる。
///
/// - プレーンテキスト: Basic Fontに復帰
/// - リッチテキスト: 直前の欧文フォントを探して復帰、見つからない場合のみBasic Fontにフォールバック
class FontFallbackRecoveryDelegate: NSObject, NSTextStorageDelegate {

    // MARK: - Properties

    /// ドキュメントへの弱参照
    weak var document: Document?

    /// フォント復帰処理中かどうか（再帰呼び出し防止用）
    private var isProcessingFontRecovery = false

    /// Smart Language Separation 処理
    private(set) var smartLanguageSeparation: SmartLanguageSeparation?

    // MARK: - Initialization

    init(document: Document) {
        self.document = document
        super.init()
        smartLanguageSeparation = SmartLanguageSeparation(document: document)
    }

    /// 段落スタイル変更処理中かどうか（再帰呼び出し防止用）
    private var isProcessingParagraphStyle = false

    // MARK: - NSTextStorageDelegate

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard let document = document else { return }

        // --- プレーンテキストの段落スタイル統一処理 ---
        if document.documentType == .plain,
           editedMask.contains(.editedAttributes),
           !isProcessingParagraphStyle,
           textStorage.length > 0 {
            applyUnifiedParagraphStyle(textStorage: textStorage, editedRange: editedRange)
        }

        // --- Smart Language Separation ---
        if editedMask.contains(.editedCharacters), delta >= 0 {
            // テキストビューを取得してフラグをチェック
            if let textView = textStorage.layoutManagers.first?.firstTextView as? JeditTextView,
               textView.isSmartSeparationEnglishJapaneseEnabled,
               !textView.hasMarkedText(),
               !(textView.undoManager?.isRedoing ?? false) {

                // ペースト中はスキップ
                if let separation = smartLanguageSeparation, !separation.isPasting {
                    separation.requestSeparation(for: editedRange)
                }
            }
        }
    }

    /// プレーンテキストで属性が変更された場合、段落スタイルを全文に適用
    private func applyUnifiedParagraphStyle(textStorage: NSTextStorage, editedRange: NSRange) {
        // 変更された範囲の段落スタイルを取得
        let safeLocation = min(editedRange.location, textStorage.length - 1)
        guard let changedStyle = textStorage.attribute(.paragraphStyle, at: safeLocation, effectiveRange: nil) as? NSParagraphStyle else {
            return
        }

        // 全文に同じ段落スタイルが適用されているか確認
        let fullRange = NSRange(location: 0, length: textStorage.length)
        var needsUpdate = false

        textStorage.enumerateAttribute(.paragraphStyle, in: fullRange, options: []) { value, range, stop in
            if let style = value as? NSParagraphStyle {
                // 行間隔、段落間隔などが異なる場合は更新が必要
                if style.lineSpacing != changedStyle.lineSpacing ||
                   style.paragraphSpacing != changedStyle.paragraphSpacing ||
                   style.paragraphSpacingBefore != changedStyle.paragraphSpacingBefore ||
                   style.lineHeightMultiple != changedStyle.lineHeightMultiple ||
                   style.minimumLineHeight != changedStyle.minimumLineHeight ||
                   style.maximumLineHeight != changedStyle.maximumLineHeight {
                    needsUpdate = true
                    stop.pointee = true
                }
            }
        }

        if needsUpdate {
            // Undo 登録を無効化して、NSTextView の自動 Undo グルーピングを壊さないようにする
            let undoManager = textStorage.layoutManagers.first?.firstTextView?.undoManager
            undoManager?.disableUndoRegistration()
            isProcessingParagraphStyle = true
            textStorage.addAttribute(.paragraphStyle, value: changedStyle, range: fullRange)
            isProcessingParagraphStyle = false
            undoManager?.enableUndoRegistration()
        }
    }

    func textStorage(_ textStorage: NSTextStorage, willProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        // 文字が追加された場合のみ処理（削除や属性変更のみの場合は無視）
        guard editedMask.contains(.editedCharacters), delta > 0 else { return }

        // 再帰呼び出し防止
        guard !isProcessingFontRecovery else { return }

        // 挿入された文字列を取得
        let insertedString = textStorage.attributedSubstring(from: editedRange).string

        // すべてLatin文字かどうかをチェック
        guard isAllLatinCharacters(insertedString) else { return }

        // 現在のフォントを取得
        guard editedRange.location < textStorage.length else { return }
        let currentAttributes = textStorage.attributes(at: editedRange.location, effectiveRange: nil)
        guard let currentFont = currentAttributes[.font] as? NSFont else { return }

        // 現在のフォントがLatin文字をネイティブサポートしているかチェック
        // サポートしていればフォールバックは発生していないので何もしない
        if fontSupportsLatin(currentFont) {
            return
        }

        // フォールバックが発生している（現在のフォントがLatinをサポートしていない）
        // 復帰先のフォントを決定
        guard let recoveryFont = determineRecoveryFont(for: textStorage, at: editedRange.location) else {
            return
        }

        // 復帰先フォントが現在のフォントと同じ場合は何もしない
        if currentFont.fontName == recoveryFont.fontName && currentFont.pointSize == recoveryFont.pointSize {
            return
        }

        // フォント復帰処理
        // Undo 登録を無効化して、NSTextView の自動 Undo グルーピングを壊さないようにする。
        // willProcessEditing 内での属性変更が個別の Undo アクションとして記録されると、
        // 連続したキー入力が1文字ずつ Undo される問題が発生する。
        let undoManager = textStorage.layoutManagers.first?.firstTextView?.undoManager
        undoManager?.disableUndoRegistration()
        isProcessingFontRecovery = true
        textStorage.addAttribute(.font, value: recoveryFont, range: editedRange)
        isProcessingFontRecovery = false
        undoManager?.enableUndoRegistration()
    }

    // MARK: - Font Recovery Logic

    /// 復帰先のフォントを決定する
    /// - Parameters:
    ///   - textStorage: テキストストレージ
    ///   - location: 挿入位置
    /// - Returns: 復帰先のフォント、または決定できない場合はnil
    private func determineRecoveryFont(for textStorage: NSTextStorage, at location: Int) -> NSFont? {
        guard let document = document else { return nil }

        // プレーンテキストの場合はBasic Fontに復帰
        if document.documentType == .plain {
            return getBasicFont()
        }

        // リッチテキストの場合：直前から欧文をサポートするフォントを探す
        if let latinFont = findLatinSupportingFont(in: textStorage, before: location) {
            return latinFont
        }

        // 見つからない場合はBasic Fontにフォールバック
        return getBasicFont()
    }

    /// Basic Fontを取得
    private func getBasicFont() -> NSFont? {
        guard let presetData = document?.presetData else { return nil }
        let fontData = presetData.fontAndColors
        return NSFont(name: fontData.baseFontName, size: fontData.baseFontSize)
    }

    /// 指定位置より前からLatin文字をサポートするフォントを探す
    /// - Parameters:
    ///   - textStorage: テキストストレージ
    ///   - location: 検索開始位置（この位置より前を検索）
    /// - Returns: 見つかったLatinサポートフォント、または見つからない場合はnil
    private func findLatinSupportingFont(in textStorage: NSTextStorage, before location: Int) -> NSFont? {
        guard location > 0 else { return nil }

        // 直前の位置から遡って検索
        var searchLocation = location - 1
        let maxSearchDistance = min(location, 1000) // 最大1000文字まで遡る

        while searchLocation >= 0 && (location - searchLocation) <= maxSearchDistance {
            let attributes = textStorage.attributes(at: searchLocation, effectiveRange: nil)

            if let font = attributes[.font] as? NSFont {
                // このフォントがLatin文字をサポートしているかチェック
                if fontSupportsLatin(font) {
                    return font
                }
            }

            searchLocation -= 1
        }

        return nil
    }
}
