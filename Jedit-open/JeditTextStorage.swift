//
//  JeditTextStorage.swift
//  Jedit-open
//
//  Created by Claude on 2026/02/05.
//

import Cocoa

/// カスタム行折り返し処理をサポートするNSTextStorageサブクラス
class JeditTextStorage: NSTextStorage {

    // MARK: - Properties

    /// 内部ストレージ
    private let backingStore = NSMutableAttributedString()

    /// 行折り返しタイプ (0: システムデフォルト, 1: 日本語禁則, 2: 折り返しなし)
    var lineBreakingType: Int = 0

    /// 禁則文字セット
    private var topKinsokuChars: CharacterSet = CharacterSet()
    private var endKinsokuChars: CharacterSet = CharacterSet()
    private var burasagariChars: CharacterSet = CharacterSet()
    private var bunriKinshiChars: CharacterSet = CharacterSet()

    /// Latin文字の最大コードポイント
    private let latinMax: unichar = 0x0100

    // MARK: - Initialization

    override init() {
        super.init()
        loadKinsokuCharacters()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadKinsokuCharacters()
    }

    required init?(pasteboardPropertyList: Any, ofType type: NSPasteboard.PasteboardType) {
        super.init(pasteboardPropertyList: pasteboardPropertyList, ofType: type)
        loadKinsokuCharacters()
    }

    // MARK: - NSTextStorage Required Overrides

    override var string: String {
        return backingStore.string
    }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key : Any] {
        return backingStore.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backingStore.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: str.count - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key : Any]?, range: NSRange) {
        beginEditing()
        backingStore.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    // MARK: - Line Breaking Override

    override func lineBreak(before location: Int, within aRange: NSRange) -> Int {
        switch lineBreakingType {
        case 1: // Japanese Burasagari Kinsoku
            return japaneseLineBreak(beforeIndex: location, withinRange: aRange)
        case 2: // No word wrapping
            return NSMaxRange(aRange) - 1
        default: // System default
            return super.lineBreak(before: location, within: aRange)
        }
    }

    // MARK: - Japanese Line Breaking

    private func japaneseLineBreak(beforeIndex location: Int, withinRange aRange: NSRange) -> Int {
        let defaultBreak = super.lineBreak(before: location, within: aRange)
        let delta = NSMaxRange(aRange) - defaultBreak

        var maxIndex = NSMaxRange(aRange) - 1
        if maxIndex < defaultBreak { maxIndex = defaultBreak }

        let nsString = string as NSString

        // 範囲チェック
        guard defaultBreak < nsString.length else {
            return defaultBreak
        }

        let charD = nsString.character(at: defaultBreak)

        // Latin文字でdeltaがある場合はデフォルト
        if charD < latinMax && delta > 0 {
            return defaultBreak
        }

        // maxIndex - 1 の範囲チェック
        guard maxIndex >= 1 && maxIndex - 1 < nsString.length else {
            return defaultBreak
        }

        let charC = nsString.character(at: maxIndex - 1)

        // ぶら下げ文字チェック
        if let scalar = Unicode.Scalar(charC), burasagariChars.contains(scalar) {
            return maxIndex
        }

        // 全角・半角スペース
        if charC == 0x3000 || charC == 0x0020 {
            return maxIndex
        }

        // Latin文字
        if charC < latinMax {
            var ret = maxIndex
            var currentChar = charC
            // アンダースコアまたは英数字の連続を戻る
            while ret > aRange.location + 1 {
                let prevChar = nsString.character(at: ret - 1)
                if prevChar == 0x005F /* _ */ || isAlphanumeric(prevChar) {
                    ret -= 1
                    currentChar = prevChar
                } else {
                    break
                }
            }
            return ret
        }

        // 行頭禁則文字
        if let scalar = Unicode.Scalar(charC), topKinsokuChars.contains(scalar) {
            return maxIndex - 2
        }

        // maxIndex - 2 の範囲チェック
        guard maxIndex >= 2 && maxIndex - 2 < nsString.length else {
            return maxIndex - 1
        }

        // 行末禁則・分離禁止チェック
        let charB = nsString.character(at: maxIndex - 2)

        if let scalarB = Unicode.Scalar(charB), endKinsokuChars.contains(scalarB) {
            return maxIndex - 2
        }

        if let scalarB = Unicode.Scalar(charB),
           let scalarC = Unicode.Scalar(charC),
           bunriKinshiChars.contains(scalarB) && bunriKinshiChars.contains(scalarC) {
            return maxIndex - 2
        }

        return maxIndex - 1
    }

    // MARK: - Helper Methods

    private func isAlphanumeric(_ char: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(char) else { return false }
        return CharacterSet.alphanumerics.contains(scalar)
    }

    /// UserDefaultsから禁則文字を読み込み
    func loadKinsokuCharacters() {
        let defaults = UserDefaults.standard

        if let topChars = defaults.string(forKey: UserDefaults.Keys.cantBeTopChars) {
            topKinsokuChars = CharacterSet(charactersIn: topChars)
        }
        if let endChars = defaults.string(forKey: UserDefaults.Keys.cantBeEndChars) {
            endKinsokuChars = CharacterSet(charactersIn: endChars)
        }
        if let burasagari = defaults.string(forKey: UserDefaults.Keys.burasagariChars) {
            burasagariChars = CharacterSet(charactersIn: burasagari)
        }
        if let bunriKinshi = defaults.string(forKey: UserDefaults.Keys.cantSeparateChars) {
            bunriKinshiChars = CharacterSet(charactersIn: bunriKinshi)
        }
    }

    /// 禁則文字を更新
    func updateKinsokuCharacters() {
        loadKinsokuCharacters()
    }

    /// レイアウトの再計算を要求
    func invalidateLayout() {
        let fullRange = NSRange(location: 0, length: length)
        for layoutManager in layoutManagers {
            layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
        }
    }
}
